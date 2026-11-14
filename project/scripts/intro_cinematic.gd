extends Node3D
## v0.4 — drone intro cinematic.
## A drone camera starts high over Kasserine at dawn, flies forward
## and down over the plaza / minaret / market, and descends to Aymen
## standing at the player spawn. Then the view hands over to
## first-person and the game starts (main_game.tscn).
## ~11 seconds, big SKIP button, any tap after 2 s also skips.
## The intro reuses the real city generator — the flyover shows the
## actual city, not a fake backdrop. No enemies during the intro.
## Rendering stays Mobile-safe (BG_COLOR environment, no Sky/fog).

const DURATION := 11.0
const SKIP_AFTER := 2.0

var _t := 0.0
var _finished := false
var _sound: SoundManager
var _camera: Camera3D
var _title: Label
var _subtitle: Label
var _drone_label: Label

# Flight path: position / look-target pairs, one per segment.
var _pos: Array[Vector3] = [
	Vector3(-140, 175, 190),
	Vector3(-70, 95, 120),
	Vector3(35, 40, 65),
	Vector3(12, 14, 38),
	Vector3(0, 1.7, 17),
]
var _look: Array[Vector3] = [
	Vector3(0, 0, 0),
	Vector3(0, 5, -10),
	Vector3(0, 8, -20),
	Vector3(0, 6, -10),
	Vector3(0, 1.4, 10),
]
var _seg_times: Array[float] = [2.5, 2.5, 2.5, 2.0, 1.5]

func _ready() -> void:
	_camera = $DroneCamera as Camera3D
	_sound = SoundManager.new()
	_sound.name = "SoundManager"
	add_child(_sound)
	_sound.start_wind()
	_sound.play_whoosh()
	# Aymen, the hero, standing at the player spawn — the drone
	# descends to him, then the camera becomes his first-person view.
	var hero := HeroAymen.build(self, Vector3(0, 0, 10), 0.0)
	HeroAymen.add_name_label(hero)
	_build_ui()
	_camera.position = _pos[0]
	_camera.look_at(_look[0], Vector3.UP)
	print("Phantom Ops: drone intro started")

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "IntroUI"
	layer.layer = 10
	add_child(layer)
	var ui := Control.new()
	ui.name = "UI"
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	var f := ThemeDB.fallback_font
	_drone_label = Label.new()
	_drone_label.text = "●  DRONE CAM"
	_drone_label.add_theme_font_size_override("font_size", 20)
	_drone_label.add_theme_color_override("font_color", Color(1, 0.6, 0.3))
	_drone_label.position = Vector2(24, 18)
	ui.add_child(_drone_label)
	_title = Label.new()
	_title.text = "PHANTOM OPS"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 84)
	_title.add_theme_color_override("font_color", Color(1, 0.93, 0.8))
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_title.position = Vector2(0, 120)
	_title.size = Vector2(1920, 110)
	_title.modulate.a = 0.0
	ui.add_child(_title)
	_subtitle = Label.new()
	_subtitle.text = "KASSERINE  —  TUNISIA"
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 30)
	_subtitle.add_theme_color_override("font_color", Color(1, 0.85, 0.6))
	_subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_subtitle.position = Vector2(0, 230)
	_subtitle.size = Vector2(1920, 50)
	_subtitle.modulate.a = 0.0
	ui.add_child(_subtitle)
	var skip := Button.new()
	skip.name = "Skip"
	skip.text = "SKIP  ▸"
	skip.add_theme_font_size_override("font_size", 28)
	skip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	skip.position = Vector2(-160, -130)
	skip.size = Vector2(320, 90)
	skip.pressed.connect(_on_skip_pressed)
	ui.add_child(skip)

func _process(delta: float) -> void:
	if _finished:
		return
	_t += delta
	var u := clampf(_t / DURATION, 0.0, 1.0)
	# Find the current segment and ease inside it.
	var elapsed := 0.0
	var seg := 0
	var seg_u := 0.0
	for i in range(_seg_times.size()):
		if _t <= elapsed + _seg_times[i] or i == _seg_times.size() - 1:
			seg = i
			seg_u = clampf((_t - elapsed) / _seg_times[i], 0.0, 1.0)
			break
		elapsed += _seg_times[i]
	seg_u = seg_u * seg_u * (3.0 - 2.0 * seg_u)  # smoothstep
	var a := _pos[seg]
	var b := _pos[mini(seg + 1, _pos.size() - 1)]
	_camera.position = a.lerp(b, seg_u)
	var la := _look[seg]
	var lb := _look[mini(seg + 1, _look.size() - 1)]
	_camera.look_at(la.lerp(lb, seg_u), Vector3.UP)
	# Title fades in, then out before the handover.
	var alpha := 0.0
	if _t > 0.8 and _t < 3.0:
		alpha = clampf((_t - 0.8) / 1.0, 0.0, 1.0)
	elif _t >= 3.0 and _t < 8.0:
		alpha = 1.0
	elif _t >= 8.0:
		alpha = clampf(1.0 - (_t - 8.0) / 2.0, 0.0, 1.0)
	_title.modulate.a = alpha
	_subtitle.modulate.a = alpha
	if u >= 1.0:
		_finish(false)

func _unhandled_input(event: InputEvent) -> void:
	if _finished or _t < SKIP_AFTER:
		return
	if event is InputEventScreenTouch and event.pressed:
		_finish(true)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_finish(true)

func _on_skip_pressed() -> void:
	_finish(true)

func _finish(skipped: bool) -> void:
	if _finished:
		return
	_finished = true
	if skipped:
		print("Phantom Ops: drone intro skipped")
	else:
		print("Phantom Ops: drone intro finished — handing over to Aymen")
	call_deferred("_change_to_game")

func _change_to_game() -> void:
	get_tree().change_scene_to_file("res://scenes/main_game.tscn")
