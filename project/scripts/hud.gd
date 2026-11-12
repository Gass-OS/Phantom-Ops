extends CanvasLayer

const TouchScript = preload("res://scripts/touch_controls.gd")

var player = null
var health_bar: ProgressBar
var stats_label: Label
var weather_label: Label
var death_panel: ColorRect
var flash: ColorRect

func _make_label(pos: Vector2, size_px: int) -> Label:
    var l = Label.new()
    l.position = pos
    l.add_theme_font_size_override("font_size", size_px)
    l.add_theme_color_override("font_outline_color", Color.BLACK)
    l.add_theme_constant_override("outline_size", 8)
    add_child(l)
    return l

func _ready():
    layer = 10

    flash = ColorRect.new()
    flash.color = Color(0.8, 0.0, 0.0, 0.0)
    flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(flash)
    flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    health_bar = ProgressBar.new()
    health_bar.min_value = 0
    health_bar.max_value = 100
    health_bar.value = 100
    health_bar.show_percentage = false
    health_bar.position = Vector2(30, 24)
    health_bar.size = Vector2(380, 36)
    add_child(health_bar)

    stats_label = _make_label(Vector2(30, 68), 32)
    weather_label = _make_label(Vector2(30, 112), 28)

    if DisplayServer.is_touchscreen_available():
        var touch = TouchScript.new()
        touch.player = player
        add_child(touch)
        touch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    _build_death_panel()

    GameManager.stats_changed.connect(_update_stats)
    _update_stats()

    if player != null:
        player.health_changed.connect(_on_health)
        player.player_died.connect(_on_died)

func _build_death_panel():
    death_panel = ColorRect.new()
    death_panel.color = Color(0, 0, 0, 0.65)
    death_panel.visible = false
    add_child(death_panel)
    death_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var center = CenterContainer.new()
    death_panel.add_child(center)
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var box = VBoxContainer.new()
    box.add_theme_constant_override("separation", 28)
    center.add_child(box)

    var title = Label.new()
    title.text = "YOU DIED"
    title.add_theme_font_size_override("font_size", 100)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(title)

    var again = Button.new()
    again.text = "RESTART"
    again.custom_minimum_size = Vector2(440, 130)
    again.add_theme_font_size_override("font_size", 56)
    again.pressed.connect(_on_restart)
    box.add_child(again)

    var menu = Button.new()
    menu.text = "MENU"
    menu.custom_minimum_size = Vector2(440, 110)
    menu.add_theme_font_size_override("font_size", 48)
    menu.pressed.connect(_on_menu)
    box.add_child(menu)

func _process(_delta):
    var w = get_tree().get_first_node_in_group("weather")
    if w != null:
        weather_label.text = "Weather: " + w.label_text

func _update_stats():
    stats_label.text = "Score %d   Kills %d   Wave %d" % [
        GameManager.score, GameManager.kills, GameManager.wave
    ]

func _on_health(current, maximum):
    health_bar.max_value = maximum
    health_bar.value = current
    flash.color = Color(0.8, 0.0, 0.0, 0.35)
    var tw = create_tween()
    tw.tween_property(flash, "color:a", 0.0, 0.35)

func _on_died():
    death_panel.visible = true

func _on_restart():
    get_tree().reload_current_scene()

func _on_menu():
    get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
