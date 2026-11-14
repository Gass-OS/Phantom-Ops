extends EnemyAI
class_name BossEnemy
## v0.7 — Khaled "The Wolf", leader of the fictional gang
## "The Wolves of Kasserine". Chapter 5 boss fight.
##
## Extends EnemyAI by inheritance — enemy_ai.gd is NOT edited.
## Spawn contract (chapter system):
##   var boss = BossEnemy.new()
##   boss.position = Vector3(...)
##   add_child(boss)
##   boss.target = player
## _ready() builds the body, the name label and the boss bar; the
## target may be set after add_child (as the spawner does) and
## _physics_process() is safe with a null/invalid target.
##
## LOOK: ~1.25x scale, near-black suit + long dark coat, red headband
## with hanging tails, gold chain + pendant at the neck, billboarded
## gold Label3D with the translated boss name above his head.
##
## BALANCE (player rifle 25 dmg/shot, 0.12 s cooldown, player HP 100):
##   Boss HP 500  -> 500 / 25 = 20 hits to kill.
##   Min. continuous fire to kill: 20 x 0.12 s = 2.4 s of shooting,
##   plus reloads (30-round mag: 20 shots fit in one mag, no reload
##   needed if every shot lands) and the 2 guards at 50% HP.
##   Heavy melee 25 dmg/hit, 1.2 s cooldown -> 4 hits to kill the
##   player, earliest death after ~3.6 s point-blank; the player
##   outruns him (walk 5.0 = boss chase 5.0, sprint 8.5 > 5.0) and
##   can break away during the 0.6 s charge wind-up.
##   Charge 9.0 speed is a closing move, not damage by itself — the
##   damage still comes only from the 25-dmg melee hits.
##   Verdict: winnable in ~10-20 s of real fighting, lethal only if
##   the player stands still in melee range. See the headless test.
##
## SIGNALS: boss_died(boss) in addition to the inherited
## enemy_died(enemy), so the chapter system can listen to either.

signal boss_died(boss)

const BOSS_MAX_HP := 500.0
const BOSS_SPEED := 5.0
const BOSS_HEAVY_DAMAGE := 25.0
const BOSS_ATTACK_COOLDOWN := 1.2
const BOSS_MELEE_RANGE := 2.2
const BOSS_CHARGE_SPEED := 9.0
const BOSS_WINDUP_TIME := 0.6
const BOSS_CHARGE_TIME := 0.9
const BOSS_CHARGE_COOLDOWN := 2.5
const BOSS_CHARGE_MIN_RANGE := 3.0
const BOSS_CHARGE_MAX_RANGE := 14.0
const BOSS_SCALE := 1.25
const GUARD_COUNT := 2
const GUARD_SUMMON_FRACTION := 0.5

const STATE_CHASE := 0
const STATE_WINDUP := 1
const STATE_CHARGE := 2

var _bar: BossBar = null
var _guards_summoned := false
var _attack_cooldown := 0.0
var _charge_cooldown := 0.0
var _state := STATE_CHASE
var _state_timer := 0.0
var _label: Label3D


## Translated boss name ("Khaled — The Wolf" / "Khaled — Le Loup" /
## "خالد — الذئب"). Falls back to the English name if the key is ever
## missing, so the label never shows a raw key.
static func boss_display_name() -> String:
	var t := LanguageManager.t("boss_name")
	if t == "boss_name" or t.strip_edges().is_empty():
		return "Khaled — The Wolf"
	return t


func _ready() -> void:
	# Stats BEFORE super._ready(): it sets current_health = max_health
	# and calls _build_body() (virtual — the override below runs).
	scale = Vector3.ONE * BOSS_SCALE
	max_health = BOSS_MAX_HP
	speed = BOSS_SPEED
	damage = BOSS_HEAVY_DAMAGE
	super._ready()
	_ensure_collision()
	# Citizens flee from group "zombie"; the boss counts as a threat.
	add_to_group("zombie")
	_bar = BossBar.new()
	_bar.name = "BossBar"
	add_child(_bar)
	_bar.show_boss(boss_display_name(), max_health)


func guards_summoned() -> bool:
	return _guards_summoned


func boss_bar() -> BossBar:
	return _bar


func is_charging() -> bool:
	return _state == STATE_CHARGE


func is_winding_up() -> bool:
	return _state == STATE_WINDUP


## Standalone spawn needs a shape: the spawner path adds one itself,
## so only create one when none exists (never two shapes).
func _ensure_collision() -> void:
	for child in get_children():
		if child is CollisionShape3D:
			return
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	col.shape = shape
	col.position.y = 0.9
	add_child(col)


## Boss body. Overrides EnemyAI._build_body() (called by super._ready):
## same skeleton (legs/arms kept in _leg_l/_leg_r/_arm_l/_arm_r so the
## inherited walk pose works), restyled as the gang leader.
func _build_body() -> void:
	if get_node_or_null("Body") != null:
		return
	var body := Node3D.new()
	body.name = "Body"
	add_child(body)
	var suit := StandardMaterial3D.new()
	suit.albedo_color = Color(0.08, 0.08, 0.10)
	suit.roughness = 0.85
	var coat_mat := StandardMaterial3D.new()
	coat_mat.albedo_color = Color(0.05, 0.05, 0.07)
	coat_mat.roughness = 0.9
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.62, 0.46, 0.34)
	skin.roughness = 0.9
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.10, 0.10, 0.11)
	dark.roughness = 0.8
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.75, 0.12, 0.10)
	red.roughness = 0.9
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.85, 0.65, 0.15)
	gold.metallic = 0.7
	gold.roughness = 0.35
	# Long dark coat: a larger, longer box around the torso, open at
	# the bottom so the legs still read when he walks.
	var coat := MeshInstance3D.new()
	var coat_mesh := BoxMesh.new()
	coat_mesh.size = Vector3(0.74, 1.10, 0.46)
	coat_mesh.material = coat_mat
	coat.mesh = coat_mesh
	coat.position.y = 0.72
	body.add_child(coat)
	var torso := MeshInstance3D.new()
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.62, 0.75, 0.34)
	torso_mesh.material = suit
	torso.mesh = torso_mesh
	torso.position.y = 1.05
	body.add_child(torso)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.22
	head_mesh.height = 0.44
	head_mesh.material = skin
	head.mesh = head_mesh
	head.position.y = 1.62
	body.add_child(head)
	# Red headband around the forehead + two hanging tails at the back.
	var band := MeshInstance3D.new()
	var band_mesh := BoxMesh.new()
	band_mesh.size = Vector3(0.48, 0.08, 0.48)
	band_mesh.material = red
	band.mesh = band_mesh
	band.position = Vector3(0, 1.70, 0)
	body.add_child(band)
	for tx in [-0.08, 0.08]:
		var tail := MeshInstance3D.new()
		var tail_mesh := BoxMesh.new()
		tail_mesh.size = Vector3(0.09, 0.28, 0.03)
		tail_mesh.material = red
		tail.mesh = tail_mesh
		tail.position = Vector3(tx, 1.52, -0.25)
		tail.rotation.x = 0.15
		body.add_child(tail)
	# Gold chain (flat band at the neck) + pendant on the chest.
	var chain := MeshInstance3D.new()
	var chain_mesh := BoxMesh.new()
	chain_mesh.size = Vector3(0.50, 0.06, 0.40)
	chain_mesh.material = gold
	chain.mesh = chain_mesh
	chain.position = Vector3(0, 1.44, 0)
	body.add_child(chain)
	var pendant := MeshInstance3D.new()
	var pendant_mesh := BoxMesh.new()
	pendant_mesh.size = Vector3(0.09, 0.13, 0.04)
	pendant_mesh.material = gold
	pendant.mesh = pendant_mesh
	pendant.position = Vector3(0, 1.30, 0.22)
	body.add_child(pendant)
	# Legs, boots, arms, rifle — same layout as a regular enemy.
	for lx in [-0.18, 0.18]:
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.22, 0.65, 0.22)
		leg_mesh.material = suit
		leg.mesh = leg_mesh
		leg.position = Vector3(lx, 0.33, 0)
		body.add_child(leg)
		if lx < 0.0:
			_leg_l = leg
		else:
			_leg_r = leg
		var boot := MeshInstance3D.new()
		var boot_mesh := BoxMesh.new()
		boot_mesh.size = Vector3(0.24, 0.14, 0.34)
		boot_mesh.material = dark
		boot.mesh = boot_mesh
		boot.position = Vector3(lx, 0.07, 0.05)
		body.add_child(boot)
	for ax in [-0.42, 0.42]:
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.16, 0.62, 0.16)
		arm_mesh.material = suit
		arm.mesh = arm_mesh
		arm.position = Vector3(ax, 1.02, 0.05)
		arm.rotation.z = -0.15 if ax < 0.0 else 0.15
		body.add_child(arm)
		if ax < 0.0:
			_arm_l = arm
		else:
			_arm_r = arm
	var gun := MeshInstance3D.new()
	var gun_mesh := BoxMesh.new()
	gun_mesh.size = Vector3(0.08, 0.12, 0.7)
	gun_mesh.material = dark
	gun.mesh = gun_mesh
	gun.position = Vector3(0.25, 1.15, 0.3)
	body.add_child(gun)
	# Name label above his head: billboarded (always faces the
	# player), fixed screen size so it stays readable at range,
	# gold text with a black outline. Arabic gets the Naskh font.
	_label = Label3D.new()
	_label.name = "BossName"
	_label.text = boss_display_name()
	_label.position.y = 2.35
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.font_size = 64
	_label.pixel_size = 0.005
	_label.modulate = Color(1.0, 0.85, 0.45)
	_label.outline_size = 12
	_label.outline_modulate = Color(0.02, 0.0, 0.0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if LanguageManager.current() == "ar":
		var arabic_font := LanguageManager.arabic_font()
		if arabic_font != null:
			_label.font = arabic_font
	body.add_child(_label)


## Boss AI. Replaces the base chase: same gravity / null-target /
## dead-player safety, but with a charge cycle (chase -> 0.6 s wind-up
## stand-still telegraph -> 0.9 s charge at 9.0 -> 2.5 s cooldown)
## and discrete heavy melee (25 dmg, 1.2 s cooldown) instead of the
## base continuous damage-per-second.
func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	if not is_instance_valid(target):
		velocity.x = 0.0
		velocity.z = 0.0
		_set_walk_pose(0.0)
		move_and_slide()
		return
	# Player dead: stop, like regular enemies — no attacking the corpse.
	if target.get("is_dead") == true:
		velocity.x = 0.0
		velocity.z = 0.0
		_state = STATE_CHASE
		_set_walk_pose(0.0)
		move_and_slide()
		return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_charge_cooldown = maxf(0.0, _charge_cooldown - delta)
	var difference: Vector3 = target.global_position - global_position
	var distance := difference.length()
	var direction := Vector3.ZERO
	if distance > 0.1:
		direction = difference.normalized()
		# Face the player (yaw only), whatever the state.
		var flat := Vector3(direction.x, 0.0, direction.z)
		if flat.length() > 0.01:
			rotation.y = atan2(-flat.x, -flat.z)
	match _state:
		STATE_WINDUP:
			# Telegraph: stand still for the wind-up, then charge.
			velocity.x = 0.0
			velocity.z = 0.0
			_set_walk_pose(0.0)
			_state_timer -= delta
			if _state_timer <= 0.0:
				_state = STATE_CHARGE
				_state_timer = BOSS_CHARGE_TIME
		STATE_CHARGE:
			velocity.x = direction.x * BOSS_CHARGE_SPEED
			velocity.z = direction.z * BOSS_CHARGE_SPEED
			_walk_phase += delta * BOSS_CHARGE_SPEED * 2.2
			_set_walk_pose(sin(_walk_phase) * 0.4)
			_state_timer -= delta
			if _state_timer <= 0.0:
				_state = STATE_CHASE
				_charge_cooldown = BOSS_CHARGE_COOLDOWN
		_:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
			_walk_phase += delta * speed * 2.2
			_set_walk_pose(sin(_walk_phase) * 0.4)
			if distance >= BOSS_CHARGE_MIN_RANGE and distance <= BOSS_CHARGE_MAX_RANGE and _charge_cooldown <= 0.0:
				_state = STATE_WINDUP
				_state_timer = BOSS_WINDUP_TIME
	# Heavy melee: one 25-dmg hit, then a 1.2 s cooldown.
	# 4 hits kill a 100-HP player — never a one-shot.
	if distance < BOSS_MELEE_RANGE and _attack_cooldown <= 0.0 and target.has_method("take_damage"):
		target.take_damage(BOSS_HEAVY_DAMAGE)
		_attack_cooldown = BOSS_ATTACK_COOLDOWN
	move_and_slide()


## Boss damage. Mirrors EnemyAI.take_damage() (dead-guard, emit,
## queue_free) plus: bar update, the one-time 50% guard summon, and
## boss_died + bar hide on death.
func take_damage(amount: float) -> void:
	if is_dead:
		return
	current_health -= amount
	if is_instance_valid(_bar):
		_bar.set_hp(current_health)
	if not _guards_summoned and current_health <= max_health * GUARD_SUMMON_FRACTION:
		_summon_guards()
	if current_health <= 0.0:
		current_health = 0.0
		is_dead = true
		if is_instance_valid(_bar):
			_bar.set_hp(0.0)
			_bar.hide_bar()
		boss_died.emit(self)
		enemy_died.emit(self)
		queue_free()


## At 50% HP, summon exactly 2 regular EnemyAI guards near the boss,
## targeting the player, in group "zombie". Only once.
func _summon_guards() -> void:
	_guards_summoned = true
	var parent := get_parent()
	if parent == null:
		return
	for i in range(GUARD_COUNT):
		var guard := EnemyAI.new()
		guard.name = "WolfGuard"
		var col := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = 0.4
		shape.height = 1.8
		col.shape = shape
		col.position.y = 0.9
		guard.add_child(col)
		guard.add_to_group("zombie")
		parent.add_child(guard)
		var angle := (TAU / float(GUARD_COUNT)) * float(i) + 0.6
		guard.global_position = global_position + Vector3(cos(angle) * 2.5, 0.0, sin(angle) * 2.5)
		guard.target = target
		if guard.has_signal("enemy_died"):
			guard.enemy_died.connect(_on_guard_died)


## Guard kills score like regular enemies (the spawner is not involved
## here, so the boss scores them itself).
func _on_guard_died(_enemy: Node) -> void:
	if is_instance_valid(GameManager):
		GameManager.add_kill()
		GameManager.add_score(100)
