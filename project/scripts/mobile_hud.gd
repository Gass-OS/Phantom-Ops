extends Control

signal move_changed(value: Vector2)
signal look_delta(value: Vector2)
signal jump_pressed
signal fire_pressed
signal pause_pressed
signal resume_pressed
signal menu_pressed
signal sprint_changed(value: bool)

var joy_id := -1
var look_id := -1
var move_value := Vector2.ZERO
var paused := false
var sprinting := false
var fire_flash := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	queue_redraw()

func _process(delta: float) -> void:
	if fire_flash > 0.0:
		fire_flash = maxf(0.0, fire_flash - delta)
		queue_redraw()

func _draw() -> void:
	var s := get_viewport_rect().size
	var w := s.x
	var h := s.y
	var scale := clampf(minf(w / 960.0, h / 540.0), 0.82, 1.45)
	var f := ThemeDB.fallback_font
	var joy := Vector2(132.0 * scale, h - 136.0 * scale)
	var radius := 82.0 * scale
	# Mission strip and health bar
	draw_rect(Rect2(20, 18, 290 * scale, 58 * scale), Color(0.025,0.045,0.065,0.82), true)
	draw_rect(Rect2(20, 18, 4 * scale, 58 * scale), Color(0.96,0.36,0.18,1), true)
	draw_string(f, Vector2(36 * scale, 40 * scale), "PHANTOM OPS  /  FIELD REPORT", HORIZONTAL_ALIGNMENT_LEFT, 270 * scale, int(13 * scale), Color(0.72,0.83,0.9))
	draw_string(f, Vector2(36 * scale, 61 * scale), "SURVIVE  •  ELIMINATE HOSTILES", HORIZONTAL_ALIGNMENT_LEFT, 270 * scale, int(15 * scale), Color.WHITE)
	# Joystick - substantially larger and screen-relative
	_button(joy, radius, Color(0.035,0.075,0.105,0.68), scale)
	_button(joy + move_value * radius * 0.52, radius * 0.39, Color(0.45,0.67,0.78,0.88), scale)
	draw_string(f, Vector2(joy.x - 32 * scale, joy.y + radius + 22 * scale), "MOVE", HORIZONTAL_ALIGNMENT_CENTER, 64 * scale, int(14 * scale), Color(0.85,0.92,0.96))
	# Right-hand combat cluster
	var fire := Vector2(w - 112 * scale, h - 142 * scale)
	var jump := Vector2(w - 250 * scale, h - 78 * scale)
	var sprint := Vector2(w - 250 * scale, h - 210 * scale)
	_button(fire, 59 * scale, Color(0.65,0.13,0.10,0.88 if fire_flash <= 0 else 1.0), scale)
	draw_string(f, Vector2(fire.x - 34 * scale, fire.y + 6 * scale), "FIRE", HORIZONTAL_ALIGNMENT_CENTER, 68 * scale, int(18 * scale), Color.WHITE)
	_button(jump, 43 * scale, Color(0.12,0.34,0.53,0.88), scale)
	draw_string(f, Vector2(jump.x - 31 * scale, jump.y + 5 * scale), "JUMP", HORIZONTAL_ALIGNMENT_CENTER, 62 * scale, int(14 * scale), Color.WHITE)
	_button(sprint, 40 * scale, Color(0.16,0.39,0.29,0.88), scale)
	draw_string(f, Vector2(sprint.x - 29 * scale, sprint.y + 5 * scale), "RUN", HORIZONTAL_ALIGNMENT_CENTER, 58 * scale, int(14 * scale), Color.WHITE)
	# Pause
	_button(Vector2(w - 45 * scale, 43 * scale), 27 * scale, Color(0.035,0.065,0.085,0.92), scale)
	draw_string(f, Vector2(w - 55 * scale, 49 * scale), "Ⅱ", HORIZONTAL_ALIGNMENT_CENTER, 20 * scale, int(20 * scale), Color.WHITE)
	if paused:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.008,0.016,0.025,0.88), true)
		draw_string(f, Vector2(w/2 - 160 * scale, h*0.34), "MISSION PAUSED", HORIZONTAL_ALIGNMENT_CENTER, 320 * scale, int(30 * scale), Color.WHITE)
		_button(Vector2(w/2, h*0.49), 54 * scale, Color(0.12,0.47,0.32,1), scale)
		draw_string(f, Vector2(w/2 - 72 * scale, h*0.49 + 7 * scale), "RESUME", HORIZONTAL_ALIGNMENT_CENTER, 144 * scale, int(18 * scale), Color.WHITE)
		_button(Vector2(w/2, h*0.64), 54 * scale, Color(0.55,0.16,0.12,1), scale)
		draw_string(f, Vector2(w/2 - 90 * scale, h*0.64 + 7 * scale), "MAIN MENU", HORIZONTAL_ALIGNMENT_CENTER, 180 * scale, int(17 * scale), Color.WHITE)

func _button(p: Vector2, r: float, color: Color, scale: float) -> void:
	draw_circle(p, r, color)
	draw_arc(p, r, 0.0, TAU, 48, Color(0.78,0.88,0.94,0.85), maxf(1.5, 2.0 * scale), true)

func _gui_input(e: InputEvent) -> void:
	var s := get_viewport_rect().size
	var scale := clampf(minf(s.x / 960.0, s.y / 540.0), 0.82, 1.45)
	if e is InputEventScreenTouch:
		if e.pressed: _start(e.index, e.position, s.x, s.y, scale)
		else: _end(e.index)
		accept_event()
	elif e is InputEventScreenDrag:
		if e.index == joy_id:
			var center := Vector2(132.0 * scale, s.y - 136.0 * scale)
			move_value = ((e.position - center) / (82.0 * scale)).limit_length(1.0)
			move_changed.emit(move_value)
			queue_redraw()
		elif e.index == look_id and not paused:
			look_delta.emit(e.relative)
		accept_event()
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed: _start(-2, e.position, s.x, s.y, scale)
		else: _end(-2)
	elif e is InputEventMouseMotion and look_id == -2 and not paused:
		look_delta.emit(e.relative)

func _start(id: int, p: Vector2, w: float, h: float, scale: float) -> void:
	if paused:
		if absf(p.y - h*0.49) < 66*scale: resume_pressed.emit()
		elif absf(p.y - h*0.64) < 66*scale: menu_pressed.emit()
		return
	if p.x > w - 78*scale and p.y < 82*scale:
		pause_pressed.emit()
	elif p.x < w*0.43 and p.y > h*0.53:
		joy_id = id
		var center := Vector2(132.0*scale, h-136.0*scale)
		move_value = ((p-center)/(82.0*scale)).limit_length(1.0)
		move_changed.emit(move_value)
		queue_redraw()
	elif p.x > w-310*scale and p.y > h-250*scale:
		if p.x > w-185*scale and p.y > h-110*scale:
			fire_flash = 0.16
			fire_pressed.emit()
			queue_redraw()
		elif p.y < h-135*scale:
			sprinting = true
			sprint_changed.emit(true)
		else:
			jump_pressed.emit()
	else:
		look_id = id

func _end(id: int) -> void:
	if id == joy_id:
		joy_id = -1
		move_value = Vector2.ZERO
		move_changed.emit(Vector2.ZERO)
		queue_redraw()
	if id == look_id: look_id = -1
	if sprinting:
		sprinting = false
		sprint_changed.emit(false)

func set_paused(v: bool) -> void:
	paused = v
	queue_redraw()
