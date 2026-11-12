extends Control

var settings_panel: PanelContainer

func _ready() -> void:
	_build_menu()

func _style_panel(panel: Control, color: Color, border: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(18)
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 26
	style.content_margin_bottom = 26
	panel.add_theme_stylebox_override("panel", style)

func _build_menu() -> void:
	var viewport := get_viewport_rect().size
	var scale := clampf(minf(viewport.x / 600.0, viewport.y / 900.0), 1.0, 1.55)
	var bg := ColorRect.new()
	bg.color = Color(0.018,0.03,0.043)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var glow := ColorRect.new()
	glow.color = Color(0.10,0.18,0.22,0.32)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(glow)
	var root := CenterContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(viewport.x*0.90, 760.0), 0)
	_style_panel(panel,Color(0.035,0.055,0.072,0.98),Color(0.23,0.43,0.49))
	root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",int(20*scale))
	panel.add_child(column)
	var eyebrow := Label.new()
	eyebrow.text = "TACTICAL SURVIVAL  /  KASSERINE DISTRICT"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_color_override("font_color",Color(0.95,0.48,0.26))
	eyebrow.add_theme_font_size_override("font_size",int(19*scale))
	column.add_child(eyebrow)
	var title := Label.new()
	title.text = "PHANTOM OPS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color",Color(0.94,0.97,0.99))
	title.add_theme_font_size_override("font_size",int(64*scale))
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "THE CITY HAS FALLEN. YOUR MISSION HAS NOT."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color",Color(0.65,0.76,0.81))
	subtitle.add_theme_font_size_override("font_size",int(17*scale))
	column.add_child(subtitle)
	column.add_child(HSeparator.new())
	_add_button(column,"DEPLOY  /  ENTER THE ZONE",_on_deploy,Color(0.67,0.20,0.13),scale)
	_add_button(column,"SETTINGS",_on_settings,Color(0.12,0.27,0.34),scale)
	_add_button(column,"EXIT GAME",_on_exit,Color(0.15,0.17,0.20),scale)
	var footer := Label.new()
	footer.text = "ANDROID FIELD BUILD  •  SURVIVE THE NIGHT"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color",Color(0.52,0.62,0.68))
	footer.add_theme_font_size_override("font_size",int(14*scale))
	column.add_child(footer)

func _add_button(parent: VBoxContainer, caption: String, action: Callable, color: Color, scale: float) -> void:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(0, int(82*scale))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size",int(23*scale))
	button.add_theme_color_override("font_color",Color.WHITE)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(13)
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	button.add_theme_stylebox_override("normal",style)
	var hover := style.duplicate()
	hover.bg_color = color.lightened(0.13)
	button.add_theme_stylebox_override("hover",hover)
	button.pressed.connect(action)
	parent.add_child(button)

func _on_deploy() -> void:
	get_tree().change_scene_to_file("res://scenes/main_game.tscn")

func _on_settings() -> void:
	if is_instance_valid(settings_panel):
		settings_panel.queue_free()
		settings_panel = null
		return
	var scale := clampf(get_viewport_rect().size.x/600.0,1.0,1.45)
	settings_panel = PanelContainer.new()
	settings_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	settings_panel.position = Vector2(-get_viewport_rect().size.x*0.42,-150*scale)
	settings_panel.custom_minimum_size = Vector2(get_viewport_rect().size.x*0.84,300*scale)
	_style_panel(settings_panel,Color(0.025,0.045,0.06,0.99),Color(0.3,0.48,0.53))
	add_child(settings_panel)
	var content := VBoxContainer.new()
	settings_panel.add_child(content)
	var heading := Label.new()
	heading.text = "FIELD SETTINGS"
	heading.add_theme_font_size_override("font_size",int(28*scale))
	content.add_child(heading)
	var info := Label.new()
	info.text = "LEFT THUMB: MOVE  •  RIGHT SIDE: LOOK / AIM\nFIRE, JUMP AND SPRINT: LARGE TOUCH BUTTONS\nRADAR: PLAYER POSITION AND HOSTILE CONTACTS\nWEATHER AND LIGHTING CHANGE DURING MISSIONS"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size",int(18*scale))
	content.add_child(info)
	_add_button(content,"CLOSE",_on_settings,Color(0.12,0.27,0.34),scale)

func _on_exit() -> void:
	get_tree().quit()
