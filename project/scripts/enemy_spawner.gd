extends Node3D
class_name EnemySpawner
## Wave spawner for Phantom Ops v0.2. Reuses EnemyAI (enemy_ai.gd).
## Spawn points come from the city generator (streets / plaza, away
## from the player). Kills are wired to GameManager for score.

@export var enemies_per_wave: int = 8
@export var max_wave_size: int = 12
@export var seconds_between_waves: float = 3.0

var wave: int = 0
var alive: int = 0
var _between_waves: bool = false
var _timer: float = 0.0
var _player: Node3D = null
var _city: Node3D = null
var _sound: SoundManager
# v0.5: set when the player dies — no more waves spawn while the
# YOU DIED screen is up, and RETRY starts a fresh spawner anyway.
var stopped := false

func stop_waves() -> void:
	stopped = true
	_between_waves = false
	set_process(false)

func _ready() -> void:
	_sound = SoundManager.new()
	_sound.name = "SoundManager"
	add_child(_sound)
	var cs := get_tree().current_scene
	if cs != null:
		_player = cs.get_node_or_null("Player") as Node3D
		_city = cs.get_node_or_null("City") as Node3D
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	# Deferred: spawning (add_child) during scene setup fails with
	# "parent node is busy setting up children".
	call_deferred("_start_wave")

func _process(delta: float) -> void:
	if stopped:
		return
	if _between_waves:
		_timer -= delta
		if _timer <= 0.0:
			_between_waves = false
			_start_wave()

func _start_wave() -> void:
	if stopped:
		return
	wave += 1
	if _sound != null:
		_sound.play_horn()
	var count: int = mini(enemies_per_wave + wave - 1, max_wave_size)
	var points: Array[Vector3] = _spawn_points()
	if points.is_empty():
		points = [Vector3(40, 0, -40), Vector3(-40, 0, 40), Vector3(60, 0, 60)]
	alive = 0
	for i in range(count):
		_spawn_enemy(points[i % points.size()] + Vector3(randf_range(-3.0, 3.0), 0, randf_range(-3.0, 3.0)))
	_update_hud()

func _spawn_points() -> Array[Vector3]:
	if _city != null:
		var pts: Array[Vector3] = []
		var raw: Variant = _city.get("spawn_points")
		if raw is Array:
			for p in raw:
				pts.append(p)
			pts.shuffle()
			return pts
	return []

func _spawn_enemy(pos: Vector3) -> void:
	var enemy := CharacterBody3D.new()
	enemy.name = "Enemy"
	enemy.set_script(load("res://scripts/enemy_ai.gd"))
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	col.shape = shape
	col.position.y = 0.9
	enemy.add_child(col)
	enemy.position = pos + Vector3(0, 1.0, 0)
	add_child(enemy)
	# Citizens look for group "zombie" to flee from.
	enemy.add_to_group("zombie")
	# EnemyAI._ready() builds its visible body; set the target after add.
	enemy.target = _player
	if enemy.has_signal("enemy_died"):
		enemy.enemy_died.connect(_on_enemy_died)
	alive += 1

func _on_enemy_died(_enemy: Node) -> void:
	alive -= 1
	if _sound != null:
		_sound.play_kill()
		_sound.play_enemy_death()
	if is_instance_valid(GameManager):
		GameManager.add_kill()
		GameManager.add_score(100)
	_update_hud()
	if alive <= 0 and not _between_waves:
		_between_waves = true
		_timer = seconds_between_waves

func _update_hud() -> void:
	var hud := _find_hud()
	if hud != null and hud.has_method("set_wave"):
		hud.set_wave(wave)
		hud.set_score(GameManager.score, GameManager.kills)

func _find_hud() -> Node:
	var layer := get_tree().root.get_node_or_null("MobileHUDLayer")
	if layer != null:
		return layer.get_node_or_null("MobileHUD")
	return null
