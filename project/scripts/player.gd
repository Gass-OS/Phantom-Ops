extends CharacterBody3D

signal health_changed(current, maximum)
signal player_died

@export var walk_speed := 5.4
@export var sprint_speed := 8.7
@export var jump_velocity := 4.8
@export var max_health := 100.0
@export var look_sensitivity := 0.0032

var current_health := 100.0
var is_dead := false
var gravity := 18.0
var mobile_move := Vector2.ZERO
var mobile_sprinting := false
var mobile_hud
var is_paused := false
var fire_cooldown := 0.0
@onready var camera: Camera3D = $Head/Camera3D

func _ready() -> void:
	add_to_group("player")
	current_health = max_health
	_build_player_visual()
	camera.position = Vector3(0, 2.55, 6.2)
	camera.rotation = Vector3(deg_to_rad(-13.0), 0.0, 0.0)
	camera.current = true
	_create_mobile_hud()
	player_died.connect(_on_player_died)

func _build_player_visual() -> void:
	if has_node("SoldierVisual"):
		return
	var root := Node3D.new()
	root.name = "SoldierVisual"
	add_child(root)
	var uniform := StandardMaterial3D.new()
	uniform.albedo_color = Color(0.12, 0.19, 0.22)
	uniform.roughness = 0.82
	var armor := StandardMaterial3D.new()
	armor.albedo_color = Color(0.22, 0.29, 0.29)
	armor.metallic = 0.12
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.58, 0.39, 0.27)
	var boots := StandardMaterial3D.new()
	boots.albedo_color = Color(0.045, 0.055, 0.06)
	_add_capsule(root, "Torso", 0.66, 0.92, Vector3(0, 0.98, 0), uniform)
	_add_capsule(root, "Head", 0.25, 0.34, Vector3(0, 1.65, 0), skin)
	_add_capsule(root, "Vest", 0.70, 0.64, Vector3(0, 1.04, -0.035), armor)
	_add_box(root, "LeftLeg", Vector3(0.24, 0.72, 0.28), Vector3(-0.19, 0.38, 0), uniform)
	_add_box(root, "RightLeg", Vector3(0.24, 0.72, 0.28), Vector3(0.19, 0.38, 0), uniform)
	_add_box(root, "LeftBoot", Vector3(0.27, 0.16, 0.42), Vector3(-0.19, 0.08, -0.07), boots)
	_add_box(root, "RightBoot", Vector3(0.27, 0.16, 0.42), Vector3(0.19, 0.08, -0.07), boots)
	_add_capsule(root, "LeftArm", 0.13, 0.70, Vector3(-0.43, 1.04, -0.02), uniform)
	_add_capsule(root, "RightArm", 0.13, 0.70, Vector3(0.43, 1.04, -0.02), uniform)
	var visor := StandardMaterial3D.new()
	visor.albedo_color = Color(0.035, 0.07, 0.085)
	_add_box(root, "HelmetVisor", Vector3(0.40, 0.10, 0.29), Vector3(0, 1.76, -0.045), visor)

func _add_capsule(parent: Node3D, node_name: String, radius: float, height: float, pos: Vector3, mat: Material) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.material = mat
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.mesh = mesh
	visual.position = pos
	parent.add_child(visual)

func _add_box(parent: Node3D, node_name: String, dimensions: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	mesh.material = mat
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.mesh = mesh
	visual.position = pos
	parent.add_child(visual)

func _create_mobile_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MobileHUDLayer"
	layer.layer = 10
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(layer)
	mobile_hud = Control.new()
	mobile_hud.name = "MobileHUD"
	mobile_hud.set_script(load("res://scripts/mobile_hud.gd"))
	layer.add_child(mobile_hud)
	mobile_hud.move_changed.connect(_on_mobile_move)
	mobile_hud.look_delta.connect(_on_mobile_look)
	mobile_hud.jump_pressed.connect(_on_mobile_jump)
	mobile_hud.fire_pressed.connect(_on_mobile_fire)
	mobile_hud.pause_pressed.connect(_on_pause)
	mobile_hud.resume_pressed.connect(_on_resume)
	mobile_hud.menu_pressed.connect(_on_menu)
	mobile_hud.sprint_changed.connect(_on_sprint)

func _on_mobile_move(value: Vector2) -> void: mobile_move = value
func _on_mobile_look(value: Vector2) -> void:
	rotate_y(-value.x * look_sensitivity)
	camera.rotation.x = clampf(camera.rotation.x - value.y * look_sensitivity, deg_to_rad(-65), deg_to_rad(28))
func _on_mobile_jump() -> void:
	if is_on_floor(): velocity.y = jump_velocity
func _on_mobile_fire() -> void:
	if fire_cooldown > 0.0: return
	fire_cooldown = 0.22
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_transform.basis.z * 95.0)
	query.exclude = [self]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var target = hit.get("collider")
		if target != null and target.has_method("take_damage"):
			target.take_damage(34.0)
func _on_sprint(value: bool) -> void: mobile_sprinting = value
func _on_pause() -> void:
	is_paused = true
	set_physics_process(false)
	mobile_hud.set_paused(true)
func _on_resume() -> void:
	is_paused = false
	set_physics_process(true)
	mobile_hud.set_paused(false)
func _on_menu() -> void:
	if is_instance_valid(mobile_hud) and mobile_hud.get_parent() != null:
		mobile_hud.get_parent().queue_free()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _physics_process(delta: float) -> void:
	if is_dead or is_paused: return
	fire_cooldown = maxf(0.0, fire_cooldown-delta)
	if not is_on_floor(): velocity.y -= gravity * delta
	var input_dir := mobile_move
	if OS.get_name() not in ["Android","iOS"]:
		input_dir = Input.get_vector("ui_left","ui_right","ui_up","ui_down")
	var direction := (transform.basis * Vector3(input_dir.x,0,input_dir.y)).normalized()
	var speed := sprint_speed if mobile_sprinting or Input.is_action_pressed("ui_accept") else walk_speed
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if OS.get_name() not in ["Android","iOS"] and Input.is_action_just_pressed("ui_select") and is_on_floor():
		velocity.y = jump_velocity
	move_and_slide()

func take_damage(amount: float) -> void:
	if is_dead: return
	current_health = maxf(0.0,current_health-amount)
	health_changed.emit(current_health,max_health)
	if current_health <= 0.0:
		is_dead = true
		player_died.emit()

func _on_player_died() -> void:
	if is_instance_valid(mobile_hud):
		mobile_hud.set_paused(true)
