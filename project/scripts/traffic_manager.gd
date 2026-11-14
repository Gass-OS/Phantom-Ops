extends Node3D
class_name PhantomTrafficManager
## v0.6 — System 4: traffic + police car + engine/siren audio.
##
## Spawns ~10 traffic cars (scripts/traffic_car.gd) driving rectangular
## loops along the city avenues, and the player's police car
## (scripts/police_car.gd) parked beside the player spawn. Owns the
## procedural engine audio for traffic and the ENTER/EXIT + SIREN
## prompt buttons (its own CanvasLayer — mobile_hud.gd is NOT edited).
##
## COORDINATOR WIRING (main_game / player.gd):
##   - Add one PhantomTrafficManager node to the main game scene
##     (or let it be created by the coordinator). It finds the player
##     (group "player") and the city itself; no scene edits needed.
##   - While police_car.is_driven is true, player.gd MUST ignore its
##     own move/look/fire input; the manager already forwards the HUD
##     joystick to police_car.set_drive_input().
##   - Police car API lives on the car node (see police_car.gd):
##     enter(player), exit() -> Vector3, set_drive_input(),
##     toggle_siren() -> bool, is_driven, get_camera_mount().
##   - The manager exposes `police_car` and `traffic_cars` for the
##     coordinator (e.g. missions that need the car).
##
## ROAD ASSUMPTION (documented): the Kasserine grid has avenues at
## x/z = -100, -50, 0, 50, 100 (KasserineCityGenerator.ROAD_POS). The
## manager reads the real road lines from the City node's "Roads"
## child (names RoadX_<n> / RoadZ_<n>) when present and falls back to
## [-100, -50, 0, 50, 100]. Loops are rectangles at half-extent 50 m
## and 100 m, so every edge runs along a real avenue and no loop
## crosses the central plaza (half 23 m) or the mosque block.

const TrafficCarScript = preload("res://scripts/traffic_car.gd")
const PoliceCarScript = preload("res://scripts/police_car.gd")

@export var traffic_count := 10
@export var police_spawn := Vector3(6.0, 0.0, 10.0)
@export var prompt_distance := 4.5
@export var engine_hear_range := 40.0

var police_car = null  # PhantomPoliceCar (untyped: avoids a hard
# dependency on the global class cache; the script is preloaded below)
var traffic_cars: Array = []

var _player: Node3D = null
var _engine_players: Array[AudioStreamPlayer] = []
var _hud: Node = null
var _hud_connected := false
var _enter_button: Button = null
var _siren_button: Button = null
var _daynight_timer := 0.0
var _hud_retry_timer := 0.0
# v0.6 System 1 (languages): loaded at runtime, never a hard
# dependency — if language_manager.gd is absent, prompts fall back
# to the English literals. Translated via LanguageManager.translate()
# (static). NOTE: LanguageManager.tr() is IMPOSSIBLE in Godot 4.2 —
# Object.tr() is a non-static native method and a static override is
# rejected by the parser — so translate() / t() is the API.
var _lang_script = null

# ---------------------------------------------------------------- setup
func _ready() -> void:
	_lang_script = load("res://scripts/language_manager.gd")
	_build_traffic()
	_build_police_car()
	_build_prompt_ui()
	_update_headlights()

## Translate a prompt key, falling back to the English literal when
## the languages system is unavailable. Never calls .tr().
func _tr(key: String, fallback: String) -> String:
	if _lang_script != null:
		return String(_lang_script.translate(key))
	return fallback

## Set a prompt button's text only when it changed, and (re)apply
## the language font (Arabic needs Noto Naskh + RTL, see
## LanguageManager.apply_font_to).
func _set_prompt_text(button: Button, text: String) -> void:
	if button == null or button.text == text:
		return
	button.text = text
	if _lang_script != null:
		_lang_script.apply_font_to(button)

func _road_lines() -> Array[float]:
	# Real road lines from the city generator's Roads node, if the
	# scene has one; otherwise the documented grid fallback.
	var lines: Array[float] = []
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		var city := tree.current_scene.get_node_or_null("City")
		if city != null:
			var roads := city.get_node_or_null("Roads")
			if roads != null:
				for child in roads.get_children():
					var n := String(child.name)
					if n.begins_with("RoadX_"):
						var v := float(n.trim_prefix("RoadX_"))
						if not lines.has(v):
							lines.append(v)
	lines.sort()
	if lines.is_empty():
		lines = [-100.0, -50.0, 0.0, 50.0, 100.0]
	return lines

func _loop_points(half_extent: float, clockwise: bool) -> Array[Vector3]:
	var pts: Array[Vector3] = [
		Vector3(half_extent, 0, half_extent),
		Vector3(-half_extent, 0, half_extent),
		Vector3(-half_extent, 0, -half_extent),
		Vector3(half_extent, 0, -half_extent),
	]
	if clockwise:
		pts.reverse()
	return pts

func _point_on_loop(loop: Array[Vector3], frac: float) -> Vector3:
	# Walk the rectangle perimeter and return the point at frac 0..1.
	var total := 0.0
	var lens: Array[float] = []
	for i in range(loop.size()):
		var l := loop[i].distance_to(loop[(i + 1) % loop.size()])
		lens.append(l)
		total += l
	var target := clampf(frac, 0.0, 1.0) * total
	for i in range(loop.size()):
		if target <= lens[i]:
			var a := loop[i]
			var b := loop[(i + 1) % loop.size()]
			return a.lerp(b, target / maxf(lens[i], 0.001))
		target -= lens[i]
	return loop[0]

## Index of the corner a car placed at `frac` should drive to FIRST.
## A car spawned mid-edge must head for the next corner along the
## loop — if route_index stays 0 it beelines for the first corner
## straight across the city interior (through buildings / the player).
func _next_corner_index(loop: Array[Vector3], frac: float) -> int:
	var total := 0.0
	var lens: Array[float] = []
	for i in range(loop.size()):
		var l := loop[i].distance_to(loop[(i + 1) % loop.size()])
		lens.append(l)
		total += l
	var target := clampf(frac, 0.0, 1.0) * total
	for i in range(loop.size()):
		if target <= lens[i]:
			return (i + 1) % loop.size()
		target -= lens[i]
	return 1

func _build_traffic() -> void:
	var lines := _road_lines()
	# Loops on the two outer avenue rings that exist in the grid.
	var extents: Array[float] = []
	for h in [50.0, 100.0]:
		if lines.has(h) or lines.has(-h):
			extents.append(h)
	if extents.is_empty():
		extents = [50.0, 100.0]
	var loops: Array = []
	for i in range(extents.size()):
		loops.append(_loop_points(extents[i], i % 2 == 1))
	var colors: Array[Color] = [
		Color(0.72, 0.12, 0.08), Color(0.08, 0.24, 0.55),
		Color(0.72, 0.68, 0.55), Color(0.10, 0.12, 0.13),
		Color(0.52, 0.53, 0.52), Color(0.15, 0.45, 0.25),
	]
	# One speed per loop (tiny jitter only) so cars on the same loop
	# never catch up and stack on each other.
	var loop_speeds: Array[float] = [7.0, 9.0]
	var per_loop: Array[int] = [0, 0]
	var stream := PoliceCarScript.engine_loop_stream()
	for i in range(traffic_count):
		var li := i % loops.size()
		var loop: Array[Vector3] = loops[li]
		var slot := per_loop[li]
		per_loop[li] = slot + 1
		var in_loop := 0
		for j in range(traffic_count):
			if j % loops.size() == li:
				in_loop += 1
		var frac := float(slot) / float(maxi(1, in_loop))
		var car = TrafficCarScript.new()
		car.name = "TrafficCar_%02d" % i
		var cruise := loop_speeds[li % loop_speeds.size()] + randf_range(-0.3, 0.3)
		car.configure(loop, colors[i % colors.size()], cruise)
		add_child(car)
		car.global_position = _point_on_loop(loop, frac)
		# Drive to the NEXT corner, not route[0] (see _next_corner_index).
		car.route_index = _next_corner_index(loop, frac)
		traffic_cars.append(car)
		var player_audio := AudioStreamPlayer.new()
		player_audio.name = "TrafficEngine_%02d" % i
		player_audio.stream = stream
		player_audio.volume_db = -80.0
		player_audio.pitch_scale = 0.75 + (cruise - 6.0) / 4.0 * 0.5
		add_child(player_audio)
		_engine_players.append(player_audio)
		if PoliceCarScript._sound_enabled():
			player_audio.play()
	print("Phantom Ops: traffic ready — %d cars on %d loops" % [traffic_cars.size(), loops.size()])

func _build_police_car() -> void:
	police_car = PoliceCarScript.new()
	police_car.name = "PoliceCar"
	add_child(police_car)
	police_car.global_position = police_spawn
	police_car.rotation.y = 0.0
	print("Phantom Ops: police car parked at %s" % str(police_spawn))

# ---------------------------------------------------------------- prompt UI
func _build_prompt_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TrafficPromptLayer"
	layer.layer = 11
	add_child(layer)
	_enter_button = Button.new()
	_enter_button.name = "EnterExitButton"
	_enter_button.add_theme_font_size_override("font_size", 26)
	_enter_button.custom_minimum_size = Vector2(320, 68)
	_enter_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_enter_button.position = Vector2(-160, -300)
	_enter_button.visible = false
	layer.add_child(_enter_button)
	_set_prompt_text(_enter_button, _tr("prompt_enter_car", "ENTER POLICE CAR"))
	_enter_button.pressed.connect(_on_enter_button_pressed)
	_siren_button = Button.new()
	_siren_button.name = "SirenButton"
	_siren_button.add_theme_font_size_override("font_size", 22)
	_siren_button.custom_minimum_size = Vector2(170, 60)
	_siren_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_siren_button.position = Vector2(-350, -330)
	_siren_button.visible = false
	layer.add_child(_siren_button)
	_set_prompt_text(_siren_button, _tr("siren_off", "SIREN: OFF"))
	_siren_button.pressed.connect(_on_siren_button_pressed)

func _on_enter_button_pressed() -> void:
	if police_car == null:
		return
	if police_car.is_driven:
		police_car.exit()
		return
	var p := _find_player()
	if p != null:
		police_car.enter(p)

func _on_siren_button_pressed() -> void:
	if police_car == null:
		return
	var on: bool = police_car.toggle_siren()
	_set_prompt_text(_siren_button, _tr("siren_on" if on else "siren_off", "SIREN: ON" if on else "SIREN: OFF"))

func _unhandled_input(event: InputEvent) -> void:
	# Desktop convenience: E enters/exits the car. Harmless on mobile.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E and police_car != null:
			if police_car.is_driven:
				police_car.exit()
			elif _find_player() != null and _find_player().global_position.distance_to(police_car.global_position) <= prompt_distance:
				police_car.enter(_find_player())

# ---------------------------------------------------------------- runtime
func _find_player() -> Node3D:
	if _player != null and is_instance_valid(_player):
		return _player
	var tree := get_tree()
	if tree == null:
		return null
	_player = tree.get_first_node_in_group("player") as Node3D
	return _player

func _try_connect_hud() -> void:
	if _hud_connected:
		return
	var tree := get_tree()
	if tree == null:
		return
	var hud := tree.root.get_node_or_null("MobileHUDLayer/MobileHUD")
	if hud == null or not hud.has_signal("move_changed"):
		return
	hud.move_changed.connect(_on_hud_move)
	_hud = hud
	_hud_connected = true

func _on_hud_move(v: Vector2) -> void:
	if police_car == null or not police_car.is_driven:
		return
	# Joystick up is -Y; throttle is +forward.
	police_car.set_drive_input(v.x, -v.y)

func _is_dark() -> bool:
	# Day/night (another worker's system): read it IF it exists.
	# Group "day_night", or a DayNight node in the current scene.
	# Supported: is_night() method, is_night property, time_of_day
	# property (0..24 h, dark < 6 or >= 18). Default: NOT dark
	# (headlights off) when no day/night system is present.
	var tree := get_tree()
	if tree == null:
		return false
	var node: Node = tree.get_first_node_in_group("day_night")
	if node == null and tree.current_scene != null:
		node = tree.current_scene.get_node_or_null("DayNight")
	if node == null:
		return false
	if node.has_method("is_night"):
		return node.call("is_night") == true
	var v = node.get("is_night")
	if v != null:
		return v == true
	var tod = node.get("time_of_day")
	if tod != null:
		var h := float(tod)
		return h < 6.0 or h >= 18.0
	var hr = node.get("hour")
	if hr != null:
		var hh := float(hr)
		return hh < 6.0 or hh >= 18.0
	return false

func _update_headlights() -> void:
	var dark := _is_dark()
	for car in traffic_cars:
		if is_instance_valid(car) and car.has_method("set_headlights"):
			car.set_headlights(dark)
	if police_car != null:
		police_car.set_headlights(dark)

func _update_engine_audio() -> void:
	var p := _find_player()
	var player_pos := Vector3.ZERO
	if p != null:
		player_pos = p.global_position
	elif police_car != null:
		player_pos = police_car.global_position
	var sound_on: bool = PoliceCarScript._sound_enabled()
	for i in range(traffic_cars.size()):
		var car = traffic_cars[i]
		var audio: AudioStreamPlayer = _engine_players[i] if i < _engine_players.size() else null
		if audio == null or not is_instance_valid(car):
			continue
		if not sound_on:
			if audio.playing:
				audio.stop()
			continue
		var d := (car as Node3D).global_position.distance_to(player_pos)
		if d > engine_hear_range + 5.0:
			if audio.playing:
				audio.stop()
			continue
		if not audio.playing:
			audio.play()
		# -8 dB up close, fading to silence at the hear range.
		var f := clampf(d / engine_hear_range, 0.0, 1.0)
		audio.volume_db = lerpf(-8.0, -32.0, f)
		# Only the nearest cars get real headlight beams (Mobile
		# light budget: 2 spotlights per car would be 20 lights).
		if car.has_method("set_spotlights_enabled"):
			car.set_spotlights_enabled(d < 25.0)

func _process(delta: float) -> void:
	_hud_retry_timer -= delta
	if _hud_retry_timer <= 0.0:
		_hud_retry_timer = 0.5
		_try_connect_hud()
	_daynight_timer -= delta
	if _daynight_timer <= 0.0:
		_daynight_timer = 1.0
		_update_headlights()
	_update_engine_audio()
	if police_car == null:
		return
	# If the driver dies while driving, get them out of the car so
	# the death flow (YOU DIED overlay) can run on foot.
	if police_car.is_driven:
		var p := _find_player()
		if p != null and p.get("is_dead") == true:
			police_car.exit()
	# Prompt button state.
	if _enter_button == null:
		return
	var player := _find_player()
	if player == null:
		_enter_button.visible = false
		_siren_button.visible = false
		return
	if police_car.is_driven:
		_enter_button.visible = true
		_set_prompt_text(_enter_button, _tr("prompt_exit_car", "EXIT CAR"))
		_siren_button.visible = true
		_set_prompt_text(_siren_button, _tr("siren_on" if police_car.siren_on else "siren_off", "SIREN: ON" if police_car.siren_on else "SIREN: OFF"))
	else:
		_siren_button.visible = false
		var near := player.global_position.distance_to(police_car.global_position) <= prompt_distance
		_enter_button.visible = near
		if near:
			_set_prompt_text(_enter_button, _tr("prompt_enter_car", "ENTER POLICE CAR"))
