extends Control
var elapsed := 0.0
var phase := 0
var title_label: Label
var story_label: Label
var tag_label: Label
var cards: Array[Dictionary] = [
 {"title":"THE CITY HAS FALLEN","body":"Kasserine is under threat. Streets are no longer safe, and every decision matters.","tag":"01 / THE OUTBREAK"},
 {"title":"PROTECT THE PEOPLE","body":"Civilians move through the district. Watch for danger, help where you can, and avoid infected zones.","tag":"02 / CIVILIAN LIFE"},
 {"title":"YOUR MISSION STARTS NOW","body":"Explore the city, survive hostile waves, and complete your objectives. Stay alert. Stay alive.","tag":"03 / DEPLOYMENT"}
]
func _ready() -> void:
 var bg := ColorRect.new()
 bg.color = Color(0.015,0.025,0.04)
 bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(bg)
 var art := Control.new()
 art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 art.draw.connect(_draw_city.bind(art))
 add_child(art)
 var shade := ColorRect.new()
 shade.color = Color(0.01,0.02,0.03,0.45)
 shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(shade)
 var col := VBoxContainer.new()
 col.name = "Briefing"
 col.anchor_left = 0.07
 col.anchor_right = 0.93
 col.anchor_top = 0.18
 col.anchor_bottom = 0.84
 col.add_theme_constant_override("separation",18)
 add_child(col)
 var logo := Label.new()
 logo.text = "⬟  PHANTOM OPS"
 logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 logo.add_theme_font_size_override("font_size",42)
 logo.add_theme_color_override("font_color",Color(0.96,0.98,1))
 col.add_child(logo)
 var line := ColorRect.new()
 line.custom_minimum_size.y = 3
 line.color = Color(0.84,0.25,0.16)
 col.add_child(line)
 tag_label = Label.new()
 tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 tag_label.add_theme_font_size_override("font_size",17)
 tag_label.add_theme_color_override("font_color",Color(1,0.48,0.29))
 col.add_child(tag_label)
 title_label = Label.new()
 title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 title_label.add_theme_font_size_override("font_size",40)
 title_label.add_theme_color_override("font_color",Color.WHITE)
 col.add_child(title_label)
 story_label = Label.new()
 story_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 story_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 story_label.add_theme_font_size_override("font_size",22)
 story_label.add_theme_color_override("font_color",Color(0.78,0.85,0.9))
 col.add_child(story_label)
 var skip := Button.new()
 skip.text = "CONTINUE"
 skip.custom_minimum_size.y = 60
 skip.pressed.connect(_open_menu)
 col.add_child(skip)
 _show_card()
func _process(delta: float) -> void:
 elapsed += delta
 if elapsed >= 5.0:
  elapsed = 0.0
  phase += 1
  if phase >= cards.size():
   _open_menu()
  else:
   _show_card()
func _draw_city(c: Control) -> void:
 var s := c.size
 var horizon := s.y * 0.56
 for i in range(13):
  var x := float(i) * s.x / 12.0
  var h := 90.0 + float((i * 41) % 155)
  c.draw_rect(Rect2(x,horizon-h,s.x/14.0,h),Color(0.12,0.20,0.25,0.82))
  c.draw_rect(Rect2(x+8,horizon-h+18,8,12),Color(0.92,0.52,0.28,0.85))
 c.draw_rect(Rect2(0,horizon,s.x,s.y-horizon),Color(0.045,0.065,0.08,0.9))
 c.draw_line(Vector2(0,horizon),Vector2(s.x,horizon),Color(0.8,0.3,0.2,0.8),3.0)
 for j in range(5):
  var px := s.x * (0.18 + j * 0.15)
  c.draw_circle(Vector2(px,horizon+76),12,Color(0.02,0.03,0.04))
  c.draw_rect(Rect2(px-8,horizon+86,16,48),Color(0.12,0.17,0.2))
func _show_card() -> void:
 var item: Dictionary = cards[phase]
 tag_label.text = item.tag
 title_label.text = item.title
 story_label.text = item.body
func _open_menu() -> void:
 if is_inside_tree():
  get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
