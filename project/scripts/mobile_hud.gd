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
# v0.2 HUD state (set by Player / EnemySpawner via the setters below).
var health := 100.0
var max_health := 100.0
var ammo := 30
var mag_size := 30
var reloading := false
var score := 0
var kills := 0
var wave := 1
var compass_yaw := 0.0
var _hitmarker_until := 0
const JOY := Vector2(112, -128)
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	queue_redraw()
func _process(_delta: float) -> void:
	if _hitmarker_until > 0 and Time.get_ticks_msec() > _hitmarker_until:
		_hitmarker_until = 0
		queue_redraw()
# --- setters (safe to call before _ready: they only store + redraw) ---
func set_health(current: float, maximum: float) -> void:
	health = current
	max_health = maximum
	queue_redraw()
func set_ammo(current: int, mag: int, is_reloading: bool) -> void:
	ammo = current
	mag_size = mag
	reloading = is_reloading
	queue_redraw()
func set_score(new_score: int, new_kills: int) -> void:
	score = new_score
	kills = new_kills
	queue_redraw()
func set_wave(new_wave: int) -> void:
	wave = new_wave
	queue_redraw()
func set_compass(yaw: float) -> void:
	if absf(yaw - compass_yaw) > 0.02:
		compass_yaw = yaw
		queue_redraw()
func show_hitmarker() -> void:
	_hitmarker_until = Time.get_ticks_msec() + 250
	queue_redraw()
func _draw() -> void:
	var s := get_viewport_rect().size
	var w := s.x
	var h := s.y
	var f := ThemeDB.fallback_font
	var c := Vector2(112, h - 128)
	_button(c, 76, Color(0.08,0.12,0.16,0.48))
	_button(c + move_value * 43, 29, Color(0.75,0.82,0.86,0.8))
	draw_string(f, Vector2(34,h-24), "MOVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	_button(Vector2(w-94,h-116), 42, Color(0.72,0.16,0.12,0.78))
	draw_string(f, Vector2(w-125,h-108), "FIRE", HORIZONTAL_ALIGNMENT_CENTER, 62, 16, Color.WHITE)
	_button(Vector2(w-194,h-72), 34, Color(0.16,0.38,0.58,0.8))
	draw_string(f, Vector2(w-222,h-67), "JUMP", HORIZONTAL_ALIGNMENT_CENTER, 56, 12, Color.WHITE)
	_button(Vector2(w-194,h-158), 32, Color(0.22,0.25,0.29,0.8))
	draw_string(f, Vector2(w-222,h-154), "RUN", HORIZONTAL_ALIGNMENT_CENTER, 56, 12, Color.WHITE)
	_button(Vector2(w-42,42), 25, Color(0.08,0.10,0.13,0.85))
	draw_string(f, Vector2(w-51,48), "Ⅱ", HORIZONTAL_ALIGNMENT_CENTER, 18, 18, Color.WHITE)
	draw_rect(Rect2(18,18,170,34), Color(0.02,0.03,0.04,0.55), true)
	draw_string(f, Vector2(28,41), "PHANTOM OPS  •  FIELD", HORIZONTAL_ALIGNMENT_LEFT, 160, 12, Color.WHITE)
	# --- v0.2: health bar under the title chip ---
	var hp_ratio := clampf(health / maxf(max_health, 1.0), 0.0, 1.0)
	draw_rect(Rect2(18, 58, 180, 16), Color(0.02,0.03,0.04,0.6), true)
	var hp_col := Color(0.25,0.75,0.30) if hp_ratio > 0.5 else (Color(0.9,0.7,0.2) if hp_ratio > 0.25 else Color(0.85,0.2,0.15))
	draw_rect(Rect2(20, 60, 176 * hp_ratio, 12), hp_col, true)
	draw_string(f, Vector2(24, 71), "HP %d" % int(health), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	# --- v0.2: score / kills / wave, top centre ---
	var status := "SCORE %d    KILLS %d    WAVE %d" % [score, kills, wave]
	draw_rect(Rect2(w / 2 - 170, 18, 340, 30), Color(0.02,0.03,0.04,0.55), true)
	draw_string(f, Vector2(w / 2 - 160, 39), status, HORIZONTAL_ALIGNMENT_LEFT, 320, 14, Color.WHITE)
	# --- v0.2: compass strip under the status bar ---
	_draw_compass(f, w)
	# --- v0.2: ammo, above the FIRE button ---
	var ammo_text := "RELOADING..." if reloading else "AMMO  %d / %d" % [ammo, mag_size]
	var ammo_col := Color(0.95,0.75,0.3) if reloading or ammo <= 6 else Color.WHITE
	draw_string(f, Vector2(w - 260, h - 205), ammo_text, HORIZONTAL_ALIGNMENT_LEFT, 200, 16, ammo_col)
	# --- v0.2: crosshair + hit marker, screen centre ---
	if not paused:
		var cx := w / 2
		var cy := h / 2
		var ch := Color(1, 1, 1, 0.9)
		draw_line(Vector2(cx - 16, cy), Vector2(cx - 6, cy), ch, 2)
		draw_line(Vector2(cx + 6, cy), Vector2(cx + 16, cy), ch, 2)
		draw_line(Vector2(cx, cy - 16), Vector2(cx, cy - 6), ch, 2)
		draw_line(Vector2(cx, cy + 6), Vector2(cx, cy + 16), ch, 2)
		draw_circle(Vector2(cx, cy), 1.5, ch)
		if _hitmarker_until > 0:
			var hm := Color(1.0, 0.25, 0.2, 0.95)
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					draw_line(Vector2(cx + sx * 8, cy + sy * 8), Vector2(cx + sx * 18, cy + sy * 18), hm, 3)
	if paused:
		draw_rect(Rect2(Vector2.ZERO,s), Color(0.01,0.02,0.03,0.82), true)
		draw_string(f, Vector2(w/2-100,h*0.36), "MISSION PAUSED", HORIZONTAL_ALIGNMENT_CENTER, 200, 24, Color.WHITE)
		_button(Vector2(w/2,h*0.49), 38, Color(0.12,0.42,0.30,0.98))
		draw_string(f, Vector2(w/2-48,h*0.49+5), "RESUME", HORIZONTAL_ALIGNMENT_CENTER, 96, 15, Color.WHITE)
		_button(Vector2(w/2,h*0.60), 38, Color(0.45,0.16,0.13,0.98))
		draw_string(f, Vector2(w/2-58,h*0.60+5), "MAIN MENU", HORIZONTAL_ALIGNMENT_CENTER, 116, 14, Color.WHITE)
func _draw_compass(f: Font, w: float) -> void:
	var heading := wrapf(-rad_to_deg(compass_yaw), 0.0, 360.0)
	var labels := {0.0: "N", 45.0: "NE", 90.0: "E", 135.0: "SE", 180.0: "S", 225.0: "SW", 270.0: "W", 315.0: "NW"}
	var cx := w / 2
	for offset in range(-60, 61, 15):
		var ang := wrapf(heading + float(offset), 0.0, 360.0)
		var x := cx + float(offset) * 3.0
		var label := ""
		for a in labels.keys():
			if absf(wrapf(ang - a, -180.0, 180.0)) < 8.0:
				label = labels[a]
		if label != "":
			draw_string(f, Vector2(x - 10, 72), label, HORIZONTAL_ALIGNMENT_CENTER, 20, 13, Color(1, 0.85, 0.5))
		else:
			draw_line(Vector2(x, 60), Vector2(x, 66), Color(1, 1, 1, 0.6), 1)
	draw_line(Vector2(cx, 56), Vector2(cx, 60), Color(1, 0.85, 0.5), 2)
func _button(p: Vector2, r: float, color: Color) -> void:
	draw_circle(p,r,color)
	draw_arc(p,r,0,TAU,48,Color(0.9,0.94,1,0.85),2,true)
func _gui_input(e: InputEvent) -> void:
	var s := get_viewport_rect().size
	if e is InputEventScreenTouch:
		if e.pressed: _start(e.index,e.position,s.x,s.y)
		else: _end(e.index)
		accept_event()
	elif e is InputEventScreenDrag:
		if e.index == joy_id:
			move_value = ((e.position - Vector2(112,s.y-128))/76).limit_length(1)
			move_changed.emit(move_value)
			queue_redraw()
		elif e.index == look_id and not paused: look_delta.emit(e.relative)
		accept_event()
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed: _start(-2,e.position,s.x,s.y)
		else: _end(-2)
	elif e is InputEventMouseMotion and look_id == -2 and not paused:
		look_delta.emit(e.relative)
func _start(id: int,p: Vector2,w: float,h: float) -> void:
	if paused:
		if absf(p.y-h*0.49)<48: resume_pressed.emit()
		elif absf(p.y-h*0.60)<48: menu_pressed.emit()
		return
	if p.x>w-76 and p.y<82: pause_pressed.emit()
	elif p.x<w*0.43 and p.y>h*0.55:
		joy_id=id
		move_value=((p-Vector2(112,h-128))/76).limit_length(1)
		move_changed.emit(move_value)
		queue_redraw()
	elif p.x>w-245 and p.y>h-205:
		if p.y>h-105 and p.x>w-150: fire_pressed.emit()
		elif p.y>h-115: jump_pressed.emit()
		else:
			sprinting=true
			sprint_changed.emit(true)
	else: look_id=id
func _end(id: int) -> void:
	if id==joy_id:
		joy_id=-1
		move_value=Vector2.ZERO
		move_changed.emit(Vector2.ZERO)
		queue_redraw()
	if id==look_id: look_id=-1
	if sprinting:
		sprinting=false
		sprint_changed.emit(false)
func set_paused(v: bool) -> void:
	paused=v
	queue_redraw()
