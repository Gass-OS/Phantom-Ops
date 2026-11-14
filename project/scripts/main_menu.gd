extends Control

var _sound: SoundManager

func _ready():
	if is_instance_valid(GameManager):
		GameManager.reset_game()
	_sound = SoundManager.new()
	_sound.name = "SoundManager"
	add_child(_sound)
	_sound.start_wind()
	$Play.pressed.connect(_on_deploy_pressed)

func _on_deploy_pressed():
	if _sound != null:
		_sound.play_click()
	get_tree().change_scene_to_file(
		"res://scenes/main_game.tscn"
	)
