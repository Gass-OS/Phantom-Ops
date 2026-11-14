extends CanvasLayer
class_name PhantomMissionPanel
## Phantom Ops v0.6 — SYSTEM 2: POLICE MISSIONS — mission HUD panel.
##
## Self-contained UI only: it draws the current mission and knows NOTHING
## about mission logic. PhantomMissionDirector (mission_director.gd) owns
## all logic and calls the API below. The director passes already
## translated strings in, so this panel never touches LanguageManager.
##
## Layout (top-left, above the MobileHUD touch buttons which live at the
## screen edges/bottom): title, objective detail, distance, reward,
## countdown timer, plus a big centre banner for MISSION COMPLETE / FAILED.

var _title_label: Label
var _detail_label: Label
var _distance_label: Label
var _reward_label: Label
var _timer_label: Label
var _banner_label: Label
var _chapter_label: Label  # v0.7: "CHAPTER 1 — FIRST PATROL", hidden in free play.
var _banner_timer: float = 0.0
var _panel: PanelContainer

func _ready() -> void:
	layer = 8
	_build()

func _process(delta: float) -> void:
	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer <= 0.0 and is_instance_valid(_banner_label):
			_banner_label.visible = false

func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "MissionPanel"
	# v0.6 integration: below the HUD title chip (18,18,250x46) and HP
	# bar (18,72,260x24) — at (24,24) the panel sat underneath them.
	_panel.position = Vector2(24, 110)
	_panel.custom_minimum_size = Vector2(380, 110)
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	_panel.add_child(column)

	# v0.7: chapter header, shown only while a story chapter is active.
	_chapter_label = Label.new()
	_chapter_label.add_theme_font_size_override("font_size", 16)
	_chapter_label.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
	_chapter_label.visible = false
	column.add_child(_chapter_label)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 21)
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.76, 0.34))
	column.add_child(_title_label)

	_detail_label = Label.new()
	_detail_label.add_theme_font_size_override("font_size", 15)
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_detail_label)

	_distance_label = Label.new()
	_distance_label.add_theme_font_size_override("font_size", 15)
	_distance_label.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
	column.add_child(_distance_label)

	_reward_label = Label.new()
	_reward_label.add_theme_font_size_override("font_size", 15)
	_reward_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55))
	column.add_child(_reward_label)

	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 15)
	_timer_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
	column.add_child(_timer_label)

	# Centre banner (hidden until show_banner is called).
	_banner_label = Label.new()
	_banner_label.name = "MissionBanner"
	_banner_label.add_theme_font_size_override("font_size", 34)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner_label.position = Vector2(-260, 130)
	_banner_label.size = Vector2(520, 60)
	_banner_label.visible = false
	add_child(_banner_label)

# --- API used by PhantomMissionDirector -------------------------------------

## Show a new mission. money/score are the rewards paid on completion.
func show_mission(title: String, detail: String, money: int, score: int) -> void:
	if is_instance_valid(_panel):
		_panel.visible = true
	if is_instance_valid(_title_label):
		_title_label.text = title
	if is_instance_valid(_detail_label):
		_detail_label.text = detail
	if is_instance_valid(_reward_label):
		_reward_label.text = "Reward: %d dinars  •  %d XP" % [money, score]
	set_distance(-1.0, "")
	set_time_left(-1.0)

## Distance to the current objective in metres; -1 hides the line.
## `what` is an optional short suffix, e.g. "Checkpoint 2/3".
func set_distance(dist: float, what: String = "") -> void:
	if not is_instance_valid(_distance_label):
		return
	if dist < 0.0:
		_distance_label.text = ""
		return
	var suffix := ("  •  " + what) if what != "" else ""
	_distance_label.text = "Distance: %dm%s" % [int(round(dist)), suffix]

## Countdown in seconds; -1 hides the line. Turns red under 15s.
func set_time_left(seconds: float) -> void:
	if not is_instance_valid(_timer_label):
		return
	if seconds < 0.0:
		_timer_label.text = ""
		return
	_timer_label.text = "Time: %ds" % int(ceil(seconds))
	if seconds <= 15.0:
		_timer_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
	else:
		_timer_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))

## Free-form status line (replaces the detail text), e.g. "Helping… 2s".
func set_status(text: String) -> void:
	if is_instance_valid(_detail_label):
		_detail_label.text = text

## Big centre banner for 2.5s. success=true -> green, else red.
func show_banner(text: String, success: bool) -> void:
	if not is_instance_valid(_banner_label):
		return
	_banner_label.text = text
	_banner_label.add_theme_color_override(
		"font_color", Color(0.4, 1.0, 0.45) if success else Color(1.0, 0.35, 0.3))
	_banner_label.visible = true
	_banner_timer = 2.5

## Hide everything (used between missions / when the director is idle).
func clear() -> void:
	if is_instance_valid(_panel):
		_panel.visible = false
	if is_instance_valid(_banner_label):
		_banner_label.visible = false
	_banner_timer = 0.0

## v0.7: show the chapter header line ("CHAPTER 1 — FIRST PATROL").
## Hidden in free play; call clear_chapter() when the chapter ends.
func set_chapter(text: String) -> void:
	if is_instance_valid(_chapter_label):
		_chapter_label.text = text
		_chapter_label.visible = text != ""

func clear_chapter() -> void:
	if is_instance_valid(_chapter_label):
		_chapter_label.visible = false
		_chapter_label.text = ""
