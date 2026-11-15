class_name WeaponManager
extends Node
## v0.8 — Weapons + Wanted: the arsenal.
##
## Owns all 5 weapons, their stats, per-weapon mag/reserve ammo,
## ownership / rank gates / prices, reload + cooldown timers, the
## scoped (sniper zoom) state, procedural viewmodels, and ammo
## drops from dead enemies. The Player calls try_fire() from its
## fire path and does the raycast/tracer itself using the stats
## returned by get_current_stats() — this manager never raycasts.
##
## FALLBACK: if no WeaponManager is present the Player keeps its
## legacy rifle fire path untouched (see player.gd). This manager
## is equally defensive the other way: every GameManager /
## CampaignManager / EnemySpawner lookup is null-guarded, so it
## works in a bare headless scene with none of them present.
##
## AMMO DROP: listens to each enemy's `enemy_died` signal (found by
## scanning group "zombie", never by editing enemy_spawner.gd).
## 25% chance per death: one AmmoPickup at the corpse, amount =
## one full magazine of a RANDOM owned weapon (spreads ammo across
## the arsenal instead of always feeding the current gun).
## FALLBACK: if no EnemySpawner is ever found in the scene (e.g. a
## test scene with no spawner), a pickup spawns near the player
## every 40 s instead, same amounts. The spawner path is preferred
## whenever the spawner exists.
##
## PERSISTENCE: state lives in user://weapons.cfg (own file — the
## campaign save in campaign_manager.gd is another worker's file
## and is NOT touched). to_dict()/load_from_dict() are the public
## API: the coordinator may instead carry the dict inside the
## campaign save; load_from_dict() called afterwards wins over the
## file, and _save_weapons() keeps the file in sync on buy/unlock.
## Old v0.7 save (no weapons data): owned = [pistol, rifle],
## rifle equipped, reserves at start values.

signal weapon_changed(id: String)
signal ammo_changed(mag: int, reserve: int)
signal reload_started()
signal reload_finished()
signal shot_fired(was_hit: bool, target_group: String)
signal weapon_unlocked(id: String)
signal scoped_changed(scoped: bool)

const SAVE_PATH := "user://weapons.cfg"
const DROP_CHANCE := 0.25
const FALLBACK_DROP_INTERVAL := 40.0
const PISTOL_INFINITE_RESERVE := -1

## Order shown in the armoury and used by cycle_weapon().
const WEAPON_ORDER: Array[String] = ["pistol", "rifle", "smg", "shotgun", "sniper"]

## Rank indices — same scale as CampaignManager (0 Officer,
## 1 Sergeant, 2 Lieutenant, 3 Captain).
const RANK_OFFICER := 0
const RANK_SERGEANT := 1
const RANK_LIEUTENANT := 2

const STATS := {
	"pistol": {
		"damage": 25, "interval": 0.25, "auto": false, "mag_size": 12,
		"reload_time": 1.0, "spread_deg": 1.5, "range": 40.0,
		"pellets": 1, "price": 0, "min_rank": 0, "reserve_start": -1,
	},
	"rifle": {
		"damage": 34, "interval": 0.12, "auto": true, "mag_size": 30,
		"reload_time": 1.4, "spread_deg": 1.0, "range": 80.0,
		"pellets": 1, "price": 0, "min_rank": 0, "reserve_start": 120,
	},
	"smg": {
		"damage": 16, "interval": 0.07, "auto": true, "mag_size": 32,
		"reload_time": 1.2, "spread_deg": 3.5, "range": 30.0,
		"pellets": 1, "price": 1500, "min_rank": 0, "reserve_start": 160,
	},
	"shotgun": {
		"damage": 12, "interval": 0.9, "auto": false, "mag_size": 6,
		"reload_time": 2.2, "spread_deg": 9.0, "range": 18.0,
		"pellets": 8, "price": 2500, "min_rank": 1, "reserve_start": 24,
	},
	"sniper": {
		"damage": 150, "interval": 1.5, "auto": false, "mag_size": 5,
		"reload_time": 2.5, "spread_deg": 0.1, "range": 200.0,
		"pellets": 1, "price": 5000, "min_rank": 2, "reserve_start": 15,
	},
}

var _player: Node = null
var _sound: SoundManager = null
var _current_id := "rifle"
var _owned: Array[String] = ["pistol", "rifle"]
var _mags: Dictionary = {}
var _reserves: Dictionary = {}
var _cooldown_timer := 0.0
var _reloading := false
var _reload_timer := 0.0
var _scoped := false
var _dry_click_timer := 0.0
var _scan_timer := 0.0
var _fallback_timer := FALLBACK_DROP_INTERVAL
var _saw_spawner := false
var _connected_enemies: Dictionary = {}
var _setup_done := false


func _ready() -> void:
	# v0.8 (coordinator integration): group registration so
	# CampaignManager._find_manager() can locate this manager even
	# when SceneTree.current_scene is not the game scene — mirrors
	# WantedManager.add_to_group("wanted_manager").
	add_to_group("weapon_manager")
	_reset_to_defaults()
	_load_weapons_file()


func _reset_to_defaults() -> void:
	_current_id = "rifle"
	_owned = ["pistol", "rifle"]
	_mags.clear()
	_reserves.clear()
	for id in WEAPON_ORDER:
		_mags[id] = int(STATS[id]["mag_size"])
		_reserves[id] = int(STATS[id]["reserve_start"])
	_cooldown_timer = 0.0
	_reloading = false
	_reload_timer = 0.0
	_scoped = false


## Called by the Player in _ready (after add_child, so _ready ran).
## Safe to call twice; the second call is a no-op.
func setup(player: Node) -> void:
	if _setup_done:
		return
	_setup_done = true
	_player = player
	# Weapon sounds: prefer the Player's own SoundManager (one node
	# already drives wind/murmur); fall back to our own instance.
	if _player != null:
		var ps: Variant = _player.get("_sound")
		if ps is SoundManager:
			_sound = ps
	if _sound == null:
		_sound = SoundManager.new()
		_sound.name = "WeaponSoundManager"
		add_child(_sound)
	# Sync the Player's legacy ammo vars so mobile_hud.set_ammo()
	# (fed from player.ammo / player.mag_size) stays correct.
	_sync_player_ammo_vars()
	emit_ammo()


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
	if _dry_click_timer > 0.0:
		_dry_click_timer -= delta
	if _reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_finish_reload()
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 0.5
		_scan_enemies()
	if not _saw_spawner:
		_fallback_timer -= delta
		if _fallback_timer <= 0.0:
			_fallback_timer = FALLBACK_DROP_INTERVAL
			_spawn_fallback_pickup()


# ------------------------------------------------------------------ queries
func get_all_ids() -> Array[String]:
	return WEAPON_ORDER.duplicate()


func get_current_id() -> String:
	return _current_id


func get_current_stats() -> Dictionary:
	return get_stats(_current_id)


func get_stats(id: String) -> Dictionary:
	if not STATS.has(id):
		return {}
	var s: Dictionary = STATS[id]
	return {
		"id": id,
		"damage": int(s["damage"]),
		"interval": float(s["interval"]),
		"auto": bool(s["auto"]),
		"mag_size": int(s["mag_size"]),
		"reload_time": float(s["reload_time"]),
		"spread_deg": float(s["spread_deg"]),
		"range": float(s["range"]),
		"pellets": int(s["pellets"]),
	}


func get_price(id: String) -> int:
	if not STATS.has(id):
		return 0
	return int(STATS[id]["price"])


func get_min_rank(id: String) -> int:
	if not STATS.has(id):
		return 0
	return int(STATS[id]["min_rank"])


func get_mag() -> int:
	return int(_mags.get(_current_id, 0))


func get_mag_for(id: String) -> int:
	return int(_mags.get(id, 0))


## Reserve for the current weapon. -1 = INFINITE (pistol only).
func get_reserve() -> int:
	return int(_reserves.get(_current_id, 0))


func get_reserve_for(id: String) -> int:
	return int(_reserves.get(id, 0))


func get_owned() -> Array[String]:
	return _owned.duplicate()


func is_owned(id: String) -> bool:
	return id in _owned


func is_scoped() -> bool:
	return _scoped


func is_reloading() -> bool:
	return _reloading


# ------------------------------------------------------------------ economy
func _player_rank() -> int:
	var cm := get_node_or_null("/root/CampaignManager")
	if cm != null and cm.has_method("get_rank"):
		return int(cm.call("get_rank"))
	return 0


func _player_money() -> int:
	var gm := get_node_or_null("/root/GameManager")
	if gm != null:
		return int(gm.get("money"))
	return 0


func can_buy(id: String) -> bool:
	if not STATS.has(id):
		return false
	if is_owned(id):
		return false
	if _player_rank() < get_min_rank(id):
		return false
	return _player_money() >= get_price(id)


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.has_method("spend_money"):
		if not bool(gm.call("spend_money", get_price(id))):
			return false
	_owned.append(id)
	_save_weapons()
	weapon_unlocked.emit(id)
	return true


## Grant without payment (e.g. chapter reward: SMG = ch.2,
## shotgun = ch.4 — the coordinator calls this). `free` is kept
## in the signature per spec; the grant is always free. Returns
## false only for an unknown id; true when owned afterwards
## (including already-owned — idempotent).
func unlock(id: String, free: bool) -> bool:
	if not STATS.has(id):
		return false
	if is_owned(id):
		return true
	_owned.append(id)
	_save_weapons()
	weapon_unlocked.emit(id)
	return true


func equip(id: String) -> bool:
	if not STATS.has(id):
		return false
	if not is_owned(id):
		return false
	if id == _current_id:
		return true
	_current_id = id
	_cooldown_timer = 0.0
	_reloading = false
	_reload_timer = 0.0
	# Leaving the sniper clears the scope (FOV + crosshair reset
	# is driven by scoped_changed + the Player's handler).
	if id != "sniper" and _scoped:
		set_scoped(false)
	_save_weapons()
	_sync_player_ammo_vars()
	weapon_changed.emit(id)
	emit_ammo()
	return true


func cycle_weapon() -> String:
	if _owned.is_empty():
		return _current_id
	var idx := _owned.find(_current_id)
	# Next owned weapon in WEAPON_ORDER after the current one.
	var order_idx := WEAPON_ORDER.find(_current_id)
	for step in range(1, WEAPON_ORDER.size() + 1):
		var next_id: String = WEAPON_ORDER[(order_idx + step) % WEAPON_ORDER.size()]
		if next_id in _owned:
			equip(next_id)
			return next_id
	return _current_id


# ------------------------------------------------------------------ firing
## The Player calls this from its fire path (press for every weapon;
## hold-tick only for auto weapons — the Player gates that).
## Returns true only when a round actually left the barrel: consumes
## 1 mag round, starts the cooldown, plays the weapon sound.
## False when mag empty (dry click, throttled), reloading, cooling
## down, or the player is dead. The Player reads pellets / spread /
## damage / range from get_current_stats() and does the raycast(s).
func try_fire() -> bool:
	if _player != null and bool(_player.get("is_dead")):
		return false
	if _reloading:
		return false
	if _cooldown_timer > 0.0:
		return false
	if get_mag() <= 0:
		if _dry_click_timer <= 0.0:
			_dry_click_timer = 0.3
			if _sound != null and _sound.has_method("play_dry_fire"):
				_sound.play_dry_fire()
		return false
	_mags[_current_id] = get_mag() - 1
	_cooldown_timer = float(STATS[_current_id]["interval"])
	_play_shot_sound()
	_sync_player_ammo_vars()
	emit_ammo()
	return true


## Called by the Player AFTER its raycast(s), so listeners (HUD /
## wanted system) learn whether the shot hit and what it hit.
func report_shot(was_hit: bool, target_group: String) -> void:
	shot_fired.emit(was_hit, target_group)


func start_reload() -> bool:
	if _reloading:
		return false
	if get_mag() >= int(STATS[_current_id]["mag_size"]):
		return false
	var reserve := get_reserve()
	if reserve == 0:
		return false
	_reloading = true
	_reload_timer = float(STATS[_current_id]["reload_time"])
	if _sound != null:
		_sound.play_reload()
	reload_started.emit()
	return true


func _finish_reload() -> void:
	_reloading = false
	var mag_size := int(STATS[_current_id]["mag_size"])
	var need := mag_size - get_mag()
	if need > 0:
		var reserve := get_reserve()
		if reserve == PISTOL_INFINITE_RESERVE:
			_mags[_current_id] = mag_size
		else:
			var take := mini(need, reserve)
			_mags[_current_id] = get_mag() + take
			_reserves[_current_id] = reserve - take
	if _sound != null:
		_sound.play_reload_done()
	_sync_player_ammo_vars()
	reload_finished.emit()
	emit_ammo()


## Refill every owned weapon's reserve to its start value (called
## on mission / chapter completion — the coordinator wires it).
## Current mags are NOT touched; the pistol is infinite anyway.
func refill_all_reserves() -> void:
	for id in _owned:
		if STATS.has(id):
			_reserves[id] = int(STATS[id]["reserve_start"])
	emit_ammo()


func add_reserve(id: String, amount: int) -> void:
	if not STATS.has(id) or amount <= 0:
		return
	if int(_reserves.get(id, 0)) == PISTOL_INFINITE_RESERVE:
		return
	_reserves[id] = int(_reserves.get(id, 0)) + amount
	if id == _current_id:
		emit_ammo()


func emit_ammo() -> void:
	ammo_changed.emit(get_mag(), get_reserve())


## Scoped aim (sniper only — other weapons ignore the call).
## Emits scoped_changed; the Player/coordinator sets camera FOV
## 75 -> 30 and the WeaponHud swaps to the scope ring.
func set_scoped(scoped: bool) -> void:
	if _current_id != "sniper":
		scoped = false
	if scoped == _scoped:
		return
	_scoped = scoped
	scoped_changed.emit(_scoped)


func _play_shot_sound() -> void:
	if _sound == null:
		return
	match _current_id:
		"pistol":
			if _sound.has_method("play_pistol"):
				_sound.play_pistol()
		"smg":
			if _sound.has_method("play_smg"):
				_sound.play_smg()
		"shotgun":
			if _sound.has_method("play_shotgun"):
				_sound.play_shotgun()
		"sniper":
			if _sound.has_method("play_sniper"):
				_sound.play_sniper()
		_:
			_sound.play_shot()


func _sync_player_ammo_vars() -> void:
	if _player == null:
		return
	var s := get_current_stats()
	if s.is_empty():
		return
	_player.set("ammo", get_mag())
	_player.set("mag_size", int(s["mag_size"]))
	_player.set("reload_time", float(s["reload_time"]))
	_player.set("fire_cooldown", float(s["interval"]))


# ------------------------------------------------------------------ drops
func _scan_enemies() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var scene := tree.current_scene
	if scene != null and scene.get_node_or_null("EnemySpawner") != null:
		_saw_spawner = true
	for enemy in tree.get_nodes_in_group("zombie"):
		var node := enemy as Node
		if node == null:
			continue
		var key := node.get_instance_id()
		if _connected_enemies.has(key):
			continue
		if node.has_signal("enemy_died"):
			node.enemy_died.connect(_on_enemy_died)
			_connected_enemies[key] = true


func _on_enemy_died(enemy: Node) -> void:
	var key := 0
	if enemy != null:
		key = enemy.get_instance_id()
		_connected_enemies.erase(key)
	if _player != null and bool(_player.get("is_dead")):
		return
	if randf() > DROP_CHANCE:
		return
	var pos := Vector3.ZERO
	if enemy is Node3D:
		pos = (enemy as Node3D).global_position
	_spawn_pickup(pos + Vector3(0.0, 0.6, 0.0))


func _spawn_pickup(at: Vector3) -> void:
	if _owned.is_empty():
		return
	var id: String = _owned[randi() % _owned.size()]
	var amount := int(STATS[id]["mag_size"])
	var pickup := AmmoPickup.new()
	pickup.name = "AmmoPickup"
	var scene := get_tree().current_scene
	if scene != null:
		scene.add_child(pickup)
	else:
		add_child(pickup)
	pickup.setup(id, amount, at)
	if pickup.has_signal("collected"):
		pickup.collected.connect(_on_pickup_collected)


func _on_pickup_collected(weapon_id: String, amount: int) -> void:
	add_reserve(weapon_id, amount)
	if _sound != null:
		_sound.play_reload_done()


func _spawn_fallback_pickup() -> void:
	# No spawner ever seen: drop a pickup near the player so ammo
	# still flows in spawner-less scenes. Never runs in the real
	# game (main_game always has an EnemySpawner).
	if _player == null or not (_player is Node3D):
		return
	if bool(_player.get("is_dead")):
		return
	var base := (_player as Node3D).global_position
	var ang := randf() * TAU
	var dist := randf_range(4.0, 8.0)
	_spawn_pickup(base + Vector3(cos(ang) * dist, 0.6, sin(ang) * dist))


# ------------------------------------------------------------------ viewmodels
## Muzzle-flash anchor per weapon (local to the viewmodel root).
## The Player re-parents its flash + light here on weapon swap.
func get_muzzle_offset(id: String) -> Vector3:
	match id:
		"pistol":
			return Vector3(0, 0.02, -0.38)
		"smg":
			return Vector3(0, 0.02, -0.62)
		"shotgun":
			return Vector3(0, 0.03, -0.78)
		"sniper":
			return Vector3(0, 0.03, -0.95)
		_:
			return Vector3(0, 0.02, -0.72)


## One procedural viewmodel per weapon, built from primitives in
## the Player's _create_viewmodel() style. The rifle keeps the
## existing v0.5 look (same parts, same materials) — no regression.
## Returned node has NO muzzle flash/light: the Player re-parents
## its own flash + light onto the new viewmodel on swap.
func build_viewmodel(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Viewmodel_" + id
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.13, 0.13, 0.15)
	metal.roughness = 0.45
	metal.metallic = 0.6
	var grip_mat := StandardMaterial3D.new()
	grip_mat.albedo_color = Color(0.20, 0.16, 0.12)
	grip_mat.roughness = 0.9
	var tan_mat := StandardMaterial3D.new()
	tan_mat.albedo_color = Color(0.45, 0.38, 0.26)
	tan_mat.roughness = 0.85
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.38, 0.24, 0.12)
	wood_mat.roughness = 0.8
	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.72, 0.55, 0.42)
	skin_mat.roughness = 0.9
	var scope_mat := StandardMaterial3D.new()
	scope_mat.albedo_color = Color(0.05, 0.07, 0.10)
	scope_mat.roughness = 0.25
	scope_mat.metallic = 0.8
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.10, 0.25, 0.35)
	glass_mat.roughness = 0.05
	glass_mat.metallic = 0.9
	match id:
		"pistol":
			_box(root, Vector3(0, 0.0, -0.05), Vector3(0.07, 0.06, 0.28), metal)
			_box(root, Vector3(0, 0.045, -0.05), Vector3(0.05, 0.02, 0.26), metal)
			_box(root, Vector3(0, -0.09, 0.06), Vector3(0.06, 0.14, 0.08), grip_mat)
			_box(root, Vector3(0, 0.02, -0.20), Vector3(0.055, 0.04, 0.06), metal)
			_box(root, Vector3(0, 0.06, -0.17), Vector3(0.02, 0.03, 0.02), metal)
			_cyl(root, Vector3(0, 0.0, -0.24), 0.022, 0.12, metal)
			_box(root, Vector3(0, -0.07, -0.10), Vector3(0.06, 0.05, 0.09), skin_mat)
		"smg":
			_box(root, Vector3(0, 0, 0.02), Vector3(0.08, 0.11, 0.42), metal)
			_box(root, Vector3(0, 0.02, -0.32), Vector3(0.05, 0.05, 0.26), metal)
			_box(root, Vector3(0, -0.15, -0.02), Vector3(0.05, 0.24, 0.08), metal)
			_box(root, Vector3(0, -0.09, 0.12), Vector3(0.06, 0.12, 0.09), grip_mat)
			_box(root, Vector3(0, -0.01, 0.30), Vector3(0.07, 0.09, 0.14), grip_mat)
			_box(root, Vector3(0, 0.08, -0.02), Vector3(0.03, 0.04, 0.10), metal)
			_cyl(root, Vector3(0, 0.02, -0.52), 0.028, 0.22, metal)
			_box(root, Vector3(0, -0.07, -0.28), Vector3(0.06, 0.05, 0.09), skin_mat)
		"shotgun":
			_cyl(root, Vector3(0, 0.03, -0.30), 0.035, 0.62, metal)
			_cyl(root, Vector3(0, -0.03, -0.28), 0.03, 0.55, wood_mat)
			_box(root, Vector3(0, 0.0, 0.05), Vector3(0.09, 0.10, 0.42), wood_mat)
			_box(root, Vector3(0, -0.02, -0.42), Vector3(0.10, 0.08, 0.22), wood_mat)
			_box(root, Vector3(0, -0.01, 0.34), Vector3(0.08, 0.11, 0.18), wood_mat)
			_box(root, Vector3(0, -0.10, 0.10), Vector3(0.07, 0.13, 0.09), grip_mat)
			_box(root, Vector3(0, 0.08, -0.58), Vector3(0.02, 0.04, 0.02), metal)
			_box(root, Vector3(0, -0.08, -0.38), Vector3(0.07, 0.06, 0.10), skin_mat)
		"sniper":
			_box(root, Vector3(0, 0, 0.05), Vector3(0.08, 0.11, 0.50), metal)
			_cyl(root, Vector3(0, 0.02, -0.55), 0.024, 0.70, metal)
			_cyl(root, Vector3(0, 0.10, -0.10), 0.045, 0.34, scope_mat)
			_cyl(root, Vector3(0, 0.10, -0.28), 0.035, 0.03, glass_mat)
			_box(root, Vector3(0, 0.055, -0.10), Vector3(0.04, 0.05, 0.08), metal)
			_box(root, Vector3(0, -0.11, 0.02), Vector3(0.05, 0.16, 0.08), metal)
			_box(root, Vector3(0, -0.09, 0.12), Vector3(0.06, 0.12, 0.09), grip_mat)
			_box(root, Vector3(0, -0.01, 0.38), Vector3(0.08, 0.11, 0.18), wood_mat)
			_box(root, Vector3(0.055, 0.02, 0.05), Vector3(0.05, 0.03, 0.03), metal)
			_box(root, Vector3(0, -0.07, -0.30), Vector3(0.06, 0.05, 0.09), skin_mat)
		_:
			# Rifle: the exact v0.5 parts (copied from player.gd so
			# the service rifle looks identical after a swap back).
			var parts: Array = [
				[Vector3(0, 0, 0), Vector3(0.09, 0.13, 0.55), metal],
				[Vector3(0, 0.02, -0.38), Vector3(0.05, 0.05, 0.30), metal],
				[Vector3(0, 0.09, -0.05), Vector3(0.03, 0.05, 0.04), metal],
				[Vector3(0, 0.125, -0.05), Vector3(0.05, 0.03, 0.09), metal],
				[Vector3(0, 0.0, -0.42), Vector3(0.11, 0.11, 0.22), tan_mat],
				[Vector3(0, -0.09, -0.38), Vector3(0.05, 0.09, 0.06), grip_mat],
				[Vector3(0, -0.13, 0.02), Vector3(0.06, 0.20, 0.09), tan_mat],
				[Vector3(0, -0.01, 0.36), Vector3(0.08, 0.11, 0.16), grip_mat],
				[Vector3(0, -0.10, 0.12), Vector3(0.07, 0.14, 0.10), grip_mat],
				[Vector3(0, -0.06, -0.18), Vector3(0.06, 0.10, 0.08), grip_mat],
				[Vector3(0, 0.02, -0.66), Vector3(0.06, 0.06, 0.14), metal],
				[Vector3(0, -0.08, -0.42), Vector3(0.07, 0.06, 0.10), skin_mat],
				[Vector3(0, 0.075, -0.30), Vector3(0.06, 0.02, 0.42), metal],
				[Vector3(0.05, 0.03, 0.10), Vector3(0.04, 0.02, 0.08), metal],
				[Vector3(0, 0.10, -0.55), Vector3(0.02, 0.06, 0.02), metal],
				[Vector3(0, -0.01, 0.45), Vector3(0.09, 0.13, 0.03), grip_mat],
				[Vector3(0.045, -0.06, 0.0), Vector3(0.02, 0.04, 0.05), metal],
			]
			for p in parts:
				_box(root, p[0], p[1], p[2])
			_cyl(root, Vector3(0, 0.02, -0.55), 0.025, 0.30, metal)
	return root


func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mi.mesh = box
	mi.position = pos
	parent.add_child(mi)


func _cyl(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.material = mat
	mi.mesh = cyl
	mi.rotation_degrees = Vector3(90, 0, 0)
	mi.position = pos
	parent.add_child(mi)


# ------------------------------------------------------------------ persistence
func to_dict() -> Dictionary:
	return {
		"current": _current_id,
		"owned": _owned.duplicate(),
		"mags": _mags.duplicate(),
		"reserves": _reserves.duplicate(),
	}


func load_from_dict(d: Dictionary) -> void:
	# No early return on an empty dict: "no weapons data" (old
	# v0.7 save) means the defaults below, not "keep whatever
	# state _ready loaded from the weapons file".
	var cur := String(d.get("current", "rifle"))
	if cur in STATS and cur in _owned:
		_current_id = cur
	var owned_raw: Array = d.get("owned", ["pistol", "rifle"])
	var new_owned: Array[String] = []
	for v in owned_raw:
		var id := String(v)
		if id in STATS and id not in new_owned:
			new_owned.append(id)
	if new_owned.is_empty():
		new_owned = ["pistol", "rifle"]
	_owned = new_owned
	if _current_id not in _owned:
		_current_id = "rifle" if "rifle" in _owned else _owned[0]
	var mags_raw: Dictionary = d.get("mags", {})
	var res_raw: Dictionary = d.get("reserves", {})
	for id in WEAPON_ORDER:
		var ms := int(STATS[id]["mag_size"])
		_mags[id] = clampi(int(mags_raw.get(id, ms)), 0, ms)
		var rs: int = int(res_raw.get(id, STATS[id]["reserve_start"]))
		_reserves[id] = rs if (rs == PISTOL_INFINITE_RESERVE or rs >= 0) else int(STATS[id]["reserve_start"])
		if id == "pistol":
			_reserves[id] = PISTOL_INFINITE_RESERVE
	_cooldown_timer = 0.0
	_reloading = false
	_scoped = false
	_sync_player_ammo_vars()
	emit_ammo()


func _save_weapons() -> void:
	var cfg := ConfigFile.new()
	var d := to_dict()
	cfg.set_value("weapons", "current", d["current"])
	cfg.set_value("weapons", "owned", d["owned"])
	cfg.set_value("weapons", "mags", d["mags"])
	cfg.set_value("weapons", "reserves", d["reserves"])
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("WeaponManager: could not save %s (err %d)." % [SAVE_PATH, err])


func _load_weapons_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var d := {
		"current": String(cfg.get_value("weapons", "current", "rifle")),
		"owned": cfg.get_value("weapons", "owned", ["pistol", "rifle"]),
		"mags": cfg.get_value("weapons", "mags", {}),
		"reserves": cfg.get_value("weapons", "reserves", {}),
	}
	load_from_dict(d)
