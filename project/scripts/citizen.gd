extends CharacterBody3D

var is_female: bool = false
var variant: int = 0

var axis: int = 0
var city_extent: float = 220.0
var spawn_near_center: bool = false
var spawn_center: Vector3 = Vector3.ZERO
var spawn_radius: float = 55.0
var lane: float = 0.0
var target: Vector3 = Vector3.ZERO
var wait_time: float = 0.0
var gravity: float = 14.0
var walk_phase: float = 0.0
var flee_timer: float = 0.0
var threat_dir: Vector3 = Vector3.ZERO

var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D

var skins = [Color(0.87, 0.70, 0.52), Color(0.76, 0.58, 0.42), Color(0.68, 0.50, 0.36)]
var robe_colors = [
    Color(0.93, 0.90, 0.82), Color(0.80, 0.78, 0.72),
    Color(0.55, 0.42, 0.30), Color(0.35, 0.40, 0.50)
]
var dress_colors = [
    Color(0.20, 0.25, 0.40), Color(0.45, 0.20, 0.30), Color(0.15, 0.40, 0.40),
    Color(0.30, 0.30, 0.30), Color(0.55, 0.35, 0.50)
]
var hijab_colors = [
    Color(0.95, 0.95, 0.95), Color(0.85, 0.40, 0.55), Color(0.20, 0.55, 0.60),
    Color(0.50, 0.30, 0.60), Color(0.15, 0.20, 0.40)
]

func _ready():
    add_to_group("civilian")

    axis = randi() % 2
    floor_snap_length = 0.42
    floor_stop_on_slope = true
    if spawn_near_center:
        lane = (spawn_center.z if axis == 0 else spawn_center.x) + [-3.2, 3.2][randi() % 2]
        position = _lane_point(randf_range(-spawn_radius, spawn_radius))
        target = _lane_point(randf_range(-spawn_radius, spawn_radius))
    else:
        lane = [-160.0, -80.0, 0.0, 80.0, 160.0][randi() % 5] + [-3.2, 3.2][randi() % 2]
        position = _lane_point(randf_range(-city_extent, city_extent))
        target = _lane_point(randf_range(-100.0, 100.0))

    var col = CollisionShape3D.new()
    var cap = CapsuleShape3D.new()
    cap.radius = 0.35
    cap.height = 1.7
    col.shape = cap
    add_child(col)

    _build_model()

func _lane_point(along: float) -> Vector3:
    if axis == 0:
        return Vector3(spawn_center.x + along, 0.9, lane)
    return Vector3(lane, 0.9, spawn_center.z + along)

func _part(mesh: Mesh, color: Color, pos: Vector3, parent: Node3D) -> MeshInstance3D:
    var mi = MeshInstance3D.new()
    mi.mesh = mesh
    var mat = StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = 1.0
    mi.material_override = mat
    mi.position = pos
    parent.add_child(mi)
    return mi

func _build_model():
    var skin = skins[variant % skins.size()]
    var cloth = robe_colors[variant % robe_colors.size()]
    if is_female:
        cloth = dress_colors[variant % dress_colors.size()]

    # Long robe (jebba for men, long dress for women)
    var robe = CylinderMesh.new()
    robe.top_radius = 0.26
    robe.bottom_radius = 0.36
    robe.height = 1.35
    _part(robe, cloth, Vector3(0, -0.175, 0), self)

    var head = SphereMesh.new()
    head.radius = 0.14
    head.height = 0.28

    if is_female:
        var hijab_color = hijab_colors[int(variant / 2) % hijab_colors.size()]
        _part(head, skin, Vector3(0, 0.62, -0.07), self)

        var hood = SphereMesh.new()
        hood.radius = 0.19
        hood.height = 0.40
        _part(hood, hijab_color, Vector3(0, 0.63, 0.03), self)

        var cape = CylinderMesh.new()
        cape.top_radius = 0.28
        cape.bottom_radius = 0.31
        cape.height = 0.5
        _part(cape, hijab_color, Vector3(0, 0.25, 0), self)
    else:
        _part(head, skin, Vector3(0, 0.62, 0), self)

        var cap_mesh = CylinderMesh.new()
        cap_mesh.top_radius = 0.11
        cap_mesh.bottom_radius = 0.13
        cap_mesh.height = 0.16
        var cap_color = Color(0.7, 0.1, 0.1)
        if variant % 3 == 1:
            cap_color = Color(0.95, 0.95, 0.95)
        _part(cap_mesh, cap_color, Vector3(0, 0.78, 0), self)

        if variant % 3 == 2:
            var beard = SphereMesh.new()
            beard.radius = 0.08
            beard.height = 0.16
            _part(beard, Color(0.12, 0.1, 0.1), Vector3(0, 0.56, -0.1), self)

    # Arms
    arm_l = _make_arm(Vector3(-0.30, 0.4, 0), cloth, skin)
    arm_r = _make_arm(Vector3(0.30, 0.4, 0), cloth, skin)
    leg_l = _make_leg(Vector3(-0.14, -0.15, 0), cloth)
    leg_r = _make_leg(Vector3(0.14, -0.15, 0), cloth)

func _make_leg(pos: Vector3, cloth: Color) -> Node3D:
    var pivot = Node3D.new()
    pivot.position = pos
    add_child(pivot)
    var leg = CapsuleMesh.new()
    leg.radius = 0.085
    leg.height = 0.72
    _part(leg, cloth, Vector3(0, -0.30, 0), pivot)
    return pivot

func _make_arm(pos: Vector3, cloth: Color, skin: Color) -> Node3D:
    var pivot = Node3D.new()
    pivot.position = pos
    add_child(pivot)

    var arm = CapsuleMesh.new()
    arm.radius = 0.07
    arm.height = 0.6
    _part(arm, cloth, Vector3(0, -0.28, 0), pivot)

    var hand = SphereMesh.new()
    hand.radius = 0.06
    hand.height = 0.12
    _part(hand, skin, Vector3(0, -0.6, 0), pivot)
    return pivot

func _physics_process(delta):
    if not is_on_floor():
        velocity.y = maxf(velocity.y - gravity * delta, -28.0)
    elif velocity.y < 0.0:
        velocity.y = 0.0

    # Look for zombies nearby
    flee_timer -= delta
    if flee_timer <= 0.0:
        flee_timer = 0.4
        threat_dir = Vector3.ZERO
        for z in get_tree().get_nodes_in_group("zombie"):
            var d = global_position - z.global_position
            d.y = 0.0
            if d.length() < 14.0:
                threat_dir += d.normalized()

    var dir = Vector3.ZERO
    var spd = 1.5

    if threat_dir != Vector3.ZERO:
        spd = 4.2
        if axis == 0:
            dir = Vector3(signf(threat_dir.x), 0, 0)
        else:
            dir = Vector3(0, 0, signf(threat_dir.z))
    else:
        var diff = target - global_position
        diff.y = 0.0
        if wait_time > 0.0:
            wait_time -= delta
        elif diff.length() < 1.2:
            wait_time = randf_range(1.0, 4.0)
            target = _lane_point(randf_range(-100.0, 100.0))
        else:
            dir = diff.normalized()

    velocity.x = dir.x * spd
    velocity.z = dir.z * spd
    move_and_slide()

    if dir != Vector3.ZERO:
        rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), delta * 6.0)
        walk_phase += delta * spd * 3.0
        arm_l.rotation.x = sin(walk_phase) * 0.6
        arm_r.rotation.x = -sin(walk_phase) * 0.6
        leg_l.rotation.x = -sin(walk_phase) * 0.48
        leg_r.rotation.x = sin(walk_phase) * 0.48
    else:
        arm_l.rotation.x = lerpf(arm_l.rotation.x, 0.0, delta * 5.0)
        arm_r.rotation.x = lerpf(arm_r.rotation.x, 0.0, delta * 5.0)
        leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.0, delta * 5.0)
        leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.0, delta * 5.0)
