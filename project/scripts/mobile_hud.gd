extends Control
## Phantom Ops v0.3 — touch HUD.
## v0.3 fix: the drawn buttons and the tap test now come from ONE layout
## (_layout), so a tap can never miss a button it can see. v0.2 drew FIRE
## at (w-94, h-116) r42 but tested a rectangle (x > w-150, y > h-105):
## only the bottom sliver of FIRE fired — a centre tap fell through to
## sprint. Now every button is a proper circle hit-test, FIRE first.
## Buttons are ~1.7x bigger than v0.2 and scale with the viewport.
signal move_changed(value: Vector2)
signal look_delta(value: Vector2)
signal jump_pressed
signal fire_pressed
signal fire_held_changed(value: bool)
signal pause_pressed
signal resume_pressed
signal menu_pressed
# v0.5: death flow. RETRY reloads the game, death_menu_pressed goes
# to the main menu. Before v0.5 nothing listened to player_died, so
# death left the player frozen with no screen and no way out.
signal retry_pressed
signal death_menu_pressed
signal sound_toggled(value: bool)
signal voices_toggled(value: bool)
signal sprint_changed(value: bool)
var joy_id := -1
var look_id := -1
var fire_id := -1
var run_id := -1
var move_value := Vector2.ZERO
var paused := false
# v0.5 death state. While dead the game buttons are inert and only
# the RETRY / MAIN MENU buttons respond.
var dead := false
var death_score := 0
var death_kills := 0
var death_wave := 1
var sprinting := false
var sound_on := true
var voices_on := true
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

# One layout for drawing AND hit-testing. Base sizes are for a
# 1920x1080 landscape viewport; they scale down a little on small
# screens and up a little on very large ones, never below 0.7x.
func _layout(w: float, h: float) -> Dictionary:
	var s := clampf(minf(w / 1920.0, h / 1080.0), 0.7, 1.25)
	return {
		"joy_c": Vector2(170.0 * s, h - 170.0 * s),
		"joy_r": 118.0 * s,
		"knob_r": 46.0 * s,
		"fire_c": Vector2(w - 130.0 * s, h - 150.0 * s),
		"fire_r": 80.0 * s,
		"jump_c": Vector2(w - 330.0 * s, h - 95.0 * s),
		"jump_r": 60.0 * s,
		"run_c": Vector2(w - 330.0 * s, h - 250.0 * s),
		"run_r": 56.0 * s,
		"pause_c": Vector2(w - 60.0 * s, 60.0 * s),
		"pause_r": 40.0 * s,
		"resume_c": Vector2(w * 0.5, h * 0.47),
		"resume_r": 58.0 * s,
		"menu_c": Vector2(w * 0.5, h * 0.60),
		"menu_r": 58.0 * s,
		"sound_c": Vector2(w * 0.5, h * 0.73),
		"sound_r": 58.0 * s,
		"voices_c": Vector2(w * 0.5, h * 0.86),
		"voices_r": 58.0 * s,
		"retry_c": Vector2(w * 0.5, h * 0.58),
		"retry_r": 58.0 * s,
		"death_menu_c": Vector2(w * 0.5, h * 0.76),
		"death_menu_r": 58.0 * s,
		"s": s,
	}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	queue_redraw()

func _process(_delta: float) -> void:
	if _hitmarker_until > 0 and Time.get_ticks_msec() > _hitmarker_until:
		_hitmarker_until = 0
		queue_redraw()

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

func set_sound_on(v: bool) -> void:
	sound_on = v
	queue_redraw()

# v0.5: show the death overlay. Called once from player._on_player_died.
func show_death(final_score: int, final_kills: int, final_wave: int) -> void:
	dead = true
	death_score = final_score
	death_kills = final_kills
	death_wave = final_wave
	# Release any held buttons so a held FIRE cannot leak into retry.
	fire_id = -1
	joy_id = -1
	look_id = -1
	run_id = -1
	sprinting = false
	move_value = Vector2.ZERO
	queue_redraw()

func is_dead_shown() -> bool:
	return dead

func set_voices_on(v: bool) -> void:
	voices_on = v
	queue_redraw()

func _draw() -> void:
	var s := get_viewport_rect().size
	var w := s.x
	var h := s.y
	var lay := _layout(w, h)
	var sc: float = lay["s"]
	# v0.6: translated UI. Arabic uses the Noto Naskh font (cached
	# inside LanguageManager); FR/EN use the default theme font.
	var f: Font = LanguageManager.font_for_current()
	if f == null:
		f = ThemeDB.fallback_font
	var joy_c: Vector2 = lay["joy_c"]
	var joy_r: float = lay["joy_r"]
	# Joystick.
	_button(joy_c, joy_r, Color(0.08, 0.12, 0.16, 0.48))
	_button(joy_c + move_value * (joy_r - 46.0 * sc), 46.0 * sc, Color(0.75, 0.82, 0.86, 0.8))
	draw_string(f, Vector2(joy_c.x - 46.0 * sc, joy_c.y + joy_r + 34.0 * sc), LanguageManager.translate("hud_move"), HORIZONTAL_ALIGNMENT_CENTER, 92.0 * sc, int(22.0 * sc), Color.WHITE)
	# FIRE / JUMP / RUN — same centres/radii as the hit test.
	var fire_c: Vector2 = lay["fire_c"]
	var fire_r: float = lay["fire_r"]
	var fire_col := Color(0.85, 0.16, 0.12, 0.9) if fire_id != -1 else Color(0.72, 0.16, 0.12, 0.78)
	_button(fire_c, fire_r, fire_col)
	draw_string(f, Vector2(fire_c.x - fire_r, fire_c.y + 9.0 * sc), LanguageManager.translate("hud_fire"), HORIZONTAL_ALIGNMENT_CENTER, fire_r * 2.0, int(26.0 * sc), Color.WHITE)
	var jump_c: Vector2 = lay["jump_c"]
	var jump_r: float = lay["jump_r"]
	_button(jump_c, jump_r, Color(0.16, 0.38, 0.58, 0.8))
	draw_string(f, Vector2(jump_c.x - jump_r, jump_c.y + 7.0 * sc), LanguageManager.translate("hud_jump"), HORIZONTAL_ALIGNMENT_CENTER, jump_r * 2.0, int(20.0 * sc), Color.WHITE)
	var run_c: Vector2 = lay["run_c"]
	var run_r: float = lay["run_r"]
	var run_col := Color(0.35, 0.45, 0.50, 0.95) if sprinting else Color(0.22, 0.25, 0.29, 0.8)
	_button(run_c, run_r, run_col)
	draw_string(f, Vector2(run_c.x - run_r, run_c.y + 7.0 * sc), LanguageManager.translate("hud_run"), HORIZONTAL_ALIGNMENT_CENTER, run_r * 2.0, int(20.0 * sc), Color.WHITE)
	# Pause.
	var pause_c: Vector2 = lay["pause_c"]
	var pause_r: float = lay["pause_r"]
	_button(pause_c, pause_r, Color(0.08, 0.10, 0.13, 0.85))
	draw_string(f, Vector2(pause_c.x - pause_r, pause_c.y + 10.0 * sc), "II", HORIZONTAL_ALIGNMENT_CENTER, pause_r * 2.0, int(28.0 * sc), Color.WHITE)
	# Title chip + health bar (bigger than v0.2).
	draw_rect(Rect2(18, 18, 250, 46), Color(0.02, 0.03, 0.04, 0.55), true)
	draw_string(f, Vector2(30, 48), "PHANTOM OPS  •  FIELD", HORIZONTAL_ALIGNMENT_LEFT, 230, int(18.0 * sc), Color.WHITE)
	var hp_ratio := clampf(health / maxf(max_health, 1.0), 0.0, 1.0)
	draw_rect(Rect2(18, 72, 260, 24), Color(0.02, 0.03, 0.04, 0.6), true)
	var hp_col := Color(0.25, 0.75, 0.30) if hp_ratio > 0.5 else (Color(0.9, 0.7, 0.2) if hp_ratio > 0.25 else Color(0.85, 0.2, 0.15))
	draw_rect(Rect2(20, 74, 256 * hp_ratio, 20), hp_col, true)
	draw_string(f, Vector2(26, 92), "%s %d" % [LanguageManager.translate("hud_hp"), int(health)], HORIZONTAL_ALIGNMENT_LEFT, -1, int(16.0 * sc), Color.WHITE)
	# Score / kills / wave, top centre.
	var status := "%s %d    %s %d    %s %d" % [LanguageManager.translate("hud_score"), score, LanguageManager.translate("hud_kills"), kills, LanguageManager.translate("hud_wave"), wave]
	draw_rect(Rect2(w / 2 - 230, 18, 460, 42), Color(0.02, 0.03, 0.04, 0.55), true)
	draw_string(f, Vector2(w / 2 - 215, 47), status, HORIZONTAL_ALIGNMENT_LEFT, 430, int(20.0 * sc), Color.WHITE)
	_draw_compass(f, w)
	# Ammo, above FIRE; hold-to-fire hint under it.
	var ammo_text := LanguageManager.translate("hud_reloading") if reloading else "%s  %d / %d" % [LanguageManager.translate("hud_ammo"), ammo, mag_size]
	var ammo_col := Color(0.95, 0.75, 0.3) if reloading or ammo <= 6 else Color.WHITE
	draw_string(f, Vector2(fire_c.x - 130.0 * sc, fire_c.y - fire_r - 18.0 * sc), ammo_text, HORIZONTAL_ALIGNMENT_LEFT, 260.0 * sc, int(24.0 * sc), ammo_col)
	draw_string(f, Vector2(fire_c.x - 130.0 * sc, fire_c.y + fire_r + 30.0 * sc), LanguageManager.translate("hud_hold_fire"), HORIZONTAL_ALIGNMENT_LEFT, 260.0 * sc, int(14.0 * sc), Color(1, 1, 1, 0.65))
	# Crosshair + hit marker, screen centre.
	if not paused and not dead:
		var cx := w / 2
		var cy := h / 2
		var ch := Color(1, 1, 1, 0.9)
		draw_line(Vector2(cx - 22, cy), Vector2(cx - 8, cy), ch, 3)
		draw_line(Vector2(cx + 8, cy), Vector2(cx + 22, cy), ch, 3)
		draw_line(Vector2(cx, cy - 22), Vector2(cx, cy - 8), ch, 3)
		draw_line(Vector2(cx, cy + 8), Vector2(cx, cy + 22), ch, 3)
		draw_circle(Vector2(cx, cy), 2.0, ch)
		if _hitmarker_until > 0:
			var hm := Color(1.0, 0.25, 0.2, 0.95)
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					draw_line(Vector2(cx + sx * 10, cy + sy * 10), Vector2(cx + sx * 24, cy + sy * 24), hm, 4)
	if paused:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.01, 0.02, 0.03, 0.82), true)
		draw_string(f, Vector2(w / 2 - 200, h * 0.30), LanguageManager.translate("pause_title"), HORIZONTAL_ALIGNMENT_CENTER, 400, int(34.0 * sc), Color.WHITE)
		var resume_c: Vector2 = lay["resume_c"]
		var resume_r: float = lay["resume_r"]
		_button(resume_c, resume_r, Color(0.12, 0.42, 0.30, 0.98))
		draw_string(f, Vector2(resume_c.x - 110.0 * sc, resume_c.y + 6.0 * sc), LanguageManager.translate("pause_resume"), HORIZONTAL_ALIGNMENT_CENTER, 220.0 * sc, int(22.0 * sc), Color.WHITE)
		var menu_c: Vector2 = lay["menu_c"]
		var menu_r: float = lay["menu_r"]
		_button(menu_c, menu_r, Color(0.45, 0.16, 0.13, 0.98))
		draw_string(f, Vector2(menu_c.x - 110.0 * sc, menu_c.y + 6.0 * sc), LanguageManager.translate("pause_menu"), HORIZONTAL_ALIGNMENT_CENTER, 220.0 * sc, int(20.0 * sc), Color.WHITE)
		var sound_c: Vector2 = lay["sound_c"]
		var sound_r: float = lay["sound_r"]
		_button(sound_c, sound_r, Color(0.16, 0.30, 0.45, 0.98))
		var sound_text := LanguageManager.translate("sound_on") if sound_on else LanguageManager.translate("sound_off")
		draw_string(f, Vector2(sound_c.x - 120.0 * sc, sound_c.y + 6.0 * sc), sound_text, HORIZONTAL_ALIGNMENT_CENTER, 240.0 * sc, int(20.0 * sc), Color.WHITE)
		var voices_c: Vector2 = lay["voices_c"]
		var voices_r: float = lay["voices_r"]
		_button(voices_c, voices_r, Color(0.30, 0.35, 0.20, 0.98))
		var voices_text := LanguageManager.translate("voices_on") if voices_on else LanguageManager.translate("voices_off")
		draw_string(f, Vector2(voices_c.x - 120.0 * sc, voices_c.y + 6.0 * sc), voices_text, HORIZONTAL_ALIGNMENT_CENTER, 240.0 * sc, int(20.0 * sc), Color.WHITE)
	if dead:
		# v0.5 death overlay: dark red wash over the whole screen, big
		# YOU DIED, final stats, RETRY + MAIN MENU. Drawn last so it
		# covers the game buttons.
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.10, 0.01, 0.01, 0.88), true)
		draw_string(f, Vector2(w / 2 - 320, h * 0.26), LanguageManager.translate("death_title"), HORIZONTAL_ALIGNMENT_CENTER, 640, int(64.0 * sc), Color(0.95, 0.25, 0.18))
		var stats := "%s %d    %s %d    %s %d" % [LanguageManager.translate("death_score"), death_score, LanguageManager.translate("death_kills"), death_kills, LanguageManager.translate("death_wave"), death_wave]
		draw_string(f, Vector2(w / 2 - 320, h * 0.40), stats, HORIZONTAL_ALIGNMENT_CENTER, 640, int(26.0 * sc), Color(1, 0.9, 0.75))
		var retry_c: Vector2 = lay["retry_c"]
		var retry_r: float = lay["retry_r"]
		_button(retry_c, retry_r, Color(0.12, 0.42, 0.30, 0.98))
		draw_string(f, Vector2(retry_c.x - 130.0 * sc, retry_c.y + 8.0 * sc), LanguageManager.translate("death_retry"), HORIZONTAL_ALIGNMENT_CENTER, 260.0 * sc, int(24.0 * sc), Color.WHITE)
		var dm_c: Vector2 = lay["death_menu_c"]
		var dm_r: float = lay["death_menu_r"]
		_button(dm_c, dm_r, Color(0.45, 0.16, 0.13, 0.98))
		draw_string(f, Vector2(dm_c.x - 130.0 * sc, dm_c.y + 8.0 * sc), LanguageManager.translate("death_menu"), HORIZONTAL_ALIGNMENT_CENTER, 260.0 * sc, int(22.0 * sc), Color.WHITE)

func _draw_compass(f: Font, w: float) -> void:
	var heading := wrapf(-rad_to_deg(compass_yaw), 0.0, 360.0)
	var labels := {0.0: "N", 45.0: "NE", 90.0: "E", 135.0: "SE", 180.0: "S", 225.0: "SW", 270.0: "W", 315.0: "NW"}
	var cx := w / 2
	for offset in range(-60, 61, 15):
		var ang := wrapf(heading + float(offset), 0.0, 360.0)
		var x := cx + float(offset) * 4.0
		var label := ""
		for a in labels.keys():
			if absf(wrapf(ang - a, -180.0, 180.0)) < 8.0:
				label = labels[a]
		if label != "":
			draw_string(f, Vector2(x - 14, 92), label, HORIZONTAL_ALIGNMENT_CENTER, 28, 18, Color(1, 0.85, 0.5))
		else:
			draw_line(Vector2(x, 76), Vector2(x, 84), Color(1, 1, 1, 0.6), 1)
	draw_line(Vector2(cx, 70), Vector2(cx, 76), Color(1, 0.85, 0.5), 2)

func _button(p: Vector2, r: float, color: Color) -> void:
	draw_circle(p, r, color)
	draw_arc(p, r, 0, TAU, 48, Color(0.9, 0.94, 1, 0.85), 3, true)

func _gui_input(e: InputEvent) -> void:
	var s := get_viewport_rect().size
	if e is InputEventScreenTouch:
		if e.pressed:
			_start(e.index, e.position, s.x, s.y)
		else:
			_end(e.index)
		accept_event()
	elif e is InputEventScreenDrag:
		if e.index == joy_id:
			var lay := _layout(s.x, s.y)
			var joy_c: Vector2 = lay["joy_c"]
			var joy_r: float = lay["joy_r"]
			move_value = ((e.position - joy_c) / joy_r).limit_length(1)
			move_changed.emit(move_value)
			queue_redraw()
		elif e.index == look_id and not paused and not dead:
			look_delta.emit(e.relative)
		accept_event()
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_start(-2, e.position, s.x, s.y)
		else:
			_end(-2)
	elif e is InputEventMouseMotion and look_id == -2 and not paused and not dead:
		look_delta.emit(e.relative)

func _start(id: int, p: Vector2, w: float, h: float) -> void:
	var lay := _layout(w, h)
	if dead:
		# Only the death buttons respond; every game button is inert.
		if p.distance_to(lay["retry_c"]) <= float(lay["retry_r"]) + 12.0:
			retry_pressed.emit()
		elif p.distance_to(lay["death_menu_c"]) <= float(lay["death_menu_r"]) + 12.0:
			death_menu_pressed.emit()
		return
	if paused:
		# Circle hit-tests, same centres as drawn — no y-only bands.
		if p.distance_to(lay["resume_c"]) <= float(lay["resume_r"]) + 12.0:
			resume_pressed.emit()
		elif p.distance_to(lay["menu_c"]) <= float(lay["menu_r"]) + 12.0:
			menu_pressed.emit()
		elif p.distance_to(lay["sound_c"]) <= float(lay["sound_r"]) + 12.0:
			sound_on = not sound_on
			sound_toggled.emit(sound_on)
			queue_redraw()
		elif p.distance_to(lay["voices_c"]) <= float(lay["voices_r"]) + 12.0:
			voices_on = not voices_on
			voices_toggled.emit(voices_on)
			queue_redraw()
		return
	if p.distance_to(lay["pause_c"]) <= float(lay["pause_r"]) + 12.0:
		pause_pressed.emit()
		return
	# FIRE first: it is the biggest button and must never be shadowed.
	if p.distance_to(lay["fire_c"]) <= float(lay["fire_r"]) + 10.0:
		fire_id = id
		fire_pressed.emit()
		fire_held_changed.emit(true)
		queue_redraw()
		return
	if p.distance_to(lay["jump_c"]) <= float(lay["jump_r"]) + 10.0:
		jump_pressed.emit()
		return
	if p.distance_to(lay["run_c"]) <= float(lay["run_r"]) + 10.0:
		run_id = id
		sprinting = true
		sprint_changed.emit(true)
		queue_redraw()
		return
	var joy_c: Vector2 = lay["joy_c"]
	var joy_r: float = lay["joy_r"]
	if p.x < w * 0.43 and p.y > h * 0.55:
		joy_id = id
		move_value = ((p - joy_c) / joy_r).limit_length(1)
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
	if id == look_id:
		look_id = -1
	if id == fire_id:
		fire_id = -1
		fire_held_changed.emit(false)
		queue_redraw()
	if id == run_id:
		run_id = -1
		if sprinting:
			sprinting = false
			sprint_changed.emit(false)
			queue_redraw()

# Public wrappers for the headless hit-test (underscore methods are
# private in GDScript and cannot be called from another script).
# These call this file's own _layout()/_start()/_end(), so the test
# exercises the real hit classification, not a copy of it.
func layout_for_test(w: float, h: float) -> Dictionary:
	return _layout(w, h)

func start_for_test(id: int, p: Vector2, w: float, h: float) -> void:
	_start(id, p, w, h)

func end_for_test(id: int) -> void:
	_end(id)

func fire_held_for_test() -> bool:
	return fire_id != -1

func set_paused(v: bool) -> void:
	paused = v
	queue_redraw()
