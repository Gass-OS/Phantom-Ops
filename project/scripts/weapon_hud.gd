class_name WeaponHud
extends Control
## v0.8 — standalone weapon HUD cluster. The coordinator adds this
## Control into the existing MobileHUDLayer (AFTER the MobileHUD
## child, so its buttons sit on top); it never touches mobile_hud.gd.
## Root has MOUSE_FILTER_IGNORE so look-drag passes through except
## on the real buttons. Drawn crosshair/scope ring/hitmarker live
## in _draw(); the MobileHUD still draws its own crosshair — when
## scoped, this cluster draws the scope ring OVER it and the
## coordinator should hide the MobileHUD crosshair if it can.
##
## Buttons are BIG (v0.3 HUD scale is the floor): RELOAD is 90 px
## tall, CYCLE 80 px, both 260 px wide. Layout is anchored to the
## right edge, mid-height, clear of the FIRE button (bottom-right)
## and the pause button (top-right).

signal reload_pressed
signal cycle_pressed
signal aim_toggled(scoped: bool)

const HITMARKER_MS := 120

var _wm: WeaponManager = null
var _name_label: Label
var _ammo_label: Label
var _reload_button: Button
var _cycle_button: Button
var _aim_button: Button
var _scoped := false
var _hitmarker_until := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	var f := LanguageManager.font_for_current()
	# --- Ammo panel, top-right under the pause button. ---
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -340.0
	panel.offset_right = -20.0
	panel.offset_top = 120.0
	panel.offset_bottom = 240.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.04, 0.55)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vb)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 30)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if f != null:
		_name_label.add_theme_font_override("font", f)
	vb.add_child(_name_label)
	_ammo_label = Label.new()
	_ammo_label.add_theme_font_size_override("font_size", 44)
	_ammo_label.add_theme_color_override("font_color", Color.WHITE)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if f != null:
		_ammo_label.add_theme_font_override("font", f)
	vb.add_child(_ammo_label)
	# --- RELOAD button (90 px tall), right edge mid-height. ---
	_reload_button = Button.new()
	_reload_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_reload_button.offset_left = -280.0
	_reload_button.offset_right = -20.0
	_reload_button.offset_top = 300.0
	_reload_button.offset_bottom = 390.0
	_reload_button.add_theme_font_size_override("font_size", 30)
	_reload_button.text = LanguageManager.t("hud_reload")
	LanguageManager.apply_font_to(_reload_button)
	_reload_button.pressed.connect(func() -> void: reload_pressed.emit())
	add_child(_reload_button)
	# --- CYCLE button (80 px tall) under RELOAD. ---
	_cycle_button = Button.new()
	_cycle_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_cycle_button.offset_left = -280.0
	_cycle_button.offset_right = -20.0
	_cycle_button.offset_top = 410.0
	_cycle_button.offset_bottom = 490.0
	_cycle_button.add_theme_font_size_override("font_size", 26)
	_cycle_button.text = ""
	LanguageManager.apply_font_to(_cycle_button)
	_cycle_button.pressed.connect(func() -> void: cycle_pressed.emit())
	add_child(_cycle_button)
	# --- AIM button (80 px tall) under CYCLE — sniper only, toggles
	# the scope (FOV zoom). Hidden for every other weapon.
	_aim_button = Button.new()
	_aim_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_aim_button.offset_left = -280.0
	_aim_button.offset_right = -20.0
	_aim_button.offset_top = 510.0
	_aim_button.offset_bottom = 590.0
	_aim_button.add_theme_font_size_override("font_size", 26)
	_aim_button.text = LanguageManager.t("hud_aim")
	LanguageManager.apply_font_to(_aim_button)
	_aim_button.pressed.connect(func() -> void: aim_toggled.emit(not _scoped))
	_aim_button.visible = false
	add_child(_aim_button)
	_refresh()


func setup(weapon_manager: WeaponManager) -> void:
	_wm = weapon_manager
	if _wm == null:
		return
	if _wm.has_signal("weapon_changed"):
		_wm.weapon_changed.connect(_on_weapon_changed)
	if _wm.has_signal("ammo_changed"):
		_wm.ammo_changed.connect(_on_ammo_changed)
	if _wm.has_signal("scoped_changed"):
		_wm.scoped_changed.connect(set_scoped_visual)
	_refresh()


func _process(_delta: float) -> void:
	if _hitmarker_until > 0 and Time.get_ticks_msec() > _hitmarker_until:
		_hitmarker_until = 0
		queue_redraw()


func _on_weapon_changed(_id: String) -> void:
	_refresh()


func _on_ammo_changed(_mag: int, _reserve: int) -> void:
	_refresh()


func _refresh() -> void:
	if _name_label == null or _ammo_label == null:
		return
	if _wm == null:
		_name_label.text = LanguageManager.t("weapon_rifle")
		_ammo_label.text = "%s  -- / --" % LanguageManager.t("hud_ammo")
		if _cycle_button != null:
			_cycle_button.text = ""
		return
	var id := _wm.get_current_id()
	_name_label.text = LanguageManager.t("weapon_" + id)
	var mag := _wm.get_mag()
	var reserve := _wm.get_reserve()
	var reserve_text := "∞" if reserve < 0 else str(reserve)
	var reloading := _wm.is_reloading()
	if reloading:
		_ammo_label.text = LanguageManager.t("hud_reloading")
	else:
		_ammo_label.text = "%s  %d / %s" % [LanguageManager.t("hud_ammo"), mag, reserve_text]
	if _cycle_button != null:
		var next_id := _next_owned_id()
		_cycle_button.text = LanguageManager.t("weapon_" + next_id) if next_id != "" else ""
		_cycle_button.disabled = _wm.get_owned().size() < 2
	if _reload_button != null:
		_reload_button.disabled = reloading
	if _aim_button != null:
		_aim_button.visible = _wm != null and _wm.get_current_id() == "sniper"
		_aim_button.text = LanguageManager.t("hud_aim") + (" ✓" if _scoped else "")
	queue_redraw()


func _next_owned_id() -> String:
	if _wm == null:
		return ""
	var owned := _wm.get_owned()
	if owned.size() < 2:
		return _wm.get_current_id()
	var order := _wm.get_all_ids()
	var idx := order.find(_wm.get_current_id())
	for step in range(1, order.size() + 1):
		var next_id: String = order[(idx + step) % order.size()]
		if next_id in owned:
			return next_id
	return _wm.get_current_id()


## Flash the hitmarker X for 120 ms. Called by the Player on a
## successful hit (same call site as mobile_hud.show_hitmarker()).
func show_hitmarker() -> void:
	_hitmarker_until = Time.get_ticks_msec() + HITMARKER_MS
	queue_redraw()


## Swap the centre crosshair for a scope ring while sniping.
## Called from WeaponManager.scoped_changed (wired in setup()) and
## by the Player/coordinator when toggling aim.
func set_scoped_visual(scoped: bool) -> void:
	_scoped = scoped
	_refresh()
	queue_redraw()


func _draw() -> void:
	var s := get_viewport_rect().size
	var cx := s.x / 2.0
	var cy := s.y / 2.0
	if _scoped:
		var ring := Color(0.05, 0.05, 0.05, 0.92)
		draw_circle(Vector2(cx, cy), 150.0, ring)
		draw_arc(Vector2(cx, cy), 150.0, 0, TAU, 64, Color(0.9, 0.9, 0.9, 0.95), 4.0, true)
		draw_arc(Vector2(cx, cy), 110.0, 0, TAU, 64, Color(0.9, 0.9, 0.9, 0.6), 2.0, true)
		var ch := Color(1, 1, 1, 0.95)
		draw_line(Vector2(cx - 150, cy), Vector2(cx - 12, cy), ch, 2.0)
		draw_line(Vector2(cx + 12, cy), Vector2(cx + 150, cy), ch, 2.0)
		draw_line(Vector2(cx, cy - 150), Vector2(cx, cy - 12), ch, 2.0)
		draw_line(Vector2(cx, cy + 12), Vector2(cx, cy + 150), ch, 2.0)
	if _hitmarker_until > 0:
		var hm := Color(1.0, 0.25, 0.2, 0.95)
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				draw_line(Vector2(cx + sx * 12, cy + sy * 12), Vector2(cx + sx * 28, cy + sy * 28), hm, 5.0)
