extends CharacterBody3D
class_name EnemyAI

signal enemy_died(enemy)

@export var max_health := 85.0
@export var speed := 2.8
@export var damage := 12.0
@export var detection_range := 48.0
@export var attack_range := 1.8
@export var attack_cooldown := 1.25

var current_health := 85.0
var target: Node3D
var is_dead := false
var gravity := 18.0
var attack_timer := 0.0
var hit_flash := 0.0
var gait_phase := 0.0

func _ready() -> void:
	current_health = max_health
	floor_snap_length = 0.45
	floor_stop_on_slope = true
	add_to_group("hostiles")
	add_to_group("zombie")
	if not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player")
	if get_node_or_null("CollisionShape3D") == null:
		var body_shape := CapsuleShape3D.new()
		body_shape.radius = 0.4
		body_shape.height = 1.8
		var body_collision := CollisionShape3D.new()
		body_collision.name = "CollisionShape3D"
		body_collision.shape = body_shape
		add_child(body_collision)
	_build_zombie_visual()

func _physics_process(delta: float) -> void:
	if is_dead: return
	attack_timer = maxf(0.0, attack_timer - delta)
	if not is_on_floor():
		velocity.y = maxf(velocity.y - gravity * delta, -30.0)
	elif velocity.y < 0.0:
		velocity.y = 0.0
	if not is_instance_valid(target):
		velocity.x = move_toward(velocity.x, 0.0, speed*delta*3.0)
		velocity.z = move_toward(velocity.z, 0.0, speed*delta*3.0)
		move_and_slide()
		return
	var offset := target.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance <= detection_range and distance > attack_range:
		var direction := offset.normalized()
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		look_at(Vector3(target.global_position.x, global_position.y, target.global_position.z), Vector3.UP)
		gait_phase += delta * 8.0
	elif distance <= attack_range:
		velocity.x = move_toward(velocity.x,0.0,speed*delta*4.0)
		velocity.z = move_toward(velocity.z,0.0,speed*delta*4.0)
		if attack_timer <= 0.0 and target.has_method("take_damage"):
			target.take_damage(damage)
			attack_timer = attack_cooldown
	else:
		velocity.x = move_toward(velocity.x,0.0,speed*delta)
		velocity.z = move_toward(velocity.z,0.0,speed*delta)
	move_and_slide()
	var left := get_node_or_null("ZombieVisual/LeftLeg")
	var right := get_node_or_null("ZombieVisual/RightLeg")
	if left is Node3D: left.rotation.x = sin(gait_phase) * 0.42
	if right is Node3D: right.rotation.x = -sin(gait_phase) * 0.42

func _build_zombie_visual() -> void:
	var root := Node3D.new()
	root.name = "ZombieVisual"
	root.position.y = -0.9
	add_child(root)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.24, 0.34, 0.25)
	var torn := StandardMaterial3D.new()
	torn.albedo_color = Color(0.12, 0.16, 0.14)
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.24
	head_mesh.height = 0.48
	_add_zombie_part(root, "Head", head_mesh, Vector3(0, 1.63, 0), skin)
	var torso := CapsuleMesh.new()
	torso.radius = 0.34
	torso.height = 0.9
	_add_zombie_part(root, "Torso", torso, Vector3(0, 0.98, 0), torn)
	var arm_mesh := CapsuleMesh.new()
	arm_mesh.radius = 0.12
	arm_mesh.height = 0.72
	_add_zombie_part(root, "LeftArm", arm_mesh, Vector3(-0.43, 1.0, -0.02), skin)
	_add_zombie_part(root, "RightArm", arm_mesh, Vector3(0.43, 1.0, -0.02), skin)
	var leg_mesh := CapsuleMesh.new()
	leg_mesh.radius = 0.14
	leg_mesh.height = 0.78
	_add_zombie_part(root, "LeftLeg", leg_mesh, Vector3(-0.17, 0.38, 0), torn)
	_add_zombie_part(root, "RightLeg", leg_mesh, Vector3(0.17, 0.38, 0), torn)
	var eye := StandardMaterial3D.new()
	eye.albedo_color = Color(0.9, 0.08, 0.025)
	eye.emission_enabled = true
	eye.emission = Color(0.9, 0.025, 0.01)
	var eye_mesh := BoxMesh.new()
	eye_mesh.size = Vector3(0.34, 0.07, 0.08)
	_add_zombie_part(root, "Eyes", eye_mesh, Vector3(0, 1.66, -0.21), eye)

func _add_zombie_part(parent: Node3D, label: String, mesh: Mesh, at: Vector3, material: Material) -> void:
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	visual.material_override = material
	visual.position = at
	parent.add_child(visual)

func take_damage(amount: float) -> void:
	if is_dead: return
	current_health = maxf(0.0,current_health-amount)
	var visual := get_node_or_null("Visual")
	if visual is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.65,0.12,0.09)
		visual.material_override = material
	if current_health <= 0.0:
		is_dead = true
		enemy_died.emit(self)
		GameManager.add_kill()
		queue_free()
