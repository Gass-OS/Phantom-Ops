extends Control

func _ready():
	if is_instance_valid(GameManager):
		GameManager.reset_game()
	$Play.pressed.connect(_on_deploy_pressed)

func _on_deploy_pressed():
	get_tree().change_scene_to_file(
		"res://scenes/main_game.tscn"
	)
