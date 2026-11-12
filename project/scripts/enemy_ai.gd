extends CharacterBody3D

signal enemy_died(enemy)

@export var max_health: float = 60.0
@export var speed: float = 3.2
@export var damage: float = 12.0
@export var sight_range: float = 45.0

var current_health: float = 60.0
var target = null
var is_dead: bool = false
var gravity: float = 14.0
var walk_phase: float = 0.0
var stuck_timer: float = 0.0
var dodge_timer: float = 0.0
var dodge_sign: float = 1.0
var wander_target: Vector3 = Vector3.ZERO

var arm_l: Node3D
var arm_r: Node3D

func _ready():
    add_to_group("zombie")
    current_health = max_health
    speed = speed * randf_range(0.85, 1.25)
    wander_target = GameManager.random_road_point()

    var col = CollisionShape3D.new()
    var cap = CapsuleShape3D.new()
    cap.radius = 0.38
    cap.height = 1.8
    col.shape = cap
    add_child(col)

    _build_model()

func _part(mesh: Mesh, color: Color, pos: Vector3, parent: Node3D, glow: bool = false) -> MeshInstance3D:
    var mi = MeshInstance3D.new()
    mi.mesh = mesh
    var mat = StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = 1.0
    if glow:
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mi.material_override = mat
    mi.position = pos
    parent.add_child(mi)
    return mi

func _build_model():
    var skin = Color(0.42, 0.58, 0.38)
    var cloth = Color(0.25, 0.27, 0.22)
    var pants = Color(0.16, 0.17, 0.2)

    var torso = BoxMesh.new()
    torso.size = Vector3(0.55, 0.7, 0.3)
    _part(torso, cloth, Vector3(0, 0.25, 0), self)

    for x in [-0.14, 0.14]:
        var leg = BoxMesh.new()
        leg.size = Vector3(0.2, 0.8, 0.22)
        _part(leg, pants, Vector3(x, -0.5, 0), self)

    var head = SphereMesh.new()
    head.radius = 0.17
    head.height = 0.34
    _part(head, skin, Vector3(0, 0.78, 0), self)

    for x in [-0.07, 0.07]:
        var eye = SphereMesh.new()
        eye.radius = 0.03
        eye.height = 0.06
        _part(eye, Color(1.0, 0.1, 0.05), Vector3(x, 0.8, -0.15), self, true)

    arm_l = _make_arm(Vector3(-0.38, 0.5, 0), skin)
    arm_r = _make_arm(Vector3(0.38, 0.5, 0), skin)

func _make_arm(pos: Vector3, skin: Color) -> Node3D:
    var pivot = Node3D.new()
    pivot.position = pos
    pivot.rotation_degrees.x = 80.0
    add_child(pivot)

    var arm = BoxMesh.new()
    arm.size = Vector3(0.14, 0.6, 0.14)
    _part(arm, skin, Vector3(0, -0.3, 0), pivot)
    return pivot

func _physics_process(delta):
    if is_dead:
        return

    if not is_on_floor():
        velocity.y -= gravity * delta

    if not is_instance_valid(target):
        target = get_tree().get_first_node_in_group("player")

    var dir = Vector3.ZERO
    var look_dir = Vector3.ZERO
    var chasing = false
    var biting = false

    if is_instance_valid(target) and not target.is_dead:
        var diff = target.global_position - global_position
        diff.y = 0.0
        var dist = diff.length()
        if dist < sight_range and dist > 0.01:
            chasing = true
            look_dir = diff / dist
            if dist < 1.8:
                biting = true
                if target.has_method("take_damage"):
                    target.take_damage(damage * delta)
            else:
                dir = look_dir

    if not chasing:
        var wdiff = wander_target - global_position
        wdiff.y = 0.0
        if wdiff.length() < 2.0:
            wander_target = GameManager.random_road_point()
        else:
            dir = wdiff.normalized()
        look_dir = dir

    # Simple obstacle dodging
    if dir != Vector3.ZERO and not biting:
        if get_real_velocity().length() < 0.4:
            stuck_timer += delta
            if stuck_timer > 0.8:
                stuck_timer = 0.0
                dodge_timer = 1.0
                dodge_sign = 1.0 if randi() % 2 == 0 else -1.0
        else:
            stuck_timer = 0.0
    if dodge_timer > 0.0:
        dodge_timer -= delta
        dir = dir.rotated(Vector3.UP, dodge_sign * PI / 2.0)

    var spd = speed
    if not chasing:
        spd = speed * 0.4

    velocity.x = dir.x * spd
    velocity.z = dir.z * spd
    move_and_slide()

    if look_dir != Vector3.ZERO:
        rotation.y = lerp_angle(rotation.y, atan2(-look_dir.x, -look_dir.z), delta * 8.0)

    walk_phase += delta * spd * 2.0
    arm_l.rotation.x = deg_to_rad(80.0) + sin(walk_phase) * 0.15
    arm_r.rotation.x = deg_to_rad(80.0) - sin(walk_phase) * 0.15

func take_damage(amount: float):
    if is_dead:
        return
    current_health -= amount
    if current_health <= 0.0:
        _die()

func _die():
    is_dead = true
    remove_from_group("zombie")
    collision_layer = 0
    collision_mask = 0
    GameManager.add_kill()
    enemy_died.emit(self)

    var tween = create_tween()
    tween.tween_property(self, "rotation_degrees:x", 90.0, 0.4)
    tween.tween_interval(1.5)
    tween.tween_callback(queue_free)
