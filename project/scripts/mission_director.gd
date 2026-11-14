extends Node3D
class_name PhantomMissionDirector
## Phantom Ops v0.6 — SYSTEM 2: POLICE MISSIONS.
##
## The player is a Kasserine police officer. Four mission types chain in
## order and then repeat forever:
##   (a) RESPOND — robbery at a marked spot; defeat the 3 spawned criminals.
##   (b) HELP    — a poor citizen needs help; reach them, then the help
##                 interaction completes the mission (see _HELP RULE below).
##   (c) CHASE   — a criminal flees on foot; get within 4 m to catch him.
##   (d) PATROL  — visit 3 checkpoints in order.
## Each mission pays dinars (GameManager.money, if that worker has added
## it — see _MONEY NOTE) + score, and has a fail condition (timeout, or
## the criminal escaping in CHASE). Missions start automatically 3 s
## after the game starts; the next starts 2.5 s after the previous one
## completes or fails. Nothing here can crash the game if a target
## despawns: every node access is guarded with is_instance_valid().
##
## _MONEY NOTE — GameManager.money dependency (another worker owns it):
##   game_manager.gd NOW has `money` + add_money() + money_changed (it
##   landed while this system was being built). _grant_reward() prefers
##   add_money() (so money_changed fires and the HUD updates), falls back
##   to the direct `money` property, and only warns if neither exists.
##   This file still NEVER assumes `money` exists, and no edit to
##   game_manager.gd was made here.
##
## _HELP RULE — the citizen worker owns the help interaction. Completion
##   is EITHER path, whichever happens first:
##   1. The citizen worker / coordinator calls notify_help_given(citizen)
##      when its help interaction happens -> instant completion.
##   2. Fallback: the player stands within 5 m of the needy citizen for
##      3 s (the "helping…" timer) -> completion. This guarantees the
##      mission can always finish even if no interaction is ever wired.
##   If no civilian exists at all when HELP starts, a fallback marker
##   point is used and arrival + the same 3 s timer completes it.
##
## _TRANSLATION NOTE — LanguageManager EXISTS now (landed while this
##   system was being built): class_name LanguageManager, RefCounted,
##   static API LanguageManager.translate(key) / t(key); there is NO
##   autoload and NO static tr() (a static tr() cannot override the
##   native Object.tr() in Godot 4.2). _tr() below therefore loads the
##   script defensively (FileAccess.file_exists first, so this file
##   still parses/runs if language_manager.gd is ever removed) and calls
##   the instance tr() on a cached instance, which delegates to
##   translate(). Keys used that already exist in its STRINGS table:
##   mission_respond / mission_help / mission_chase / mission_patrol
##   (titles), mission_complete / mission_failed (banners). The
##   mission_*_detail and mission_helping keys do NOT exist there yet —
##   they fall back to the English strings below until the language
##   worker adds them; that fallback is by design, never a crash.
##
## WIRING (for the coordinator): main_game.gd ALREADY instantiates this
##   director at runtime (MissionScript.new(), node name "MissionDirector")
##   — no main_game.tscn edit is needed. Signals emitted:
##   mission_started(id, title), mission_completed(id, title, money, score),
##   mission_failed(id, title, reason). Public methods the coordinator or
##   other workers may call: notify_help_given(citizen), skip_mission(),
##   current_mission_id().

signal mission_started(mission_id: String, title: String)
signal mission_completed(mission_id: String, title: String, money: int, score: int)
signal mission_failed(mission_id: String, title: String, reason: String)

const PanelScript := preload("res://scripts/mission_panel.gd")
const EnemyScript := preload("res://scripts/enemy_ai.gd")

# First mission starts this long after the game starts; gap between missions.
const START_DELAY := 3.0
const BETWEEN_DELAY := 2.5
# Chase tuning: player walks 5.0 m/s, sprints 8.5 (player.gd), so 4.6 is
# catchable on foot but still a real chase.
const CHASE_SPEED := 4.6
const CHASE_CATCH_DIST := 4.0
const CHASE_ESCAPE_DIST := 90.0
const HELP_ARRIVE_DIST := 5.0
const HELP_HOLD_TIME := 3.0
const PATROL_ARRIVE_DIST := 4.0

# The chain. Points are street/plaza spots inside the ~300 m city.
# reward_money = dinars, reward_score = XP. time_limit = fail timeout (s).
var missions := [
	{
		"id": "respond", "type": "respond",
		"title_key": "mission_respond", "title": "🚨 RESPOND: ROBBERY IN PROGRESS",
		"detail_key": "mission_respond_detail",
		"detail": "Robbery reported! Reach the marked location and stop the criminals.",
		"point": Vector3(40, 0, -60), "reward_money": 150, "reward_score": 300,
		"time_limit": 150.0, "enemy_count": 3,
	},
	{
		"id": "help", "type": "help",
		"title_key": "mission_help", "title": "🤝 HELP A CITIZEN IN NEED",
		"detail_key": "mission_help_detail",
		"detail": "A poor citizen needs help. Reach them and give what you can.",
		"point": Vector3(-30, 0, 45), "reward_money": 80, "reward_score": 150,
		"time_limit": 120.0,
	},
	{
		"id": "chase", "type": "chase",
		"title_key": "mission_chase", "title": "🏃 CHASE THE FLEEING CRIMINAL",
		"detail_key": "mission_chase_detail",
		"detail": "A criminal is fleeing on foot! Catch him before he escapes.",
		"point": Vector3(-60, 0, -20), "reward_money": 200, "reward_score": 400,
		"time_limit": 90.0,
	},
	{
		"id": "patrol", "type": "patrol",
		"title_key": "mission_patrol", "title": "🚓 PATROL THE DISTRICT",
		"detail_key": "mission_patrol_detail",
		"detail": "Patrol duty: visit all 3 checkpoints in order.",
		"point": Vector3(60, 0, 80), "reward_money": 120, "reward_score": 250,
		"time_limit": 180.0,
		"checkpoints": [Vector3(60, 0, 80), Vector3(-70, 0, -60), Vector3(0, 0, -110)],
	},
]

var current_index := 0
var _state := "idle"  # idle | waiting | active | between
var _delay_timer := START_DELAY
var _time_left := 0.0
var _player: Node3D = null
var _panel: PanelScript = null
var _objective: Area3D = null
var _beacon: MeshInstance3D = null
var _beacon_mat: StandardMaterial3D = null
var _beacon_base_y := 0.0
var _pulse := 0.0

# Per-mission live targets (all guarded with is_instance_valid).
var _respond_targets: Array = []
var _chase_target: Node3D = null
var _chase_dir := Vector3(1, 0, 0)
var _help_citizen: Node3D = null
var _help_hold := 0.0
var _patrol_points: Array = []
var _patrol_index := 0

func _ready() -> void:
	_panel = PanelScript.new()
	_panel.name = "MissionPanel"
	add_child(_panel)
	_panel.clear()
	_find_player()
	_state = "waiting"
	_delay_timer = START_DELAY
	# v0.6 integration: instant HELP completion when the citizen
	# interaction manager reports help given (deferred — the manager
	# node may be added after this one; guarded if it never exists).
	call_deferred("_wire_interaction")

func _wire_interaction() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var im := scene.get_node_or_null("InteractionManager")
	if im == null or not im.has_signal("help_completed"):
		return
	if not im.is_connected("help_completed", notify_help_given):
		im.connect("help_completed", notify_help_given)

func _find_player() -> void:
	if is_instance_valid(_player):
		return
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		var scene := get_tree().current_scene
		if scene != null:
			_player = scene.get_node_or_null("Player") as Node3D

func _process(delta: float) -> void:
	_find_player()
	_pulse += delta
	_pulse_beacon()
	match _state:
		"waiting":
			_delay_timer -= delta
			if _delay_timer <= 0.0:
				_start_current_mission()
		"between":
			_delay_timer -= delta
			if _delay_timer <= 0.0:
				_start_current_mission()
		"active":
			_tick_active(delta)

## Public API ---------------------------------------------------------------

func current_mission_id() -> String:
	if _state != "active":
		return ""
	return String(missions[current_index % missions.size()].get("id", ""))

## Called by the citizen worker / coordinator when its help interaction
## happens. Completes HELP instantly if that mission is active. Safe to
## call at any other time (no-op).
func notify_help_given(citizen: Node) -> void:
	if _state != "active":
		return
	if String(missions[current_index % missions.size()].get("type", "")) != "help":
		return
	if is_instance_valid(_help_citizen) and citizen != _help_citizen:
		return  # help given to a different citizen; ignore
	_complete_current()

## Coordinator/debug hook: abandon the current mission as failed.
func skip_mission() -> void:
	if _state == "active":
		_fail_current("skipped")

# --- Mission lifecycle ------------------------------------------------------

func _start_current_mission() -> void:
	if missions.is_empty():
		return
	var data: Dictionary = missions[current_index % missions.size()]
	_state = "active"
	_time_left = float(data.get("time_limit", 120.0))
	_help_hold = 0.0
	_patrol_index = 0
	_patrol_points = []
	_respond_targets.clear()
	_chase_target = null
	_help_citizen = null

	var title := _tr(String(data.get("title_key", "")), String(data.get("title", "")))
	var detail := _tr(String(data.get("detail_key", "")), String(data.get("detail", "")))
	if is_instance_valid(_panel):
		_panel.show_mission(title, detail,
			int(data.get("reward_money", 0)), int(data.get("reward_score", 0)))
	mission_started.emit(String(data.get("id", "")), title)

	match String(data.get("type", "")):
		"respond":
			_create_objective(Vector3(data.get("point", Vector3.ZERO)), 3.0, false)
			_spawn_respond_enemies(Vector3(data.get("point", Vector3.ZERO)),
				int(data.get("enemy_count", 3)))
		"help":
			_start_help_mission()
		"chase":
			_create_objective(Vector3(data.get("point", Vector3.ZERO)), 3.0, false)
			_spawn_chase_criminal(Vector3(data.get("point", Vector3.ZERO)))
		"patrol":
			_patrol_points = (data.get("checkpoints", []) as Array).duplicate()
			if _patrol_points.is_empty():
				_patrol_points = [Vector3(data.get("point", Vector3.ZERO))]
			_create_objective(_patrol_points[0], 4.0, true)
		_:
			_create_objective(Vector3(data.get("point", Vector3.ZERO)), 3.0, true)

func _complete_current() -> void:
	if _state != "active":
		return
	var data: Dictionary = missions[current_index % missions.size()]
	var title := _tr(String(data.get("title_key", "")), String(data.get("title", "")))
	_state = "between"
	_delay_timer = BETWEEN_DELAY
	_cleanup_targets()
	var money := int(data.get("reward_money", 0))
	var score := int(data.get("reward_score", 0))
	_grant_reward(money, score)
	if is_instance_valid(_panel):
		_panel.show_banner(
			_tr("mission_complete", "MISSION COMPLETE") + "  +%d dinars  +%d XP" % [money, score], true)
	mission_completed.emit(String(data.get("id", "")), title, money, score)
	current_index = (current_index + 1) % missions.size()

func _fail_current(reason: String) -> void:
	if _state != "active":
		return
	var data: Dictionary = missions[current_index % missions.size()]
	var title := _tr(String(data.get("title_key", "")), String(data.get("title", "")))
	_state = "between"
	_delay_timer = BETWEEN_DELAY
	_cleanup_targets()
	if is_instance_valid(_panel):
		_panel.show_banner(_tr("mission_failed", "MISSION FAILED") + " — " + reason, false)
	mission_failed.emit(String(data.get("id", "")), title, reason)
	current_index = (current_index + 1) % missions.size()

## Pays score always; dinars via GameManager.add_money() when that
##   worker's API exists (it does now: money + add_money + money_changed
##   in game_manager.gd), else by direct `money` property, else a warning.
##   Never assumes `money` exists — see _MONEY NOTE in the header.
func _grant_reward(money: int, score: int) -> void:
	if is_instance_valid(GameManager):
		GameManager.add_score(score)
		if GameManager.has_method("add_money"):
			GameManager.add_money(money)
		elif "money" in GameManager:
			GameManager.money = int(GameManager.get("money")) + money
		else:
			push_warning("MissionDirector: GameManager.money not present yet — "
				+ "paid %d XP only, %d dinars skipped" % [score, money])
	else:
		push_warning("MissionDirector: GameManager missing, reward lost")

# --- Per-frame active-mission logic -----------------------------------------

func _tick_active(delta: float) -> void:
	# Player dead (YOU DIED screen up) or missing: freeze timers, keep HUD.
	if not is_instance_valid(_player):
		return
	if _player.get("is_dead") == true:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_fail_current("time up")
		return
	if is_instance_valid(_panel):
		_panel.set_time_left(_time_left)

	var data: Dictionary = missions[current_index % missions.size()]
	match String(data.get("type", "")):
		"respond":
			_tick_respond()
		"help":
			_tick_help(delta)
		"chase":
			_tick_chase(delta)
		"patrol":
			_tick_patrol()

func _player_dist_to(pos: Vector3) -> float:
	if not is_instance_valid(_player):
		return -1.0
	var d: Vector3 = _player.global_position - pos
	d.y = 0.0
	return d.length()

func _tick_respond() -> void:
	# Prune targets that were freed without dying (despawn safety).
	var alive: Array = []
	for t in _respond_targets:
		if is_instance_valid(t):
			alive.append(t)
	_respond_targets = alive
	if _respond_targets.is_empty():
		# All criminals gone without enemy_died firing (despawned) —
		# do not soft-lock: fail the mission and move on.
		_fail_current("criminals escaped")
		return
	if is_instance_valid(_panel) and is_instance_valid(_objective):
		_panel.set_distance(_player_dist_to(_objective.global_position),
			"Criminals left: %d" % _respond_targets.size())

func _tick_help(delta: float) -> void:
	var target_pos := Vector3.ZERO
	if is_instance_valid(_help_citizen):
		target_pos = _help_citizen.global_position
	elif is_instance_valid(_objective):
		target_pos = _objective.global_position
	else:
		return
	# Beacon follows the (walking) citizen.
	if is_instance_valid(_objective):
		_objective.global_position = Vector3(target_pos.x, 0.0, target_pos.z)
	var dist := _player_dist_to(target_pos)
	if is_instance_valid(_panel):
		_panel.set_distance(dist, "")
	if dist >= 0.0 and dist <= HELP_ARRIVE_DIST:
		_help_hold += delta
		if is_instance_valid(_panel):
			_panel.set_status(_tr("mission_helping", "Helping… %ds" % int(ceil(HELP_HOLD_TIME - _help_hold))))
		if _help_hold >= HELP_HOLD_TIME:
			_complete_current()
	else:
		_help_hold = 0.0

func _tick_chase(delta: float) -> void:
	if not is_instance_valid(_chase_target):
		_fail_current("criminal vanished")
		return
	# Flee directly away from the player, with a gentle weave so the
	# path is not a perfect straight line.
	var away: Vector3 = _chase_target.global_position - _player.global_position
	away.y = 0.0
	if away.length() < 0.5:
		away = _chase_dir
	away = away.normalized()
	var weave := Vector3(-away.z, 0, away.x) * sin(_pulse * 1.7) * 0.35
	var dir: Vector3 = (away + weave).normalized()
	_chase_target.global_position += dir * CHASE_SPEED * delta
	_chase_target.global_position.y = 0.0
	_chase_target.rotation.y = atan2(-dir.x, -dir.z)
	if is_instance_valid(_objective):
		_objective.global_position = _chase_target.global_position
	var dist := _player_dist_to(_chase_target.global_position)
	if is_instance_valid(_panel):
		_panel.set_distance(dist, "Catch him!")
	if dist >= 0.0 and dist <= CHASE_CATCH_DIST:
		_complete_current()
	elif dist > CHASE_ESCAPE_DIST:
		_fail_current("criminal escaped")

func _tick_patrol() -> void:
	if _patrol_index >= _patrol_points.size():
		return
	if is_instance_valid(_panel) and is_instance_valid(_objective):
		_panel.set_distance(_player_dist_to(_objective.global_position),
			"Checkpoint %d/%d" % [_patrol_index + 1, _patrol_points.size()])

# --- Mission setup ----------------------------------------------------------

func _start_help_mission() -> void:
	# Prefer a real citizen: nearest one in group "civilian" to the player.
	var best: Node3D = null
	var best_dist := INF
	var origin := Vector3.ZERO
	if is_instance_valid(_player):
		origin = _player.global_position
	for c in get_tree().get_nodes_in_group("civilian"):
		var cn := c as Node3D
		if not is_instance_valid(cn):
			continue
		var d := cn.global_position.distance_to(origin)
		if d < best_dist:
			best_dist = d
			best = cn
	if is_instance_valid(best):
		_help_citizen = best
		_create_objective(best.global_position, 5.0, false)
	else:
		# No citizens spawned (yet): fall back to a fixed marker point.
		push_warning("MissionDirector: HELP mission found no civilian, using fallback point")
		_create_objective(Vector3(missions[current_index % missions.size()].get("point", Vector3.ZERO)), 5.0, false)

func _spawn_respond_enemies(point: Vector3, count: int) -> void:
	for i in range(count):
		var enemy := CharacterBody3D.new()
		enemy.name = "MissionCriminal_%02d" % i
		enemy.set_script(EnemyScript)
		var col := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = 0.4
		shape.height = 1.8
		col.shape = shape
		col.position.y = 0.9
		enemy.add_child(col)
		# Spread around the robbery point so they are not stacked.
		var offset := Vector3(randf_range(-4.0, 4.0), 0, randf_range(-4.0, 4.0))
		enemy.position = point + offset + Vector3(0, 1.0, 0)
		add_child(enemy)
		# Same pattern as enemy_spawner.gd: group "zombie" (citizens flee,
		# gunfire can hit them — they are criminals, NOT civilians).
		enemy.add_to_group("zombie")
		enemy.set("target", _player)
		if enemy.has_signal("enemy_died"):
			enemy.enemy_died.connect(_on_respond_enemy_died)
		_respond_targets.append(enemy)

func _on_respond_enemy_died(enemy: Node) -> void:
	if _state != "active":
		return
	_respond_targets.erase(enemy)
	if _respond_targets.is_empty():
		_complete_current()

## The fleeing criminal: a plain Node3D with a procedural body. Deliberately
## NOT in group "zombie" (citizens must not flee him, waves must not count
## him) and with NO take_damage — he is caught by proximity only, so the
## player cannot end the chase by shooting him from 40 m away.
func _spawn_chase_criminal(point: Vector3) -> void:
	var runner := Node3D.new()
	runner.name = "MissionFugitive"
	runner.position = Vector3(point.x, 0.0, point.z)
	runner.add_to_group("mission_criminal")
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.55, 0.1, 0.1)  # red jacket: stands out
	body_mat.roughness = 0.9
	var torso := MeshInstance3D.new()
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.55, 0.75, 0.3)
	torso_mesh.material = body_mat
	torso.mesh = torso_mesh
	torso.position.y = 1.05
	runner.add_child(torso)
	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.76, 0.58, 0.42)
	skin_mat.roughness = 0.9
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.16
	head_mesh.height = 0.32
	head_mesh.material = skin_mat
	head.mesh = head_mesh
	head.position.y = 1.62
	runner.add_child(head)
	var leg_mat := StandardMaterial3D.new()
	leg_mat.albedo_color = Color(0.12, 0.12, 0.14)
	leg_mat.roughness = 1.0
	for sx in [-0.14, 0.14]:
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.18, 0.7, 0.18)
		leg_mesh.material = leg_mat
		leg.mesh = leg_mesh
		leg.position = Vector3(sx, 0.35, 0)
		runner.add_child(leg)
	add_child(runner)
	_chase_target = runner
	_chase_dir = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)).normalized()

# --- Beacon / objective area (kept from the v0.5 director, extended) --------

func _create_objective(point: Vector3, radius: float, use_trigger: bool) -> void:
	_clear_objective()
	_objective = Area3D.new()
	_objective.name = "MissionObjective_%02d" % current_index
	_objective.position = Vector3(point.x, 0.0, point.z)
	_objective.collision_layer = 0
	_objective.collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	_objective.add_child(shape)

	# Tall light column: visible across the city so the player can always
	# find the objective. Cheap unlit transparent cylinder, Mobile-safe
	# (no Sky / fog / MSAA involved).
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = Color(0.95, 0.55, 0.12, 0.28)
	_beacon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color(1.0, 0.38, 0.06)
	_beacon_mat.emission_energy_multiplier = 1.6
	_beacon = MeshInstance3D.new()
	var column := CylinderMesh.new()
	column.top_radius = 0.45
	column.bottom_radius = 0.45
	column.height = 60.0
	_beacon.mesh = column
	_beacon.material_override = _beacon_mat
	_beacon.position.y = 30.0
	_beacon_base_y = 30.0
	_objective.add_child(_beacon)

	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.32
	base_mesh.bottom_radius = 0.75
	base_mesh.height = 2.8
	base.mesh = base_mesh
	base.material_override = _beacon_mat
	base.position.y = 1.4
	_objective.add_child(base)

	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 1.4
	ring_mesh.outer_radius = 1.58
	ring.mesh = ring_mesh
	ring.position.y = 0.12
	ring.material_override = _beacon_mat
	_objective.add_child(ring)

	add_child(_objective)
	if use_trigger:
		_objective.body_entered.connect(_on_objective_reached)

func _pulse_beacon() -> void:
	if not is_instance_valid(_beacon) or not is_instance_valid(_beacon_mat):
		return
	var s := 1.0 + sin(_pulse * 3.0) * 0.12
	_beacon.scale = Vector3(s, 1.0, s)
	_beacon_mat.albedo_color.a = 0.22 + sin(_pulse * 3.0) * 0.08

## Arrival trigger — used by PATROL (and any future arrive-to-complete
## mission). RESPOND / HELP / CHASE complete through their own logic.
func _on_objective_reached(body: Node3D) -> void:
	if _state != "active":
		return
	if not is_instance_valid(body) or not body.is_in_group("player"):
		return
	if not is_instance_valid(_objective):
		return
	var data: Dictionary = missions[current_index % missions.size()]
	if String(data.get("type", "")) != "patrol":
		return
	_patrol_index += 1
	if _patrol_index >= _patrol_points.size():
		_complete_current()
		return
	# Move the beacon to the next checkpoint.
	_clear_objective()
	_create_objective(_patrol_points[_patrol_index], 4.0, true)

# --- Cleanup ------------------------------------------------------------------

func _cleanup_targets() -> void:
	_clear_objective()
	for t in _respond_targets:
		if is_instance_valid(t):
			t.queue_free()
	_respond_targets.clear()
	if is_instance_valid(_chase_target):
		_chase_target.queue_free()
	_chase_target = null
	_help_citizen = null
	_help_hold = 0.0

func _clear_objective() -> void:
	if is_instance_valid(_objective):
		_objective.queue_free()
	_objective = null
	_beacon = null
	_beacon_mat = null

# --- Translation ------------------------------------------------------------
# Cached LanguageManager instance (RefCounted, no _init side effects).
# Built lazily so this file still works if language_manager.gd is absent.
var _lang_inst: RefCounted = null
var _lang_tried := false

## Returns the translated string for `key` via LanguageManager when it
## exists, else the English fallback. Never references LanguageManager
## directly by class name: the load is guarded by FileAccess so a missing
## language_manager.gd cannot break this file, and a missing key (the
## translator returns the key itself) also falls back to English.
func _tr(key: String, fallback: String) -> String:
	if key == "":
		return fallback
	if not _lang_tried:
		_lang_tried = true
		if FileAccess.file_exists("res://scripts/language_manager.gd"):
			var scr: Script = load("res://scripts/language_manager.gd")
			if scr != null:
				var inst: Variant = scr.new()
				if inst is RefCounted and (inst as Object).has_method("tr"):
					_lang_inst = inst
	if _lang_inst != null:
		var v: Variant = _lang_inst.call("tr", key)
		if v is String and String(v) != "" and String(v) != key:
			return String(v)
	# Belt and braces: a LanguageManager autoload, if one is ever added.
	var lm: Node = null
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		lm = get_tree().root.get_node_or_null("LanguageManager")
	if lm != null and lm.has_method("tr"):
		var v2: Variant = lm.call("tr", key)
		if v2 is String and String(v2) != "" and String(v2) != key:
			return String(v2)
	return fallback
