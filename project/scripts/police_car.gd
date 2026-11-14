extends CharacterBody3D
class_name PhantomPoliceCar
## v0.6 — System 4: the player's drivable police car.
##
## COORDINATOR API (wire into player.gd / main_game — do NOT edit this
## file's owner files, call these from the coordinator):
##   enter(player: Node3D) -> bool
##       Parks the player inside the car: hides + disables the player
##       body (physics/process off, collision off), snaps the player
##       to the driver's seat and steers the player with the car, so
##       the player camera (child of the player) follows automatically.
##       Returns false if already driven, player is null, or dead.
##       While driven the coordinator MUST ignore the player's own
##       move/look/fire input (check `is_driven`) and instead route
##       the HUD joystick to set_drive_input().
##   exit() -> Vector3
##       Puts the player back on foot at a safe spot beside the car
##       (shape-query tested, never inside a building, y >= 1.0) and
##       restores the player body. Returns the exit position.
##   set_drive_input(steer: float, throttle: float)
##       steer -1..1 (+1 = right), throttle -1..1 (+1 = accelerate,
##       -1 = brake / reverse). Call every frame while driven, or
##       once per input change — the car keeps the last values.
##       Desktop: the car also reads ui_left/ui_right/ui_up/ui_down
##       itself while driven (keyboard fallback).
##   toggle_siren() -> bool
##       Toggles the two-tone siren + flashing light bar. Returns the
##       new siren state. Also see set_siren(on: bool).
##   is_driven: bool — true while a player is inside.
##   get_camera_mount() -> Node3D
##       Mount at the driver's head. Only needed if the coordinator
##       wants to re-parent the player camera; normally NOT needed —
##       enter() moves the player node with the car, so the camera
##       follows on its own. Provided for a chase-cam option.
##   get_exit_position() -> Vector3 — safe exit spot without exiting.
##   get_speed() -> float — current |speed| in m/s.
##
## Sounds are generated procedurally here (AudioStreamWAV, same
## technique as SoundManager); sound_manager.gd is NOT touched.
## Siren volume follows SoundManager.sound_on (read guarded).

signal entered
signal exited

const MIX_RATE := 22050
const MAX_SPEED := 18.0
const REVERSE_MAX := 6.0
const ACCEL := 10.0
const BRAKE := 18.0
const TURN_RATE := 1.9
const GRAVITY := 9.8

var is_driven := false
var siren_on := false
var headlights_on := false

var _driver: Node3D = null
var _saved_layer := 0
var _saved_mask := 0
var _speed := 0.0
var _steer := 0.0
var _throttle := 0.0
var _flash_timer := 0.0
var _sound_timer := 0.0

var _red_mat: StandardMaterial3D = null
var _blue_mat: StandardMaterial3D = null
var _lamp_mat: StandardMaterial3D = null
var _red_light: OmniLight3D = null
var _blue_light: OmniLight3D = null
var _front_pivots: Array[Node3D] = []
var _wheel_nodes: Array[Node3D] = []
var _camera_mount: Node3D = null
var _siren_player: AudioStreamPlayer = null
var _engine_player: AudioStreamPlayer = null
var _spotlights: Array[SpotLight3D] = []

static var _engine_cache: AudioStreamWAV = null
static var _siren_cache: AudioStreamWAV = null

# ---------------------------------------------------------------- audio
## Shared seamless engine rumble: 1 s loop, 55 Hz + harmonics (all
## integer cycles in 1 s, so the loop point is click-free). Traffic
## cars reuse this stream via traffic_manager.gd.
static func engine_loop_stream() -> AudioStreamWAV:
	if _engine_cache != null:
		return _engine_cache
	var n := MIX_RATE
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in range(n):
		var t := float(i) / MIX_RATE
		var v := sin(TAU * 55.0 * t) * 0.45
		v += sin(TAU * 110.0 * t) * 0.25
		v += sin(TAU * 165.0 * t) * 0.12
		v *= 0.85 + 0.15 * sin(TAU * 2.0 * t)
		samples[i] = v * 0.6
	_engine_cache = _pack(samples)
	_engine_cache.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_engine_cache.loop_begin = 0
	_engine_cache.loop_end = n
	return _engine_cache

## Two-tone hi-lo siren: 1.6 s loop, 0.4 s of 880 Hz then 0.4 s of
## 660 Hz, twice. Both tones complete whole cycles in 0.4 s, so the
## loop and the tone joins are click-free.
static func siren_loop_stream() -> AudioStreamWAV:
	if _siren_cache != null:
		return _siren_cache
	var n := int(MIX_RATE * 1.6)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in range(n):
		var t := float(i) / MIX_RATE
		var seg := int(t / 0.4) % 2
		var f := 880.0 if seg == 0 else 660.0
		var ph := TAU * f * t
		samples[i] = (sin(ph) * 0.5 + sin(ph * 2.0) * 0.12) * 0.55
	_siren_cache = _pack(samples)
	_siren_cache.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_siren_cache.loop_begin = 0
	_siren_cache.loop_end = n
	return _siren_cache

static func _pack(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v := clampf(samples[i], -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream

static func _sound_enabled() -> bool:
	# SoundManager is a project class_name (player.gd reads it the
	# same way). Static access, no node lookup needed.
	return SoundManager.sound_on

# ---------------------------------------------------------------- build
func _ready() -> void:
	floor_snap_length = 0.5
	_build_vehicle()
	_build_audio()

func _box(label: String, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	add_child(mi)
	return mi

func _build_vehicle() -> void:
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.92, 0.90)
	white.metallic = 0.35
	white.roughness = 0.30
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color(0.05, 0.16, 0.55)
	blue.metallic = 0.3
	blue.roughness = 0.4
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.03, 0.10, 0.14)
	glass.metallic = 0.3
	glass.roughness = 0.15
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.02, 0.02, 0.025)
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1.0, 0.85, 0.55)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.65, 0.25)
	lamp.emission_energy_multiplier = 0.25
	_lamp_mat = lamp
	var tail := StandardMaterial3D.new()
	tail.albedo_color = Color(0.55, 0.05, 0.04)
	tail.emission_enabled = true
	tail.emission = Color(0.85, 0.08, 0.05)
	tail.emission_energy_multiplier = 0.8
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.70, 0.02, 0.02)
	red.emission_enabled = true
	red.emission = Color(1.0, 0.05, 0.05)
	red.emission_energy_multiplier = 0.15
	_red_mat = red
	var bluemat := StandardMaterial3D.new()
	bluemat.albedo_color = Color(0.02, 0.05, 0.80)
	bluemat.emission_enabled = true
	bluemat.emission = Color(0.10, 0.25, 1.0)
	bluemat.emission_energy_multiplier = 0.15
	_blue_mat = bluemat
	# Body: white chassis + cabin, blue stripe + blue doors band.
	_box("Chassis", Vector3(2.0, 0.62, 4.2), Vector3(0, 0.72, 0), white)
	_box("Cabin", Vector3(1.7, 0.72, 2.0), Vector3(0, 1.32, -0.15), glass)
	_box("Bonnet", Vector3(1.84, 0.22, 1.05), Vector3(0, 1.0, -1.45), white)
	_box("Roof", Vector3(1.72, 0.10, 1.95), Vector3(0, 1.72, -0.15), white)
	_box("StripeL", Vector3(0.06, 0.22, 4.0), Vector3(-1.01, 0.82, 0), blue)
	_box("StripeR", Vector3(0.06, 0.22, 4.0), Vector3(1.01, 0.82, 0), blue)
	_box("BumperF", Vector3(2.02, 0.18, 0.16), Vector3(0, 0.48, -2.12), rubber)
	_box("BumperR", Vector3(2.02, 0.18, 0.16), Vector3(0, 0.48, 2.12), rubber)
	_box("Grille", Vector3(1.2, 0.18, 0.08), Vector3(0, 0.78, -2.12), rubber)
	for side in [-1.0, 1.0]:
		_box("Headlight", Vector3(0.36, 0.18, 0.08), Vector3(side * 0.68, 0.82, -2.14), lamp)
		_box("Taillight", Vector3(0.36, 0.16, 0.08), Vector3(side * 0.68, 0.82, 2.14), tail)
		var spot := SpotLight3D.new()
		spot.name = "HeadlightBeam"
		spot.position = Vector3(side * 0.68, 0.82, -2.1)
		spot.rotation_degrees = Vector3(-6, 0, 0)
		spot.light_color = Color(1.0, 0.9, 0.65)
		spot.light_energy = 0.0
		spot.spot_range = 26.0
		spot.spot_angle = 32.0
		spot.shadow_enabled = false
		spot.visible = false
		add_child(spot)
		_spotlights.append(spot)
	# POLICE labels: both flanks + rear (Label3D, Latin only — the
	# fallback font has no Arabic glyphs, same as the shop signs).
	for side in [-1.0, 1.0]:
		var label := Label3D.new()
		label.name = "PoliceLabel"
		label.text = "POLICE"
		label.font_size = 96
		label.pixel_size = 0.008
		label.modulate = Color(0.05, 0.16, 0.55)
		label.outline_size = 8
		label.outline_modulate = Color.WHITE
		label.position = Vector3(side * 1.06, 1.05, 0)
		label.rotation.y = PI * 0.5 * side
		add_child(label)
	var rear := Label3D.new()
	rear.name = "PoliceLabelRear"
	rear.text = "POLICE"
	rear.font_size = 96
	rear.pixel_size = 0.008
	rear.modulate = Color(0.05, 0.16, 0.55)
	rear.outline_size = 8
	rear.outline_modulate = Color.WHITE
	rear.position = Vector3(0, 1.05, 2.16)
	add_child(rear)
	# Roof light bar: base + red (left) / blue (right) lenses.
	_box("LightBarBase", Vector3(1.3, 0.10, 0.45), Vector3(0, 1.82, -0.15), rubber)
	_box("LightBarRed", Vector3(0.58, 0.22, 0.4), Vector3(-0.33, 1.95, -0.15), red)
	_box("LightBarBlue", Vector3(0.58, 0.22, 0.4), Vector3(0.33, 1.95, -0.15), bluemat)
	_red_light = OmniLight3D.new()
	_red_light.name = "RedBeacon"
	_red_light.position = Vector3(-0.33, 2.05, -0.15)
	_red_light.light_color = Color(1.0, 0.08, 0.08)
	_red_light.light_energy = 0.0
	_red_light.omni_range = 12.0
	add_child(_red_light)
	_blue_light = OmniLight3D.new()
	_blue_light.name = "BlueBeacon"
	_blue_light.position = Vector3(0.33, 2.05, -0.15)
	_blue_light.light_color = Color(0.10, 0.25, 1.0)
	_blue_light.light_energy = 0.0
	_blue_light.omni_range = 12.0
	add_child(_blue_light)
	# Wheels: front pair on steering pivots, rear pair fixed.
	for side in [-1.0, 1.0]:
		for axle in [-1.3, 1.35]:
			var wheel := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.38
			cyl.bottom_radius = 0.38
			cyl.height = 0.24
			wheel.mesh = cyl
			wheel.material_override = rubber
			wheel.rotation.z = PI * 0.5
			if axle < 0.0:
				var pivot := Node3D.new()
				pivot.name = "SteerPivot"
				pivot.position = Vector3(side * 1.02, 0.42, axle)
				pivot.add_child(wheel)
				add_child(pivot)
				_front_pivots.append(pivot)
			else:
				wheel.position = Vector3(side * 1.02, 0.42, axle)
				add_child(wheel)
			_wheel_nodes.append(wheel)
	# Collision + camera mount (driver's head, slightly forward).
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 1.7, 4.2)
	col.shape = shape
	col.position.y = 0.85
	add_child(col)
	_camera_mount = Node3D.new()
	_camera_mount.name = "CameraMount"
	_camera_mount.position = Vector3(0, 1.5, 0.4)
	add_child(_camera_mount)

func _build_audio() -> void:
	_siren_player = AudioStreamPlayer.new()
	_siren_player.name = "SirenPlayer"
	_siren_player.stream = siren_loop_stream()
	_siren_player.volume_db = -10.0
	add_child(_siren_player)
	_engine_player = AudioStreamPlayer.new()
	_engine_player.name = "EnginePlayer"
	_engine_player.stream = engine_loop_stream()
	_engine_player.volume_db = -26.0
	add_child(_engine_player)
	if _sound_enabled():
		_engine_player.play()

# ---------------------------------------------------------------- API
func get_camera_mount() -> Node3D:
	return _camera_mount

func get_speed() -> float:
	return absf(_speed)

func enter(player: Node3D) -> bool:
	if is_driven:
		return false
	if player == null or not is_instance_valid(player):
		return false
	# NOTE: no bool(...) cast here — GDScript 4.2 has no bool()
	# constructor; a missing property returns null, which is falsy
	# via `== true` but would crash bool(null).
	if player.get("is_dead") == true:
		return false
	_driver = player
	_saved_layer = int(player.get("collision_layer")) if player.get("collision_layer") != null else 0
	_saved_mask = int(player.get("collision_mask")) if player.get("collision_mask") != null else 0
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	# v0.6 integration: tell the player to ignore on-foot input while
	# driving (player.gd guards fire/jump/look on is_driving).
	player.set("is_driving", true)
	player.set("collision_layer", 0)
	player.set("collision_mask", 0)
	player.set_physics_process(false)
	player.set_process(false)
	player.visible = false
	# Seat the driver: player node rides with the car (its camera
	# follows automatically), facing the car's heading.
	_sync_driver_to_seat()
	_steer = 0.0
	_throttle = 0.0
	is_driven = true
	entered.emit()
	return true

func exit() -> Vector3:
	if not is_driven:
		return get_exit_position()
	var pos := get_exit_position()
	_restore_driver(pos)
	is_driven = false
	_steer = 0.0
	_throttle = 0.0
	_speed = 0.0
	exited.emit()
	return pos

func set_drive_input(steer: float, throttle: float) -> void:
	_steer = clampf(steer, -1.0, 1.0)
	_throttle = clampf(throttle, -1.0, 1.0)

func toggle_siren() -> bool:
	return set_siren(not siren_on)

func set_siren(on: bool) -> bool:
	siren_on = on
	_apply_siren_audio()
	return siren_on

func set_headlights(on: bool) -> void:
	headlights_on = on
	if _lamp_mat != null:
		_lamp_mat.emission_energy_multiplier = 2.6 if on else 0.25
	for s in _spotlights:
		s.visible = on
		s.light_energy = 2.5 if on else 0.0

func get_exit_position() -> Vector3:
	# Candidates in car-local space: driver side first, then the
	# other side, then behind, then in front. Each is shape-tested
	# against the world (0.6 m sphere at standing height); the car
	# itself is excluded. Fallback is the driver side regardless.
	var candidates: Array[Vector3] = [
		Vector3(-2.4, 0, 0.3), Vector3(2.4, 0, 0.3),
		Vector3(-2.4, 0, 2.8), Vector3(2.4, 0, 2.8),
		Vector3(0, 0, -3.6),
	]
	for local in candidates:
		var world := to_global(local)
		world.y = 1.0
		world.x = clampf(world.x, -145.0, 145.0)
		world.z = clampf(world.z, -145.0, 145.0)
		if _spot_is_clear(world):
			return world
	var fallback := to_global(candidates[0])
	fallback.y = 1.0
	fallback.x = clampf(fallback.x, -145.0, 145.0)
	fallback.z = clampf(fallback.z, -145.0, 145.0)
	return fallback

func _spot_is_clear(at: Vector3) -> bool:
	var space := get_world_3d()
	if space == null:
		return true
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.6
	query.shape = sphere
	query.transform = Transform3D(Basis(), at)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hits := space.direct_space_state.intersect_shape(query)
	return hits.is_empty()

func _sync_driver_to_seat() -> void:
	if _driver == null or not is_instance_valid(_driver):
		return
	_driver.global_position = global_position + Vector3(0, 0.95, 0)
	_driver.rotation.y = rotation.y

func _restore_driver(pos: Vector3) -> void:
	if _driver == null or not is_instance_valid(_driver):
		return
	var d := _driver
	_driver = null
	d.global_position = pos
	d.rotation.y = rotation.y
	if d is CharacterBody3D:
		(d as CharacterBody3D).velocity = Vector3.ZERO
	d.set("collision_layer", _saved_layer)
	d.set("collision_mask", _saved_mask)
	d.set("is_driving", false)
	d.visible = true
	d.set_physics_process(true)
	d.set_process(true)

func _apply_siren_audio() -> void:
	if _siren_player == null:
		return
	if siren_on and _sound_enabled():
		if not _siren_player.playing:
			_siren_player.play()
	else:
		if _siren_player.playing:
			_siren_player.stop()

# ---------------------------------------------------------------- drive
func _physics_process(delta: float) -> void:
	# Parked: just stay grounded (spawned a touch high, or on a slope).
	if not is_driven:
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		else:
			velocity.y = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	# Desktop keyboard fallback (mobile uses set_drive_input via HUD).
	if OS.get_name() not in ["Android", "iOS"]:
		var kb := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if kb.length() > 0.05:
			_steer = kb.x
			_throttle = -kb.y
	# Arcade drive: throttle accelerates, reverse-throttle brakes
	# first, then reverses; gentle drag when no input.
	if _throttle > 0.0:
		_speed += ACCEL * _throttle * delta
	elif _throttle < 0.0:
		if _speed > 0.5:
			_speed += BRAKE * _throttle * delta
		else:
			_speed += ACCEL * 0.6 * _throttle * delta
	else:
		_speed = move_toward(_speed, 0.0, 3.0 * delta)
	_speed = clampf(_speed, -REVERSE_MAX, MAX_SPEED)
	# Steering: sharper at low speed, none at a standstill; reversed
	# when backing up.
	var steer_factor := clampf(absf(_speed) / 6.0, 0.0, 1.0)
	if absf(_speed) > 0.05:
		rotation.y -= _steer * TURN_RATE * steer_factor * delta * signf(_speed)
	var forward := Vector3(-sin(rotation.y), 0, -cos(rotation.y))
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	velocity.x = forward.x * _speed
	velocity.z = forward.z * _speed
	move_and_slide()
	# Wall hit (NOT the floor — get_slide_collision_count() counts
	# floor contact too, and damping on that would cap the car at
	# ~1.5 m/s). Gentle scrub only: 0.98/frame still stops the car
	# in ~1 s of grinding a wall, but a light graze doesn't kill it.
	if is_on_wall():
		_speed *= 0.98
	# Wheels: spin with speed, front pivots steer visually.
	for w in _wheel_nodes:
		w.rotate_x(_speed * delta * 1.8)
	for p in _front_pivots:
		p.rotation.y = _steer * 0.45
	_sync_driver_to_seat()

func _process(delta: float) -> void:
	# Light bar: alternate red/blue at ~4 Hz while the siren is on.
	if siren_on:
		_flash_timer += delta
		var phase := int(_flash_timer * 8.0) % 2
		var red_on := phase == 0
		_red_mat.emission_energy_multiplier = 3.5 if red_on else 0.15
		_blue_mat.emission_energy_multiplier = 0.15 if red_on else 3.5
		_red_light.light_energy = 2.2 if red_on else 0.0
		_blue_light.light_energy = 0.0 if red_on else 2.2
	else:
		_red_mat.emission_energy_multiplier = 0.15
		_blue_mat.emission_energy_multiplier = 0.15
		_red_light.light_energy = 0.0
		_blue_light.light_energy = 0.0
	# Sound on/off can change in the pause menu — re-check ~4x/sec.
	_sound_timer -= delta
	if _sound_timer <= 0.0:
		_sound_timer = 0.25
		_apply_siren_audio()
		if _engine_player != null:
			if _sound_enabled():
				if not _engine_player.playing:
					_engine_player.play()
			elif _engine_player.playing:
				_engine_player.stop()
	if _engine_player != null and _engine_player.playing:
		var load_f := absf(_speed) / MAX_SPEED
		_engine_player.pitch_scale = 0.8 + load_f * 0.7
		_engine_player.volume_db = -14.0 if is_driven else -26.0
