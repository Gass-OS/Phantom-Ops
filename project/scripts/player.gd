extends CharacterBody3D

signal health_changed(current, maximum)
signal player_died

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 5.5
@export var max_health: float = 100.0
@export var look_sensitivity: float = 0.004

var current_health: float = 100.0
var is_dead: bool = false
var gravity: float = 14.0

var mobile_move: Vector2 = Vector2.ZERO
var mobile_look: Vector2 = Vector2.ZERO
var jump_requested: bool = false
var shoot_held: bool = false
var fire_cooldown: float = 0.0
var muzzle_timer: float = 0.0

var head: Node3D
var camera: Camera3D
var muzzle: MeshInstance3D

func _ready():
    add_to_group("player")
    current_health = max_health

    var col = CollisionShape3D.new()
    var cap = CapsuleShape3D.new()
    cap.radius = 0.4
    cap.height = 1.8
    col.shape = cap
    add_child(col)

    head = Node3D.new()
    head.position = Vector3(0, 0.65, 0)
    add_child(head)

    camera = Camera3D.new()
    camera.fov = 75.0
    camera.far = 400.0
    head.add_child(camera)
    camera.make_current()

    var gun = MeshInstance3D.new()
    var gun_mesh = BoxMesh.new()
    gun_mesh.size = Vector3(0.08, 0.12, 0.5)
    var gun_mat = StandardMaterial3D.new()
    gun_mat.albedo_color = Color(0.1, 0.1, 0.12)
    gun_mesh.material = gun_mat
    gun.mesh = gun_mesh
    gun.position = Vector3(0.25, -0.25, -0.6)
    camera.add_child(gun)

    muzzle = MeshInstance3D.new()
    var flash = SphereMesh.new()
    flash.radius = 0.08
    flash.height = 0.16
    var flash_mat = StandardMaterial3D.new()
    flash_mat.albedo_color = Color(1.0, 0.8, 0.2)
    flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    flash.material = flash_mat
    muzzle.mesh = flash
    muzzle.position = Vector3(0, 0, -0.35)
    muzzle.visible = false
    gun.add_child(muzzle)

func _physics_process(delta):
    if is_dead:
        return

    var on_phone = OS.get_name() in ["Android", "iOS"]

    # Look
    if mobile_look != Vector2.ZERO:
        rotate_y(-mobile_look.x * look_sensitivity)
        head.rotation.x = clampf(
            head.rotation.x - mobile_look.y * look_sensitivity, -1.2, 1.2
        )
        mobile_look = Vector2.ZERO

    if not is_on_floor():
        velocity.y -= gravity * delta

    # Move
    var input_dir = mobile_move
    if not on_phone:
        input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

    var direction = transform.basis * Vector3(input_dir.x, 0, input_dir.y)
    if direction.length() > 1.0:
        direction = direction.normalized()

    var speed = walk_speed
    if on_phone:
        if input_dir.length() > 0.92:
            speed = sprint_speed
    elif Input.is_action_pressed("ui_accept"):
        speed = sprint_speed

    velocity.x = direction.x * speed
    velocity.z = direction.z * speed

    # Jump
    if (jump_requested or Input.is_action_just_pressed("ui_select")) and is_on_floor():
        velocity.y = jump_velocity
    jump_requested = false

    move_and_slide()

    # Shoot
    fire_cooldown -= delta
    var want_fire = shoot_held
    if not on_phone and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
        want_fire = true
    if want_fire and fire_cooldown <= 0.0:
        _shoot(on_phone)
        fire_cooldown = 0.18

    if muzzle_timer > 0.0:
        muzzle_timer -= delta
        if muzzle_timer <= 0.0:
            muzzle.visible = false

func _shoot(on_phone: bool):
    muzzle.visible = true
    muzzle_timer = 0.05
    if on_phone:
        Input.vibrate_handheld(15)

    var from = camera.global_position
    var to = from - camera.global_transform.basis.z * 80.0
    var query = PhysicsRayQueryParameters3D.create(from, to)
    query.exclude = [get_rid()]
    var result = get_world_3d().direct_space_state.intersect_ray(query)
    if result.has("collider"):
        var hit = result["collider"]
        if hit != null and hit.has_method("take_damage"):
            hit.take_damage(25.0)

func take_damage(amount: float):
    if is_dead:
        return
    current_health = maxf(0.0, current_health - amount)
    health_changed.emit(current_health, max_health)
    if current_health <= 0.0:
        is_dead = true
        player_died.emit()
