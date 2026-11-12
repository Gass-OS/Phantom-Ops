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
