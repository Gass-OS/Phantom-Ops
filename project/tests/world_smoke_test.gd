extends SceneTree

func _initialize() -> void:
	call_deferred("_run_world_test")

func _run_world_test() -> void:
	# Exercise the real Android entry path: menu -> Deploy -> mission scene.
	var menu_scene := load("res://scenes/main_menu.tscn") as PackedScene
	if menu_scene == null:
		push_error("MENU_SMOKE_FAIL: main menu could not load")
		quit(1)
		return
	var menu := menu_scene.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	var deploy := _find_deploy_button(menu)
	if deploy == null:
		push_error("MENU_SMOKE_FAIL: Deploy button was not created")
		quit(1)
		return
	deploy.pressed.emit()
	await create_timer(2.0).timeout
	if current_scene == null or current_scene.scene_file_path != "res://scenes/main_game.tscn":
		push_error("MENU_SMOKE_FAIL: Deploy did not enter main_game.tscn")
		quit(1)
		return
	print("MENU_SMOKE_PASS: Deploy entered mission scene")

	var buildings := get_nodes_in_group("city_building").size()
	var civilians := get_nodes_in_group("civilian").size()
	var traffic := get_nodes_in_group("traffic").size()
	print("WORLD_SMOKE_COUNTS buildings=", buildings, " civilians=", civilians, " traffic=", traffic)
	if buildings < 100 or civilians < 35 or traffic < 10:
		push_error("WORLD_SMOKE_FAIL: expected >=100 buildings, >=35 civilians and >=10 traffic vehicles")
		quit(1)
		return
	print("WORLD_SMOKE_PASS: dense city, pedestrians and traffic instantiated")
	quit(0)

func _find_deploy_button(node: Node) -> Button:
	if node is Button and (node as Button).text.contains("DEPLOY"):
		return node as Button
	for child in node.get_children():
		var found := _find_deploy_button(child)
		if found != null:
			return found
	return null
