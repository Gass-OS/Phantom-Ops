#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

cd "$HOME/Phantom-Ops"

echo "=== PHANTOM OPS UPDATE v2 ==="

mkdir -p .github/workflows project/scenes project/scripts build
rm -f .github/workflows/blank.yml

# ---------------------------------------------------------------
# 1. project.godot  (compatibility renderer, 1280x720, landscape)
# ---------------------------------------------------------------
cat > project/project.godot <<'EOF'
config_version=5

[application]
config/name="Phantom Ops"
run/main_scene="res://scenes/main_menu.tscn"
config/features=PackedStringArray("4.2", "GL Compatibility")

[autoload]
GameManager="*res://scripts/game_manager.gd"

[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
window/handheld/orientation=4

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
EOF

# ---------------------------------------------------------------
# 2. Game manager (autoload)
# ---------------------------------------------------------------
cat > project/scripts/game_manager.gd <<'EOF'
extends Node

signal stats_changed

var score: int = 0
var kills: int = 0
var wave: int = 1

func add_score(points: int):
    score += points
    stats_changed.emit()

func add_kill():
    kills += 1
    add_score(100)

func reset_game():
    score = 0
    kills = 0
    wave = 1
    stats_changed.emit()

func random_road_point() -> Vector3:
    var lines = [-45.0, 0.0, 45.0]
    var line = lines[randi() % 3]
    var along = randf_range(-100.0, 100.0)
    var p = Vector3(line + randf_range(-3.0, 3.0), 1.0, along)
    if randi() % 2 == 0:
        p = Vector3(along, 1.0, line + randf_range(-3.0, 3.0))
    if Vector2(p.x, p.z).length() < 6.0:
        p.z += 12.0
    return p
EOF

# ---------------------------------------------------------------
# 3. Player (builds its own camera, gun, collision)
# ---------------------------------------------------------------
cat > project/scripts/player.gd <<'EOF'
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
EOF

# ---------------------------------------------------------------
# 4. City: textured ground, roads, buildings WITH WINDOWS, minaret, palms
# ---------------------------------------------------------------
cat > project/scripts/kasserine_city_generator.gd <<'EOF'
extends Node3D

const ROAD_LINES = [-45.0, 0.0, 45.0]
const CELLS = [-60.0, -30.0, 30.0, 60.0]

var wall_colors = [
    Color(0.85, 0.76, 0.60),
    Color(0.92, 0.88, 0.80),
    Color(0.80, 0.62, 0.45),
    Color(0.88, 0.82, 0.70),
    Color(0.75, 0.68, 0.58)
]
var glass_mat: StandardMaterial3D
var lit_mat: StandardMaterial3D

func _ready():
    randomize()

    glass_mat = StandardMaterial3D.new()
    glass_mat.albedo_color = Color(0.12, 0.18, 0.26)
    glass_mat.roughness = 0.2
    glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

    lit_mat = StandardMaterial3D.new()
    lit_mat.albedo_color = Color(1.0, 0.85, 0.45)
    lit_mat.emission_enabled = true
    lit_mat.emission = Color(1.0, 0.8, 0.35)
    lit_mat.emission_energy_multiplier = 1.4
    lit_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

    _build_ground()
    _build_roads()
    _build_buildings()
    _build_minaret()
    _build_palms()
    _build_walls()

# ---------- ground ----------
func _build_ground():
    var ground = StaticBody3D.new()
    ground.name = "Ground"

    var grad = Gradient.new()
    grad.set_color(0, Color(0.90, 0.80, 0.62))
    grad.set_color(1, Color(0.68, 0.56, 0.38))

    var noise = FastNoiseLite.new()
    noise.frequency = 0.04

    var tex = NoiseTexture2D.new()
    tex.width = 512
    tex.height = 512
    tex.seamless = true
    tex.noise = noise
    tex.color_ramp = grad

    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(1, 1, 1)
    mat.albedo_texture = tex
    mat.uv1_scale = Vector3(25, 25, 1)
    mat.roughness = 1.0

    var plane = PlaneMesh.new()
    plane.size = Vector2(260, 260)
    plane.material = mat

    var mesh_instance = MeshInstance3D.new()
    mesh_instance.mesh = plane
    ground.add_child(mesh_instance)

    var col = CollisionShape3D.new()
    var shape = BoxShape3D.new()
    shape.size = Vector3(260, 1.0, 260)
    col.shape = shape
    col.position.y = -0.5
    ground.add_child(col)

    add_child(ground)

# ---------- roads ----------
func _add_flat_box(size: Vector3, pos: Vector3, mat: Material):
    var mi = MeshInstance3D.new()
    var box = BoxMesh.new()
    box.size = size
    box.material = mat
    mi.mesh = box
    mi.position = pos
    add_child(mi)

func _build_roads():
    var road_mat = StandardMaterial3D.new()
    road_mat.albedo_color = Color(0.22, 0.22, 0.24)
    road_mat.roughness = 0.9

    var line_mat = StandardMaterial3D.new()
    line_mat.albedo_color = Color(0.95, 0.85, 0.3)
    line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

    for line in ROAD_LINES:
        _add_flat_box(Vector3(10, 0.06, 240), Vector3(line, 0.03, 0), road_mat)
        _add_flat_box(Vector3(240, 0.06, 10), Vector3(0, 0.03, line), road_mat)
        _add_flat_box(Vector3(0.25, 0.02, 240), Vector3(line, 0.07, 0), line_mat)
        _add_flat_box(Vector3(240, 0.02, 0.25), Vector3(0, 0.07, line), line_mat)

# ---------- buildings ----------
func _build_buildings():
    var index = 0
    for cx in CELLS:
        for cz in CELLS:
            var pos = Vector3(
                cx + randf_range(-3.0, 3.0), 0.0, cz + randf_range(-3.0, 3.0)
            )
            _create_building(index, pos)
            index += 1

func _create_building(index: int, pos: Vector3):
    var sx = randf_range(9.0, 14.0)
    var sy = randf_range(7.0, 16.0)
    var sz = randf_range(9.0, 14.0)

    var building = StaticBody3D.new()
    building.name = "Building_%02d" % index
    building.position = pos

    var wall = StandardMaterial3D.new()
    wall.albedo_color = wall_colors[randi() % wall_colors.size()]
    wall.roughness = 1.0

    var box = BoxMesh.new()
    box.size = Vector3(sx, sy, sz)
    box.material = wall

    var mesh_instance = MeshInstance3D.new()
    mesh_instance.mesh = box
    mesh_instance.position.y = sy / 2.0
    building.add_child(mesh_instance)

    var collision = CollisionShape3D.new()
    var shape = BoxShape3D.new()
    shape.size = box.size
    collision.shape = shape
    collision.position.y = sy / 2.0
    building.add_child(collision)

    # Roof parapet
    var roof_mat = StandardMaterial3D.new()
    roof_mat.albedo_color = Color(0.95, 0.93, 0.88)
    var roof = BoxMesh.new()
    roof.size = Vector3(sx + 0.4, 0.5, sz + 0.4)
    roof.material = roof_mat
    var roof_instance = MeshInstance3D.new()
    roof_instance.mesh = roof
    roof_instance.position.y = sy + 0.25
    building.add_child(roof_instance)

    _add_windows(building, sx, sy, sz)
    add_child(building)

func _add_windows(building: Node3D, sx: float, sy: float, sz: float):
    var dark = SurfaceTool.new()
    dark.begin(Mesh.PRIMITIVE_TRIANGLES)
    dark.set_material(glass_mat)

    var lit = SurfaceTool.new()
    lit.begin(Mesh.PRIMITIVE_TRIANGLES)
    lit.set_material(lit_mat)

    var dark_count = 0
    var lit_count = 0

    var normals = [
        Vector3(0, 0, 1), Vector3(0, 0, -1),
        Vector3(1, 0, 0), Vector3(-1, 0, 0)
    ]

    for n in normals:
        var half_depth = sz / 2.0
        var width = sx
        if absf(n.x) > 0.5:
            half_depth = sx / 2.0
            width = sz

        var right = Vector3.UP.cross(n)
        var cols = int((width - 1.5) / 3.0)
        var rows = int((sy - 2.5) / 3.2)

        for row in range(rows):
            for col in range(cols):
                var offset = (col - (cols - 1) / 2.0) * 3.0
                var y = 2.8 + row * 3.2
                var center = n * (half_depth + 0.03) + right * offset + Vector3(0, y, 0)
                if randf() < 0.3:
                    _add_quad(lit, center, right, n, 1.2, 1.6)
                    lit_count += 1
                else:
                    _add_quad(dark, center, right, n, 1.2, 1.6)
                    dark_count += 1

    if dark_count > 0:
        var dark_instance = MeshInstance3D.new()
        dark_instance.mesh = dark.commit()
        building.add_child(dark_instance)
    if lit_count > 0:
        var lit_instance = MeshInstance3D.new()
        lit_instance.mesh = lit.commit()
        building.add_child(lit_instance)

func _add_quad(st: SurfaceTool, center: Vector3, right: Vector3, normal: Vector3, w: float, h: float):
    var rx = right * (w / 2.0)
    var uy = Vector3.UP * (h / 2.0)
    var a = center - rx - uy
    var b = center + rx - uy
    var c = center + rx + uy
    var d = center - rx + uy
    for v in [a, b, c, a, c, d]:
        st.set_normal(normal)
        st.add_vertex(v)

# ---------- minaret in the middle of the crossroads ----------
func _build_minaret():
    var tower = StaticBody3D.new()
    tower.name = "Minaret"

    var white = StandardMaterial3D.new()
    white.albedo_color = Color(0.95, 0.94, 0.9)
    var green = StandardMaterial3D.new()
    green.albedo_color = Color(0.1, 0.5, 0.35)

    var shaft_mesh = CylinderMesh.new()
    shaft_mesh.top_radius = 1.5
    shaft_mesh.bottom_radius = 2.0
    shaft_mesh.height = 26.0
    shaft_mesh.material = white
    var shaft = MeshInstance3D.new()
    shaft.mesh = shaft_mesh
    shaft.position.y = 13.0
    tower.add_child(shaft)

    var balcony_mesh = CylinderMesh.new()
    balcony_mesh.top_radius = 2.4
    balcony_mesh.bottom_radius = 2.4
    balcony_mesh.height = 0.6
    balcony_mesh.material = green
    var balcony = MeshInstance3D.new()
    balcony.mesh = balcony_mesh
    balcony.position.y = 22.0
    tower.add_child(balcony)

    var cap_mesh = CylinderMesh.new()
    cap_mesh.top_radius = 0.0
    cap_mesh.bottom_radius = 2.2
    cap_mesh.height = 4.5
    cap_mesh.material = green
    var cap = MeshInstance3D.new()
    cap.mesh = cap_mesh
    cap.position.y = 28.3
    tower.add_child(cap)

    var col = CollisionShape3D.new()
    var shape = CylinderShape3D.new()
    shape.radius = 2.0
    shape.height = 26.0
    col.shape = shape
    col.position.y = 13.0
    tower.add_child(col)

    add_child(tower)

# ---------- palm trees along the two main roads ----------
func _build_palms():
    var trunk_mat = StandardMaterial3D.new()
    trunk_mat.albedo_color = Color(0.45, 0.32, 0.2)
    var leaf_mat = StandardMaterial3D.new()
    leaf_mat.albedo_color = Color(0.2, 0.5, 0.22)
    leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

    for i in range(-7, 8):
        var along = i * 14.0
        if absf(along) < 9.0 or absf(absf(along) - 45.0) < 8.0:
            continue
        for side in [-6.2, 6.2]:
            _make_palm(Vector3(side, 0, along), trunk_mat, leaf_mat)
            _make_palm(Vector3(along, 0, side), trunk_mat, leaf_mat)

func _make_palm(pos: Vector3, trunk_mat: Material, leaf_mat: Material):
    var palm = Node3D.new()
    palm.position = pos

    var trunk_mesh = CylinderMesh.new()
    trunk_mesh.top_radius = 0.18
    trunk_mesh.bottom_radius = 0.28
    trunk_mesh.height = 6.5
    trunk_mesh.material = trunk_mat
    var trunk = MeshInstance3D.new()
    trunk.mesh = trunk_mesh
    trunk.position.y = 3.25
    palm.add_child(trunk)

    for i in range(6):
        var pivot = Node3D.new()
        pivot.position = Vector3(0, 6.4, 0)
        pivot.rotation_degrees.y = i * 60.0
        palm.add_child(pivot)

        var frond_mesh = BoxMesh.new()
        frond_mesh.size = Vector3(0.6, 0.06, 3.4)
        frond_mesh.material = leaf_mat
        var frond = MeshInstance3D.new()
        frond.mesh = frond_mesh
        frond.position = Vector3(0, -0.3, -1.5)
        frond.rotation_degrees.x = -18.0
        pivot.add_child(frond)

    add_child(palm)

# ---------- invisible walls at the edge of the map ----------
func _build_walls():
    _add_wall(Vector3(0, 5, 125), Vector3(260, 10, 2))
    _add_wall(Vector3(0, 5, -125), Vector3(260, 10, 2))
    _add_wall(Vector3(125, 5, 0), Vector3(2, 10, 260))
    _add_wall(Vector3(-125, 5, 0), Vector3(2, 10, 260))

func _add_wall(pos: Vector3, size: Vector3):
    var body = StaticBody3D.new()
    body.position = pos
    var col = CollisionShape3D.new()
    var shape = BoxShape3D.new()
    shape.size = size
    col.shape = shape
    body.add_child(col)
    add_child(body)
EOF

# ---------------------------------------------------------------
# 5. Weather: sky, fog, rain, sandstorm, changes every ~1 minute
# ---------------------------------------------------------------
cat > project/scripts/weather.gd <<'EOF'
extends Node3D

enum State { CLEAR, FOG, RAIN, SANDSTORM }

var state = State.CLEAR
var label_text: String = "Clear"
var timer: float = 25.0

var env: Environment
var sun: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var rain: CPUParticles3D
var dust: CPUParticles3D
var player = null

var t_fog_density: float = 0.002
var t_fog_color: Color = Color(0.85, 0.78, 0.65)
var t_light: float = 1.2
var t_sky_top: Color = Color(0.25, 0.5, 0.85)
var t_sky_horizon: Color = Color(0.75, 0.82, 0.9)

func _ready():
    randomize()
    add_to_group("weather")

    sky_mat = ProceduralSkyMaterial.new()
    var sky = Sky.new()
    sky.sky_material = sky_mat

    env = Environment.new()
    env.background_mode = Environment.BG_SKY
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_energy = 1.0
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.fog_enabled = true

    var we = WorldEnvironment.new()
    we.environment = env
    add_child(we)

    sun = DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-50, 35, 0)
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 80.0
    add_child(sun)

    # Rain
    rain = CPUParticles3D.new()
    rain.amount = 600
    rain.lifetime = 1.1
    rain.preprocess = 1.0
    rain.emitting = false
    rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
    rain.emission_box_extents = Vector3(25, 0.5, 25)
    rain.direction = Vector3(0.1, -1, 0)
    rain.spread = 3.0
    rain.gravity = Vector3(0, -25, 0)
    rain.initial_velocity_min = 12.0
    rain.initial_velocity_max = 16.0
    var drop = BoxMesh.new()
    drop.size = Vector3(0.02, 0.6, 0.02)
    var drop_mat = StandardMaterial3D.new()
    drop_mat.albedo_color = Color(0.7, 0.8, 1.0, 0.6)
    drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    drop.material = drop_mat
    rain.mesh = drop
    add_child(rain)

    # Sand / dust
    dust = CPUParticles3D.new()
    dust.amount = 400
    dust.lifetime = 1.8
    dust.preprocess = 1.0
    dust.emitting = false
    dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
    dust.emission_box_extents = Vector3(2, 5, 25)
    dust.direction = Vector3(1, 0.05, 0.1)
    dust.spread = 8.0
    dust.gravity = Vector3.ZERO
    dust.initial_velocity_min = 18.0
    dust.initial_velocity_max = 26.0
    var grain = BoxMesh.new()
    grain.size = Vector3(0.12, 0.12, 0.5)
    var grain_mat = StandardMaterial3D.new()
    grain_mat.albedo_color = Color(0.8, 0.65, 0.4, 0.5)
    grain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    grain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    grain.material = grain_mat
    dust.mesh = grain
    add_child(dust)

    _set_state(State.CLEAR, true)
    timer = 25.0

func _set_state(new_state, instant: bool = false):
    state = new_state
    timer = randf_range(45.0, 75.0)
    rain.emitting = false
    dust.emitting = false

    match state:
        State.CLEAR:
            label_text = "Clear"
            t_fog_density = 0.002
            t_fog_color = Color(0.85, 0.78, 0.65)
            t_light = 1.2
            t_sky_top = Color(0.25, 0.5, 0.85)
            t_sky_horizon = Color(0.75, 0.82, 0.9)
        State.FOG:
            label_text = "Fog"
            t_fog_density = 0.02
            t_fog_color = Color(0.75, 0.77, 0.8)
            t_light = 0.6
            t_sky_top = Color(0.55, 0.6, 0.68)
            t_sky_horizon = Color(0.7, 0.72, 0.75)
        State.RAIN:
            label_text = "Rain"
            t_fog_density = 0.008
            t_fog_color = Color(0.45, 0.5, 0.55)
            t_light = 0.45
            t_sky_top = Color(0.3, 0.35, 0.42)
            t_sky_horizon = Color(0.45, 0.5, 0.55)
            rain.emitting = true
        State.SANDSTORM:
            label_text = "Sandstorm"
            t_fog_density = 0.03
            t_fog_color = Color(0.78, 0.6, 0.35)
            t_light = 0.7
            t_sky_top = Color(0.7, 0.55, 0.35)
            t_sky_horizon = Color(0.8, 0.65, 0.4)
            dust.emitting = true

    if instant:
        env.fog_density = t_fog_density
        env.fog_light_color = t_fog_color
        sun.light_energy = t_light
        _set_sky(t_sky_top, t_sky_horizon)

func _set_sky(top: Color, horizon: Color):
    sky_mat.sky_top_color = top
    sky_mat.sky_horizon_color = horizon
    sky_mat.ground_horizon_color = horizon
    sky_mat.ground_bottom_color = horizon.darkened(0.3)

func _process(delta):
    if not is_instance_valid(player):
        player = get_tree().get_first_node_in_group("player")
    else:
        rain.global_position = player.global_position + Vector3(0, 18, 0)
        dust.global_position = player.global_position + Vector3(-14, 3, 0)

    timer -= delta
    if timer <= 0.0:
        var next = randi() % 4
        if next == state:
            next = (next + 1) % 4
        _set_state(next)

    var k = clampf(delta * 0.5, 0.0, 1.0)
    env.fog_density = lerpf(env.fog_density, t_fog_density, k)
    env.fog_light_color = env.fog_light_color.lerp(t_fog_color, k)
    sun.light_energy = lerpf(sun.light_energy, t_light, k)
    _set_sky(
        sky_mat.sky_top_color.lerp(t_sky_top, k),
        sky_mat.sky_horizon_color.lerp(t_sky_horizon, k)
    )
EOF

# ---------------------------------------------------------------
# 6. Citizens (men and women) walking along the roads
# ---------------------------------------------------------------
cat > project/scripts/citizen.gd <<'EOF'
extends CharacterBody3D

var is_female: bool = false
var variant: int = 0

var axis: int = 0
var lane: float = 0.0
var target: Vector3 = Vector3.ZERO
var wait_time: float = 0.0
var gravity: float = 14.0
var walk_phase: float = 0.0
var flee_timer: float = 0.0
var threat_dir: Vector3 = Vector3.ZERO

var arm_l: Node3D
var arm_r: Node3D

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
    lane = [-45.0, 0.0, 45.0][randi() % 3] + [-3.2, 3.2][randi() % 2]
    position = _lane_point(randf_range(-100.0, 100.0))
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
        return Vector3(along, 1.0, lane)
    return Vector3(lane, 1.0, along)

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
        velocity.y -= gravity * delta

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
    else:
        arm_l.rotation.x = lerpf(arm_l.rotation.x, 0.0, delta * 5.0)
        arm_r.rotation.x = lerpf(arm_r.rotation.x, 0.0, delta * 5.0)
EOF

# ---------------------------------------------------------------
# 7. Zombie
# ---------------------------------------------------------------
cat > project/scripts/enemy_ai.gd <<'EOF'
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
EOF

# ---------------------------------------------------------------
# 8. Spawner (citizens at start, zombie waves)
# ---------------------------------------------------------------
cat > project/scripts/world_spawner.gd <<'EOF'
extends Node

const CitizenScript = preload("res://scripts/citizen.gd")
const ZombieScript = preload("res://scripts/enemy_ai.gd")

var player = null
var spawn_timer: float = 4.0
var max_zombies: int = 8

func _ready():
    call_deferred("_spawn_initial")

func _spawn_initial():
    for i in range(16):
        var c = CitizenScript.new()
        c.is_female = (i % 2 == 1)
        c.variant = i
        get_parent().add_child(c)
    for i in range(3):
        _spawn_zombie()

func _process(delta):
    if not is_instance_valid(player) or player.is_dead:
        return

    var new_wave = 1 + int(GameManager.kills / 8.0)
    if new_wave != GameManager.wave:
        GameManager.wave = new_wave
        max_zombies = 6 + new_wave * 2
        GameManager.stats_changed.emit()

    spawn_timer -= delta
    if spawn_timer <= 0.0:
        spawn_timer = maxf(2.0, 7.0 - GameManager.wave * 0.4)
        if get_tree().get_nodes_in_group("zombie").size() < max_zombies:
            _spawn_zombie()

func _spawn_zombie():
    var p = GameManager.random_road_point()
    if is_instance_valid(player):
        for i in range(10):
            if p.distance_to(player.global_position) > 28.0:
                break
            p = GameManager.random_road_point()
    var z = ZombieScript.new()
    z.max_health = 50.0 + GameManager.wave * 10.0
    z.position = p
    get_parent().add_child(z)
EOF

# ---------------------------------------------------------------
# 9. HUD (health, score, weather, death screen)
# ---------------------------------------------------------------
cat > project/scripts/hud.gd <<'EOF'
extends CanvasLayer

const TouchScript = preload("res://scripts/touch_controls.gd")

var player = null
var health_bar: ProgressBar
var stats_label: Label
var weather_label: Label
var death_panel: ColorRect
var flash: ColorRect

func _make_label(pos: Vector2, size_px: int) -> Label:
    var l = Label.new()
    l.position = pos
    l.add_theme_font_size_override("font_size", size_px)
    l.add_theme_color_override("font_outline_color", Color.BLACK)
    l.add_theme_constant_override("outline_size", 8)
    add_child(l)
    return l

func _ready():
    layer = 10

    flash = ColorRect.new()
    flash.color = Color(0.8, 0.0, 0.0, 0.0)
    flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(flash)
    flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    health_bar = ProgressBar.new()
    health_bar.min_value = 0
    health_bar.max_value = 100
    health_bar.value = 100
    health_bar.show_percentage = false
    health_bar.position = Vector2(30, 24)
    health_bar.size = Vector2(380, 36)
    add_child(health_bar)

    stats_label = _make_label(Vector2(30, 68), 32)
    weather_label = _make_label(Vector2(30, 112), 28)

    if DisplayServer.is_touchscreen_available():
        var touch = TouchScript.new()
        touch.player = player
        add_child(touch)
        touch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    _build_death_panel()

    GameManager.stats_changed.connect(_update_stats)
    _update_stats()

    if player != null:
        player.health_changed.connect(_on_health)
        player.player_died.connect(_on_died)

func _build_death_panel():
    death_panel = ColorRect.new()
    death_panel.color = Color(0, 0, 0, 0.65)
    death_panel.visible = false
    add_child(death_panel)
    death_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var center = CenterContainer.new()
    death_panel.add_child(center)
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var box = VBoxContainer.new()
    box.add_theme_constant_override("separation", 28)
    center.add_child(box)

    var title = Label.new()
    title.text = "YOU DIED"
    title.add_theme_font_size_override("font_size", 100)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(title)

    var again = Button.new()
    again.text = "RESTART"
    again.custom_minimum_size = Vector2(440, 130)
    again.add_theme_font_size_override("font_size", 56)
    again.pressed.connect(_on_restart)
    box.add_child(again)

    var menu = Button.new()
    menu.text = "MENU"
    menu.custom_minimum_size = Vector2(440, 110)
    menu.add_theme_font_size_override("font_size", 48)
    menu.pressed.connect(_on_menu)
    box.add_child(menu)

func _process(_delta):
    var w = get_tree().get_first_node_in_group("weather")
    if w != null:
        weather_label.text = "Weather: " + w.label_text

func _update_stats():
    stats_label.text = "Score %d   Kills %d   Wave %d" % [
        GameManager.score, GameManager.kills, GameManager.wave
    ]

func _on_health(current, maximum):
    health_bar.max_value = maximum
    health_bar.value = current
    flash.color = Color(0.8, 0.0, 0.0, 0.35)
    var tw = create_tween()
    tw.tween_property(flash, "color:a", 0.0, 0.35)

func _on_died():
    death_panel.visible = true

func _on_restart():
    get_tree().reload_current_scene()

func _on_menu():
    get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
EOF

# ---------------------------------------------------------------
# 10. Touch controls (big floating joystick, look, FIRE, JUMP)
# ---------------------------------------------------------------
cat > project/scripts/touch_controls.gd <<'EOF'
extends Control

const JOY_RADIUS: float = 120.0
const FIRE_RADIUS: float = 95.0
const JUMP_RADIUS: float = 65.0

var player = null

var joy_id: int = -1
var joy_origin: Vector2 = Vector2.ZERO
var joy_pos: Vector2 = Vector2.ZERO
var look_id: int = -1
var fire_id: int = -1

func _ready():
    mouse_filter = Control.MOUSE_FILTER_IGNORE

func _fire_center() -> Vector2:
    var s = get_viewport_rect().size
    return Vector2(s.x - 170.0, s.y - 190.0)

func _jump_center() -> Vector2:
    var s = get_viewport_rect().size
    return Vector2(s.x - 360.0, s.y - 110.0)

func _input(event):
    if event is InputEventScreenTouch:
        if event.pressed:
            _on_press(event.index, event.position)
        else:
            _on_release(event.index)
    elif event is InputEventScreenDrag:
        _on_drag(event.index, event.position, event.relative)

func _on_press(id: int, pos: Vector2):
    var ok = is_instance_valid(player)
    if pos.distance_to(_fire_center()) < FIRE_RADIUS + 15.0 and fire_id == -1:
        fire_id = id
        if ok:
            player.shoot_held = true
    elif pos.distance_to(_jump_center()) < JUMP_RADIUS + 15.0:
        if ok:
            player.jump_requested = true
    elif pos.x < get_viewport_rect().size.x * 0.45 and joy_id == -1:
        joy_id = id
        joy_origin = pos
        joy_pos = pos
    elif look_id == -1:
        look_id = id
    queue_redraw()

func _on_release(id: int):
    var ok = is_instance_valid(player)
    if id == fire_id:
        fire_id = -1
        if ok:
            player.shoot_held = false
    if id == joy_id:
        joy_id = -1
        if ok:
            player.mobile_move = Vector2.ZERO
    if id == look_id:
        look_id = -1
    queue_redraw()

func _on_drag(id: int, pos: Vector2, rel: Vector2):
    var ok = is_instance_valid(player)
    if id == joy_id:
        var v = pos - joy_origin
        if v.length() > JOY_RADIUS:
            v = v.normalized() * JOY_RADIUS
        joy_pos = joy_origin + v
        if ok:
            if v.length() < 12.0:
                player.mobile_move = Vector2.ZERO
            else:
                player.mobile_move = v / JOY_RADIUS
    elif id == look_id:
        if ok:
            player.mobile_look += rel
    queue_redraw()

func _draw():
    var size_v = get_viewport_rect().size
    var font = ThemeDB.fallback_font

    # Joystick
    if joy_id != -1:
        draw_circle(joy_origin, JOY_RADIUS, Color(1, 1, 1, 0.12))
        draw_arc(joy_origin, JOY_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 4.0)
        draw_circle(joy_pos, 50.0, Color(1, 1, 1, 0.45))
    else:
        var hint = Vector2(200.0, size_v.y - 190.0)
        draw_arc(hint, JOY_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 3.0)
        draw_circle(hint, 45.0, Color(1, 1, 1, 0.15))

    # Fire button
    var fire_alpha = 0.55
    if fire_id != -1:
        fire_alpha = 0.85
    draw_circle(_fire_center(), FIRE_RADIUS, Color(0.9, 0.15, 0.1, fire_alpha))
    draw_string(font, _fire_center() + Vector2(-FIRE_RADIUS, 12), "FIRE",
        HORIZONTAL_ALIGNMENT_CENTER, FIRE_RADIUS * 2.0, 34, Color.WHITE)

    # Jump button
    draw_circle(_jump_center(), JUMP_RADIUS, Color(0.2, 0.5, 0.9, 0.55))
    draw_string(font, _jump_center() + Vector2(-JUMP_RADIUS, 10), "JUMP",
        HORIZONTAL_ALIGNMENT_CENTER, JUMP_RADIUS * 2.0, 26, Color.WHITE)

    # Crosshair
    var c = size_v / 2.0
    draw_line(c + Vector2(-16, 0), c + Vector2(-5, 0), Color.WHITE, 2.0)
    draw_line(c + Vector2(5, 0), c + Vector2(16, 0), Color.WHITE, 2.0)
    draw_line(c + Vector2(0, -16), c + Vector2(0, -5), Color.WHITE, 2.0)
    draw_line(c + Vector2(0, 5), c + Vector2(0, 16), Color.WHITE, 2.0)
EOF

# ---------------------------------------------------------------
# 11. Main menu (big UI, built in code)
# ---------------------------------------------------------------
cat > project/scripts/main_menu.gd <<'EOF'
extends Control

func _ready():
    var bg = ColorRect.new()
    bg.color = Color(0.07, 0.075, 0.09)
    add_child(bg)
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var center = CenterContainer.new()
    add_child(center)
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var box = VBoxContainer.new()
    box.add_theme_constant_override("separation", 28)
    center.add_child(box)

    var title = Label.new()
    title.text = "PHANTOM OPS"
    title.add_theme_font_size_override("font_size", 110)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(title)

    var sub = Label.new()
    sub.text = "KASSERINE - OPERATIONS"
    sub.add_theme_font_size_override("font_size", 40)
    sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(sub)

    var play = Button.new()
    play.text = "DEPLOY"
    play.custom_minimum_size = Vector2(520, 150)
    play.add_theme_font_size_override("font_size", 70)
    play.pressed.connect(_on_deploy_pressed)
    box.add_child(play)

func _on_deploy_pressed():
    get_tree().change_scene_to_file("res://scenes/main_game.tscn")
EOF

cat > project/scenes/main_menu.tscn <<'EOF'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/main_menu.gd" id="1"]

[node name="MainMenu" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1")
EOF

# ---------------------------------------------------------------
# 12. Main game scene (everything is built in code)
# ---------------------------------------------------------------
cat > project/scripts/main_game.gd <<'EOF'
extends Node3D

const PlayerScript = preload("res://scripts/player.gd")
const CityScript = preload("res://scripts/kasserine_city_generator.gd")
const WeatherScript = preload("res://scripts/weather.gd")
const SpawnerScript = preload("res://scripts/world_spawner.gd")
const HudScript = preload("res://scripts/hud.gd")

func _ready():
    GameManager.reset_game()

    var city = CityScript.new()
    city.name = "City"
    add_child(city)

    var player = PlayerScript.new()
    player.name = "Player"
    player.position = Vector3(0, 1.0, 12)
    add_child(player)

    var weather = WeatherScript.new()
    weather.name = "Weather"
    add_child(weather)

    var spawner = SpawnerScript.new()
    spawner.name = "Spawner"
    spawner.player = player
    add_child(spawner)

    var hud = HudScript.new()
    hud.name = "HUD"
    hud.player = player
    add_child(hud)
EOF

cat > project/scenes/main_game.tscn <<'EOF'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/main_game.gd" id="1"]

[node name="MainGame" type="Node3D"]
script = ExtResource("1")
EOF

# ---------------------------------------------------------------
# 13. GitHub workflow (fixed signing step, no more literal \n)
# ---------------------------------------------------------------
cat > .github/workflows/build-android.yml <<'EOF'
name: Build Phantom Ops Android APK

on:
  push:
    branches:
      - main
  workflow_dispatch:

permissions:
  contents: read

jobs:
  build:
    name: Build Godot Android APK
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Java 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Setup Android SDK
        uses: android-actions/setup-android@v4
        with:
          packages: 'platform-tools'

      - name: Install Android SDK components
        run: |
          yes | sdkmanager --licenses || true
          sdkmanager \
            "platform-tools" \
            "platforms;android-33" \
            "build-tools;33.0.2"

      - name: Install Godot 4.2.2
        run: |
          wget -q \
            https://github.com/godotengine/godot/releases/download/4.2.2-stable/Godot_v4.2.2-stable_linux.x86_64.zip \
            -O godot.zip

          unzip -q godot.zip

          sudo install \
            Godot_v4.2.2-stable_linux.x86_64 \
            /usr/local/bin/godot

          godot --version

      - name: Install Godot export templates
        run: |
          mkdir -p ~/.local/share/godot/export_templates/4.2.2.stable

          wget -q \
            https://github.com/godotengine/godot/releases/download/4.2.2-stable/Godot_v4.2.2-stable_export_templates.tpz \
            -O templates.tpz

          mkdir templates
          unzip -q templates.tpz -d templates

          cp -r templates/templates/. \
            ~/.local/share/godot/export_templates/4.2.2.stable/

      - name: Configure Android signing
        run: |
          mkdir -p project ~/.config/godot
          rm -f project/debug.keystore

          keytool -genkeypair -v \
            -keystore project/debug.keystore \
            -alias androiddebugkey \
            -keyalg RSA -keysize 2048 -validity 10000 \
            -storepass android -keypass android \
            -dname "CN=Android Debug,O=Android,C=US"

          cat > ~/.config/godot/editor_settings-4.tres <<EOF2
          [gd_resource type="EditorSettings" format=3]

          [resource]
          export/android/android_sdk_path = "$ANDROID_HOME"
          export/android/java_sdk_path = "$JAVA_HOME"
          export/android/debug_keystore = "$GITHUB_WORKSPACE/project/debug.keystore"
          export/android/debug_keystore_user = "androiddebugkey"
          export/android/debug_keystore_pass = "android"
          EOF2

      - name: Validate and import project
        run: |
          godot --headless \
            --editor \
            --path project \
            --quit

      - name: Export Android APK
        run: |
          mkdir -p build

          godot --headless \
            --path project \
            --export-debug \
            "Android" \
            "$GITHUB_WORKSPACE/build/PhantomOps.apk"

          test -s build/PhantomOps.apk

      - name: Upload APK artifact
        uses: actions/upload-artifact@v4
        with:
          name: PhantomOps-Debug-APK
          path: build/PhantomOps.apk
          if-no-files-found: error
          retention-days: 14
EOF

# ---------------------------------------------------------------
# 14. Commit and push automatically
# ---------------------------------------------------------------
echo
echo "Files written. Committing and pushing..."

git add -A
git commit -m "Phantom Ops v2: windows, citizens, zombies, weather, ground, touch UI, workflow fix" || echo "(nothing to commit)"
git push || echo "!! git push failed - run 'git push' manually"

echo
echo "=================================="
echo " DONE - check the Actions tab on GitHub"
echo "=================================="
