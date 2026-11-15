class_name ArmouryPanel
extends Control
## v0.8 — WEAPONS / ARMOURY shop (full-screen).
##
## IMPORTANT (lesson from Monster Merge): all content is built as
## DIRECT children of this Control. There is NO internal CanvasLayer
## — a CanvasLayer ignores its parent Control's visibility, so
## hiding the panel would leave it on screen. The coordinator adds
## this Control into an existing CanvasLayer and toggles visible.
##
## One row per weapon: name, description, stat bars (damage /
## fire rate / range), price in DT, rank requirement, and one
## action button: BUY / EQUIP (owned) / EQUIPPED / locked with the
## rank text / not enough DT. The player's current DT is shown at
## the top (live from GameManager). Every change applies
## immediately and persists via WeaponManager (user://weapons.cfg);
## the coordinator may additionally carry to_dict() in the campaign
## save — load_from_dict() afterwards wins.

signal closed

var _wm: WeaponManager = null
var _rows_vbox: VBoxContainer
var _money_label: Label
var _row_buttons: Dictionary = {}
var _money_connected := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.03, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	margin.add_child(vb)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	vb.add_child(header)
	var title := Label.new()
	title.text = LanguageManager.t("armoury_title")
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	LanguageManager.apply_font_to(title)
	header.add_child(title)
	_money_label = Label.new()
	_money_label.add_theme_font_size_override("font_size", 32)
	_money_label.add_theme_color_override("font_color", Color(0.6, 0.95, 0.5))
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	LanguageManager.apply_font_to(_money_label)
	header.add_child(_money_label)
	var close_button := Button.new()
	close_button.text = LanguageManager.t("menu_close")
	close_button.custom_minimum_size = Vector2(200, 72)
	close_button.add_theme_font_size_override("font_size", 28)
	LanguageManager.apply_font_to(close_button)
	close_button.pressed.connect(close)
	header.add_child(close_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_rows_vbox = VBoxContainer.new()
	_rows_vbox.add_theme_constant_override("separation", 14)
	_rows_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_vbox)


func open(weapon_manager: WeaponManager) -> void:
	_wm = weapon_manager
	visible = true
	_connect_money()
	_refresh()


func close() -> void:
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func _connect_money() -> void:
	if _money_connected:
		return
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.has_signal("money_changed"):
		gm.money_changed.connect(_on_money_changed)
		_money_connected = true


func _on_money_changed(_money: int) -> void:
	_refresh_money()
	_refresh_buttons()


func _refresh_money() -> void:
	if _money_label == null:
		return
	var money := 0
	var gm := get_node_or_null("/root/GameManager")
	if gm != null:
		money = int(gm.get("money"))
	_money_label.text = "%s: %d DT" % [LanguageManager.t("hud_money"), money]


func _refresh() -> void:
	_refresh_money()
	_rebuild_rows()


func _rebuild_rows() -> void:
	if _rows_vbox == null:
		return
	for child in _rows_vbox.get_children():
		child.queue_free()
	_row_buttons.clear()
	if _wm == null:
		return
	for id in _wm.get_all_ids():
		_rows_vbox.add_child(_build_row(id))


func _build_row(id: String) -> PanelContainer:
	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.10, 0.92)
	style.set_corner_radius_all(12)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	row.add_theme_stylebox_override("panel", style)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	row.add_child(hb)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	hb.add_child(info)
	var name_label := Label.new()
	name_label.text = LanguageManager.t("weapon_" + id)
	name_label.add_theme_font_size_override("font_size", 34)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	LanguageManager.apply_font_to(name_label)
	info.add_child(name_label)
	var desc := Label.new()
	desc.text = LanguageManager.t("weapon_desc_" + id)
	desc.add_theme_font_size_override("font_size", 22)
	desc.add_theme_color_override("font_color", Color(0.85, 0.88, 0.90))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	LanguageManager.apply_font_to(desc)
	info.add_child(desc)
	var stats := _wm.get_stats(id)
	info.add_child(_stat_bar("armoury_stat_damage", float(stats["damage"]) / 150.0))
	info.add_child(_stat_bar("armoury_stat_firerate", clampf(1.0 / float(stats["interval"]) / 14.3, 0.0, 1.0)))
	info.add_child(_stat_bar("armoury_stat_range", float(stats["range"]) / 200.0))
	var price_label := Label.new()
	var price := _wm.get_price(id)
	var rank := _wm.get_min_rank(id)
	var rank_name := ""
	var cm := get_node_or_null("/root/CampaignManager")
	if cm != null and cm.has_method("rank_name"):
		rank_name = String(cm.call("rank_name", rank))
	if price <= 0:
		price_label.text = LanguageManager.t("armoury_free")
	else:
		price_label.text = "%d DT" % price
	if rank > 0:
		price_label.text += "  •  %s" % rank_name
	price_label.add_theme_font_size_override("font_size", 26)
	price_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	LanguageManager.apply_font_to(price_label)
	info.add_child(price_label)
	var button := Button.new()
	button.custom_minimum_size = Vector2(260, 84)
	button.add_theme_font_size_override("font_size", 28)
	LanguageManager.apply_font_to(button)
	button.pressed.connect(_on_row_button.bind(id))
	hb.add_child(button)
	_row_buttons[id] = button
	_update_row_button(id, button)
	return row


func _stat_bar(label_key: String, ratio: float) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = LanguageManager.t(label_key)
	label.custom_minimum_size = Vector2(160, 0)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.8, 0.84, 0.86))
	LanguageManager.apply_font_to(label)
	hb.add_child(label)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(ratio, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(420, 22)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(bar)
	return hb


func _update_row_button(id: String, button: Button) -> void:
	if _wm == null:
		return
	if _wm.get_current_id() == id:
		button.text = LanguageManager.t("armoury_equipped")
		button.disabled = true
		return
	if _wm.is_owned(id):
		button.text = LanguageManager.t("armoury_equip")
		button.disabled = false
		return
	var cm_rank := 0
	var cm := get_node_or_null("/root/CampaignManager")
	if cm != null and cm.has_method("get_rank"):
		cm_rank = int(cm.call("get_rank"))
	if cm_rank < _wm.get_min_rank(id):
		var rank_name := ""
		if cm != null and cm.has_method("rank_name"):
			rank_name = String(cm.call("rank_name", _wm.get_min_rank(id)))
		button.text = "%s: %s" % [LanguageManager.t("armoury_locked_rank"), rank_name]
		button.disabled = true
		return
	var gm_money := 0
	var gm := get_node_or_null("/root/GameManager")
	if gm != null:
		gm_money = int(gm.get("money"))
	if gm_money < _wm.get_price(id):
		button.text = LanguageManager.t("armoury_not_enough_dt")
		button.disabled = true
		return
	button.text = LanguageManager.t("armoury_buy")
	button.disabled = false


func _refresh_buttons() -> void:
	for id in _row_buttons.keys():
		var button := _row_buttons[id] as Button
		if is_instance_valid(button):
			_update_row_button(String(id), button)


func _on_row_button(id: String) -> void:
	if _wm == null:
		return
	var changed := false
	if _wm.is_owned(id):
		changed = _wm.equip(id)
	else:
		changed = _wm.buy(id)
	if changed:
		# v0.8 (coordinator integration): flush the campaign save
		# immediately — the throttled 1 s flush is not fast enough if
		# the player dies and the scene reloads first.
		var cm := get_node_or_null("/root/CampaignManager")
		if cm != null and cm.has_method("save_now"):
			cm.call("save_now")
	_refresh()
