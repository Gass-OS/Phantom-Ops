extends Control

func _ready():
    var bg = ColorRect.new()
    bg.color = Color(0.07, 0.075, 0.09)
    add_child(bg)
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var center = CenterContainer.new()
    add_child(center)
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var box = VBoxContainer.new()
    box.add_theme_constant_override("separation", 28)
    center.add_child(box)

    var title = Label.new()
    title.text = "PHANTOM OPS"
    title.add_theme_font_size_override("font_size", 110)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(title)

    var sub = Label.new()
    sub.text = "KASSERINE - OPERATIONS"
    sub.add_theme_font_size_override("font_size", 40)
    sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(sub)

    var play = Button.new()
    play.text = "DEPLOY"
    play.custom_minimum_size = Vector2(520, 150)
    play.add_theme_font_size_override("font_size", 70)
    play.pressed.connect(_on_deploy_pressed)
    box.add_child(play)

func _on_deploy_pressed():
    get_tree().change_scene_to_file("res://scenes/main_game.tscn")
