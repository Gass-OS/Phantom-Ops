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
##
## v0.7 STORY CAMPAIGN — chapter mode (Worker B: Chapter Flow).
##   start_chapter(n) (n = 1..5) builds that chapter's objective sequence
##   out of the EXISTING mission types (patrol / help / respond / chase)
##   plus two chapter-only types (informant / boss) and runs it instead
##   of the free-play chain. When no chapter is active, the v0.6
##   free-play chain works exactly as before.
##   Chapters (vs "The Wolves of Kasserine", boss Khaled "The Wolf"):
##     1 FIRST PATROL  — patrol 3 checkpoints -> help 1 citizen -> stop
##                       1 robbery (2 criminals).
##     2 SOUK ROBBERY  — robbery at the souk stalls (3 criminals), then
##                       chase the fleeing thief (catch within 4 m).
##     3 NIGHT SHIFT   — force night + more rain; defend the plaza (4
##                       criminals), then the mosque (5 criminals).
##     4 THE INFORMANT — find the ONE suspicious man in the crowd and
##                       CHECK him; checking anyone else just greets
##                       them and the chapter continues.
##     5 THE WOLF      — boss fight at the plaza (BossEnemy, another
##                       worker's script; falls back to a 5-criminal
##                       wave if the boss script is absent).
##   Flow: intro card (chapter_intro.gd, ~7 s, SKIP, world paused) ->
##   objectives via the mission panel + beacon -> results card
##   (NEXT CHAPTER / MENU) or fail card (RETRY / MENU); chapter 5 shows
##   the ending card. Death mid-chapter: YOU DIED -> RETRY restarts
##   THAT chapter (player.gd sets the static pending_retry_chapter and
##   reloads the scene; _check_pending_chapter picks it up).
##   CampaignManager (another worker's autoload) is notified DEFENSIVELY:
##   it is looked up with get_node_or_null("CampaignManager") — NEVER
##   referenced by bare name, because the file must still parse if the
##   autoload is ever unregistered. Real contract (campaign_manager.gd):
##   - The menu sets the chapter with CampaignManager.start_chapter(n)
##     (sets current_chapter) before going to intro.tscn, so on scene
##     start this director reads CampaignManager.current_chapter and
##     starts it. No pending_chapter property exists.
##   - Completion: complete_chapter(chapter, xp_reward, money_reward).
##     money_reward is passed as 0 ON PURPOSE: the chapter's dinars
##     (step rewards + completion bonus) were already paid through
##     GameManager.add_money, and CampaignManager syncs them via
##     money_changed — passing them again would pay them twice.
##   - Failure has no CampaignManager method; _notify_campaign_failed
##     tries on_chapter_failed / chapter_failed and does nothing when
##     neither exists. Without CampaignManager the chapters still run
##     start-to-finish; only the save is missing.

signal mission_started(mission_id: String, title: String)
signal mission_completed(mission_id: String, title: String, money: int, score: int)
signal mission_failed(mission_id: String, title: String, reason: String)
signal chapter_started(chapter: int)
signal chapter_completed(chapter: int, xp: int, money: int, time_sec: float)
signal chapter_failed(chapter: int, reason: String)

const PanelScript := preload("res://scripts/mission_panel.gd")
const EnemyScript := preload("res://scripts/enemy_ai.gd")
const ChapterIntroScript := preload("res://scripts/chapter_intro.gd")

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

# --- v0.7 Story Campaign: chapter mode ------------------------------------
# pending_retry_chapter survives a scene reload (static): player.gd sets
# it on death-RETRY so the fresh director restarts that chapter.
static var pending_retry_chapter := 0
const CHAPTER_COUNT := 5
const CHAPTER_BONUS_MONEY := 250
const CHAPTER_BONUS_SCORE := 500
const FINAL_BONUS_MONEY := 500
const FINAL_BONUS_SCORE := 1000
# Key city spots. Mosque (-75, 75) and plaza (0, 0) are the v0.4/v0.5
# landmarks; the souk stalls sit on the plaza's south-east street;
# the boss waits north of the player's (0, 10) spawn so he is never
# on top of the player when the chapter starts.
const PLAZA_POINT := Vector3(0, 0, 0)
const MOSQUE_POINT := Vector3(-75, 0, 75)
const SOUK_POINT := Vector3(30, 0, 45)
const BOSS_POINT := Vector3(0, 0, -30)
var current_chapter := 0  # 0 = free play, 1..5 = story chapter active
var _chapter_active := false
var _chapter_steps: Array = []
var _chapter_step := 0
var _chapter_elapsed := 0.0
var _chapter_start_score := 0
var _chapter_start_kills := 0
var _chapter_start_money := 0
var _chapter_intro: CanvasLayer = null
var _informant: Node3D = null
var _informant_pick_t := 0.0
var _boss: Node3D = null
var _boss_fallback := false
# Chapter 3 night state, saved so it can be restored when the chapter ends.
var _night_saved := false
var _saved_time_of_day := 0.15
var _saved_time_scale := 1.0
var _saved_rain_min := 90.0
var _saved_rain_max := 180.0

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
	# v0.7: a pending chapter from the menu (CampaignManager) or a
	# death-RETRY (static flag) starts here, after the scene settles.
	call_deferred("_check_pending_chapter")

func _wire_interaction() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var im := scene.get_node_or_null("InteractionManager")
	if im == null or not im.has_signal("help_completed"):
		return
	if not im.is_connected("help_completed", notify_help_given):
		im.connect("help_completed", notify_help_given)
	# v0.7: chapter 4 (THE INFORMANT) completes through CHECK.
	if im.has_signal("check_completed") and not im.is_connected("check_completed", _on_check_completed):
		im.connect("check_completed", _on_check_completed)

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
	# v0.7: chapter clock (results card + CampaignManager stats). Only
	# counts while a chapter step is running or between steps; the
	# intro card pauses the tree, so its ~7 s are never counted.
	if _chapter_active and (_state == "active" or _state == "between"):
		_chapter_elapsed += delta
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

## The step dict the director is currently running: the active chapter
## step in chapter mode, else the current free-play mission. {} when
## there is nothing to run (empty mission list outside a chapter).
func _current_data() -> Dictionary:
	if _chapter_active and _chapter_step >= 0 and _chapter_step < _chapter_steps.size():
		return _chapter_steps[_chapter_step]
	if missions.is_empty():
		return {}
	return missions[current_index % missions.size()]

func current_mission_id() -> String:
	if _state != "active":
		return ""
	return String(_current_data().get("id", ""))

## Called by the citizen worker / coordinator when its help interaction
## happens. Completes HELP instantly if that mission is active. Safe to
## call at any other time (no-op).
func notify_help_given(citizen: Node) -> void:
	if _state != "active":
		return
	if String(_current_data().get("type", "")) != "help":
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
	var data: Dictionary = _current_data()
	if data.is_empty():
		return
	_state = "active"
	_time_left = float(data.get("time_limit", 120.0))
	_help_hold = 0.0
	_patrol_index = 0
	_patrol_points = []
	_respond_targets.clear()
	_chase_target = null
	_help_citizen = null
	_informant = null
	_informant_pick_t = 0.0
	_boss = null
	_boss_fallback = false

	var title := _tr(String(data.get("title_key", "")), String(data.get("title", "")))
	var detail := _tr(String(data.get("detail_key", "")), String(data.get("detail", "")))
	if is_instance_valid(_panel):
		_panel.show_mission(title, detail,
			int(data.get("reward_money", 0)), int(data.get("reward_score", 0)))
		if _chapter_active:
			_panel.set_chapter("CHAPTER %d — %s" % [current_chapter, _chapter_title(current_chapter)])
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
		"informant":
			# v0.7 ch4: pick the informant now (citizens may still be
			# spawning; _tick_informant keeps retrying until one is found).
			_pick_informant()
			var ipos: Vector3 = Vector3(data.get("point", PLAZA_POINT))
			if is_instance_valid(_informant):
				ipos = _informant.global_position
			_create_objective(ipos, 5.0, false)
		"boss":
			# v0.7 ch5: the boss at the plaza, or a tough wave if the
			# boss script (another worker) is not in the project yet.
			_create_objective(Vector3(data.get("point", BOSS_POINT)), 6.0, false)
			if not _spawn_boss(Vector3(data.get("point", BOSS_POINT))):
				push_warning("MissionDirector: boss_enemy.gd missing — "
					+ "chapter 5 falls back to a tough criminal wave")
				_boss_fallback = true
				_spawn_respond_enemies(Vector3(data.get("point", BOSS_POINT)), 5)
		_:
			_create_objective(Vector3(data.get("point", Vector3.ZERO)), 3.0, true)

func _complete_current() -> void:
	if _state != "active":
		return
	var data: Dictionary = _current_data()
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
	if _chapter_active:
		# Advance to the next chapter step; the last step finishes
		# the chapter (results / ending card) instead of chaining.
		_chapter_step += 1
		if _chapter_step >= _chapter_steps.size():
			_finish_chapter()
		return
	current_index = (current_index + 1) % missions.size()

func _fail_current(reason: String) -> void:
	if _state != "active":
		return
	var data: Dictionary = _current_data()
	var title := _tr(String(data.get("title_key", "")), String(data.get("title", "")))
	if _chapter_active:
		# A failed step fails the whole chapter: fail card with
		# RETRY (same chapter) / MENU — no auto-advance.
		_fail_chapter(reason)
		return
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

	var data: Dictionary = _current_data()
	match String(data.get("type", "")):
		"respond":
			_tick_respond()
		"help":
			_tick_help(delta)
		"chase":
			_tick_chase(delta)
		"patrol":
			_tick_patrol()
		"informant":
			_tick_informant(delta)
		"boss":
			_tick_boss()

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
		_create_objective(Vector3(_current_data().get("point", Vector3.ZERO)), 5.0, false)

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
	var data: Dictionary = _current_data()
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
	# v0.7: chapter-only live targets.
	if is_instance_valid(_boss):
		_boss.queue_free()
	_boss = null
	_boss_fallback = false
	_informant = null

func _clear_objective() -> void:
	if is_instance_valid(_objective):
		_objective.queue_free()
	_objective = null
	_beacon = null
	_beacon_mat = null

# --- v0.7 Story Campaign --------------------------------------------------
# Chapter mode. All chapter steps reuse the v0.6 mission machinery
# (panel + beacon + tick logic); only "informant" and "boss" are new
# types, and they live here too. Free play is untouched when no chapter
# is active (current_chapter == 0).

## Start chapter `n` (1..5). Shows the intro card first; the first
## objective starts when the card closes (SKIP or ~7 s timer).
func start_chapter(n: int) -> void:
	if n < 1 or n > CHAPTER_COUNT:
		push_warning("MissionDirector: no chapter %d (1..%d)" % [n, CHAPTER_COUNT])
		return
	if _state == "active":
		_cleanup_targets()
	current_chapter = n
	_chapter_active = true
	_chapter_steps = _build_chapter_steps(n)
	_chapter_step = 0
	_chapter_elapsed = 0.0
	_chapter_start_score = _gm_score()
	_chapter_start_kills = _gm_kills()
	_chapter_start_money = _gm_money()
	# Keep CampaignManager.current_chapter in sync with what is
	# actually playing (matters for NEXT-chapter and for DEPLOY
	# after MENU: the menu replays current_chapter). Harmless when
	# the autoload is absent; start_chapter() there is only a setter
	# + unlock check, never a scene change.
	var cm := _campaign_manager()
	if cm != null and cm.has_method("start_chapter"):
		cm.call("start_chapter", n)
	_apply_chapter_environment(n)
	_ensure_chapter_intro()
	_state = "intro"  # _process has no "intro" arm: nothing ticks.
	chapter_started.emit(n)
	if is_instance_valid(_panel):
		_panel.set_chapter("CHAPTER %d — %s" % [n, _chapter_title(n)])
	_chapter_intro.show_intro(n, _chapter_title(n), _chapter_story(n),
		_tr("boss_intro", "Khaled \"The Wolf\" — leader of the Wolves. He does not run.") if n == 5 else "")

## The objective sequence for a chapter. Each step is a mission dict
## (same fields as the free-play `missions` array); the panel, beacon
## and tick logic are shared.
func _build_chapter_steps(n: int) -> Array:
	match n:
		1:
			return [
				{
					"id": "ch1_patrol", "type": "patrol",
					"title_key": "mission_patrol", "title": "🚓 PATROL THE DISTRICT",
					"detail_key": "mission_patrol_detail",
					"detail": "Patrol duty: visit all 3 checkpoints in order.",
					"point": Vector3(60, 0, 80), "reward_money": 120, "reward_score": 250,
					"time_limit": 240.0,
					"checkpoints": [Vector3(60, 0, 80), Vector3(-70, 0, -60), Vector3(0, 0, -110)],
				},
				{
					"id": "ch1_help", "type": "help",
					"title_key": "mission_help", "title": "🤝 HELP A CITIZEN IN NEED",
					"detail_key": "mission_help_detail",
					"detail": "A poor citizen needs help. Reach them and give what you can.",
					"point": Vector3(-30, 0, 45), "reward_money": 80, "reward_score": 150,
					"time_limit": 180.0,
				},
				{
					"id": "ch1_respond", "type": "respond",
					"title_key": "mission_respond", "title": "🚨 RESPOND: ROBBERY IN PROGRESS",
					"detail_key": "mission_respond_detail",
					"detail": "Robbery reported! Reach the marked location and stop the criminals.",
					"point": Vector3(40, 0, -60), "reward_money": 150, "reward_score": 300,
					"time_limit": 180.0, "enemy_count": 2,
				},
			]
		2:
			return [
				{
					"id": "ch2_respond", "type": "respond",
					"title_key": "mission_respond", "title": "🚨 ROBBERY AT THE SOUK",
					"detail_key": "", "detail": "Robbery at the market stalls! Stop the thieves.",
					"point": SOUK_POINT, "reward_money": 200, "reward_score": 400,
					"time_limit": 180.0, "enemy_count": 3,
				},
				{
					"id": "ch2_chase", "type": "chase",
					"title_key": "mission_chase", "title": "🏃 CHASE THE FLEEING THIEF",
					"detail_key": "mission_chase_detail",
					"detail": "A thief is fleeing on foot! Catch him before he escapes.",
					"point": SOUK_POINT, "reward_money": 200, "reward_score": 400,
					"time_limit": 120.0,
				},
			]
		3:
			return [
				{
					"id": "ch3_plaza", "type": "respond",
					"title_key": "", "title": "🌙 DEFEND THE PLAZA — WAVE 1",
					"detail_key": "", "detail": "Night attack! Criminals are hitting the plaza. Stop them all.",
					"point": PLAZA_POINT, "reward_money": 200, "reward_score": 400,
					"time_limit": 240.0, "enemy_count": 4,
				},
				{
					"id": "ch3_mosque", "type": "respond",
					"title_key": "", "title": "🌙 DEFEND THE MOSQUE — WAVE 2",
					"detail_key": "", "detail": "Wave 2 — they are attacking the mosque now. Hold the line!",
					"point": MOSQUE_POINT, "reward_money": 250, "reward_score": 500,
					"time_limit": 240.0, "enemy_count": 5,
				},
			]
		4:
			return [
				{
					"id": "ch4_informant", "type": "informant",
					"title_key": "", "title": "🕵️ FIND THE INFORMANT",
					"detail_key": "", "detail": "Someone in the crowd knows where The Wolf hides. Find the suspicious man and CHECK him.",
					"point": PLAZA_POINT, "reward_money": 200, "reward_score": 500,
					"time_limit": 300.0,
				},
			]
		5:
			return [
				{
					"id": "ch5_boss", "type": "boss",
					"title_key": "", "title": "🐺 THE WOLF — FINAL FIGHT",
					"detail_key": "", "detail": "Khaled \"The Wolf\" is waiting at the plaza. Take him down and free Kasserine!",
					"point": BOSS_POINT, "reward_money": 500, "reward_score": 1000,
					"time_limit": 600.0,
				},
			]
	return []

# --- Chapter titles / stories (LanguageManager keys; English fallback) -----

func _chapter_title(n: int) -> String:
	var fallbacks := ["", "FIRST PATROL", "THE SOUK ROBBERY", "NIGHT SHIFT", "THE INFORMANT", "THE WOLF"]
	var fb := ""
	if n >= 1 and n <= CHAPTER_COUNT:
		fb = fallbacks[n]
	return _tr("chapter_%d_title" % n, fb)

func _chapter_story(n: int) -> String:
	var fallbacks := {
		1: "Your first day on patrol in Kasserine.\nWalk the checkpoints, help the people — and show the Wolves this city has a new officer.",
		2: "A robbery at the souk stalls!\nStop the thieves, then run down the one who flees.",
		3: "Night falls over Kasserine and the Wolves come out.\nHold the plaza and the mosque until dawn.",
		4: "Someone in the crowd knows where The Wolf hides.\nFind the suspicious man and CHECK him — but be careful who you accuse.",
		5: "It ends tonight. Khaled \"The Wolf\" is waiting at the plaza with his pack.\nTake him down and free Kasserine.",
	}
	return _tr("chapter_%d_story" % n, String(fallbacks.get(n, "")))

# --- Chapter intro / cards --------------------------------------------------

func _ensure_chapter_intro() -> void:
	if is_instance_valid(_chapter_intro):
		return
	_chapter_intro = ChapterIntroScript.new()
	_chapter_intro.name = "ChapterIntro"
	add_child(_chapter_intro)
	_chapter_intro.intro_finished.connect(_on_intro_finished)
	_chapter_intro.next_chapter_pressed.connect(_on_chapter_next)
	_chapter_intro.retry_chapter_pressed.connect(_on_chapter_retry)
	_chapter_intro.menu_pressed.connect(_on_chapter_menu)

func _on_intro_finished() -> void:
	if not _chapter_active:
		return
	# Short beat after the card closes, then the first objective starts.
	_state = "waiting"
	_delay_timer = 0.5

func _on_chapter_next() -> void:
	var n := current_chapter + 1
	if n < 1 or n > CHAPTER_COUNT:
		_go_to_menu()
		return
	start_chapter(n)

func _on_chapter_retry() -> void:
	if current_chapter >= 1 and current_chapter <= CHAPTER_COUNT:
		start_chapter(current_chapter)

func _on_chapter_menu() -> void:
	_go_to_menu()

## Back to the main menu. Campaign progress lives in CampaignManager's
## save file (written on chapter completion) and is NOT touched here;
## only the run score/money are reset, like the normal menu path.
func _go_to_menu() -> void:
	_chapter_active = false
	if get_tree() != null:
		get_tree().paused = false
		var layer: Node = get_tree().root.get_node_or_null("MobileHUDLayer")
		if layer != null:
			layer.queue_free()
	if is_instance_valid(GameManager):
		GameManager.reset_game()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# --- Chapter finish / fail ----------------------------------------------------

func _finish_chapter() -> void:
	var n := current_chapter
	_state = "idle"
	_cleanup_targets()
	_restore_environment()
	if is_instance_valid(_panel):
		_panel.clear()
		_panel.clear_chapter()
	var bonus_money := FINAL_BONUS_MONEY if n == CHAPTER_COUNT else CHAPTER_BONUS_MONEY
	var bonus_score := FINAL_BONUS_SCORE if n == CHAPTER_COUNT else CHAPTER_BONUS_SCORE
	_grant_reward(bonus_money, bonus_score)
	var xp := _gm_score() - _chapter_start_score
	var money := _gm_money() - _chapter_start_money
	var kills := _gm_kills() - _chapter_start_kills
	var t := _chapter_elapsed
	_chapter_active = false
	chapter_completed.emit(n, xp, money, t)
	_notify_campaign_completed(n, xp, money, t)
	_ensure_chapter_intro()
	if n >= CHAPTER_COUNT:
		_chapter_intro.show_ending(
			_tr("ending_title", "KASSERINE IS FREE"),
			_tr("ending_text", "The Wolf is down. The souk is loud again, the mosque is safe, and Kasserine has its officer.\nThank you for playing, Aymen."),
			_gm_score(), _gm_kills(), t, xp, money)
		current_chapter = 0
	else:
		_chapter_intro.show_results(n, _chapter_title(n),
			_gm_score(), _gm_kills(), t, xp, money, false)

func _fail_chapter(reason: String) -> void:
	var n := current_chapter
	_state = "idle"
	_cleanup_targets()
	_restore_environment()
	if is_instance_valid(_panel):
		_panel.clear()
		_panel.clear_chapter()
	_chapter_active = false
	chapter_failed.emit(n, reason)
	_notify_campaign_failed(n, reason)
	_ensure_chapter_intro()
	_chapter_intro.show_fail(n, _chapter_title(n), reason)
	# current_chapter stays n so RETRY restarts this chapter.

# --- CampaignManager (defensive; the autoload may not exist yet) -----------

func _campaign_manager() -> Node:
	# NEVER a bare `CampaignManager` reference: it is not registered in
	# project.godot yet, so the parser would reject this file.
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null("CampaignManager")

## Called when a chapter starts (menu or death-RETRY): the menu worker
## sets CampaignManager.current_chapter via start_chapter(); player.gd
## sets the static pending_retry_chapter on death-RETRY. The retry
## flag wins when both are set (same chapter in practice).
func _check_pending_chapter() -> void:
	if pending_retry_chapter >= 1 and pending_retry_chapter <= CHAPTER_COUNT:
		var n := pending_retry_chapter
		pending_retry_chapter = 0
		start_chapter(n)
		return
	# Menu entry: DEPLOY / CONTINUE / chapter select all set
	# CampaignManager.current_chapter before changing to intro.tscn.
	var cm := _campaign_manager()
	if cm != null:
		var cur: Variant = cm.get("current_chapter")
		if cur != null and int(cur) >= 1 and int(cur) <= CHAPTER_COUNT:
			start_chapter(int(cur))

## Notify CampaignManager a chapter was completed. Canonical API:
## complete_chapter(chapter, xp_reward, money_reward) — money_reward
## is 0 on purpose (see the header note): the chapter's dinars were
## already paid through GameManager.add_money and synced via
## money_changed, so passing them again would pay them twice.
func _notify_campaign_completed(chapter: int, xp: int, money: int, time_sec: float) -> void:
	var cm := _campaign_manager()
	if cm == null:
		return
	if cm.has_method("complete_chapter"):
		cm.call("complete_chapter", chapter, xp, 0)
	elif cm.has_method("on_chapter_completed"):
		cm.call("on_chapter_completed", chapter, xp, money, time_sec)

func _notify_campaign_failed(chapter: int, reason: String) -> void:
	var cm := _campaign_manager()
	if cm == null:
		return
	if cm.has_method("on_chapter_failed"):
		cm.call("on_chapter_failed", chapter, reason)
	elif cm.has_method("chapter_failed"):
		cm.call("chapter_failed", chapter)

# --- Chapter 3 environment (night + rain) -----------------------------------

func _get_day_night() -> Node:
	if get_tree() == null:
		return null
	var dn: Node = get_tree().get_first_node_in_group("day_night")
	if dn != null:
		return dn
	var scene := get_tree().current_scene
	if scene != null:
		return scene.get_node_or_null("DayNight")
	return null

func _apply_chapter_environment(n: int) -> void:
	if n != 3:
		return
	var dn := _get_day_night()
	if dn == null:
		return
	if _night_saved:
		return
	_night_saved = true
	_saved_time_of_day = float(dn.get("time_of_day"))
	_saved_time_scale = float(dn.get("time_scale"))
	_saved_rain_min = float(dn.get("rain_min_gap"))
	_saved_rain_max = float(dn.get("rain_max_gap"))
	if dn.has_method("force_night"):
		dn.call("force_night")
	# More frequent showers for the night shift (15–40 s gaps instead
	# of 90–180 s); day_night.gd itself is untouched beyond force_night().
	dn.set("rain_min_gap", 15.0)
	dn.set("rain_max_gap", 40.0)

func _restore_environment() -> void:
	if not _night_saved:
		return
	_night_saved = false
	var dn := _get_day_night()
	if dn == null:
		return
	dn.set("time_scale", _saved_time_scale)
	if dn.has_method("force_time"):
		dn.call("force_time", _saved_time_of_day)
	dn.set("rain_min_gap", _saved_rain_min)
	dn.set("rain_max_gap", _saved_rain_max)

# --- Chapter 4: the informant -------------------------------------------------

## Pick the informant: a suspicious, non-criminal citizen (the CHECK
## prompt already exists for him via InteractionManager). If none
## exists, any citizen is marked suspicious (never a criminal, so
## CHECK greets instead of making him flee). Citizens spawn over time,
## so _tick_informant retries until one is found.
func _pick_informant() -> void:
	if is_instance_valid(_informant):
		return
	if get_tree() == null:
		return
	var candidates: Array = []
	var any_citizen: Node3D = null
	for c in get_tree().get_nodes_in_group("civilian"):
		var cn := c as Node3D
		if not is_instance_valid(cn):
			continue
		if any_citizen == null:
			any_citizen = cn
		if bool(cn.get("is_suspicious")) and not bool(cn.get("is_criminal")):
			candidates.append(cn)
	var chosen: Node3D = null
	if not candidates.is_empty():
		chosen = candidates[randi() % candidates.size()]
	elif is_instance_valid(any_citizen):
		chosen = any_citizen
		chosen.set("is_suspicious", true)
		chosen.set("is_criminal", false)
	if not is_instance_valid(chosen):
		return
	# The informant must offer CHECK, not HELP/GIVE: clear those flags.
	chosen.set("is_in_need", false)
	chosen.set("is_poor", false)
	_informant = chosen
	if chosen.has_method("say_text"):
		chosen.call("say_text",
			_tr("chapter_informant_hint", "Psst... I know where The Wolf hides."), 5.0)

func _tick_informant(delta: float) -> void:
	if not is_instance_valid(_informant):
		_informant_pick_t -= delta
		if _informant_pick_t <= 0.0:
			_informant_pick_t = 2.0
			_pick_informant()
		if is_instance_valid(_panel):
			_panel.set_distance(-1.0, "")
			_panel.set_status(_tr("chapter_informant_search", "Searching the crowd..."))
		return
	var pos: Vector3 = _informant.global_position
	# Beacon follows the walking informant (same pattern as HELP).
	if is_instance_valid(_objective):
		_objective.global_position = Vector3(pos.x, 0.0, pos.z)
	var dist := _player_dist_to(pos)
	if is_instance_valid(_panel):
		_panel.set_distance(dist, _tr("chapter_informant_label", "The suspicious man"))

## InteractionManager CHECK result. Only the informant completes the
## chapter; checking any other suspicious citizen just greets them
## (the interaction manager already shows that) and play continues.
func _on_check_completed(citizen: Node, _was_criminal: bool) -> void:
	if not _chapter_active or _state != "active":
		return
	if String(_current_data().get("type", "")) != "informant":
		return
	if not is_instance_valid(_informant):
		return
	if citizen != _informant:
		return
	_complete_current()

# --- Chapter 5: the boss -------------------------------------------------------

## Spawn Khaled "The Wolf" (BossEnemy, another worker's script:
## class_name BossEnemy, extends EnemyAI, signal boss_died).
## Returns false when the script is absent — the caller then falls
## back to a tough 5-criminal wave. Never crashes when the boss
## script is missing or malformed.
func _spawn_boss(point: Vector3) -> bool:
	if not FileAccess.file_exists("res://scripts/boss_enemy.gd"):
		return false
	var boss_script: Script = load("res://scripts/boss_enemy.gd")
	if boss_script == null:
		return false
	var boss: Variant = boss_script.new()
	if not (boss is CharacterBody3D):
		push_warning("MissionDirector: boss_enemy.gd did not produce a CharacterBody3D")
		return false
	var body := boss as CharacterBody3D
	body.name = "BossTheWolf"
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45
	shape.height = 1.9
	col.shape = shape
	col.position.y = 0.95
	body.add_child(col)
	body.position = point + Vector3(0, 1.0, 0)
	add_child(body)
	body.add_to_group("zombie")
	body.set("target", _player)
	# The lambdas take the emitted argument (boss_died(boss) /
	# enemy_died(enemy) both emit one) and drop it: Godot 4.2
	# REJECTS a 0-arg callable connected to a 1-arg signal at emit
	# time ("Method expected 0 arguments, but called with 1").
	if body.has_signal("boss_died"):
		body.connect("boss_died", func(_b) -> void: _on_boss_died())
	elif body.has_signal("enemy_died"):
		body.connect("enemy_died", func(_e) -> void: _on_boss_died())
	else:
		push_warning("MissionDirector: boss has neither boss_died nor enemy_died signal")
	_boss = body
	return true

func _on_boss_died() -> void:
	if not _chapter_active or _state != "active":
		return
	if String(_current_data().get("type", "")) != "boss":
		return
	_boss = null
	_complete_current()

func _tick_boss() -> void:
	if _boss_fallback:
		# No boss script: the fallback wave completes like RESPOND.
		_tick_respond()
		return
	if not is_instance_valid(_boss):
		_fail_current("The Wolf escaped")
		return
	var dist := _player_dist_to(_boss.global_position)
	if is_instance_valid(_panel):
		_panel.set_distance(dist, _tr("boss_name", "Khaled \"The Wolf\""))
		if _boss.get("current_health") != null and _boss.get("max_health") != null:
			_panel.set_status("Boss HP: %d / %d" % [
				int(maxf(0.0, float(_boss.get("current_health")))),
				int(float(_boss.get("max_health")))])

# --- GameManager stat helpers (guarded; the autoload always exists) ----------

func _gm_score() -> int:
	return int(GameManager.score) if is_instance_valid(GameManager) else 0

func _gm_kills() -> int:
	return int(GameManager.kills) if is_instance_valid(GameManager) else 0

func _gm_money() -> int:
	return int(GameManager.money) if is_instance_valid(GameManager) else 0

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
