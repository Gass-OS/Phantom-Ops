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
# v0.8 WANTED: heat level cached at wave start (0 when WantedManager is
# absent — the game then behaves exactly as v0.7). _interval_factor
# shrinks the gap between waves at higher heat.
var _heat_level: int = 0
var _interval_factor: float = 1.0
# Defensive load of wanted_manager.gd (same pattern mission_director.gd
# uses for LanguageManager): the spawner must still parse and run if
# the wanted script is ever removed.
var _wm_script: Script = null
var _wm_tried := false
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
	# v0.8 WANTED: heat grows the wave and quickens the pace.
	# L2 +2 / x0.8, L3 +3 / x0.7, L4 +4 / x0.6, L5 as L4 (plus the hit
	# squad, which WantedManager spawns separately). The cap rises by
	# the same bonus so the +N is real at every wave, not just early.
	_heat_level = _heat_level_now()
	var bonus := 0
	_interval_factor = 1.0
	match _heat_level:
		2:
			bonus = 2
			_interval_factor = 0.8
		3:
			bonus = 3
			_interval_factor = 0.7
		4, 5:
			bonus = 4
			_interval_factor = 0.6
	var count: int = mini(enemies_per_wave + wave - 1 + bonus, max_wave_size + bonus)
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
	# v0.8 WANTED: every spawned enemy gets the current heat variant.
	_build_enemy_at(pos, _heat_level, "Enemy")

## Shared construction for wave enemies and the hit squad (same body,
## collision, group, target and death wiring — only the variant level
## and the node name differ).
func _build_enemy_at(pos: Vector3, variant_level: int, enemy_name: String) -> CharacterBody3D:
	var enemy := CharacterBody3D.new()
	enemy.name = enemy_name
	enemy.set_script(load("res://scripts/enemy_ai.gd"))
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	col.shape = shape
	col.position.y = 0.9
	enemy.add_child(col)
	enemy.position = pos + Vector3(0, 1.0, 0)
	# v0.8 WANTED: set the variant BEFORE add_child, so EnemyAI._ready()
	# builds the right look first time (no free/rebuild afterwards).
	enemy.set("variant_level", variant_level)
	add_child(enemy)
	# Citizens look for group "zombie" to flee from.
	enemy.add_to_group("zombie")
	# EnemyAI._ready() builds its visible body; set the target after add.
	enemy.target = _player
	# v0.8 WANTED: heat variant (no-op when the method is absent).
	if enemy.has_method("apply_variant"):
		enemy.call("apply_variant", variant_level)
	if enemy.has_signal("enemy_died"):
		enemy.enemy_died.connect(_on_enemy_died)
	alive += 1
	return enemy

## v0.8 WANTED — hit squad: 4 L5 elites near the player, called ONLY by
## WantedManager when heat first reaches L5 (never during the boss
## fight — the manager guards that). Returns the spawned enemies so the
## manager can track their deaths and pay the bounty. Empty when the
## spawner is stopped (player dead) or the player is missing.
func spawn_hit_squad() -> Array:
	var squad: Array = []
	if stopped:
		return squad
	if _player == null or not is_instance_valid(_player):
		return squad
	var spots := _squad_spots()
	if spots.is_empty():
		return squad
	for i in range(4):
		var enemy := _build_enemy_at(spots[i % spots.size()], 5, "HitSquad_%02d" % i)
		enemy.set_meta("hit_squad", true)
		squad.append(enemy)
	_update_hud()
	return squad

## Squad spawn spots: prefer real street/plaza spawn points within
## 40 m of the player (safe by construction), fill the rest with a
## ring around the player (15 m, clamped to the city bounds).
func _squad_spots() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	var pp: Vector3 = _player.global_position
	for p in _spawn_points():
		var d := p - pp
		d.y = 0.0
		if d.length() <= 40.0:
			spots.append(p)
		if spots.size() >= 4:
			break
	var i := 0
	while spots.size() < 4 and i < 4:
		var angle := (TAU / 4.0) * float(i) + 0.7
		var ring := pp + Vector3(cos(angle) * 15.0, 0.0, sin(angle) * 15.0)
		ring.x = clampf(ring.x, -145.0, 145.0)
		ring.z = clampf(ring.z, -145.0, 145.0)
		spots.append(ring)
		i += 1
	return spots

## Current heat level via WantedManager (0 = absent / v0.7 behaviour).
func _heat_level_now() -> int:
	var wm := _wanted_manager()
	if wm == null:
		return 0
	if wm.has_method("get_level"):
		return int(wm.call("get_level"))
	return 0

## WantedManager lookup without a hard class dependency: null when the
## script is missing or the coordinator did not add the node.
func _wanted_manager() -> Node:
	if not _wm_tried:
		_wm_tried = true
		if FileAccess.file_exists("res://scripts/wanted_manager.gd"):
			_wm_script = load("res://scripts/wanted_manager.gd") as Script
	if _wm_script == null:
		return null
	return _wm_script.call("find_in", get_tree()) as Node

func _on_enemy_died(_enemy: Node) -> void:
	alive -= 1
	# v0.8 WANTED: killing a gang member is +6 heat (null-guarded;
	# nothing changes when WantedManager is absent).
	var wm := _wanted_manager()
	if wm != null and wm.has_method("add_heat"):
		wm.call("add_heat", 6.0, "kill")
	if _sound != null:
		_sound.play_kill()
		_sound.play_enemy_death()
	if is_instance_valid(GameManager):
		GameManager.add_kill()
		GameManager.add_score(100)
	_update_hud()
	if alive <= 0 and not _between_waves:
		_between_waves = true
		# v0.8 WANTED: hotter waves return sooner.
		_timer = seconds_between_waves * _interval_factor

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
