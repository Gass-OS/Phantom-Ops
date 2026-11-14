extends Node3D
class_name DayNightCycle
## SYSTEM 6 — Day / night + rain / thunder (Phantom-Ops v0.6).
##
## Self-contained Node3D. The coordinator only has to add ONE node to
## scenes/main_game.tscn (see the wiring note at the bottom of this file).
## It finds the existing WorldEnvironment, DirectionalLight3D sun and the
## player at runtime — it creates none of those itself.
##
## DANGER — v0.2 lesson, do not "improve" this: NEVER use ProceduralSky,
## Sky ambient, fog, ACES or MSAA. The environment stays BG_COLOR (1)
## with COLOR ambient (2) at all times; if anything ever rendered black
## on the phone it was the sky/fog path. This script only lerps
## background_color / ambient_light_color / ambient_light_energy and
## moves the sun. It never touches fog, tonemap or the sky.
##
## Cycle: a full day lasts DAY_LENGTH_SECONDS (default 240 s = 4 min).
##   time_of_day 0.00 = dawn   (06:00)   0.25 = noon  (12:00)
##              0.50 = dusk   (18:00)   0.75 = midnight (00:00)
##   Start time defaults to 0.15 (mid-morning, bright daylight) so the
##   player opens on a readable city; dusk arrives ~84 s into a match.
## Rain: NOT constant. First shower 90–150 s after start, then a random
##   gap of 90–180 s between showers. Each shower lasts 30–60 s.
##   While raining the sky/ambient darken ~28%, CPUParticles3D rain
##   follows the player, thunder rumbles (procedural AudioStreamWAV
##   generated inside this script) and lightning briefly spikes
##   ambient_light_energy. When rain stops everything returns to normal.

signal dusk_reached
signal rain_started
signal rain_stopped

## --- tuning (exports so the coordinator / testers can tweak in-editor) ---
@export var day_length_seconds: float = 240.0  ## full day cycle, seconds
@export var start_time_of_day: float = 0.15    ## 0.0 dawn .. 1.0 dawn
@export var time_scale: float = 1.0            ## 1.0 normal, 0.0 frozen
@export var rain_min_gap: float = 90.0         ## seconds between showers
@export var rain_max_gap: float = 180.0
@export var rain_min_duration: float = 30.0    ## seconds per shower
@export var rain_max_duration: float = 60.0
@export var rain_darkening: float = 0.72       ## sky/ambient multiplier in rain
@export var rain_drop_count: int = 320         ## mobile-safe: a few hundred
@export var show_clock: bool = true            ## small on-screen HH:MM label
@export var thunder_enabled: bool = true

## --- public state (read these from other systems) ---
var time_of_day: float = 0.15  ## 0.0–1.0, see header
var is_night: bool = false
var is_raining: bool = false
var night_factor: float = 0.0  ## 0.0 = full day, 1.0 = full night (smooth)

## Keyframes: [time, bg_color, ambient_color, ambient_energy].
## v0.5's dusk look is keyframe 0.50 exactly: BG (0.42, 0.44, 0.55),
## ambient (0.62, 0.60, 0.58), energy 0.75.
const KEYFRAMES: Array = [
	[0.00, Color(0.58, 0.48, 0.52), Color(0.70, 0.60, 0.58), 0.65],
	[0.125, Color(0.55, 0.68, 0.85), Color(0.75, 0.78, 0.85), 0.95],
	[0.25, Color(0.45, 0.65, 0.90), Color(0.80, 0.83, 0.90), 1.10],
	[0.375, Color(0.55, 0.62, 0.80), Color(0.75, 0.72, 0.70), 0.90],
	[0.50, Color(0.42, 0.44, 0.55), Color(0.62, 0.60, 0.58), 0.75],
	[0.625, Color(0.16, 0.18, 0.30), Color(0.30, 0.33, 0.45), 0.45],
	[0.75, Color(0.07, 0.09, 0.18), Color(0.20, 0.23, 0.35), 0.35],
	[0.875, Color(0.10, 0.12, 0.24), Color(0.24, 0.26, 0.38), 0.40],
	[1.00, Color(0.58, 0.48, 0.52), Color(0.70, 0.60, 0.58), 0.65],
]

const _MIX_RATE := 22050

var _env: Environment = null
var _world_env: WorldEnvironment = null
var _sun: DirectionalLight3D = null
var _player: Node3D = null
var _rain: CPUParticles3D = null
var _thunder_player: AudioStreamPlayer = null
var _thunder_stream: AudioStreamWAV = null
var _clock_label: Label = null

var _prev_time: float = 0.15
var _dusk_emitted_this_cycle: bool = false
var _rain_timer: float = 120.0  ## countdown to next shower (randomised in _ready)
var _rain_time_left: float = 0.0
var _rain_blend: float = 0.0  ## 0.0 dry -> 1.0 full rain look (smooth)
var _thunder_timer: float = 8.0
var _flash: float = 0.0  ## lightning flash energy, decays fast
var _group_refresh_timer: float = 0.0
var _lamp_lights: Array = []  ## { "light": OmniLight3D, "base": float }
var _window_meshes: Array = []  ## MeshInstance3D, visible at night only
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	add_to_group("day_night")
	time_of_day = clampf(start_time_of_day, 0.0, 1.0)
	_prev_time = time_of_day
	_rain_timer = _rng.randf_range(90.0, 150.0)
	_rescan_scene_nodes()
	_build_rain()
	_build_thunder()
	_build_clock()
	_refresh_night_groups()
	_apply_time()


func _process(delta: float) -> void:
	# The city builds its Sun / WorldEnvironment at runtime; if either
	# was missing at _ready (node order), keep looking — never crash.
	if _world_env == null or not is_instance_valid(_world_env) or _sun == null or not is_instance_valid(_sun):
		_rescan_scene_nodes()
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D

	# --- advance the clock ---
	if time_scale > 0.0 and day_length_seconds > 0.0:
		_prev_time = time_of_day
		time_of_day = fmod(time_of_day + (delta * time_scale) / day_length_seconds, 1.0)
		if time_of_day < _prev_time:
			# Wrapped past midnight into a new day: dusk can fire again.
			_dusk_emitted_this_cycle = false
		_check_dusk_crossing()

	# --- rain scheduling ---
	_update_rain(delta)
	# --- lightning flash decay ---
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)

	_apply_time()
	_update_rain_position()
	_update_clock()

	# Night groups may be populated late (buildings worker adds lamps
	# during city build); re-scan cheaply every 2 s.
	_group_refresh_timer -= delta
	if _group_refresh_timer <= 0.0:
		_group_refresh_timer = 2.0
		_refresh_night_groups()


# ------------------------------------------------------------------ API
func force_time(t: float) -> void:
	"""Jump the clock (testing / missions). Emits dusk_reached if the jump crosses dusk."""
	_prev_time = time_of_day
	time_of_day = clampf(t, 0.0, 1.0)
	if time_of_day < _prev_time:
		_dusk_emitted_this_cycle = false
	_check_dusk_crossing()
	_apply_time()


func force_night() -> void:
	"""v0.7 — jump the clock to midnight (00:00) and FREEZE it there
	(time_scale = 0.0) so the chapter stays night. Used by chapter 3
	(NIGHT SHIFT). The dusk flag is pre-set so the jump does NOT
	re-emit dusk_reached (no second adhan). Restore with
	force_time(saved_time) + time_scale = saved_scale — the caller
	(MissionDirector) owns saving/restoring those values."""
	time_scale = 0.0
	_dusk_emitted_this_cycle = true
	_prev_time = time_of_day
	time_of_day = 0.75
	_apply_time()


func force_rain(duration: float = -1.0) -> void:
	"""Start a shower now (testing). Duration 30–60 s if not given."""
	if is_raining:
		return
	_start_rain(duration if duration > 0.0 else _rng.randf_range(rain_min_duration, rain_max_duration))


func stop_rain() -> void:
	"""End a shower now; the sky blends back to normal."""
	if not is_raining:
		return
	is_raining = false
	_rain_time_left = 0.0
	_rain_timer = _rng.randf_range(rain_min_gap, rain_max_gap)
	if is_instance_valid(_rain):
		_rain.emitting = false
	rain_stopped.emit()


func set_thunder_enabled(enabled: bool) -> void:
	thunder_enabled = enabled


# ------------------------------------------------------------------ time
func _check_dusk_crossing() -> void:
	# Dusk is time 0.50. Fire once per cycle when the clock crosses it,
	# whether by normal advance or by force_time(). The adhan worker's
	# manager listens for this signal.
	if _dusk_emitted_this_cycle:
		return
	if _prev_time < 0.50 and time_of_day >= 0.50:
		_dusk_emitted_this_cycle = true
		dusk_reached.emit()


func _night_factor_for(t: float) -> float:
	# 0.0 in daylight, ramps up 0.50 -> 0.62 (dusk), full night until
	# 0.92, ramps back down 0.92 -> 0.99 (pre-dawn).
	if t < 0.50 or t >= 0.99:
		return 0.0
	if t < 0.62:
		return smoothstep(0.50, 0.62, t)
	if t < 0.92:
		return 1.0
	return 1.0 - smoothstep(0.92, 0.99, t)


func _sample_keyframes(t: float) -> Array:
	var prev: Array = KEYFRAMES[0]
	for kf in KEYFRAMES:
		if t <= float(kf[0]):
			var span: float = float(kf[0]) - float(prev[0])
			var k: float = 0.0 if span <= 0.0 else clampf((t - float(prev[0])) / span, 0.0, 1.0)
			return [
				(prev[1] as Color).lerp(kf[1] as Color, k),
				(prev[2] as Color).lerp(kf[2] as Color, k),
				lerpf(float(prev[3]), float(kf[3]), k),
			]
		prev = kf
	return [KEYFRAMES[KEYFRAMES.size() - 1][1], KEYFRAMES[KEYFRAMES.size() - 1][2], KEYFRAMES[KEYFRAMES.size() - 1][3]]


func _apply_time() -> void:
	var sample: Array = _sample_keyframes(time_of_day)
	var bg: Color = sample[0]
	var amb: Color = sample[1]
	var amb_energy: float = sample[2]

	night_factor = _night_factor_for(time_of_day)
	is_night = night_factor > 0.5

	# Rain darkens / cools the sky a bit; blend in/out smoothly via
	# _rain_blend (0.0 dry -> 1.0 full rain look over ~2 s).
	var darken: float = lerpf(1.0, rain_darkening, clampf(_rain_blend, 0.0, 1.0))
	bg = bg * darken
	amb = amb * darken
	amb_energy *= lerpf(1.0, 0.8, clampf(_rain_blend, 0.0, 1.0))

	# Lightning: a brief ambient spike only (never a sky/background change).
	amb_energy += _flash

	if _env != null:
		# Safety net, every frame: these two must NEVER change, or the
		# phone risks the v0.2 black screen. Fog/tonemap/sky untouched.
		_env.background_mode = Environment.BG_COLOR
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_env.background_color = bg
		_env.ambient_light_color = amb
		_env.ambient_light_energy = amb_energy

	if is_instance_valid(_sun):
		# Sun path: horizon at dawn (t=0), overhead at noon (t=0.25),
		# horizon at dusk (t=0.5), below horizon at night.
		var elevation: float = sin(TAU * time_of_day) * 65.0
		var azimuth: float = 90.0 + time_of_day * 360.0
		_sun.rotation_degrees = Vector3(-elevation, azimuth, 0.0)
		var day_k: float = clampf(sin(TAU * time_of_day), 0.0, 1.0)
		# Low sun = warm orange; high sun = near-white.
		var warm: Color = Color(1.0, 0.55, 0.30)
		var noon: Color = Color(1.0, 0.95, 0.85)
		_sun.light_color = warm.lerp(noon, clampf(elevation / 65.0, 0.0, 1.0))
		# Still a real low warm sun at dawn/dusk (0.55), brightest at
		# noon (1.15), off once the sun is below the horizon at night.
		_sun.light_energy = (0.55 + 0.60 * day_k) if elevation > 0.0 else 0.0
		# At night the sun is off; keep shadows enabled so dawn/dusk
		# shadows return instantly instead of being rebuilt.

	_apply_night_lights()


func _apply_night_lights() -> void:
	# Lamps: real OmniLights fade with night_factor (keeps their own
	# base energy — v0.5 plaza lamps are 1.4). Windows: binary visible
	# toggle past the dusk blend so they pop on as it gets dark.
	for entry in _lamp_lights:
		var light: OmniLight3D = entry["light"]
		if not is_instance_valid(light):
			continue
		light.light_energy = float(entry["base"]) * night_factor
		light.visible = night_factor > 0.02
	for mesh in _window_meshes:
		if is_instance_valid(mesh):
			(mesh as MeshInstance3D).visible = night_factor > 0.30


# ------------------------------------------------------------------ lookup
func _rescan_scene_nodes() -> void:
	var root: Node = get_tree().current_scene
	if root == null:
		root = get_tree().root
	if root == null:
		return
	# WorldEnvironment: prefer the scene's own node, else any in the tree.
	if _world_env == null or not is_instance_valid(_world_env):
		var we: Node = root.find_child("WorldEnvironment", true, false)
		if we is WorldEnvironment:
			_world_env = we
		else:
			var found: Array[Node] = root.find_children("*", "WorldEnvironment", true, false)
			if not found.is_empty():
				_world_env = found[0] as WorldEnvironment
		if _world_env != null:
			_env = _world_env.environment
			if _env == null:
				_env = Environment.new()
				_world_env.environment = _env
	# Sun: prefer the city generator's "Sun", else any DirectionalLight3D.
	if _sun == null or not is_instance_valid(_sun):
		var sun_node: Node = root.find_child("Sun", true, false)
		if sun_node is DirectionalLight3D:
			_sun = sun_node
		else:
			var suns: Array[Node] = root.find_children("*", "DirectionalLight3D", true, false)
			if not suns.is_empty():
				_sun = suns[0] as DirectionalLight3D
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D


func _refresh_night_groups() -> void:
	# Groups are owned by the buildings worker; they may be EMPTY (its
	# changes differ, or it runs later) — then we simply have fewer
	# lights. Never crash, never spam warnings about it.
	var tree: SceneTree = get_tree()
	_lamp_lights.clear()
	_window_meshes.clear()
	var seen_lights: Dictionary = {}
	var seen_windows: Dictionary = {}

	# --- street lamps: OmniLight3D members of group "street_lamp". ---
	# A group member may also be a lamp container node: then take its
	# OmniLight3D descendants. (Mosque courtyard lanterns light up too
	# if the buildings worker puts them in this group.)
	for member in tree.get_nodes_in_group("street_lamp"):
		for light in _collect_lights(member):
			if is_instance_valid(light) and not seen_lights.has(light.get_instance_id()):
				seen_lights[light.get_instance_id()] = true
				_lamp_lights.append({"light": light, "base": light.light_energy if light.light_energy > 0.0 else 1.4})
	# Fallback: v0.5 lamps already carry an OmniLight3D named
	# "LampLight" (6 near the plaza). If the group is empty, use those
	# so night still has street light even without the other worker.
	if _lamp_lights.is_empty():
		var root: Node = tree.current_scene
		if root != null:
			for node in root.find_children("LampLight", "OmniLight3D", true, false):
				var light := node as OmniLight3D
				if is_instance_valid(light) and not seen_lights.has(light.get_instance_id()):
					seen_lights[light.get_instance_id()] = true
					_lamp_lights.append({"light": light, "base": light.light_energy if light.light_energy > 0.0 else 1.4})

	# --- lit windows: MeshInstance3D members of group "lit_window". ---
	# Toggle is visible-only: the buildings worker designs these as
	# add-on glow meshes that are safe to hide by day. Container
	# members contribute no windows (a lamp head must not be treated
	# as a window) — only direct MeshInstance3D members count.
	for member in tree.get_nodes_in_group("lit_window"):
		if member is MeshInstance3D and not seen_windows.has(member.get_instance_id()):
			seen_windows[member.get_instance_id()] = true
			_window_meshes.append(member)


func _collect_lights(node: Node) -> Array:
	var out: Array = []
	if node is OmniLight3D:
		out.append(node)
	elif node is Node3D:
		for child in (node as Node).find_children("*", "OmniLight3D", true, false):
			out.append(child)
	return out


# ------------------------------------------------------------------ rain
func _build_rain() -> void:
	_rain = CPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = rain_drop_count
	_rain.lifetime = 0.7
	_rain.preprocess = 0.0
	_rain.emitting = false
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(22.0, 0.5, 22.0)
	_rain.direction = Vector3(0.15, -1.0, 0.05)
	_rain.spread = 2.0
	_rain.gravity = Vector3(0.0, -30.0, 0.0)
	_rain.initial_velocity_min = 14.0
	_rain.initial_velocity_max = 20.0
	_rain.scale_amount_min = 0.8
	_rain.scale_amount_max = 1.2
	var drop := BoxMesh.new()
	drop.size = Vector3(0.02, 0.55, 0.02)
	var drop_mat := StandardMaterial3D.new()
	drop_mat.albedo_color = Color(0.70, 0.80, 1.0, 0.55)
	drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.material = drop_mat
	_rain.mesh = drop
	add_child(_rain)


func _update_rain(delta: float) -> void:
	if is_raining:
		_rain_time_left -= delta
		_rain_blend = minf(1.0, _rain_blend + delta * 0.5)  # ~2 s fade-in
		# Thunder + lightning every 6–14 s while raining.
		_thunder_timer -= delta
		if _thunder_timer <= 0.0:
			_thunder_timer = _rng.randf_range(6.0, 14.0)
			_do_thunder()
		if _rain_time_left <= 0.0:
			stop_rain()
	else:
		_rain_blend = maxf(0.0, _rain_blend - delta * 0.5)  # ~2 s fade-out
		_rain_timer -= delta
		if _rain_timer <= 0.0:
			_start_rain(_rng.randf_range(rain_min_duration, rain_max_duration))


func _start_rain(duration: float) -> void:
	is_raining = true
	_rain_time_left = duration
	_thunder_timer = _rng.randf_range(2.0, 5.0)  # first rumble comes soon
	if is_instance_valid(_rain):
		_rain.emitting = true
	rain_started.emit()


func _update_rain_position() -> void:
	if not is_instance_valid(_rain):
		return
	if is_instance_valid(_player):
		# Rain volume hovers 16 m above the player so it always falls
		# where the camera is; the city is 300 m wide, the player walks.
		_rain.global_position = _player.global_position + Vector3(0.0, 16.0, 0.0)
	elif not _rain.emitting:
		_rain.global_position = global_position + Vector3(0.0, 16.0, 0.0)


# ------------------------------------------------------------------ thunder
func _build_thunder() -> void:
	_thunder_player = AudioStreamPlayer.new()
	_thunder_player.name = "ThunderPlayer"
	_thunder_player.bus = "Master"
	_thunder_player.volume_db = -6.0
	add_child(_thunder_player)


func _make_thunder_stream() -> AudioStreamWAV:
	if _thunder_stream != null:
		return _thunder_stream
	# Procedural thunder, generated once and cached: 2.8 s of brown-ish
	# noise (leaky integrator over white noise) for the rumble, a low
	# 55 Hz sine underneath, and a short sharp crack at the start.
	# Same 16-bit / 22050 Hz recipe as sound_manager.gd, built locally
	# so this script never touches sound_manager.gd.
	var dur := 2.8
	var n := int(_MIX_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 987654
	var brown := 0.0
	var phase := 0.0
	for i in range(n):
		var t := float(i) / _MIX_RATE
		var white := rng.randf_range(-1.0, 1.0)
		brown = clampf((brown + 0.02 * white) / 1.02, -1.0, 1.0)
		phase += TAU * 55.0 / _MIX_RATE
		var crack := 0.0
		if t < 0.12:
			# Initial crack: raw noise, gone in ~0.1 s.
			crack = white * 0.9 * (1.0 - t / 0.12)
		var rumble := brown * 2.2 + sin(phase) * 0.25
		var env := exp(-1.4 * t)
		samples[i] = clampf((rumble * env + crack) * 0.8, -1.0, 1.0)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = _MIX_RATE
	stream.stereo = false
	stream.data = data
	_thunder_stream = stream
	return stream


func _do_thunder() -> void:
	# Lightning: brief ambient spike, then the sound. Flash first so
	# the light leads the rumble.
	_flash = 1.4
	if thunder_enabled and is_instance_valid(_thunder_player):
		_thunder_player.stream = _make_thunder_stream()
		_thunder_player.play()


# ------------------------------------------------------------------ clock
func _build_clock() -> void:
	if not show_clock:
		return
	var layer := CanvasLayer.new()
	layer.name = "DayNightClockLayer"
	layer.layer = 10
	add_child(layer)
	_clock_label = Label.new()
	_clock_label.name = "ClockLabel"
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_label.add_theme_font_size_override("font_size", 18)
	_clock_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_clock_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_clock_label.add_theme_constant_override("outline_size", 4)
	_clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# v0.6 integration: top-right, BELOW the money chip (w-340..w-112,
	# y 16-62). Centre-top (y 6) sat underneath the HUD score bar.
	_clock_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_clock_label.position = Vector2(-340.0, 66.0)
	_clock_label.size = Vector2(228.0, 28.0)
	layer.add_child(_clock_label)


func _update_clock() -> void:
	if not is_instance_valid(_clock_label):
		return
	# 0.0 = 06:00, 0.25 = 12:00, 0.50 = 18:00, 0.75 = 00:00.
	var hours24: float = fmod(6.0 + time_of_day * 24.0, 24.0)
	var h: int = int(hours24)
	var m: int = int((hours24 - h) * 60.0)
	var icon := "☀"
	if is_raining:
		icon = "🌧"
	elif is_night:
		icon = "🌙"
	elif time_of_day >= 0.44 and time_of_day < 0.56:
		icon = "🌇"
	_clock_label.text = "%s %02d:%02d" % [icon, h, m]


# ------------------------------------------------------------------ wiring
# COORDINATOR — add exactly this to scenes/main_game.tscn (nothing else):
#
#   [ext_resource type="Script" path="res://scripts/day_night.gd" id="5"]
#   (next free id after the existing 1–4; renumber if other workers
#    added ext_resources first)
#
#   [node name="DayNight" type="Node3D" parent="."]
#   script = ExtResource("5")
#
# No other scene edits needed: the script finds WorldEnvironment,
# the Sun DirectionalLight3D and the player (group "player") itself.
# The adhan worker connects the signal like this:
#   day_night.dusk_reached.connect(_on_dusk_reached)
# where day_night is the node above (get_node("DayNight") from MainGame,
# or get_tree().get_first_node_in_group("day_night")).
# Optional tuning from any script: day_night.force_time(0.5),
# day_night.force_rain(), day_night.time_scale = 0.0 (freeze the clock).
