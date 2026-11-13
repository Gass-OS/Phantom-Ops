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
	if buildings < 50 or civilians < 20 or traffic < 8:
		push_error("WORLD_SMOKE_FAIL: expected >=50 buildings, >=20 civilians and >=8 traffic vehicles")
		quit(1)
		return
	print("WORLD_SMOKE_PASS: dense city, pedestrians and traffic instantiated")

	var game := current_scene
	var city := game.get_node_or_null("City")
	if city == null:
		push_error("CITY_LIFE_FAIL: City node missing")
		quit(1)
		return
	for landmark in ["PharmacyLandmark", "MagazineLandmark", "DistrictSchool", "NeighborhoodMosque", "NeighborhoodPark", "FruitVegetableMarket"]:
		if city.find_child(landmark, true, false) == null:
			push_error("CITY_LIFE_FAIL: missing " + landmark)
			quit(1)
			return
	if game.get_node_or_null("CityLifeVoice") == null:
		push_error("CITY_VOICE_FAIL: ambient voice controller missing")
		quit(1)
		return
	print("CITY_LIFE_PASS: all six landmarks and ambient voice controller present")

	var player := game.get_node_or_null("Player")
	if player == null:
		push_error("EXIT_SMOKE_FAIL: player missing")
		quit(1)
		return
	player.call("_on_menu")
	await create_timer(1.0).timeout
	if current_scene == null or current_scene.scene_file_path != "res://scenes/main_menu.tscn":
		push_error("EXIT_SMOKE_FAIL: safe return to main menu failed")
		quit(1)
		return
	if root.find_child("MobileHUDLayer", true, false) != null:
		push_error("EXIT_SMOKE_FAIL: mobile HUD layer leaked after scene exit")
		quit(1)
		return
	print("EXIT_SMOKE_PASS: game scene and mobile HUD cleanly unloaded")
	quit(0)

func _find_deploy_button(node: Node) -> Button:
	if node is Button and (node as Button).text.contains("DEPLOY"):
		return node as Button
	for child in node.get_children():
		var found := _find_deploy_button(child)
		if found != null:
			return found
	return null
