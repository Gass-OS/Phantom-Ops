extends Node
class_name WantedManager
## Phantom Ops v0.8 — WANTED / HEAT.
##
## The gang's heat on the player, 0-100, in 5 levels:
##   L0 0 (Clean), L1 1-20, L2 21-40, L3 41-60, L4 61-80, L5 81-100 (Most Wanted).
## Heat drives enemy variants (enemy_ai.apply_variant), wave size / pace
## (enemy_spawner), and the L5 hit squad. The boss fight (boss_enemy.gd,
## Khaled) is NEVER touched by heat.
##
## COORDINATOR WIRING (nothing here edits another worker's file):
##   1. Add ONE WantedManager node as a child of the MainGame scene root
##      (name "WantedManager"). find_in() locates it from anywhere.
##   2. Add ONE HeatHud (scripts/heat_hud.gd) as a child of MobileHUDLayer
##      and call heat_hud.setup(wanted_manager).
##   3. WILD FIRE — the weapons worker owns the fire code, so this file
##      cannot hook it directly. ONE guarded line in the fire path
##      (player.gd _on_mobile_fire, or weapon_manager.gd if it takes over
##      firing), after the raycast, when the shot dealt NO damage (ray hit
##      nothing, hit a civilian, or hit an object without take_damage):
##        var wm := WantedManager.find_in(get_tree())
##        if wm != null: wm.register_missed_shot()
##      register_missed_shot() itself checks for a civilian within 15 m
##      and only then adds heat. Civilians stay NON-TARGETABLE (v0.4 rule):
##      heat from chaos comes from firing wildly NEAR civilians, NEVER
##      from killing them (impossible — they have no take_damage).
##   4. SAVE — CampaignManager (another worker) persists heat with
##      to_dict() and restores it with load_from_dict(). On load the saved
##      heat is HALVED (rounded down): a new session never starts at Most
##      Wanted just because the last one ended there.
##   5. BOSS FIGHT — the hit squad is suppressed automatically while a
##      boss node ("BossTheWolf") exists or the MissionDirector is running
##      a "boss" mission step. If the coordinator needs to force it, call
##      set_boss_fight_active(true/false).
##   6. SOUND — hit_squad_spawned() is for the HUD banner; the sting is
##      the play_sting signal: the coordinator connects it to a sound
##      (sound_manager.gd is NOT edited here).
##
## HEAT RULES (as implemented):
##   kill a gang member .......... +6   (EnemySpawner._on_enemy_died)
##   enemy alive within 40 m ..... +1.0/s, but this source can never raise
##                                  the TOTAL past 60 (L3 cap): once heat
##                                  is 60+, mere proximity adds nothing —
##                                  only kills / CHASE / wild fire push
##                                  higher. No separate contribution needs
##                                  tracking: the cap is on the total.
##   CHASE mission starts ........ +15  (auto: MissionDirector.mission_started
##                                  when the id contains "chase"; manual
##                                  backup: mission_went_loud("chase")).
##   wild fire ................... +0.5 per missed shot while a civilian is
##                                  within 15 m (see wiring 3 above).
##   decay ....................... -2.0/s once no enemy has been within 40 m
##                                  for 15 s.
##   safe zone ................... -4.0/s near the mosque (within 25 m) or
##                                  the police car (within 15 m); applies
##                                  immediately, but only while no enemy is
##                                  within 40 m (you cannot lay low mid-fight).
##                                  If neither safe-zone node can be found
##                                  (bare test scene), the player's spawn
##                                  point counts as the safe zone instead.
##   mission / chapter completes . reset_after_chapter() (-30, floor 0),
##                                  auto-wired to mission_completed and
##                                  chapter_completed.
## If WantedManager is absent from the scene, the game behaves exactly as
## v0.7: no heat, no variants, no squad (every consumer null-guards).

signal heat_changed(level: int, heat: float)
signal heat_level_up(level: int)
signal heat_level_down(level: int)
signal hit_squad_spawned()
signal squad_defeated(bounty: int)
## The coordinator connects this to a sting sound. Never played here.
signal play_sting

const MAX_HEAT := 100.0
const KILL_HEAT := 6.0
const CHASE_HEAT := 15.0
const WILD_FIRE_HEAT := 0.5
const COMBAT_HEAT_RATE := 1.0
const COMBAT_HEAT_CAP := 60.0
const IDLE_DECAY_DELAY := 15.0
const IDLE_DECAY_RATE := 2.0
const SAFE_DECAY_RATE := 4.0
const COMBAT_RADIUS := 40.0
const CIVILIAN_RADIUS := 15.0
const MOSQUE_RADIUS := 25.0
const POLICE_CAR_RADIUS := 15.0
const SCAN_INTERVAL := 0.5
const CHAPTER_RESET := 30.0
const SQUAD_SIZE := 4
const SQUAD_BOUNTY := 500
## The mosque is a fixed v0.4 landmark (city generator builds the
## "Mosque" node at this position; mission_director.MOSQUE_POINT agrees).
## Used only when the live Mosque node cannot be found in the tree.
const MOSQUE_POS := Vector3(-75.0, 0.0, 75.0)

var _heat: float = 0.0
var _level: int = 0
var _last_emitted_heat: float = 0.0

var _player: Node3D = null
var _spawn_pos: Vector3 = Vector3(0.0, 0.0, 10.0)
var _spawn_pos_known := false
var _spawner: Node = null
var _director: Node = null
var _director_connected := false
var _mosque_pos: Vector3 = MOSQUE_POS
var _mosque_found := false
var _police_car: Node3D = null
## Which safe zone resolved, for debugging: "mosque" | "police_car" |
## "spawn" (fallback when neither node exists) | "none".
var _safe_zone_mode := "none"

var _scan_timer := 0.0
var _enemy_near := false
var _near_safe := false
var _decaying := false
var _time_since_enemy_near := 0.0
var _boss_forced := false

var _squad_spawned := false
var _squad_members: Array = []
var _squad_alive := 0

## Level thresholds: L0 is exactly 0; L1 1-20, L2 21-40, L3 41-60,
## L4 61-80, L5 81-100.
static func level_for_heat(heat: float) -> int:
	if heat <= 0.0:
		return 0
	if heat <= 20.0:
		return 1
	if heat <= 40.0:
		return 2
	if heat <= 60.0:
		return 3
	if heat <= 80.0:
		return 4
	return 5

## Find the WantedManager in the current scene (null when the
## coordinator did not add one — callers must behave as v0.7 then).
static func find_in(tree: SceneTree) -> WantedManager:
	if tree == null:
		return null
	var grouped := tree.get_first_node_in_group("wanted_manager")
	if grouped is WantedManager:
		return grouped
	var scene := tree.current_scene
	if scene != null:
		return _find_recursive(scene)
	return null

static func _find_recursive(node: Node) -> WantedManager:
	if node is WantedManager:
		return node
	for child in node.get_children():
		var found := _find_recursive(child)
		if found != null:
			return found
	return null

func _ready() -> void:
	add_to_group("wanted_manager")
	call_deferred("_late_ready")

func _late_ready() -> void:
	_find_player()
	_find_spawner()
	_wire_director()
	_find_safe_zones()

func get_heat() -> float:
	return _heat

func get_level() -> int:
	return _level

## True while heat is currently falling (drives the HeatHud lay-low hint).
func is_decaying() -> bool:
	return _decaying

func is_near_safe_zone() -> bool:
	return _near_safe

## Add heat, clamped 0-100. Emits heat_changed (throttled to 0.1 steps so
## per-frame decay does not spam listeners) and heat_level_up /
## heat_level_down when the level changes.
func add_heat(amount: float, reason: String) -> void:
	if amount == 0.0:
		return
	var old_level := _level
	var new_heat := clampf(_heat + amount, 0.0, MAX_HEAT)
	var applied := new_heat - _heat
	if applied == 0.0:
		return
	_heat = new_heat
	_level = level_for_heat(_heat)
	if _level < 5:
		_squad_spawned = false
	if _level != old_level:
		if _level > old_level:
			heat_level_up.emit(_level)
		else:
			heat_level_down.emit(_level)
	if absf(_heat - _last_emitted_heat) >= 0.1 or _level != old_level:
		_last_emitted_heat = _heat
		heat_changed.emit(_level, _heat)
	if _level == 5 and old_level < 5 and not _squad_spawned:
		_try_spawn_hit_squad()

## Combat heat only: +amount/s while an enemy is near. Capped on the
## TOTAL: proximity alone can never raise heat past 60 (COMBAT_HEAT_CAP
## / L3). Kills / CHASE / wild fire are non-combat sources and CAN push
## past 60 — they go through add_heat() directly.
func _add_combat_heat(amount: float) -> void:
	if amount <= 0.0:
		return
	var allowed := minf(amount, COMBAT_HEAT_CAP - _heat)
	if allowed <= 0.0:
		return
	add_heat(allowed, "combat")

## Set heat directly (chapter save/restore path). No halving here —
## load_from_dict() does the halving.
func set_heat(value: float) -> void:
	var old_level := _level
	_heat = clampf(value, 0.0, MAX_HEAT)
	_level = level_for_heat(_heat)
	if _level < 5:
		_squad_spawned = false
	if _level > old_level:
		heat_level_up.emit(_level)
	elif _level < old_level:
		heat_level_down.emit(_level)
	_last_emitted_heat = _heat
	heat_changed.emit(_level, _heat)

## Heat drops by 30 after a mission / chapter ends (floor 0). Wired to
## MissionDirector.mission_completed + chapter_completed; the
## coordinator may also call it directly.
func reset_after_chapter() -> void:
	add_heat(-CHAPTER_RESET, "chapter_end")

func to_dict() -> Dictionary:
	return {"heat": _heat}

## Restore from a save dict. Old v0.7 saves have no "heat" key -> 0.
## BETWEEN SESSIONS the saved heat is HALVED (rounded down): the gang
## cools off while the player is away.
func load_from_dict(d: Dictionary) -> void:
	var saved_heat := float(d.get("heat", 0.0))
	set_heat(floorf(saved_heat * 0.5))

## Manual hook for a mission going loud. +15 only for a CHASE start
## (ids "chase" in free play, "ch2_chase" in chapter 2 — both contain
## "chase"). Primary path is the auto-connect to mission_started; this
## is the backup if the director is wired after missions start.
func mission_went_loud(kind: String) -> void:
	if kind.contains("chase"):
		add_heat(CHASE_HEAT, "chase")

## Wild-fire hook (see wiring note 3 in the header). Call ONLY when a
## shot hit NOTHING (no damage dealt). +0.5 when a civilian is within
## 15 m of the player, else nothing. Uses group "civilian", which
## citizen.gd guarantees (citizens add themselves to it in _ready).
func register_missed_shot() -> void:
	if _player == null or not is_instance_valid(_player):
		_find_player()
		if _player == null:
			return
	var pp := _player.global_position
	for c in get_tree().get_nodes_in_group("civilian"):
		var cn := c as Node3D
		if cn == null or not is_instance_valid(cn):
			continue
		var d := cn.global_position - pp
		d.y = 0.0
		if d.length() <= CIVILIAN_RADIUS:
			add_heat(WILD_FIRE_HEAT, "wild_fire")
			return

## Coordinator override for the boss-fight guard. The automatic checks
## (boss node present / director running a "boss" step) still apply on
## top of this flag.
func set_boss_fight_active(active: bool) -> void:
	_boss_forced = active

func _boss_fight_active() -> bool:
	if _boss_forced:
		return true
	var tree := get_tree()
	if tree != null:
		var scene := tree.current_scene
		# The boss node is named "BossTheWolf" (mission_director
		# _spawn_boss). find_child owned=false: runtime-added nodes
		# have no owner, so owned=true would miss them.
		if scene != null and scene.find_child("BossTheWolf", true, false) != null:
			return true
	if _director != null and is_instance_valid(_director) and _director.has_method("current_mission_id"):
		var mid := String(_director.call("current_mission_id"))
		if mid.contains("boss"):
			return true
	return false

func _process(delta: float) -> void:
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = SCAN_INTERVAL
		_refresh_scan()
	if _player == null or not is_instance_valid(_player):
		return
	if _player.get("is_dead") == true:
		return
	if _enemy_near:
		_time_since_enemy_near = 0.0
		_decaying = false
		_add_combat_heat(COMBAT_HEAT_RATE * delta)
	else:
		_time_since_enemy_near += delta
		if _near_safe:
			# Laying low at a safe zone: fast decay, immediately, but
			# never while an enemy is within 40 m (see above).
			_decaying = true
			add_heat(-SAFE_DECAY_RATE * delta, "safe_zone")
		elif _time_since_enemy_near >= IDLE_DECAY_DELAY:
			_decaying = true
			add_heat(-IDLE_DECAY_RATE * delta, "decay")
		else:
			_decaying = false

## Throttled (every 0.5 s) re-scan: refresh cached node lookups, enemy
## proximity, safe-zone proximity, and retry a pending hit-squad spawn
## (e.g. the spawner was not ready when heat first hit L5).
func _refresh_scan() -> void:
	if _player == null or not is_instance_valid(_player):
		_find_player()
	if _spawner == null or not is_instance_valid(_spawner):
		_find_spawner()
	if not _director_connected:
		_wire_director()
	if _police_car == null or not is_instance_valid(_police_car):
		_find_safe_zones()
	_refresh_proximity()
	if _level >= 5 and not _squad_spawned:
		_try_spawn_hit_squad()

func _refresh_proximity() -> void:
	_enemy_near = false
	_near_safe = false
	if _player == null or not is_instance_valid(_player):
		return
	var pp := _player.global_position
	var tree := get_tree()
	if tree != null:
		# Group "zombie" is every gang enemy: wave enemies, mission
		# criminals, boss guards — and the boss himself. All of them
		# count as "the gang is on you" for combat heat.
		for z in tree.get_nodes_in_group("zombie"):
			var zn := z as Node3D
			if zn == null or not is_instance_valid(zn):
				continue
			if zn.get("is_dead") == true:
				continue
			var d := zn.global_position - pp
			d.y = 0.0
			if d.length() <= COMBAT_RADIUS:
				_enemy_near = true
				break
	# Safe zone: mosque (node, else fixed landmark position) within
	# 25 m, or the police car within 15 m. Spawn-point fallback only
	# when neither live node could be found at all.
	var flat_pp := Vector3(pp.x, 0.0, pp.z)
	var flat_mosque := Vector3(_mosque_pos.x, 0.0, _mosque_pos.z)
	if flat_pp.distance_to(flat_mosque) <= MOSQUE_RADIUS:
		_near_safe = true
		_safe_zone_mode = "mosque"
	elif is_instance_valid(_police_car):
		if pp.distance_to(_police_car.global_position) <= POLICE_CAR_RADIUS:
			_near_safe = true
			_safe_zone_mode = "police_car"
	elif not _mosque_found:
		if _spawn_pos_known and flat_pp.distance_to(Vector3(_spawn_pos.x, 0.0, _spawn_pos.z)) <= POLICE_CAR_RADIUS:
			_near_safe = true
			_safe_zone_mode = "spawn"
	if not _near_safe:
		_safe_zone_mode = "none" if (is_instance_valid(_police_car) or _mosque_found) else "spawn"

func _find_player() -> void:
	var tree := get_tree()
	if tree == null:
		return
	_player = tree.get_first_node_in_group("player") as Node3D
	if _player == null:
		var scene := tree.current_scene
		if scene != null:
			_player = scene.get_node_or_null("Player") as Node3D
	if is_instance_valid(_player) and not _spawn_pos_known:
		_spawn_pos = _player.global_position
		_spawn_pos_known = true

func _find_spawner() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var scene := tree.current_scene
	if scene == null:
		return
	_spawner = scene.get_node_or_null("EnemySpawner")
	if _spawner == null:
		_spawner = scene.find_child("EnemySpawner", true, false)

## Auto-wire the mission signals. CHASE start = +15; mission / chapter
## completion = reset_after_chapter(). Safe when the director is absent
## (free-play scenes without missions) — everything stays 0.
func _wire_director() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var scene := tree.current_scene
	if scene == null:
		return
	_director = scene.get_node_or_null("MissionDirector")
	if _director == null:
		_director = scene.find_child("MissionDirector", true, false)
	if _director == null or not is_instance_valid(_director):
		return
	if _director.has_signal("mission_started") and not _director.is_connected("mission_started", _on_mission_started):
		_director.connect("mission_started", _on_mission_started)
	if _director.has_signal("mission_completed") and not _director.is_connected("mission_completed", _on_mission_completed):
		_director.connect("mission_completed", _on_mission_completed)
	if _director.has_signal("chapter_completed") and not _director.is_connected("chapter_completed", _on_chapter_completed):
		_director.connect("chapter_completed", _on_chapter_completed)
	_director_connected = true

func _on_mission_started(mission_id: String, _title: String) -> void:
	mission_went_loud(mission_id)

func _on_mission_completed(_mission_id: String, _title: String, _money: int, _score: int) -> void:
	reset_after_chapter()

func _on_chapter_completed(_chapter: int, _xp: int, _money: int, _time_sec: float) -> void:
	reset_after_chapter()

## Safe-zone lookups. Mosque: City/Mosque node, else any "Mosque" node,
## else the fixed MOSQUE_POS landmark. Police car: the "PoliceCar" node
## built by TrafficManager (child of TrafficManager), else its
## police_car property.
func _find_safe_zones() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var scene := tree.current_scene
	_mosque_found = false
	_mosque_pos = MOSQUE_POS
	_police_car = null
	if scene != null:
		var mosque := scene.get_node_or_null("City/Mosque") as Node3D
		if mosque == null:
			mosque = scene.find_child("Mosque", true, false) as Node3D
		if is_instance_valid(mosque):
			_mosque_pos = mosque.global_position
			_mosque_found = true
		var car := scene.find_child("PoliceCar", true, false) as Node3D
		if is_instance_valid(car):
			_police_car = car
		else:
			var tm := scene.get_node_or_null("TrafficManager")
			if tm == null:
				tm = scene.find_child("TrafficManager", true, false)
			if tm != null and tm.get("police_car") is Node3D:
				_police_car = tm.get("police_car") as Node3D

# --- Hit squad ---------------------------------------------------------------

## Spawn the 4-elite squad the FIRST time heat reaches L5 (per L5
## excursion — the flag clears when heat drops below L5). Never during
## the Khaled boss fight. The spawner builds the squad; this manager
## tracks its members and pays the bounty when all 4 die.
func _try_spawn_hit_squad() -> void:
	if _squad_spawned:
		return
	if _boss_fight_active():
		return
	if _spawner == null or not is_instance_valid(_spawner):
		_find_spawner()
		if _spawner == null:
			return
	if not _spawner.has_method("spawn_hit_squad"):
		push_warning("WantedManager: EnemySpawner has no spawn_hit_squad() — hit squad skipped")
		return
	var members: Array = _spawner.call("spawn_hit_squad")
	if members.is_empty():
		return
	_squad_spawned = true
	_squad_members.clear()
	_squad_alive = 0
	for m in members:
		var enemy := m as Node
		if enemy == null or not is_instance_valid(enemy):
			continue
		_squad_members.append(enemy)
		_squad_alive += 1
		if enemy.has_signal("enemy_died") and not enemy.is_connected("enemy_died", _on_squad_member_died):
			enemy.connect("enemy_died", _on_squad_member_died)
	if _squad_alive <= 0:
		_squad_spawned = false
		return
	hit_squad_spawned.emit()
	play_sting.emit()

## A squad member died (wired to each member's enemy_died). When the
## last one falls: +500 DT bounty via GameManager.add_money
## (null-guarded — no crash when GameManager is absent) and heat -30,
## plus the squad_defeated signal for the HUD "survived" banner.
## NOTE: each squad kill ALSO pays the normal +6 kill heat through the
## spawner's _on_enemy_died — the -30 bounty more than covers it.
func _on_squad_member_died(_enemy: Node) -> void:
	_squad_members.erase(_enemy)
	_squad_alive = maxi(0, _squad_alive - 1)
	if _squad_alive > 0:
		return
	if not _squad_spawned:
		return
	_squad_members.clear()
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.has_method("add_money"):
		gm.call("add_money", SQUAD_BOUNTY)
	add_heat(-CHAPTER_RESET, "bounty")
	squad_defeated.emit(SQUAD_BOUNTY)
