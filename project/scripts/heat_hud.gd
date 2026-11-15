extends Control
class_name HeatHud
## Phantom Ops v0.8 — WANTED HUD cluster (standalone; do NOT edit
## mobile_hud.gd). The coordinator adds ONE HeatHud as a child of
## MobileHUDLayer and calls setup(wanted_manager).
##
## Shows: 5 stars (filled gold / empty grey, drawn polygons — no new
## assets, no font-glyph gamble), a HEAT label with the level name, a
## thin heat bar, a "Lay low — heat falling..." hint while heat is
## decaying, and a full-width warning banner that flashes for 3 s when
## heat rises a level (or the hit squad / bounty events fire).
## Lightweight: refreshes ONLY on WantedManager signals, never per frame
## (the banner pulse is the only _process work, and only while visible).
## The root and every child ignore mouse input, so this cluster can sit
## on top of the HUD without ever eating a FIRE / MOVE tap.
##
## Language keys (added by the languages worker; English fallbacks below
## are used until then — missing keys never warn-spam, they fall back):
##   wanted_level_0..5, wanted_lay_low, wanted_rising,
##   wanted_hit_squad, wanted_bounty, wanted_survived.

const BAR_WIDTH := 340.0
const BAR_HEIGHT := 10.0
const BANNER_SECONDS := 3.0

const LEVEL_NAMES_EN := ["Clean", "Low", "Guarded", "High", "Severe", "MOST WANTED"]
const BAR_COLORS := [
	Color(0.35, 0.80, 0.35), Color(0.70, 0.85, 0.25), Color(1.0, 0.80, 0.15),
	Color(1.0, 0.55, 0.10), Color(1.0, 0.30, 0.10), Color(0.95, 0.05, 0.10),
]
const FALLBACKS := {
	"wanted_lay_low": "Lay low — heat falling...",
	"wanted_rising": "Heat rising!",
	"wanted_hit_squad": "HIT SQUAD INCOMING!",
	"wanted_bounty": "Bounty",
	"wanted_survived": "You survived the hit squad!",
}

## Five stars drawn as polygons (filled gold / grey outline). Drawn, not
## text, so the result does not depend on the default font carrying
## U+2605/U+2606.
class StarRow extends Control:
	var level: int = 0

	func _init() -> void:
		custom_minimum_size = Vector2(150.0, 30.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_level(v: int) -> void:
		level = clampi(v, 0, 5)
		queue_redraw()

	func _draw() -> void:
		var step := 30.0
		for i in range(5):
			_draw_star(Vector2(step * (float(i) + 0.5), 15.0), 13.0, 5.5, i < level)

	func _draw_star(center: Vector2, outer_r: float, inner_r: float, filled: bool) -> void:
		var pts := PackedVector2Array()
		for k in range(10):
			var r := outer_r if k % 2 == 0 else inner_r
			var a := -PI / 2.0 + float(k) * PI / 5.0
			pts.append(center + Vector2(cos(a), sin(a)) * r)
		if filled:
			draw_colored_polygon(pts, Color(1.0, 0.80, 0.15))
		else:
			pts.append(pts[0])
			draw_polyline(pts, Color(0.55, 0.55, 0.58), 2.0)

var _wm: WantedManager = null
var _heat: float = 0.0
var _level: int = 0
var _stars: StarRow = null
var _level_label: Label = null
var _bar: Control = null
var _bar_fg: ColorRect = null
var _hint_label: Label = null
var _banner: PanelContainer = null
var _banner_label: Label = null
var _banner_t := 0.0
var _banner_pulse := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

func _build() -> void:
	# Top-centre cluster.
	var cluster := VBoxContainer.new()
	cluster.name = "HeatCluster"
	cluster.anchor_left = 0.5
	cluster.anchor_right = 0.5
	cluster.anchor_top = 0.0
	cluster.anchor_bottom = 0.0
	cluster.offset_left = -BAR_WIDTH * 0.5
	cluster.offset_right = BAR_WIDTH * 0.5
	cluster.offset_top = 8.0
	cluster.offset_bottom = 110.0
	cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cluster)

	var row := HBoxContainer.new()
	row.name = "StarRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cluster.add_child(row)

	_stars = StarRow.new()
	_stars.name = "Stars"
	row.add_child(_stars)

	_level_label = Label.new()
	_level_label.name = "HeatLevelLabel"
	_level_label.add_theme_font_size_override("font_size", 22)
	_level_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_level_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_level_label.add_theme_constant_override("shadow_offset_x", 2)
	_level_label.add_theme_constant_override("shadow_offset_y", 2)
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_level_label)

	_bar = Control.new()
	_bar.name = "HeatBar"
	_bar.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cluster.add_child(_bar)
	var bar_bg := ColorRect.new()
	bar_bg.name = "BarBg"
	bar_bg.color = Color(0.0, 0.0, 0.0, 0.55)
	bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(bar_bg)
	_bar_fg = ColorRect.new()
	_bar_fg.name = "BarFg"
	_bar_fg.color = BAR_COLORS[0]
	_bar_fg.anchor_right = 0.0
	_bar_fg.offset_left = 0.0
	_bar_fg.offset_top = 0.0
	_bar_fg.offset_bottom = BAR_HEIGHT
	_bar_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_bar_fg)

	_hint_label = Label.new()
	_hint_label.name = "LayLowHint"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	_hint_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_hint_label.add_theme_constant_override("shadow_offset_x", 1)
	_hint_label.add_theme_constant_override("shadow_offset_y", 1)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.visible = false
	cluster.add_child(_hint_label)

	# Full-width warning banner (hidden until a banner event fires).
	_banner = PanelContainer.new()
	_banner.name = "HeatBanner"
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.anchor_top = 0.0
	_banner.anchor_bottom = 0.0
	_banner.offset_top = 116.0
	_banner.offset_bottom = 162.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.35, 0.02, 0.02, 0.88)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_banner.add_theme_stylebox_override("panel", style)
	add_child(_banner)
	_banner_label = Label.new()
	_banner_label.name = "BannerLabel"
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", 26)
	_banner_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(_banner_label)
	_banner.visible = false

	_refresh()

## Wire to a WantedManager (null hides the cluster). Safe to call twice;
## old connections are dropped first.
func setup(wanted_manager: WantedManager) -> void:
	if is_instance_valid(_wm):
		if _wm.is_connected("heat_changed", _on_heat_changed):
			_wm.disconnect("heat_changed", _on_heat_changed)
		if _wm.is_connected("heat_level_up", _on_level_up):
			_wm.disconnect("heat_level_up", _on_level_up)
		if _wm.is_connected("hit_squad_spawned", _on_hit_squad):
			_wm.disconnect("hit_squad_spawned", _on_hit_squad)
		if _wm.is_connected("squad_defeated", _on_squad_defeated):
			_wm.disconnect("squad_defeated", _on_squad_defeated)
	_wm = wanted_manager
	visible = _wm != null
	if _wm != null:
		_heat = _wm.get_heat()
		_level = _wm.get_level()
		_wm.connect("heat_changed", _on_heat_changed)
		_wm.connect("heat_level_up", _on_level_up)
		_wm.connect("hit_squad_spawned", _on_hit_squad)
		_wm.connect("squad_defeated", _on_squad_defeated)
	_refresh()

## Show the banner with a translated key for 3 s (flashing). `extra` is
## appended verbatim (used for the bounty amount).
func show_banner(text_key: String, extra: String = "") -> void:
	if _banner == null or _banner_label == null:
		return
	_banner_label.text = _tr(text_key) + extra
	LanguageManager.apply_font_to(_banner_label)
	_banner.visible = true
	_banner_t = BANNER_SECONDS
	_banner_pulse = 0.0

## Bounty banner: survived line + bounty line with the amount.
func show_bounty_banner(bounty: int) -> void:
	if _banner == null or _banner_label == null:
		return
	_banner_label.text = _tr("wanted_survived") + "\n" + _tr("wanted_bounty") + "  +%d DT" % bounty
	LanguageManager.apply_font_to(_banner_label)
	_banner.visible = true
	_banner_t = BANNER_SECONDS
	_banner_pulse = 0.0

func _process(delta: float) -> void:
	if _banner == null or not _banner.visible:
		return
	_banner_t -= delta
	_banner_pulse += delta
	# Flash: alpha pulses while the banner is up.
	var a := 0.65 + 0.35 * sin(_banner_pulse * 10.0)
	_banner.modulate.a = a
	if _banner_t <= 0.0:
		_banner.visible = false
		_banner.modulate.a = 1.0

func _on_heat_changed(level: int, heat: float) -> void:
	_level = level
	_heat = heat
	_refresh()

func _on_level_up(level: int) -> void:
	# L5 also fires hit_squad_spawned a moment later, which overwrites
	# this with the hit-squad banner (the more urgent message).
	show_banner("wanted_rising")

func _on_hit_squad() -> void:
	show_banner("wanted_hit_squad")

func _on_squad_defeated(bounty: int) -> void:
	show_bounty_banner(bounty)

func _refresh() -> void:
	if _stars == null:
		return
	_stars.set_level(_level)
	_level_label.text = "HEAT: " + _level_name(_level)
	LanguageManager.apply_font_to(_level_label)
	var frac := clampf(_heat / 100.0, 0.0, 1.0)
	_bar_fg.size = Vector2(BAR_WIDTH * frac, BAR_HEIGHT)
	_bar_fg.color = BAR_COLORS[clampi(_level, 0, 5)]
	var decaying := false
	if is_instance_valid(_wm):
		decaying = _wm.is_decaying()
	_hint_label.visible = decaying and _heat > 0.0
	if _hint_label.visible:
		_hint_label.text = _tr("wanted_lay_low")
		LanguageManager.apply_font_to(_hint_label)

func _level_name(level: int) -> String:
	var key := "wanted_level_%d" % clampi(level, 0, 5)
	var fallback: String = LEVEL_NAMES_EN[clampi(level, 0, 5)]
	return _tr(key, fallback)

## Translated string with an English fallback. Mirrors citizen.gd: the
## STRINGS dict is checked first so a key the languages worker has not
## added yet falls back quietly instead of warning on every update.
func _tr(key: String, fallback: String = "") -> String:
	if fallback == "":
		fallback = String(FALLBACKS.get(key, key))
	var strings: Dictionary = LanguageManager.STRINGS
	var lang: Dictionary = strings.get(LanguageManager.current(), {})
	var en: Dictionary = strings.get("en", {})
	if lang.has(key) or en.has(key):
		return LanguageManager.translate(key)
	return fallback
