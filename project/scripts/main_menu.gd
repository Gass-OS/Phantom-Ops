extends Node3D
## v0.4 — AAA main menu: a live 3D Kasserine city behind the UI, with
## a slow orbiting camera and Aymen (the hero scan) standing in the
## plaza. If the 3D city ever fails to build, the gradient background
## is shown instead so the menu can never go black.

var _sound: SoundManager
var _camera: Camera3D
var _angle := 0.0
# v0.7: campaign menu — CONTINUE (highest unlocked chapter),
# CHAPTER SELECT (5 chapters, locked ones greyed), rank + XP under
# the hero. DEPLOY starts CampaignManager.current_chapter: the
# chapter the player last picked (or the highest unlocked when
# fresh), so replaying an earlier chapter from the list and then
# hitting DEPLOY replays it; CONTINUE always jumps to the furthest
# unlocked chapter. Rank never gates a chapter (see
# campaign_manager.gd).
func _cm() -> Node:
	return get_node_or_null("/root/CampaignManager")

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
	$CanvasLayer/UI/Continue.pressed.connect(_on_continue_pressed)
	$CanvasLayer/UI/ChapterSelect.pressed.connect(_on_chapter_select_pressed)
	$CanvasLayer/UI/ChapterPanel/ChapterClose.pressed.connect(_on_chapter_close_pressed)
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
	var continue_b := ui.get_node("Continue") as Button
	var chapter_select := ui.get_node("ChapterSelect") as Button
	var rank_label := ui.get_node("RankLabel") as Label
	var chapter_title := ui.get_node("ChapterPanel/ChapterTitle") as Label
	var chapter_close := ui.get_node("ChapterPanel/ChapterClose") as Button
	title.text = LanguageManager.translate("menu_title")
	subtitle.text = LanguageManager.translate("menu_subtitle")
	play.text = "▶  " + LanguageManager.translate("menu_deploy")
	continue_b.text = "▶  " + LanguageManager.translate("continue_game")
	chapter_select.text = LanguageManager.translate("chapter_select")
	chapter_title.text = LanguageManager.translate("chapter_select")
	chapter_close.text = LanguageManager.translate("menu_close")
	howto.text = LanguageManager.translate("menu_how_to_play")
	controls.text = LanguageManager.translate("hud_controls")
	lang_label.text = LanguageManager.translate("menu_language")
	howto_text.text = LanguageManager.translate("how_to_play_text")
	close.text = LanguageManager.translate("menu_close")
	lang_fr.text = LanguageManager.translate("language_fr")
	lang_en.text = LanguageManager.translate("language_en")
	lang_ar.text = LanguageManager.translate("language_ar")
	_update_rank_label(rank_label)
	for c in [title, subtitle, play, continue_b, chapter_select, rank_label, chapter_title, chapter_close, howto, sound, adhan, controls, lang_label, howto_text, close, lang_fr, lang_en, lang_ar]:
		LanguageManager.apply_font_to(c)
	_update_sound_button()
	_update_adhan_button()
	_update_lang_buttons()
	_build_chapter_list()


## Rank + XP under the hero. Falls back to Officer / 0 XP when the
## campaign autoload is absent.
func _update_rank_label(rank_label: Label) -> void:
	var cm := _cm()
	var rank_name := LanguageManager.translate("rank_officer")
	var xp := 0
	if cm != null:
		rank_name = String(cm.call("rank_name", int(cm.call("get_rank"))))
		xp = int(cm.call("get_xp"))
	rank_label.text = "%s  •  XP %d" % [rank_name, xp]


## Rebuild the chapter list (translated titles, lock state). Called
## on every language change so the panel is always in sync.
func _build_chapter_list() -> void:
	var list := $CanvasLayer/UI/ChapterPanel/ChapterList as VBoxContainer
	for child in list.get_children():
		child.free()  # Immediate: rebuilds happen per language switch.
	var cm := _cm()
	for n in range(1, 6):
		var b := Button.new()
		b.custom_minimum_size = Vector2(760, 78)
		b.add_theme_font_size_override("font_size", 26)
		var title := LanguageManager.t("chapter_%d_title" % n)
		var unlocked := true
		if cm != null:
			unlocked = bool(cm.call("is_unlocked", n))
		if unlocked:
			b.text = "%d.  %s" % [n, title]
			b.pressed.connect(_on_chapter_pressed.bind(n))
		else:
			b.text = "%d.  %s  —  %s" % [n, title, LanguageManager.translate("chapter_locked")]
			b.disabled = true
			b.add_theme_color_override("font_disabled_color", Color(0.6, 0.6, 0.6, 0.8))
		LanguageManager.apply_font_to(b)
		list.add_child(b)
	# Ending line once the whole campaign (all 5 chapters) is done.
	var ending := $CanvasLayer/UI/ChapterPanel/EndingLabel as Label
	var done := false
	if cm != null:
		done = bool(cm.call("campaign_complete"))
	ending.visible = done
	if done:
		ending.text = "%s\n%s" % [LanguageManager.translate("ending_title"), LanguageManager.translate("ending_text")]
		LanguageManager.apply_font_to(ending)


func _on_continue_pressed() -> void:
	if _sound != null:
		_sound.play_click()
	var cm := _cm()
	if cm != null:
		cm.call("start_chapter", int(cm.call("highest_unlocked")))
	get_tree().change_scene_to_file("res://scenes/intro.tscn")


func _on_chapter_select_pressed() -> void:
	if _sound != null:
		_sound.play_click()
	_build_chapter_list()
	$CanvasLayer/UI/ChapterPanel.visible = true


func _on_chapter_close_pressed() -> void:
	if _sound != null:
		_sound.play_click()
	$CanvasLayer/UI/ChapterPanel.visible = false


func _on_chapter_pressed(chapter: int) -> void:
	if _sound != null:
		_sound.play_click()
	var cm := _cm()
	if cm != null and not bool(cm.call("start_chapter", chapter)):
		return
	$CanvasLayer/UI/ChapterPanel.visible = false
	get_tree().change_scene_to_file("res://scenes/intro.tscn")

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
	# v0.7: DEPLOY starts the campaign's current chapter — the one
	# the player last picked in CHAPTER SELECT, or the highest
	# unlocked chapter when fresh. (CONTINUE always jumps to the
	# highest unlocked chapter instead.)
	var cm := _cm()
	if cm != null:
		var chapter := int(cm.get("current_chapter"))
		if not bool(cm.call("is_unlocked", chapter)):
			chapter = int(cm.call("highest_unlocked"))
		cm.call("start_chapter", chapter)
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
