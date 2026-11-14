extends CanvasLayer
class_name BossBar
## v0.7 — standalone boss health bar for Khaled "The Wolf".
##
## A CanvasLayer overlay (layer 20, above the mobile HUD on layer 10)
## showing the boss name + a red HP bar at the top of the screen,
## visible only while the boss is alive. It never touches mobile_hud.gd.
##
## API (used by BossEnemy, and usable by the chapter system):
##   show_boss(name_text, max_hp) — show the bar for a boss.
##   set_hp(current)               — update the fill (clamped 0..max).
##   hide_bar()                    — hide the bar (boss died / fight over).
##   is_showing() / current_hp() / max_hp() / boss_name() — state reads.
##
## Headless-safe: show_boss()/set_hp() may be called before _ready()
## builds the controls (values are stored and applied in _ready via
## _apply()), every setter guards for missing controls, and the layout
## uses anchors only — nothing here reads the viewport size.

const BAR_HALF_WIDTH := 450.0
const BAR_TOP := 100.0
const BAR_HEIGHT := 26.0

var _boss_name: String = ""
var _max_hp: float = 1.0
var _current_hp: float = 0.0
var _root: Control
var _name_label: Label
var _bar_border: ColorRect
var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _hp_label: Label


func _ready() -> void:
	layer = 20
	visible = false
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	# Boss name, gold, centred above the bar (below the HUD's top
	# status chip, which occupies roughly y 18..60).
	_name_label = Label.new()
	_name_label.name = "BossName"
	_name_label.anchor_left = 0.5
	_name_label.anchor_right = 0.5
	_name_label.offset_left = -BAR_HALF_WIDTH
	_name_label.offset_right = BAR_HALF_WIDTH
	_name_label.offset_top = 62.0
	_name_label.offset_bottom = 94.0
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.add_theme_font_size_override("font_size", 30)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_name_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_name_label.add_theme_constant_override("outline_size", 8)
	_root.add_child(_name_label)
	# Gold border, dark backing, red fill, HP text on top.
	_bar_border = ColorRect.new()
	_bar_border.name = "BarBorder"
	_bar_border.anchor_left = 0.5
	_bar_border.anchor_right = 0.5
	_bar_border.offset_left = -BAR_HALF_WIDTH - 4.0
	_bar_border.offset_right = BAR_HALF_WIDTH + 4.0
	_bar_border.offset_top = BAR_TOP - 4.0
	_bar_border.offset_bottom = BAR_TOP + BAR_HEIGHT + 4.0
	_bar_border.color = Color(0.85, 0.65, 0.15, 0.95)
	_bar_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bar_border)
	_bar_bg = ColorRect.new()
	_bar_bg.name = "BarBackground"
	_bar_bg.anchor_left = 0.5
	_bar_bg.anchor_right = 0.5
	_bar_bg.offset_left = -BAR_HALF_WIDTH
	_bar_bg.offset_right = BAR_HALF_WIDTH
	_bar_bg.offset_top = BAR_TOP
	_bar_bg.offset_bottom = BAR_TOP + BAR_HEIGHT
	_bar_bg.color = Color(0.05, 0.02, 0.02, 0.85)
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bar_bg)
	_bar_fill = ColorRect.new()
	_bar_fill.name = "BarFill"
	_bar_fill.anchor_left = 0.5
	_bar_fill.anchor_right = 0.5
	_bar_fill.offset_left = -(BAR_HALF_WIDTH - 4.0)
	_bar_fill.offset_right = BAR_HALF_WIDTH - 4.0
	_bar_fill.offset_top = BAR_TOP + 4.0
	_bar_fill.offset_bottom = BAR_TOP + BAR_HEIGHT - 4.0
	_bar_fill.color = Color(0.78, 0.12, 0.10)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bar_fill)
	_hp_label = Label.new()
	_hp_label.name = "HpText"
	_hp_label.anchor_left = 0.5
	_hp_label.anchor_right = 0.5
	_hp_label.offset_left = -BAR_HALF_WIDTH
	_hp_label.offset_right = BAR_HALF_WIDTH
	_hp_label.offset_top = BAR_TOP
	_hp_label.offset_bottom = BAR_TOP + BAR_HEIGHT
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_label.add_theme_font_size_override("font_size", 16)
	_hp_label.add_theme_color_override("font_color", Color.WHITE)
	_hp_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_hp_label.add_theme_constant_override("outline_size", 6)
	_root.add_child(_hp_label)
	_apply()


## Show the bar for a boss. Called by BossEnemy when it spawns.
func show_boss(name_text: String, max_hp: float) -> void:
	_boss_name = name_text
	_max_hp = maxf(max_hp, 1.0)
	_current_hp = _max_hp
	visible = true
	_apply()


## Update the fill. Clamped, so overkill damage cannot invert the bar.
func set_hp(current: float) -> void:
	_current_hp = clampf(current, 0.0, _max_hp)
	_apply()


## Hide the bar. Called by BossEnemy when it dies.
func hide_bar() -> void:
	visible = false


func is_showing() -> bool:
	return visible


func current_hp() -> float:
	return _current_hp


func max_hp() -> float:
	return _max_hp


func boss_name() -> String:
	return _boss_name


func _apply() -> void:
	if _name_label == null or _bar_fill == null or _hp_label == null:
		return
	_name_label.text = _boss_name
	LanguageManager.apply_font_to(_name_label)
	LanguageManager.apply_font_to(_hp_label)
	var ratio := clampf(_current_hp / _max_hp, 0.0, 1.0)
	var inner := (BAR_HALF_WIDTH - 4.0) * 2.0
	_bar_fill.offset_left = -(BAR_HALF_WIDTH - 4.0)
	_bar_fill.offset_right = -(BAR_HALF_WIDTH - 4.0) + inner * ratio
	_hp_label.text = "%d / %d" % [int(_current_hp), int(_max_hp)]
