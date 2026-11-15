extends CharacterBody3D
class_name EnemyAI

signal enemy_died(enemy)

@export var max_health: float = 60.0
@export var speed: float = 3.5
@export var damage: float = 10.0

var current_health: float = 60.0
var target: Node3D = null
var is_dead: bool = false
# v0.8 WANTED: heat-level variant applied by the spawner via
# apply_variant(). 0 = default grunt. The boss (boss_enemy.gd) overrides
# _build_body() / _physics_process() and never gets apply_variant(),
# so variants can never leak into the Khaled fight.
var variant_level: int = 0
# v0.8 WANTED: which variant the visible Body was built for. Lets
# apply_variant() skip the rebuild when the body already matches (the
# spawner sets variant_level BEFORE add_child, so _ready builds the
# right look first time — no free/rebuild, no headless mesh noise).
var _body_variant_level: int = -1
var gravity: float = 9.8
var _leg_l: MeshInstance3D
var _leg_r: MeshInstance3D
var _arm_l: MeshInstance3D
var _arm_r: MeshInstance3D
var _walk_phase: float = 0.0

func _ready():
	current_health = max_health
	_build_body()

func _build_body() -> void:
	# Visible body, built here so a spawner only needs a CharacterBody3D
	# + this script + a collision shape. Shared materials, low poly.
	if get_node_or_null("Body") != null:
		return
	_body_variant_level = variant_level
	var body := Node3D.new()
	body.name = "Body"
	add_child(body)
	# v0.5 GTA-style variety: three uniform palettes + varied skin tones,
	# so enemies stop reading as clones.
	var palettes: Array = [
		[Color(0.23, 0.26, 0.20), Color(0.72, 0.55, 0.42)],
		[Color(0.16, 0.18, 0.24), Color(0.62, 0.46, 0.34)],
		[Color(0.38, 0.32, 0.22), Color(0.80, 0.62, 0.46)],
	]
	var pick: Array = palettes[randi() % palettes.size()]
	var uniform := StandardMaterial3D.new()
	uniform.albedo_color = pick[0]
	uniform.roughness = 0.9
	var skin := StandardMaterial3D.new()
	skin.albedo_color = pick[1]
	skin.roughness = 0.9
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.13)
	dark.roughness = 0.8
	# v0.8 WANTED: L4 elites wear a dark-red helmet.
	var helmet_mat := dark
	if variant_level == 4:
		helmet_mat = StandardMaterial3D.new()
		helmet_mat.albedo_color = Color(0.45, 0.08, 0.08)
		helmet_mat.roughness = 0.8
	var torso := MeshInstance3D.new()
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.62, 0.75, 0.34)
	torso_mesh.material = uniform
	torso.mesh = torso_mesh
	torso.position.y = 1.05
	# v0.8 WANTED: L4/L5 bulkier torso.
	if variant_level >= 4:
		torso.scale = Vector3(1.12, 1.12, 1.12)
	body.add_child(torso)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.22
	head_mesh.height = 0.44
	head_mesh.material = skin
	head.mesh = head_mesh
	head.position.y = 1.62
	body.add_child(head)
	var helmet := MeshInstance3D.new()
	var helmet_mesh := SphereMesh.new()
	helmet_mesh.radius = 0.24
	helmet_mesh.height = 0.48
	helmet_mesh.material = helmet_mat
	helmet.mesh = helmet_mesh
	helmet.position.y = 1.70
	body.add_child(helmet)
	for lx in [-0.18, 0.18]:
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.22, 0.65, 0.22)
		leg_mesh.material = uniform
		leg.mesh = leg_mesh
		leg.position = Vector3(lx, 0.33, 0)
		body.add_child(leg)
		if lx < 0.0:
			_leg_l = leg
		else:
			_leg_r = leg
		# Boot: dark box at the foot.
		var boot := MeshInstance3D.new()
		var boot_mesh := BoxMesh.new()
		boot_mesh.size = Vector3(0.24, 0.14, 0.34)
		boot_mesh.material = dark
		boot.mesh = boot_mesh
		boot.position = Vector3(lx, 0.07, 0.05)
		body.add_child(boot)
	var gun := MeshInstance3D.new()
	var gun_mesh := BoxMesh.new()
	gun_mesh.size = Vector3(0.08, 0.12, 0.7)
	gun_mesh.material = dark
	gun.mesh = gun_mesh
	gun.position = Vector3(0.25, 1.15, 0.3)
	body.add_child(gun)
	# Gun magazine + stock, so the weapon reads at distance.
	var gun_mag := MeshInstance3D.new()
	var gun_mag_mesh := BoxMesh.new()
	gun_mag_mesh.size = Vector3(0.06, 0.22, 0.1)
	gun_mag_mesh.material = dark
	gun_mag.mesh = gun_mag_mesh
	gun_mag.position = Vector3(0.25, 1.0, 0.28)
	gun_mag.rotation.x = 0.25
	body.add_child(gun_mag)
	# v0.8 WANTED: L3 gunman carries an SMG — longer dark barrel
	# jutting past the rifle muzzle + a shoulder strap across the chest.
	if variant_level >= 3:
		var barrel := MeshInstance3D.new()
		var barrel_mesh := BoxMesh.new()
		barrel_mesh.size = Vector3(0.06, 0.08, 0.9)
		barrel_mesh.material = dark
		barrel.mesh = barrel_mesh
		barrel.position = Vector3(0.25, 1.15, 0.55)
		body.add_child(barrel)
		var strap := MeshInstance3D.new()
		var strap_mesh := BoxMesh.new()
		strap_mesh.size = Vector3(0.09, 0.75, 0.06)
		strap_mesh.material = dark
		strap.mesh = strap_mesh
		strap.position = Vector3(0, 1.12, 0.24)
		strap.rotation.z = 0.5
		body.add_child(strap)
	# Backpack on the back.
	var pack := MeshInstance3D.new()
	var pack_mesh := BoxMesh.new()
	pack_mesh.size = Vector3(0.44, 0.5, 0.22)
	pack_mesh.material = dark
	pack.mesh = pack_mesh
	pack.position = Vector3(0, 1.15, -0.28)
	body.add_child(pack)
	# Arms, vest plate and headband stripe — reads at distance.
	# v0.8 WANTED: L4 elite vest is dark red, L5 hit-squad vest is black.
	var vest_mat := StandardMaterial3D.new()
	vest_mat.albedo_color = Color(0.30, 0.28, 0.20)
	if variant_level == 4:
		vest_mat.albedo_color = Color(0.45, 0.08, 0.08)
	elif variant_level >= 5:
		vest_mat.albedo_color = Color(0.05, 0.05, 0.06)
	vest_mat.roughness = 0.95
	var vest := MeshInstance3D.new()
	var vest_mesh := BoxMesh.new()
	vest_mesh.size = Vector3(0.5, 0.45, 0.10)
	vest_mesh.material = vest_mat
	vest.mesh = vest_mesh
	vest.position = Vector3(0, 1.10, 0.20)
	body.add_child(vest)
	var band_mat := StandardMaterial3D.new()
	# v0.8 WANTED: L5 hit squad wears a taller, brighter red band.
	band_mat.albedo_color = Color(0.90, 0.10, 0.10) if variant_level >= 5 else Color(0.75, 0.18, 0.12)
	band_mat.roughness = 0.9
	var band := MeshInstance3D.new()
	var band_mesh := BoxMesh.new()
	band_mesh.size = Vector3(0.46, 0.12, 0.46) if variant_level >= 5 else Vector3(0.46, 0.07, 0.46)
	band_mesh.material = band_mat
	band.mesh = band_mesh
	band.position = Vector3(0, 1.70, 0)
	body.add_child(band)
	# Vest pouches on the chest.
	for px in [-0.14, 0.14]:
		var pouch := MeshInstance3D.new()
		var pouch_mesh := BoxMesh.new()
		pouch_mesh.size = Vector3(0.16, 0.18, 0.08)
		pouch_mesh.material = dark
		pouch.mesh = pouch_mesh
		pouch.position = Vector3(px, 1.02, 0.26)
		body.add_child(pouch)
	for ax in [-0.42, 0.42]:
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.16, 0.62, 0.16)
		arm_mesh.material = uniform
		arm.mesh = arm_mesh
		arm.position = Vector3(ax, 1.02, 0.05)
		arm.rotation.z = -0.15 if ax < 0.0 else 0.15
		body.add_child(arm)
		if ax < 0.0:
			_arm_l = arm
		else:
			_arm_r = arm

## v0.8 WANTED: apply a heat-level variant (called by EnemySpawner for
## every spawned enemy). Stats + look per level:
##   L0/L1 grunt ......... HP 60,  dmg 10, speed 3.5, default look
##   L2 faster grunt ..... HP 65,  dmg 11, speed 4.2, default look
##   L3 gunman (SMG) ..... HP 75,  dmg 8,  speed 4.0, long barrel + strap
##   L4 elite (shotgun) .. HP 120, dmg 16, speed 3.8, dark-red vest +
##                          helmet, torso scale 1.12, 1.5x damage < 1.2 m
##   L5 hit-squad elite .. HP 150, dmg 18, speed 4.2, black vest + red band
## Safe to call before or after _ready: when the Body was already built
## for a different variant it is rebuilt (free() is immediate, so
## _build_body's "Body exists" guard does not trip); when called before
## _ready, _build_body picks the variant look up on its own; when the
## body already matches, no rebuild happens at all. NEVER call on the
## boss (boss_enemy.gd overrides _build_body and sets its own stats).
## NOTE — what could NOT be varied: EnemyAI has NO attack-cooldown
## variable (its attack is continuous take_damage(dmg * delta) inside
## 2 m), so the spec's "L3 fires faster (halve the cooldown)" cannot be
## done without a combat rework, which the spec forbids inventing. L3
## therefore trades damage (8) for HP/speed; its threat is the SMG look
## + speed, not a higher fire rate.
func apply_variant(level: int) -> void:
	variant_level = clampi(level, 0, 5)
	match variant_level:
		0, 1:
			max_health = 60.0
			damage = 10.0
			speed = 3.5
		2:
			max_health = 65.0
			damage = 11.0
			speed = 4.2
		3:
			max_health = 75.0
			damage = 8.0
			speed = 4.0
		4:
			max_health = 120.0
			damage = 16.0
			speed = 3.8
		5:
			max_health = 150.0
			damage = 18.0
			speed = 4.2
	current_health = max_health
	# Rebuild the visible body ONLY when it was built for a different
	# variant. The normal path (spawner sets variant_level before
	# add_child) never rebuilds: _ready already built the right look.
	# When called before _ready, there is no Body yet and the coming
	# _ready builds it with the right variant.
	var old_body := get_node_or_null("Body")
	if old_body != null and _body_variant_level != variant_level:
		old_body.free()
		_build_body()

## v0.8 WANTED: L4 elite shotgun burst — 1.5x damage only at very close
## range (< 1.2 m). Every other level returns `damage` unchanged, so
## level 0/1 behaviour is byte-identical to v0.7.
func _attack_damage(distance: float) -> float:
	if variant_level == 4 and distance < 1.2:
		return damage * 1.5
	return damage

func _physics_process(delta):
	if is_dead:
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	if not is_instance_valid(target):
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return
	# v0.5: when the player is dead, enemies stop — no more swarming
	# the corpse or dealing damage while YOU DIED is on screen.
	if target.get("is_dead") == true:
		velocity.x = 0
		velocity.z = 0
		_set_walk_pose(0.0)
		move_and_slide()
		return
	var difference = target.global_position - global_position
	var distance = difference.length()
	if distance > 0.1:
		var direction = difference.normalized()
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		# Face the player (yaw only).
		var flat := Vector3(direction.x, 0, direction.z)
		if flat.length() > 0.01:
			rotation.y = atan2(-flat.x, -flat.z)
		_walk_phase += delta * speed * 2.2
		_set_walk_pose(sin(_walk_phase) * 0.4)
	else:
		velocity.x = 0
		velocity.z = 0
		_set_walk_pose(0.0)
	if distance < 2.0 and target.has_method("take_damage"):
		target.take_damage(_attack_damage(distance) * delta)
	move_and_slide()

func _set_walk_pose(swing: float) -> void:
	if is_instance_valid(_leg_l):
		_leg_l.rotation.x = swing
	if is_instance_valid(_leg_r):
		_leg_r.rotation.x = -swing
	if is_instance_valid(_arm_l):
		_arm_l.rotation.x = -swing * 0.7
	if is_instance_valid(_arm_r):
		_arm_r.rotation.x = swing * 0.7

func take_damage(amount: float):
	if is_dead:
		return
	current_health -= amount
	if current_health <= 0:
		is_dead = true
		enemy_died.emit(self)
		queue_free()
