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

func _scale() -> float:
	var s := get_viewport_rect().size
	return clampf(minf(s.x / 600.0, s.y / 1050.0), 1.0, 1.65)

func _process(delta: float) -> void:
	if fire_flash > 0.0:
		fire_flash = maxf(0.0, fire_flash - delta)
		queue_redraw()

func _draw() -> void:
	var s := get_viewport_rect().size
	var w := s.x
	var h := s.y
	var k := _scale()
	var f := ThemeDB.fallback_font
	# Larger, readable mission panel.
	draw_rect(Rect2(18*k, 18*k, 360*k, 82*k), Color(0.018,0.035,0.05,0.9), true)
	draw_rect(Rect2(18*k, 18*k, 6*k, 82*k), Color(0.96,0.36,0.18,1), true)
	draw_string(f, Vector2(36*k, 50*k), "PHANTOM OPS  /  FIELD REPORT", HORIZONTAL_ALIGNMENT_LEFT, 330*k, int(17*k), Color(0.78,0.88,0.93))
	draw_string(f, Vector2(36*k, 80*k), "SURVIVE  •  ELIMINATE HOSTILES", HORIZONTAL_ALIGNMENT_LEFT, 330*k, int(18*k), Color.WHITE)
	# Tactical minimap with player marker and hostile blips.
	var map_center := Vector2(w - 92*k, 142*k)
	var map_size := 142*k
	draw_rect(Rect2(map_center - Vector2(map_size/2, map_size/2), Vector2(map_size,map_size)), Color(0.015,0.04,0.05,0.88), true)
	draw_rect(Rect2(map_center - Vector2(map_size/2, map_size/2), Vector2(map_size,map_size)), Color(0.56,0.72,0.76,0.9), false, 2*k)
	for i in range(-2,3):
		draw_line(map_center + Vector2(i*22*k,-map_size/2), map_center + Vector2(i*22*k,map_size/2), Color(0.20,0.34,0.37,0.8), 1*k)
		draw_line(map_center + Vector2(-map_size/2,i*22*k), map_center + Vector2(map_size/2,i*22*k), Color(0.20,0.34,0.37,0.8), 1*k)
	draw_circle(map_center, 7*k, Color(0.25,0.82,0.95))
	draw_circle(map_center + Vector2(25*k,-19*k), 5*k, Color(0.95,0.20,0.12))
	draw_circle(map_center + Vector2(-32*k,27*k), 5*k, Color(0.95,0.20,0.12))
	draw_string(f, map_center + Vector2(-45*k,map_size/2 + 22*k), "RADAR", HORIZONTAL_ALIGNMENT_CENTER, 90*k, int(13*k), Color(0.78,0.88,0.93))
	# Large movement pad.
	var joy := Vector2(154*k, h - 190*k)
	var radius := 112*k
	_button(joy, radius, Color(0.025,0.065,0.09,0.78), k)
	_button(joy + move_value * radius * 0.48, radius * 0.40, Color(0.36,0.67,0.80,0.94), k)
	draw_string(f, Vector2(joy.x - 48*k, joy.y + radius + 30*k), "MOVE", HORIZONTAL_ALIGNMENT_CENTER, 96*k, int(17*k), Color.WHITE)
	# Big combat buttons spaced for thumbs.
	var fire := Vector2(w - 112*k, h - 190*k)
	var jump := Vector2(w - 270*k, h - 92*k)
	var sprint := Vector2(w - 270*k, h - 285*k)
	_button(fire, 82*k, Color(0.65,0.13,0.10,0.94 if fire_flash <= 0 else 1.0), k)
	draw_string(f, Vector2(fire.x - 48*k, fire.y + 8*k), "ATTACK", HORIZONTAL_ALIGNMENT_CENTER, 96*k, int(22*k), Color.WHITE)
	_button(jump, 61*k, Color(0.12,0.34,0.53,0.94), k)
	draw_string(f, Vector2(jump.x - 42*k, jump.y + 7*k), "JUMP", HORIZONTAL_ALIGNMENT_CENTER, 84*k, int(17*k), Color.WHITE)
	_button(sprint, 59*k, Color(0.12,0.42,0.30,0.94), k)
	draw_string(f, Vector2(sprint.x - 42*k, sprint.y + 7*k), "RUN", HORIZONTAL_ALIGNMENT_CENTER, 84*k, int(18*k), Color.WHITE)
	_button(Vector2(w - 50*k, 48*k), 34*k, Color(0.02,0.05,0.07,0.96), k)
	draw_string(f, Vector2(w - 65*k, 57*k), "Ⅱ", HORIZONTAL_ALIGNMENT_CENTER, 30*k, int(25*k), Color.WHITE)
	if paused:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.008,0.016,0.025,0.9), true)
		draw_string(f, Vector2(w/2 - 180*k, h*0.35), "MISSION PAUSED", HORIZONTAL_ALIGNMENT_CENTER, 360*k, int(34*k), Color.WHITE)
		_button(Vector2(w/2, h*0.49), 76*k, Color(0.12,0.47,0.32,1), k)
		draw_string(f, Vector2(w/2 - 88*k, h*0.49 + 8*k), "RESUME", HORIZONTAL_ALIGNMENT_CENTER, 176*k, int(22*k), Color.WHITE)
		_button(Vector2(w/2, h*0.64), 76*k, Color(0.55,0.16,0.12,1), k)
		draw_string(f, Vector2(w/2 - 110*k, h*0.64 + 8*k), "MAIN MENU", HORIZONTAL_ALIGNMENT_CENTER, 220*k, int(20*k), Color.WHITE)

func _button(p: Vector2, r: float, color: Color, k: float) -> void:
	draw_circle(p, r, color)
	draw_arc(p, r, 0.0, TAU, 48, Color(0.82,0.91,0.96,0.95), maxf(2.0, 2.5*k), true)

func _gui_input(e: InputEvent) -> void:
	var s := get_viewport_rect().size
	var w := s.x
	var h := s.y
	var k := _scale()
	if e is InputEventScreenTouch:
		if e.pressed: _start(e.index, e.position, w, h, k)
		else: _end(e.index)
		accept_event()
	elif e is InputEventScreenDrag:
		if e.index == joy_id:
			var center := Vector2(154*k, h - 190*k)
			move_value = ((e.position - center) / (112*k)).limit_length(1.0)
			move_changed.emit(move_value)
			queue_redraw()
		elif e.index == look_id and not paused:
			look_delta.emit(e.relative)
		accept_event()
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed: _start(-2, e.position, w, h, k)
		else: _end(-2)
	elif e is InputEventMouseMotion and look_id == -2 and not paused:
		look_delta.emit(e.relative)

func _start(id: int, p: Vector2, w: float, h: float, k: float) -> void:
	if paused:
		if absf(p.y - h*0.49) < 90*k:
			resume_pressed.emit()
		elif absf(p.y - h*0.64) < 90*k:
			menu_pressed.emit()
		return
	if p.x > w - 95*k and p.y < 100*k:
		pause_pressed.emit()
		return
	var joy := Vector2(154*k, h - 190*k)
	var fire := Vector2(w - 112*k, h - 190*k)
	var jump := Vector2(w - 270*k, h - 92*k)
	var sprint := Vector2(w - 270*k, h - 285*k)
	# Test actual button hit circles first; this prevents overlap/ordering errors
	# on narrow Android aspect ratios and guarantees ATTACK emits its signal.
	if p.distance_to(fire) <= 100*k:
		fire_flash = 0.18
		fire_pressed.emit()
		queue_redraw()
	elif p.distance_to(jump) <= 78*k:
		jump_pressed.emit()
	elif p.distance_to(sprint) <= 76*k:
		sprinting = true
		sprint_changed.emit(true)
	elif p.x < w*0.46 and p.y > h*0.52:
		joy_id = id
		move_value = ((p - joy) / (112*k)).limit_length(1.0)
		move_changed.emit(move_value)
		queue_redraw()
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
