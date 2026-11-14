extends Node3D
## v0.4 — AAA main menu: a live 3D Kasserine city behind the UI, with
## a slow orbiting camera and Aymen (the hero scan) standing in the
## plaza. If the 3D city ever fails to build, the gradient background
## is shown instead so the menu can never go black.

var _sound: SoundManager
var _camera: Camera3D
var _angle := 0.0

func _ready() -> void:
	if is_instance_valid(GameManager):
		GameManager.reset_game()
	_sound = SoundManager.new()
	_sound.name = "SoundManager"
	add_child(_sound)
	_sound.start_wind()
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
	_update_sound_button()

func _process(delta: float) -> void:
	# Slow orbit around the plaza, looking at the minaret / city.
	_angle += delta * 0.06
	var r := 58.0
	_camera.position = Vector3(cos(_angle) * r, 24.0 + sin(_angle * 0.7) * 4.0, sin(_angle) * r)
	_camera.look_at(Vector3(0, 9, -5), Vector3.UP)

func _update_sound_button() -> void:
	var b := $CanvasLayer/UI/Sound as Button
	b.text = "SOUND: ON" if SoundManager.sound_on else "SOUND: OFF"

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
