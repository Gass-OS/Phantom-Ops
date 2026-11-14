extends Node
class_name InteractionManager
## Phantom Ops v0.6 — citizen interaction + money HUD (SYSTEM 3).
## Standalone: finds the player via group "player" and citizens via
## group "civilian". Builds its OWN CanvasLayer UI at runtime — it
## does NOT touch mobile_hud.gd. The coordinator only has to add one
## node with this script to main_game.tscn (see wiring note at the
## bottom of this file).
##
## Every 0.15 s it finds the nearest ACTIONABLE citizen within 4 m:
##   HELP   — a citizen in need (is_in_need, set by the mission worker)
##            Free. +50 score. Citizen says thank you, stops asking.
##   GIVE   — a poor citizen (is_poor, not yet helped). Costs 10 DT
##            via GameManager.spend_money, +25 score, "thank you"
##            bubble. If the player cannot afford it: toast + a sad
##            bubble, no money spent.
##   CHECK  — a suspicious citizen (is_suspicious: criminals in
##            disguise + nervous innocents). If criminal: he flees
##            fast (state FLEE — the mission worker can treat it as a
##            chase), +25 score, criminal_exposed emitted. If innocent:
##            greeting bubble, no penalty.
##   Other citizens get no prompt (they greet via the existing
##   player.gd proximity TTS instead).
##
## Money HUD: its own small "DT n" chip top-right, left of the pause
## button, updated from GameManager.money_changed. Money itself is
## earned by missions (GameManager.add_money) — this manager only
## spends it. Buttons are big and touch-friendly (~360x110).
##
## Signals for the coordinator / mission worker:
##   give_completed(citizen), help_completed(citizen),
##   criminal_exposed(citizen), check_completed(citizen, was_criminal)

signal give_completed(citizen: Node)
signal help_completed(citizen: Node)
signal criminal_exposed(citizen: Node)
signal check_completed(citizen: Node, was_criminal: bool)

const PROMPT_RANGE := 4.0
const SCAN_INTERVAL := 0.15
const GIVE_COST := 10
const GIVE_SCORE := 25
const HELP_SCORE := 50
const EXPOSE_SCORE := 25

var _player: Node3D = null
var _gm: Node = null
var _target: Node = null
var _action: String = ""
var _scan_t: float = 0.0
var _player_search_t: float = 0.0

var _layer: CanvasLayer
var _prompt_button: Button
var _money_label: Label
var _toast_label: Label
var _toast_t: float = 0.0

func _ready() -> void:
	_gm = get_node_or_null("/root/GameManager")
	if _gm != null and _gm.has_signal("money_changed"):
		_gm.connect("money_changed", _on_money_changed)
	_build_ui()
	_refresh_language()
	_update_money_label()

func _process(delta: float) -> void:
	_refresh_language()
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0 and _toast_label != null:
			_toast_label.visible = false
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_INTERVAL
		_scan()

# ------------------------------------------------------------ scanning

func _scan() -> void:
	_player_search_t -= SCAN_INTERVAL
	if _player == null or not is_instance_valid(_player):
		if _player_search_t <= 0.0:
			_player_search_t = 1.0
			_player = get_tree().get_first_node_in_group("player") as Node3D
		_show_prompt(null, "")
		return
	# Dead player: no interactions.
	if bool(_player.get("is_dead")):
		_show_prompt(null, "")
		return
	var best: Node = null
	var best_action := ""
	var best_d := PROMPT_RANGE
	for c in get_tree().get_nodes_in_group("civilian"):
		var action := _action_for(c)
		if action == "":
			continue
		var d = _player.global_position.distance_to((c as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = c
			best_action = action
	_show_prompt(best, best_action)

# "" = not actionable right now; otherwise "help" / "give" / "check".
func _action_for(c: Node) -> String:
	if c == null or not is_instance_valid(c):
		return ""
	if bool(c.get("is_in_need")) and not bool(c.get("helped")):
		return "help"
	if bool(c.get("is_poor")) and not bool(c.get("helped")):
		return "give"
	if bool(c.get("is_suspicious")):
		return "check"
	return ""

# ------------------------------------------------------------ UI (own)

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "InteractionUI"
	_layer.layer = 10
	add_child(_layer)

	# Money chip, top-right: left of the HUD pause button
	# (pause sits at w-60, r40; score chip is top-centre).
	var chip := PanelContainer.new()
	chip.name = "MoneyChip"
	chip.anchor_left = 1.0
	chip.anchor_right = 1.0
	chip.offset_left = -340.0
	chip.offset_right = -112.0
	chip.offset_top = 16.0
	chip.offset_bottom = 62.0
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = Color(0.02, 0.03, 0.04, 0.55)
	chip_style.corner_radius_top_left = 8
	chip_style.corner_radius_top_right = 8
	chip_style.corner_radius_bottom_left = 8
	chip_style.corner_radius_bottom_right = 8
	chip.add_theme_stylebox_override("panel", chip_style)
	_layer.add_child(chip)
	_money_label = Label.new()
	_money_label.name = "MoneyLabel"
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_money_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_money_label.add_theme_font_size_override("font_size", 30)
	_money_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_money_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_money_label.add_theme_constant_override("outline_size", 6)
	_money_label.text = "DT 0"
	chip.add_child(_money_label)

	# Prompt button, bottom-centre: free space between the MOVE
	# joystick (bottom-left) and FIRE (bottom-right).
	_prompt_button = Button.new()
	_prompt_button.name = "PromptButton"
	_prompt_button.anchor_left = 0.5
	_prompt_button.anchor_right = 0.5
	_prompt_button.anchor_top = 1.0
	_prompt_button.anchor_bottom = 1.0
	_prompt_button.offset_left = -180.0
	_prompt_button.offset_right = 180.0
	_prompt_button.offset_top = -235.0
	_prompt_button.offset_bottom = -125.0
	_prompt_button.focus_mode = Control.FOCUS_NONE
	_prompt_button.add_theme_font_size_override("font_size", 34)
	_prompt_button.add_theme_color_override("font_color", Color.WHITE)
	_prompt_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_prompt_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.35, 0.55, 0.92)
	normal.corner_radius_top_left = 16
	normal.corner_radius_top_right = 16
	normal.corner_radius_bottom_left = 16
	normal.corner_radius_bottom_right = 16
	normal.border_width_left = 3
	normal.border_width_right = 3
	normal.border_width_top = 3
	normal.border_width_bottom = 3
	normal.border_color = Color(0.75, 0.85, 0.95, 0.9)
	_prompt_button.add_theme_stylebox_override("normal", normal)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.06, 0.22, 0.38, 0.95)
	_prompt_button.add_theme_stylebox_override("pressed", pressed)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.14, 0.45, 0.68, 0.95)
	_prompt_button.add_theme_stylebox_override("hover", hover)
	_prompt_button.visible = false
	_prompt_button.pressed.connect(_on_prompt_pressed)
	_layer.add_child(_prompt_button)

	# Toast: one-line feedback under the score chip.
	_toast_label = Label.new()
	_toast_label.name = "ToastLabel"
	_toast_label.anchor_left = 0.5
	_toast_label.anchor_right = 0.5
	_toast_label.offset_left = -400.0
	_toast_label.offset_right = 400.0
	_toast_label.offset_top = 72.0
	_toast_label.offset_bottom = 124.0
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 28)
	_toast_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_toast_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_toast_label.add_theme_constant_override("outline_size", 8)
	_toast_label.visible = false
	_layer.add_child(_toast_label)

func _show_prompt(target: Node, action: String) -> void:
	_target = target
	_action = action
	if _prompt_button == null:
		return
	if target == null or action == "":
		_prompt_button.visible = false
		return
	match action:
		"help":
			_prompt_button.text = _tr("prompt_help", "HELP")
		"give":
			# "GIVE 10 DT" — the cost is appended to the translated verb.
			_prompt_button.text = "%s 10 DT" % _tr("prompt_give", "GIVE")
		"check":
			_prompt_button.text = _tr("prompt_check", "CHECK")
	_prompt_button.visible = true

func _on_money_changed(money: int) -> void:
	_update_money_label()

func _update_money_label() -> void:
	if _money_label == null:
		return
	var m := 0
	if _gm != null:
		m = int(_gm.get("money"))
	_money_label.text = "DT %d" % m

func _show_toast(text: String, duration: float = 2.5) -> void:
	if _toast_label == null:
		return
	_toast_label.text = text
	_toast_label.visible = true
	_toast_t = duration

# ------------------------------------------------------------ actions

func _on_prompt_pressed() -> void:
	if _target == null or not is_instance_valid(_target) or _action == "":
		return
	match _action:
		"help":
			_do_help(_target)
		"give":
			_do_give(_target)
		"check":
			_do_check(_target)
	# Re-scan immediately: a helped citizen is no longer actionable.
	_scan()

func _do_help(c: Node) -> void:
	if _gm != null:
		_gm.call("add_score", HELP_SCORE)
	c.call("mark_helped")
	_show_toast(_tr("interact_helped", "Citizen helped!  +50 score"))
	help_completed.emit(c)

func _do_give(c: Node) -> void:
	if _gm == null:
		return
	if bool(_gm.call("spend_money", GIVE_COST)):
		_gm.call("add_score", GIVE_SCORE)
		c.call("mark_helped")
		_show_toast(_tr("interact_gave", "You gave 10 DT  •  +25 score"))
		give_completed.emit(c)
	else:
		_show_toast(_tr("interact_no_money", "Not enough dinars!"))
		c.call("say_random", [ ["citizen_sad_1", "No money... maybe next time."], ["citizen_sad_2", "Ah... I understand."] ], 3.0)

func _do_check(c: Node) -> void:
	if bool(c.get("is_criminal")):
		c.call("expose_as_criminal")
		if _gm != null:
			_gm.call("add_score", EXPOSE_SCORE)
		_show_toast(_tr("interact_criminal", "Criminal exposed! He runs!  +25"))
		criminal_exposed.emit(c)
		check_completed.emit(c, true)
	else:
		c.call("say_greeting")
		_show_toast(_tr("interact_innocent", "Just a nervous citizen. Salam!"))
		check_completed.emit(c, false)

# ------------------------------------------------------------ helpers

# Same guarded translation lookup as citizen.gd: translate the key
# when LanguageManager has it, else the English fallback — without
# spamming its "missing key" warning for keys not added yet.
func _tr(key: String, fallback: String) -> String:
	var strings: Dictionary = LanguageManager.STRINGS
	var lang: Dictionary = strings.get(LanguageManager.current(), {})
	var en: Dictionary = strings.get("en", {})
	if lang.has(key) or en.has(key):
		return LanguageManager.translate(key)
	return fallback

# Re-apply the Arabic font / RTL direction when the language changes
# (LanguageManager has no change signal, so this is polled cheaply).
var _last_lang: String = ""

func _refresh_language() -> void:
	var cur := LanguageManager.current()
	if cur == _last_lang:
		return
	_last_lang = cur
	LanguageManager.apply_font_to(_prompt_button)
	LanguageManager.apply_font_to(_money_label)
	LanguageManager.apply_font_to(_toast_label)
	if _target != null:
		_show_prompt(_target, _action)

# Test / coordinator hooks (harmless in-game).
func get_current_target() -> Node:
	return _target

func get_current_action() -> String:
	return _action

func is_prompt_visible() -> bool:
	return _prompt_button != null and _prompt_button.visible

func get_prompt_text() -> String:
	return "" if _prompt_button == null else _prompt_button.text

func get_money_label_text() -> String:
	return "" if _money_label == null else _money_label.text

func press_prompt() -> void:
	_on_prompt_pressed()

## COORDINATOR WIRING (do not edit this file to wire it — add a node):
##   In scenes/main_game.tscn add, next to CitizenSpawner:
##     [ext_resource type="Script" path="res://scripts/interaction_manager.gd" id="N"]
##     [node name="InteractionManager" type="Node" parent="."]
##     script = ExtResource("N")
##   No other wiring is needed: it finds the player (group "player")
##   and citizens (group "civilian") itself, builds its own UI, and
##   talks to the GameManager autoload directly. Mission worker: award
##   dinars with GameManager.add_money(n); mark a citizen in need with
##   citizen.set_in_need(true); listen to InteractionManager signals
##   (give_completed / help_completed / criminal_exposed /
##   check_completed) or the citizen's own citizen_helped /
##   criminal_exposed signals for mission objectives.
