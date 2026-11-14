extends CharacterBody3D
class_name EnemyAI

signal enemy_died(enemy)

@export var max_health: float = 60.0
@export var speed: float = 3.5
@export var damage: float = 10.0

var current_health: float = 60.0
var target: Node3D = null
var is_dead: bool = false
var gravity: float = 9.8

func _ready():
	current_health = max_health
	_build_body()

func _build_body() -> void:
	# Visible body, built here so a spawner only needs a CharacterBody3D
	# + this script + a collision shape. Shared materials, low poly.
	if get_node_or_null("Body") != null:
		return
	var body := Node3D.new()
	body.name = "Body"
	add_child(body)
	var uniform := StandardMaterial3D.new()
	uniform.albedo_color = Color(0.23, 0.26, 0.20)
	uniform.roughness = 0.9
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.72, 0.55, 0.42)
	skin.roughness = 0.9
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.13)
	dark.roughness = 0.8
	var torso := MeshInstance3D.new()
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.62, 0.75, 0.34)
	torso_mesh.material = uniform
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
	var helmet := MeshInstance3D.new()
	var helmet_mesh := SphereMesh.new()
	helmet_mesh.radius = 0.24
	helmet_mesh.height = 0.48
	helmet_mesh.material = dark
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
	var gun := MeshInstance3D.new()
	var gun_mesh := BoxMesh.new()
	gun_mesh.size = Vector3(0.08, 0.12, 0.7)
	gun_mesh.material = dark
	gun.mesh = gun_mesh
	gun.position = Vector3(0.25, 1.15, 0.3)
	body.add_child(gun)
	# Arms, vest plate and headband stripe — reads at distance.
	var vest_mat := StandardMaterial3D.new()
	vest_mat.albedo_color = Color(0.30, 0.28, 0.20)
	vest_mat.roughness = 0.95
	var vest := MeshInstance3D.new()
	var vest_mesh := BoxMesh.new()
	vest_mesh.size = Vector3(0.5, 0.45, 0.10)
	vest_mesh.material = vest_mat
	vest.mesh = vest_mesh
	vest.position = Vector3(0, 1.10, 0.20)
	body.add_child(vest)
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = Color(0.75, 0.18, 0.12)
	band_mat.roughness = 0.9
	var band := MeshInstance3D.new()
	var band_mesh := BoxMesh.new()
	band_mesh.size = Vector3(0.46, 0.07, 0.46)
	band_mesh.material = band_mat
	band.mesh = band_mesh
	band.position = Vector3(0, 1.70, 0)
	body.add_child(band)
	for ax in [-0.42, 0.42]:
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.16, 0.62, 0.16)
		arm_mesh.material = uniform
		arm.mesh = arm_mesh
		arm.position = Vector3(ax, 1.02, 0.05)
		arm.rotation.z = -0.15 if ax < 0.0 else 0.15
		body.add_child(arm)

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
	else:
		velocity.x = 0
		velocity.z = 0
	if distance < 2.0 and target.has_method("take_damage"):
		target.take_damage(damage * delta)
	move_and_slide()

func take_damage(amount: float):
	if is_dead:
		return
	current_health -= amount
	if current_health <= 0:
		is_dead = true
		enemy_died.emit(self)
		queue_free()
