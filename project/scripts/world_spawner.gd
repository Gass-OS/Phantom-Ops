extends Node

const CitizenScript = preload("res://scripts/citizen.gd")
const ZombieScript = preload("res://scripts/enemy_ai.gd")

var player: Node3D = null
var spawn_timer := 4.0
var max_zombies := 8
var population_target := 42
var population_check := 0.0

func _ready() -> void:
	call_deferred("_spawn_initial")

func _spawn_initial() -> void:
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		push_warning("PHANTOM OPS: citizen spawner could not find player")
		return
	for i in range(population_target):
		_spawn_citizen(i)
	for i in range(3):
		_spawn_zombie()
	print("PHANTOM OPS: spawned ", population_target, " nearby civilians")

func _spawn_citizen(index: int) -> void:
	var citizen = CitizenScript.new()
	citizen.is_female = index % 2 == 1
	citizen.variant = index + 60
	citizen.spawn_near_center = true
	citizen.spawn_center = player.global_position
	citizen.spawn_radius = 58.0
	citizen.axis = index % 2
	citizen.lane = (player.global_position.z if citizen.axis == 0 else player.global_position.x) + (9.2 if index % 4 < 2 else -9.2)
	get_parent().add_child(citizen)

func _process(delta: float) -> void:
	if not is_instance_valid(player) or player.get("is_dead") == true:
		return
	population_check += delta
	if population_check >= 8.0:
		population_check = 0.0
		var nearby := 0
		for person in get_tree().get_nodes_in_group("civilian"):
			if is_instance_valid(person) and person.global_position.distance_to(player.global_position) < 82.0:
				nearby += 1
		while nearby < 30:
			_spawn_citizen(randi())
			nearby += 1
	var new_wave := 1 + int(GameManager.kills / 8.0)
	if new_wave != GameManager.wave:
		GameManager.wave = new_wave
		max_zombies = 6 + new_wave * 2
		GameManager.stats_changed.emit()
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = maxf(2.0, 7.0 - GameManager.wave * 0.4)
		if get_tree().get_nodes_in_group("zombie").size() < max_zombies:
			_spawn_zombie()

func _spawn_zombie() -> void:
	var p = GameManager.random_road_point()
	if is_instance_valid(player):
		for i in range(10):
			if p.distance_to(player.global_position) > 28.0:
				break
			p = GameManager.random_road_point()
	var zombie = ZombieScript.new()
	zombie.max_health = 50.0 + GameManager.wave * 10.0
	zombie.position = p
	get_parent().add_child(zombie)
