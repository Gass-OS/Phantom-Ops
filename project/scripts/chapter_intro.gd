extends CanvasLayer
class_name ChapterIntro
## Phantom Ops v0.7 — Story Campaign cards (Worker B: Chapter Flow).
##
## One self-contained CanvasLayer that draws every chapter card as an
## overlay — no .tscn needed:
##   intro    — chapter number + translated title + story lines, ~7 s,
##              SKIP button; the game world is tree-paused while it shows.
##   results  — chapter complete: score / kills / time / XP / money,
##              NEXT CHAPTER + MENU.
##   fail     — chapter failed (timer): RETRY + MENU.
##   ending   — after chapter 5: ending title + text + campaign stats.
## The MissionDirector owns the logic and calls show_intro /
## show_results / show_fail / show_ending; this script only draws and
## reports button presses via signals. Every show pauses the tree and
## every close unpauses it, so a scene change can never inherit pause.
## Language: keys are read through LanguageManager.t() with English
## fallbacks (the chapter_* keys land with the language worker; until
## then the fallbacks below are used, never the raw key).

signal intro_finished
signal next_chapter_pressed
signal retry_chapter_pressed
signal menu_pressed

const INTRO_SECONDS := 7.0

var _dim: ColorRect
var _chapter_label: Label
var _title_label: Label
var _story_label: Label
var _stats_label: Label
var _skip_button: Button
var _next_button: Button
var _retry_button: Button
var _menu_button: Button
var _intro_timer := 0.0
var _mode := ""  # "" | "intro" | "results" | "fail" | "ending"

func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false

func _process(delta: float) -> void:
	if _mode != "intro" or _intro_timer <= 0.0:
		return
	_intro_timer -= delta
	if is_instance_valid(_skip_button):
		_skip_button.text = "%s (%ds)" % [_tr("skip_label", "SKIP"), int(ceil(_intro_timer))]
	if _intro_timer <= 0.0:
		_dismiss_intro()

# --- Card API (called by MissionDirector) ---------------------------------

## Chapter intro card. Pauses the world; SKIP or the ~7 s timer closes it.
func show_intro(chapter: int, title: String, story: String, boss_line: String = "") -> void:
	_mode = "intro"
	_chapter_label.text = "CHAPTER %d" % chapter
	_chapter_label.visible = true
	_title_label.text = title
	var body := story
	if boss_line != "":
		body += "\n\n" + boss_line
	_story_label.text = body
	_story_label.visible = true
	_stats_label.visible = false
	_show_buttons(true, false, false, false)
	_apply_fonts()
	_open()

## Chapter results card. `is_last` is unused today (chapter 5 shows the
## ending card instead) but kept so the caller can hide NEXT if needed.
func show_results(chapter: int, title: String, score: int, kills: int,
		time_sec: float, xp: int, money: int, is_last: bool = false) -> void:
	_mode = "results"
	_chapter_label.text = _tr("chapter_complete", "CHAPTER COMPLETE")
	_chapter_label.visible = true
	_title_label.text = title
	_story_label.visible = false
	_stats_label.text = _stats_text(score, kills, time_sec, xp, money)
	_stats_label.visible = true
	_show_buttons(false, not is_last, false, true)
	_apply_fonts()
	_open()

## Chapter fail card (timer expired, boss escaped, ...). RETRY restarts
## the same chapter; MENU goes back to the main menu.
func show_fail(chapter: int, title: String, reason: String) -> void:
	_mode = "fail"
	_chapter_label.text = "CHAPTER %d" % chapter
	_chapter_label.visible = true
	_title_label.text = title
	_story_label.text = _tr("chapter_failed", "CHAPTER FAILED") + "\n" + reason
	_story_label.visible = true
	_stats_label.visible = false
	_show_buttons(false, false, true, true)
	_apply_fonts()
	_open()

## Ending card after chapter 5: title + story + campaign totals.
func show_ending(title: String, text: String, score: int, kills: int,
		time_sec: float, xp: int, money: int) -> void:
	_mode = "ending"
	_chapter_label.visible = false
	_title_label.text = title
	_story_label.text = text
	_story_label.visible = true
	_stats_label.text = _stats_text(score, kills, time_sec, xp, money)
	_stats_label.visible = true
	_show_buttons(false, false, false, true)
	_apply_fonts()
	_open()

## Test / coordinator helper: which card is up ("" when none).
func current_mode() -> String:
	return _mode if visible else ""

# --- UI ---------------------------------------------------------------------

func _build() -> void:
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0.02, 0.02, 0.05, 0.78)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.name = "ChapterCard"
	panel.custom_minimum_size = Vector2(980, 500)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.10, 0.96)
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.95, 0.76, 0.34, 0.9)
	style.content_margin_left = 36.0
	style.content_margin_right = 36.0
	style.content_margin_top = 28.0
	style.content_margin_bottom = 28.0
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	_chapter_label = Label.new()
	_chapter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chapter_label.add_theme_font_size_override("font_size", 26)
	_chapter_label.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
	column.add_child(_chapter_label)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.add_theme_font_size_override("font_size", 46)
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.76, 0.34))
	column.add_child(_title_label)

	_story_label = Label.new()
	_story_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_story_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_story_label.add_theme_font_size_override("font_size", 26)
	_story_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
	column.add_child(_story_label)

	_stats_label = Label.new()
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_label.add_theme_font_size_override("font_size", 28)
	_stats_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55))
	column.add_child(_stats_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 24)
	column.add_child(buttons)

	_skip_button = _make_button(_tr("skip_label", "SKIP"), Color(0.25, 0.25, 0.30))
	_skip_button.pressed.connect(_on_skip_pressed)
	buttons.add_child(_skip_button)

	_next_button = _make_button(_tr("next_chapter", "NEXT CHAPTER"), Color(0.10, 0.45, 0.20))
	_next_button.pressed.connect(_on_next_pressed)
	buttons.add_child(_next_button)

	_retry_button = _make_button(_tr("retry_chapter", "RETRY"), Color(0.55, 0.30, 0.08))
	_retry_button.pressed.connect(_on_retry_pressed)
	buttons.add_child(_retry_button)

	_menu_button = _make_button(_tr("death_menu", "MAIN MENU"), Color(0.20, 0.22, 0.35))
	_menu_button.pressed.connect(_on_menu_pressed)
	buttons.add_child(_menu_button)

func _make_button(text: String, bg: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(320, 96)
	b.add_theme_font_size_override("font_size", 32)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.corner_radius_top_left = 14
	normal.corner_radius_top_right = 14
	normal.corner_radius_bottom_left = 14
	normal.corner_radius_bottom_right = 14
	normal.border_width_left = 3
	normal.border_width_right = 3
	normal.border_width_top = 3
	normal.border_width_bottom = 3
	normal.border_color = Color(1, 1, 1, 0.55)
	b.add_theme_stylebox_override("normal", normal)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = bg.darkened(0.35)
	b.add_theme_stylebox_override("pressed", pressed)
	return b

func _show_buttons(skip_b: bool, next_b: bool, retry_b: bool, menu_b: bool) -> void:
	_skip_button.visible = skip_b
	_next_button.visible = next_b
	_retry_button.visible = retry_b
	_menu_button.visible = menu_b
	if skip_b:
		_skip_button.text = _tr("skip_label", "SKIP")
	if next_b:
		_next_button.text = _tr("next_chapter", "NEXT CHAPTER")
	if retry_b:
		_retry_button.text = _tr("retry_chapter", "RETRY")
	if menu_b:
		_menu_button.text = _tr("death_menu", "MAIN MENU")

func _open() -> void:
	_intro_timer = INTRO_SECONDS if _mode == "intro" else 0.0
	visible = true
	get_tree().paused = true

func _close() -> void:
	visible = false
	_mode = ""
	_intro_timer = 0.0
	get_tree().paused = false

# --- Button handlers ---------------------------------------------------------

func _dismiss_intro() -> void:
	if _mode != "intro":
		return
	_close()
	intro_finished.emit()

func _on_skip_pressed() -> void:
	_dismiss_intro()

func _on_next_pressed() -> void:
	if _mode != "results":
		return
	_close()
	next_chapter_pressed.emit()

func _on_retry_pressed() -> void:
	if _mode != "fail":
		return
	_close()
	retry_chapter_pressed.emit()

func _on_menu_pressed() -> void:
	if _mode != "results" and _mode != "fail" and _mode != "ending":
		return
	_close()
	menu_pressed.emit()

# --- Helpers -----------------------------------------------------------------

func _stats_text(score: int, kills: int, time_sec: float, xp: int, money: int) -> String:
	var lines: Array[String] = []
	lines.append("%s: %d" % [_tr("hud_score", "SCORE"), score])
	lines.append("%s: %d" % [_tr("hud_kills", "KILLS"), kills])
	lines.append("%s: %s" % [_tr("time_label", "TIME"), _fmt_time(time_sec)])
	lines.append("%s: +%d" % [_tr("xp_earned", "XP EARNED"), xp])
	lines.append("%s: +%d DT" % [_tr("money_earned", "MONEY EARNED"), money])
	return "\n".join(lines)

func _fmt_time(t: float) -> String:
	var total := int(maxf(0.0, t))
	return "%02d:%02d" % [total / 60, total % 60]

func _apply_fonts() -> void:
	for c in [_chapter_label, _title_label, _story_label, _stats_label,
			_skip_button, _next_button, _retry_button, _menu_button]:
		LanguageManager.apply_font_to(c)

## Same guarded lookup as interaction_manager.gd: translate the key
## when LanguageManager has it, else the English fallback — without
## spamming its "missing key" warning for keys not added yet.
func _tr(key: String, fallback: String) -> String:
	var strings: Dictionary = LanguageManager.STRINGS
	var lang: Dictionary = strings.get(LanguageManager.current(), {})
	var en: Dictionary = strings.get("en", {})
	if lang.has(key) or en.has(key):
		return LanguageManager.translate(key)
	return fallback
