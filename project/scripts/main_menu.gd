extends Node3D
## v0.4 — AAA main menu: a live 3D Kasserine city behind the UI, with
## a slow orbiting camera and Aymen (the hero scan) standing in the
## plaza. If the 3D city ever fails to build, the gradient background
## is shown instead so the menu can never go black.

var _sound: SoundManager
var _camera: Camera3D
var _angle := 0.0
# v0.6: adhan toggle. A local AdhanManager instance (not in the scene
# tree as a player) just to own the persisted ON/OFF setting — the
# in-game AdhanManager loads the same settings.cfg value.
var _adhan: AdhanManager

func _ready() -> void:
	if is_instance_valid(GameManager):
		GameManager.reset_game()
	_sound = SoundManager.new()
	_sound.name = "SoundManager"
	add_child(_sound)
	_sound.start_wind()
	_adhan = AdhanManager.new()
	_adhan.name = "AdhanManager"
	add_child(_adhan)
	$CanvasLayer/UI/Adhan.pressed.connect(_on_adhan_pressed)
	_camera = $MenuCamera as Camera3D
	# Aymen, the hero, standing in the plaza in front of the city.
	var hero := HeroAymen.build(self, Vector3(-6, 0, 30), 0.0)
	HeroAymen.add_name_label(hero)
	# Fallback: if the city did not build, show the gradient.
	var city := $City as Node
	if city == null or city.get_child_count() < 50:
		$CanvasLayer/UI/BG.visible = true
	$CanvasLayer/UI/Play.pressed.connect(_on_deploy_pressed)
	$CanvasLayer/UI/HowTo.pressed.connect(_on_howto_pressed)
	$CanvasLayer/UI/Sound.pressed.connect(_on_sound_pressed)
	$CanvasLayer/UI/HowToPanel/Close.pressed.connect(_on_close_pressed)
	# v0.6 SYSTEM 1 — language switch (FR / EN / AR).
	$CanvasLayer/UI/LangFR.pressed.connect(_on_language_pressed.bind("fr"))
	$CanvasLayer/UI/LangEN.pressed.connect(_on_language_pressed.bind("en"))
	$CanvasLayer/UI/LangAR.pressed.connect(_on_language_pressed.bind("ar"))
	_apply_language()
	_update_sound_button()

func _process(delta: float) -> void:
	# Slow orbit around the plaza, looking at the minaret / city.
	_angle += delta * 0.06
	var r := 58.0
	_camera.position = Vector3(cos(_angle) * r, 24.0 + sin(_angle * 0.7) * 4.0, sin(_angle) * r)
	_camera.look_at(Vector3(0, 9, -5), Vector3.UP)

func _update_sound_button() -> void:
	var b := $CanvasLayer/UI/Sound as Button
	b.text = LanguageManager.translate("sound_on") if SoundManager.sound_on else LanguageManager.translate("sound_off")

func _update_adhan_button() -> void:
	var b := $CanvasLayer/UI/Adhan as Button
	if _adhan == null:
		return
	b.text = LanguageManager.translate("adhan_on") if _adhan.is_enabled() else LanguageManager.translate("adhan_off")

func _on_adhan_pressed() -> void:
	if _sound != null:
		_sound.play_click()
	if _adhan == null:
		return
	_adhan.set_enabled(not _adhan.is_enabled())
	_update_adhan_button()

## v0.6 SYSTEM 1 — re-render every menu string in the current language
## and apply the Arabic font (or restore the default font) on each Control.
func _apply_language() -> void:
	var ui := $CanvasLayer/UI as Control
	var title := ui.get_node("Title") as Label
	var subtitle := ui.get_node("Subtitle") as Label
	var play := ui.get_node("Play") as Button
	var howto := ui.get_node("HowTo") as Button
	var sound := ui.get_node("Sound") as Button
	var adhan := ui.get_node("Adhan") as Button
	var controls := ui.get_node("Controls") as Label
	var lang_label := ui.get_node("LanguageLabel") as Label
	var howto_text := ui.get_node("HowToPanel/HowToText") as Label
	var close := ui.get_node("HowToPanel/Close") as Button
	var lang_fr := ui.get_node("LangFR") as Button
	var lang_en := ui.get_node("LangEN") as Button
	var lang_ar := ui.get_node("LangAR") as Button
	title.text = LanguageManager.translate("menu_title")
	subtitle.text = LanguageManager.translate("menu_subtitle")
	play.text = "▶  " + LanguageManager.translate("menu_deploy")
	howto.text = LanguageManager.translate("menu_how_to_play")
	controls.text = LanguageManager.translate("hud_controls")
	lang_label.text = LanguageManager.translate("menu_language")
	howto_text.text = LanguageManager.translate("how_to_play_text")
	close.text = LanguageManager.translate("menu_close")
	lang_fr.text = LanguageManager.translate("language_fr")
	lang_en.text = LanguageManager.translate("language_en")
	lang_ar.text = LanguageManager.translate("language_ar")
	for c in [title, subtitle, play, howto, sound, adhan, controls, lang_label, howto_text, close, lang_fr, lang_en, lang_ar]:
		LanguageManager.apply_font_to(c)
	_update_sound_button()
	_update_adhan_button()
	_update_lang_buttons()

## Highlight the active language button in gold.
func _update_lang_buttons() -> void:
	var active := Color(1, 0.85, 0.6, 1)
	var idle := Color(1, 1, 1, 1)
	var ui := $CanvasLayer/UI as Control
	for code in ["fr", "en", "ar"]:
		var b := ui.get_node("LangFR" if code == "fr" else "LangEN" if code == "en" else "LangAR") as Button
		b.add_theme_color_override("font_color", active if LanguageManager.current() == code else idle)

func _on_language_pressed(code: String) -> void:
	if _sound != null:
		_sound.play_click()
	LanguageManager.set_language(code)
	_apply_language()

func _on_deploy_pressed() -> void:
	if _sound != null:
		_sound.play_click()
	get_tree().change_scene_to_file("res://scenes/intro.tscn")

func _on_howto_pressed() -> void:
	if _sound != null:
		_sound.play_click()
	$CanvasLayer/UI/HowToPanel.visible = true

func _on_close_pressed() -> void:
	if _sound != null:
		_sound.play_click()
	$CanvasLayer/UI/HowToPanel.visible = false

func _on_sound_pressed() -> void:
	SoundManager.set_sound_on(not SoundManager.sound_on)
	if SoundManager.sound_on:
		_sound.start_wind()
	else:
		_sound.stop_wind()
	_update_sound_button()
