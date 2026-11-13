extends SceneTree

func _initialize() -> void:
	call_deferred("_run_world_test")

func _run_world_test() -> void:
	var packed := load("res://scenes/main_game.tscn") as PackedScene
	if packed == null:
		push_error("WORLD_SMOKE_FAIL: main_game scene could not load")
		quit(1)
		return
	var game := packed.instantiate()
	root.add_child(game)
	await create_timer(1.5).timeout
	var buildings := get_nodes_in_group("city_building").size()
	var civilians := get_nodes_in_group("civilian").size()
	var traffic := get_nodes_in_group("traffic").size()
	print("WORLD_SMOKE_COUNTS buildings=", buildings, " civilians=", civilians, " traffic=", traffic)
	if buildings < 100 or civilians < 80 or traffic < 10:
		push_error("WORLD_SMOKE_FAIL: expected >=100 buildings, >=80 civilians and >=10 traffic vehicles")
		quit(1)
		return
	print("WORLD_SMOKE_PASS: dense city, pedestrians and traffic instantiated")
	quit(0)
