extends CharacterBody3D
signal health_changed(current, maximum)
signal player_died
@export var walk_speed := 5.0
@export var sprint_speed := 8.5
@export var jump_velocity := 4.5
@export var max_health := 100.0
@export var look_sensitivity := 0.0035
var current_health := 100.0
var is_dead := false
var gravity := 9.8
var mobile_move := Vector2.ZERO
var mobile_sprinting := false
var mobile_hud: Control
var is_paused := false
@onready var camera: Camera3D = $Head/Camera3D
func _ready() -> void:
	current_health=max_health
	_create_mobile_hud()
func _create_mobile_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name="MobileHUDLayer"
	layer.layer=10
	get_tree().root.add_child(layer)
	mobile_hud=Control.new()
	mobile_hud.name="MobileHUD"
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
func _on_mobile_move(v: Vector2) -> void: mobile_move=v
func _on_mobile_look(v: Vector2) -> void:
	rotate_y(-v.x*look_sensitivity)
	camera.rotation.x=clampf(camera.rotation.x-v.y*look_sensitivity,deg_to_rad(-80),deg_to_rad(80))
func _on_mobile_jump() -> void:
	if is_on_floor(): velocity.y=jump_velocity
func _on_mobile_fire() -> void:
	var q:=PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position-camera.global_transform.basis.z*100.0)
	q.exclude=[self]
	var hit:=get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit.collider.has_method("take_damage"): hit.collider.take_damage(25.0)
func _on_sprint(v: bool) -> void: mobile_sprinting=v
func _on_pause() -> void:
	is_paused=true
	set_physics_process(false)
	mobile_hud.set_paused(true)
func _on_resume() -> void:
	is_paused=false
	set_physics_process(true)
	mobile_hud.set_paused(false)
func _on_menu() -> void:
	mobile_hud.get_parent().queue_free()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
func _physics_process(delta: float) -> void:
	if is_dead or is_paused: return
	if not is_on_floor(): velocity.y-=gravity*delta
	var input_dir:=mobile_move
	if OS.get_name() not in ["Android","iOS"]:
		input_dir=Input.get_vector("ui_left","ui_right","ui_up","ui_down")
	var direction: Vector3=(transform.basis*Vector3(input_dir.x,0,input_dir.y)).normalized()
	var speed:=sprint_speed if mobile_sprinting or Input.is_action_pressed("ui_accept") else walk_speed
	velocity.x=direction.x*speed
	velocity.z=direction.z*speed
	if OS.get_name() not in ["Android","iOS"] and Input.is_action_just_pressed("ui_select") and is_on_floor():
		velocity.y=jump_velocity
	move_and_slide()
func take_damage(damage: float) -> void:
	if is_dead: return
	current_health=maxf(0.0,current_health-damage)
	health_changed.emit(current_health,max_health)
	if current_health<=0:
		is_dead=true
		player_died.emit()
