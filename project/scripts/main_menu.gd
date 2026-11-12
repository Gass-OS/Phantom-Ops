extends Control

var settings_panel: PanelContainer

func _ready() -> void:
	_build_menu()

func _style_panel(panel: Control, color: Color, border: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)

func _build_menu() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.025,0.038,0.052)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var glow := ColorRect.new()
	glow.color = Color(0.10,0.16,0.19,0.32)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(glow)
	var root := CenterContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560,0)
	_style_panel(panel,Color(0.035,0.055,0.072,0.96),Color(0.23,0.37,0.43))
	root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",16)
	panel.add_child(column)
	var eyebrow := Label.new()
	eyebrow.text = "TACTICAL SURVIVAL  /  KASSERINE DISTRICT"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_color_override("font_color",Color(0.85,0.43,0.24))
	eyebrow.add_theme_font_size_override("font_size",16)
	column.add_child(eyebrow)
	var title := Label.new()
	title.text = "PHANTOM OPS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color",Color(0.92,0.96,0.98))
	title.add_theme_font_size_override("font_size",48)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "THE CITY HAS FALLEN. YOUR MISSION HAS NOT."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color",Color(0.60,0.70,0.75))
	subtitle.add_theme_font_size_override("font_size",14)
	column.add_child(subtitle)
	var separator := HSeparator.new()
	column.add_child(separator)
	_add_button(column,"DEPLOY  /  ENTER THE ZONE",_on_deploy,Color(0.67,0.20,0.13))
	_add_button(column,"SETTINGS",_on_settings,Color(0.12,0.27,0.34))
	_add_button(column,"EXIT GAME",_on_exit,Color(0.15,0.17,0.20))
	var footer := Label.new()
	footer.text = "ANDROID FIELD BUILD  •  SURVIVE THE NIGHT"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color",Color(0.42,0.52,0.58))
	footer.add_theme_font_size_override("font_size",12)
	column.add_child(footer)

func _add_button(parent: VBoxContainer, caption: String, action: Callable, color: Color) -> void:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(0,64)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size",20)
	button.add_theme_color_override("font_color",Color.WHITE)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(9)
	style.content_margin_top = 12
	style.content_margin_bottom = 12
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
	settings_panel = PanelContainer.new()
	settings_panel.position = Vector2(30,30)
	settings_panel.custom_minimum_size = Vector2(360,220)
	_style_panel(settings_panel,Color(0.025,0.045,0.06,0.98),Color(0.3,0.48,0.53))
	add_child(settings_panel)
	var content := VBoxContainer.new()
	settings_panel.add_child(content)
	var heading := Label.new()
	heading.text = "FIELD SETTINGS"
	heading.add_theme_font_size_override("font_size",22)
	content.add_child(heading)
	var info := Label.new()
	info.text = "Touch joystick: left side\nLook / aim: drag the right side\nFire, jump and sprint: right controls\nWeather and lighting cycle during missions."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size",16)
	content.add_child(info)
	_add_button(content,"CLOSE",_on_settings,Color(0.12,0.27,0.34))

func _on_exit() -> void:
	get_tree().quit()
