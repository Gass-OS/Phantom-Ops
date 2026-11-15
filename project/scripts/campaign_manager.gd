extends Node
## NOTE: no `class_name` here on purpose — Godot 4.2 rejects
## `class_name CampaignManager` on a script that is ALSO the
## "CampaignManager" autoload ("Class hides an autoload singleton").
## The autoload itself provides the global `CampaignManager` name,
## so `CampaignManager.current_chapter` etc. work exactly as specced.
## v0.7 — Story Campaign: chapters, XP, ranks, persistent save.
##
## Aymen, Kasserine police officer, vs the fictional gang "The Wolves
## of Kasserine" led by boss Khaled "The Wolf". 5 chapters:
##   1 First Patrol · 2 The Souk Robbery · 3 Night Shift
##   4 The Informant · 5 The Wolf (boss fight)
##
## UNLOCK RULE: chapter 5 unlocks by finishing chapters 1-4.
## Rank is PARALLEL progression, never a gate — a low rank never
## locks a chapter, and a high rank never unlocks one early.
##
## SAVE: user://save.cfg, section "campaign":
##   highest_unlocked (int), completed (Array of ints),
##   xp (int), money (int, dinars), rank (int index, recomputed
##   from xp on load), current_chapter (int).
## Written immediately on chapter completion; XP/money changes
## update the in-memory values at once and flush to disk throttled
## (at most once per second) so a burst of kills does not hammer
## the filesystem.
##
## MONEY-SURVIVES-RESET (the v0.7 save trap): GameManager.reset_game()
## zeroes money on every game start (player._ready, RETRY, menu).
## Campaign money must NOT be lost, so reset_game() itself restores
## the saved amount from here (see game_manager.gd) — the restore
## happens inside reset, before money_changed is emitted, so no
## listener ever sees the zeroed value. XP lives only here, never
## in GameManager, so it is safe by construction. Money earned
## during play flows back here via GameManager.money_changed.
##
## RANKS (XP thresholds): Officer 0 → Sergeant 500 →
## Lieutenant 1200 → Captain 2500.
##
## Autoload: CampaignManager="*res://scripts/campaign_manager.gd"
## (project.godot [autoload], next to GameManager). It loads before
## the menu, so the menu can read rank / unlock state in _ready.
## Other workers' API: current_chapter, is_unlocked(n),
## complete_chapter(n, xp, money), add_xp(n), highest_unlocked(),
## start_chapter(n), chapter_title(n), chapter_story(n).

signal chapter_completed(chapter: int, xp_earned: int, money_earned: int)
signal rank_up(new_rank: int, rank_name: String)
signal xp_changed(xp: int, rank: int)

const SAVE_PATH := "user://save.cfg"
const CHAPTER_COUNT := 5
const RANK_THRESHOLDS: Array[int] = [0, 500, 1200, 2500]
const RANK_KEYS: Array[String] = ["rank_officer", "rank_sergeant", "rank_lieutenant", "rank_captain"]
## Language-neutral short codes for the HUD rank chip.
const RANK_SHORT: Array[String] = ["OFC", "SGT", "LT", "CPT"]
const _SAVE_FLUSH_INTERVAL := 1.0
## v0.8 CHAPTER REWARDS — finishing a chapter unlocks a weapon free:
## Chapter 2 -> SMG, Chapter 4 -> Shotgun. Granted in
## complete_chapter() via _grant_chapter_reward(); when no
## WeaponManager is in the tree at that moment the id is kept in
## _pending_unlocks (saved) and applied when a manager appears.
const CHAPTER_REWARDS := {2: "smg", 4: "shotgun"}
## v0.8 — heat lost when a chapter ends (complete OR fail), applied
## AFTER restoring the stored pre-chapter heat (see _end_chapter_heat).
const CHAPTER_END_HEAT_REDUCTION := 30
## v0.8 — scripts of the other workers' managers. They are looked up
## by path + static find_in() (see _find_manager); the class names
## are NEVER referenced directly, so this file parses and runs
## correctly before those scripts land.
const _WEAPON_MANAGER_SCRIPT := "res://scripts/weapon_manager.gd"
const _WANTED_MANAGER_SCRIPT := "res://scripts/wanted_manager.gd"

var current_chapter: int = 1
var xp: int = 0
var rank: int = 0
var saved_money: int = 0
var completed_chapters: Array[int] = []

var _highest_unlocked: int = 1
var _dirty: bool = false
var _save_timer: float = 0.0
var _banner_layer: CanvasLayer
var _banner_label: Label
## v0.8 — weapons / wanted persistence (user://save.cfg, sections
## "weapons" / "wanted"). _saved_* hold the last-known dicts: loaded
## from disk in _load(), refreshed from the live managers in
## _save_now(). Old v0.7 saves have neither section — see _load()
## for the defaults (owned [pistol, rifle], rifle equipped, heat 0).
var _saved_weapons_data: Dictionary = {}
var _saved_wanted_data: Dictionary = {}
## Chapter-reward weapon ids granted while no WeaponManager was in
## the tree (saved under "weapons" / "pending_unlocks").
var _pending_unlocks: Array[String] = []
## v0.8 — heat snapshot. _pre_chapter_heat is the WantedManager heat
## when the current chapter was FIRST entered (-1 = none stored);
## _stored_chapter is the chapter it belongs to. It is session-only
## (never saved): a fresh app start loads heat from the save
## (halved by the WantedManager itself) instead. Death/RETRY
## re-enters the SAME chapter, so the stored value is kept and
## restored exactly — heat is never reset to 0 on death.
var _pre_chapter_heat: int = -1
var _stored_chapter: int = 0
## Last live heat value seen (mirror of the manager's heat, updated
## at every save and chapter end). Carries post-chapter heat into the
## next chapter's fresh WantedManager instance (-1 = unknown yet).
var _wanted_heat_mirror: int = -1
## Instances the saved state was already applied to. A scene reload
## (death/RETRY, next chapter) creates NEW manager instances, so
## _sync_managers() re-applies to each new one.
var _applied_weapon: Node = null
var _applied_wanted: Node = null
var _weapons_save_applied: bool = false
var _wanted_save_applied: bool = false
var _sync_timer: float = 0.0


func _ready() -> void:
	_load()
	_build_rank_banner()
	# Live money sync: every GameManager money change updates the
	# saved amount (missions, GIVE interactions, spends). The flush
	# to disk is throttled in _process.
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.has_signal("money_changed"):
		gm.money_changed.connect(_on_game_money_changed)


func _process(delta: float) -> void:
	# v0.8: apply saved weapons/wanted state to the managers as soon
	# as they appear in the tree (they live in the game scene, which
	# loads after this autoload). Cheap 1 s tick; _sync_managers()
	# only acts on NEW manager instances, so it is a no-op otherwise.
	_sync_timer += delta
	if _sync_timer >= 1.0:
		_sync_timer = 0.0
		_sync_managers()
	if not _dirty:
		return
	_save_timer += delta
	if _save_timer >= _SAVE_FLUSH_INTERVAL:
		_save_timer = 0.0
		_dirty = false
		_save_now()


## Highest chapter the player may start (1 when fresh).
func highest_unlocked() -> int:
	return _highest_unlocked


func is_unlocked(chapter: int) -> bool:
	return chapter >= 1 and chapter <= CHAPTER_COUNT and chapter <= _highest_unlocked


func is_completed(chapter: int) -> bool:
	return chapter in completed_chapters


func campaign_complete() -> bool:
	return completed_chapters.size() >= CHAPTER_COUNT


## Select a chapter to play. Returns false when it is still locked.
## Does NOT change scenes — the caller (menu) changes to intro.tscn.
## v0.8 HEAT: on FIRST entry into a chapter, store the current heat
## (WantedManager.get_heat()); on re-entry into the SAME chapter
## (death/RETRY — mission_director calls this again via
## _check_pending_chapter) keep the stored value and restore it into
## the (possibly fresh) WantedManager, so heat is never reset to 0
## on death and a hot chapter can never soft-lock. The stored value
## is cleared by _end_chapter_heat() when the chapter ends.
func start_chapter(chapter: int) -> bool:
	if not is_unlocked(chapter):
		return false
	var first_entry := _stored_chapter != chapter or _pre_chapter_heat < 0
	current_chapter = chapter
	if first_entry:
		_stored_chapter = chapter
		_pre_chapter_heat = -1
		var wm := _wanted_manager()
		if wm != null and wm.has_method("get_heat"):
			_pre_chapter_heat = maxi(int(wm.call("get_heat")), 0)
	else:
		restore_chapter_heat()
	_dirty = true
	return true


## Finish a chapter: mark it done, unlock the next one, award XP
## and dinars, save immediately. Money goes through GameManager so
## the HUD updates and the money_changed sync above records it.
func complete_chapter(chapter: int, xp_reward: int, money_reward: int) -> void:
	if chapter < 1 or chapter > CHAPTER_COUNT:
		push_warning("CampaignManager: invalid chapter %d." % chapter)
		return
	if chapter not in completed_chapters:
		completed_chapters.append(chapter)
		completed_chapters.sort()
	if chapter < CHAPTER_COUNT:
		_highest_unlocked = maxi(_highest_unlocked, chapter + 1)
	else:
		_highest_unlocked = CHAPTER_COUNT
	current_chapter = chapter
	if xp_reward > 0:
		add_xp(xp_reward)
	if money_reward > 0:
		var gm := get_node_or_null("/root/GameManager")
		if gm != null and gm.has_method("add_money"):
			gm.add_money(money_reward)
		else:
			saved_money += money_reward
	# v0.8: chapter reward (Ch2 -> SMG, Ch4 -> Shotgun, free) and
	# chapter-end heat (restore pre-chapter heat, then -30) BEFORE
	# the save, so both land in save.cfg immediately.
	_grant_chapter_reward(chapter)
	_end_chapter_heat()
	_save_now()
	chapter_completed.emit(chapter, xp_reward, money_reward)


## v0.8 — fail hook. mission_director._notify_campaign_failed calls
## this (it tries on_chapter_failed first, then chapter_failed). A
## failed chapter awards nothing and unlocks nothing, but heat still
## ends at (pre-chapter heat - 30) so a failed chapter can never
## soft-lock the next attempt. The stored pre-chapter heat is
## cleared, so a RETRY stores a fresh value on re-entry.
func on_chapter_failed(chapter: int, _reason: String) -> void:
	# v0.8 (coordinator integration): a failed chapter restores the
	# pre-chapter heat EXACTLY (no -30) — it can never soft-lock the
	# next attempt. Completed chapters still get the -30 decay.
	_end_chapter_heat(false)
	_save_now()


## v0.8 — free weapon for finishing a chapter, or "" when the
## chapter has no reward. The results card can show this.
func chapter_reward_weapon(chapter: int) -> String:
	return String(CHAPTER_REWARDS.get(chapter, ""))


## v0.8 — stored pre-chapter heat (-1 when none is stored).
## _end_chapter_heat() restores this value via set_heat() and then
## calls the manager's reset_after_chapter() for the -30 reduction
## (that method only subtracts from CURRENT heat — it does not
## restore, so the restore must happen first).
func get_pre_chapter_heat() -> int:
	return _pre_chapter_heat


func has_pre_chapter_heat() -> bool:
	return _pre_chapter_heat >= 0


## v0.8 — restore the stored pre-chapter heat into the live
## WantedManager exactly (no reduction, no reset to 0). Called by
## start_chapter() on same-chapter re-entry (death/RETRY) and
## available to the coordinator whenever a fresh manager appears.
func restore_chapter_heat() -> void:
	if _pre_chapter_heat < 0:
		return
	var wm := _wanted_manager()
	if wm != null and wm.has_method("set_heat"):
		wm.call("set_heat", float(_pre_chapter_heat))


## v0.8 — flush the save immediately (campaign + weapons + wanted).
## The armoury MUST call this (or GameManager.save_progress())
## right after a purchase/unlock: the throttled 1 s flush is not
## fast enough if the player dies and the scene reloads first.
func save_now() -> void:
	_dirty = false
	_save_timer = 0.0
	_save_now()


## v0.8 — apply the loaded weapons/wanted state (and pending
## unlocks) to the managers now. Safe to call any time; it is a
## no-op when no manager is in the tree yet, and _sync_managers()
## also retries it on a 1 s tick until the managers appear.
func apply_saved_managers() -> void:
	_sync_managers()


## v0.8 — saved loadouts as loaded from save.cfg (duplicates, so
## callers cannot mutate the stored state). Defaults when the save
## has no weapons/wanted section (v0.7 save): owned [pistol,
## rifle], rifle equipped, heat 0.
func get_saved_weapons() -> Dictionary:
	return _saved_weapons_data.duplicate(true)


func get_saved_wanted() -> Dictionary:
	return _saved_wanted_data.duplicate(true)


func get_pending_unlocks() -> Array:
	return _pending_unlocks.duplicate()


## v0.8 — apply pending chapter-reward unlocks to the live
## WeaponManager. Returns how many were applied. An id stays
## pending only when no manager exists or the unlock is refused
## (and the weapon is not already owned). Persists via _dirty.
func apply_pending_unlocks() -> int:
	if _pending_unlocks.is_empty():
		return 0
	var wpm := _weapon_manager()
	if wpm == null or not wpm.has_method("unlock"):
		return 0
	var applied := 0
	var remaining: Array[String] = []
	for id in _pending_unlocks:
		if _unlock_weapon(wpm, id):
			applied += 1
		else:
			remaining.append(id)
	_pending_unlocks = remaining
	if applied > 0:
		_dirty = true
	return applied


## Grant the chapter-completion weapon reward (free). Direct unlock
## when a WeaponManager is live; otherwise the id goes to
## _pending_unlocks (saved) and is applied when a manager appears.
func _grant_chapter_reward(chapter: int) -> void:
	var weapon_id := chapter_reward_weapon(chapter)
	if weapon_id == "":
		return
	var wpm := _weapon_manager()
	if wpm != null and wpm.has_method("unlock"):
		if not _unlock_weapon(wpm, weapon_id) and weapon_id not in _pending_unlocks:
			_pending_unlocks.append(weapon_id)
	elif weapon_id not in _pending_unlocks:
		_pending_unlocks.append(weapon_id)
	_dirty = true


## Unlock one weapon for free. Returns true when the weapon ends up
## owned. unlock() may return bool, void (null = assume success
## unless is_owned() says otherwise), or nothing useful — is_owned()
## decides whenever it exists.
func _unlock_weapon(wpm: Node, weapon_id: String) -> bool:
	var r: Variant = wpm.call("unlock", weapon_id, true)
	var ok := true
	if r is bool:
		ok = bool(r)
	if wpm.has_method("is_owned"):
		ok = bool(wpm.call("is_owned", weapon_id))
	return ok


## Chapter-end heat: restore the stored pre-chapter heat, then
## apply the -30 reduction, then clear the stored value. The live
## manager's reset_after_chapter() ONLY subtracts CHAPTER_RESET (30)
## from CURRENT heat — it does not restore — so the restore via
## set_heat() MUST happen first; the else branch does the same
## reduction in one set_heat() call. With no live manager, the
## reduced value is kept as the saved wanted state so the next
## session loads it (halved by the manager, per its contract — this
## file NEVER halves heat itself).
func _end_chapter_heat(apply_reduction: bool = true) -> void:
	if _pre_chapter_heat < 0:
		return
	var reduced := maxi(_pre_chapter_heat - CHAPTER_END_HEAT_REDUCTION, 0)
	var target := reduced if apply_reduction else _pre_chapter_heat
	var wm := _wanted_manager()
	if wm != null:
		if wm.has_method("set_heat") and wm.has_method("reset_after_chapter") and apply_reduction:
			# Restore FIRST, then the manager's own -30.
			wm.call("set_heat", float(_pre_chapter_heat))
			wm.call("reset_after_chapter")
			if wm.has_method("get_heat"):
				_wanted_heat_mirror = maxi(int(wm.call("get_heat")), 0)
			else:
				_wanted_heat_mirror = target
		elif wm.has_method("set_heat"):
			wm.call("set_heat", float(target))
			_wanted_heat_mirror = target
	else:
		_wanted_heat_mirror = target
		_saved_wanted_data = {"heat": target}
	_pre_chapter_heat = -1
	_stored_chapter = 0


## v0.8 — find the other workers' managers WITHOUT naming their
## classes (a direct `WeaponManager.find_in(...)` reference would
## fail to parse in a checkout where that script does not exist
## yet). Lookup order per manager:
## 1. static find_in(tree) on the script, when it defines one
##    (WantedManager does — group + recursive scene scan).
## 2. group "weapon_manager" / "wanted_manager".
## 3. recursive scan of the current scene for a node running the
##    manager's script (covers the WeaponManager as a plain child
##    of Player, which currently defines no find_in() or group).
## Verified live APIs (2026-11-14, in-tree):
## - WeaponManager: to_dict() {current, owned, mags, reserves},
##   load_from_dict(d) (fills mags/reserves start values when a key
##   is absent; defaults owned [pistol, rifle], current "rifle"),
##   unlock(id, free) -> bool, is_owned(id) -> bool. It ALSO
##   self-persists to user://weapons.cfg (written synchronously on
##   every unlock/buy) — save.cfg [weapons] is the campaign mirror.
## - WantedManager: float heat 0-100, to_dict() {heat, combat_heat},
##   load_from_dict(d) HALVES saved heat (between sessions),
##   get_heat() -> float, set_heat(float) (no halving),
##   reset_after_chapter() subtracts 30 from CURRENT heat only.
func _find_manager(script_path: String, group_name: String) -> Node:
	if get_tree() == null:
		return null
	if ResourceLoader.exists(script_path):
		var scr: Resource = load(script_path)
		if scr != null and scr.has_method("find_in"):
			var found: Variant = scr.call("find_in", get_tree())
			if found is Node:
				return found
	var grouped: Array[Node] = get_tree().get_nodes_in_group(group_name)
	if not grouped.is_empty():
		return grouped[0]
	var scene := get_tree().current_scene
	if scene != null:
		return _find_by_script(scene, script_path)
	return null


## Last-resort lookup: walk the current scene for a node running the
## given script (covers a manager that is a plain child, e.g. the
## WeaponManager under Player, with no find_in() or group yet).
func _find_by_script(node: Node, script_path: String) -> Node:
	var s: Script = node.get_script() as Script
	if s != null and s.resource_path == script_path:
		return node
	for child in node.get_children():
		var found := _find_by_script(child, script_path)
		if found != null:
			return found
	return null


func _weapon_manager() -> Node:
	return _find_manager(_WEAPON_MANAGER_SCRIPT, "weapon_manager")


func _wanted_manager() -> Node:
	return _find_manager(_WANTED_MANAGER_SCRIPT, "wanted_manager")


## v0.8 — one-shot-per-instance sync (see _process). When a fresh
## manager instance appears (new scene load, e.g. death/RETRY or a
## new chapter):
## - WantedManager: a stored pre-chapter heat means mid-chapter
##   re-entry — restore it EXACTLY via set_heat() (never 0, never
##   re-halved). Else on the first apply of the session, load the
##   saved dict (the manager halves saved heat on load, per its own
##   contract — this file never halves). On later chapter entries,
##   restore the live heat mirror so post-chapter heat carries over.
##   (WantedManager has no self-persistence, so this per-instance
##   apply is its only restore path.)
## - WeaponManager: load_from_dict() ONCE per session — the manager
##   self-restores from its own synchronously-written
##   user://weapons.cfg on every scene load, so re-applying the
##   (up to 1 s stale) save.cfg dict to later instances could only
##   downgrade it. Pending reward unlocks are additive and
##   idempotent, so they ARE applied to every new instance.
func _sync_managers() -> void:
	if get_tree() == null:
		return
	var wm := _wanted_manager()
	if wm != null and wm != _applied_wanted:
		_applied_wanted = wm
		if _pre_chapter_heat >= 0:
			if wm.has_method("set_heat"):
				wm.call("set_heat", float(_pre_chapter_heat))
		elif not _wanted_save_applied:
			_wanted_save_applied = true
			if wm.has_method("load_from_dict"):
				wm.call("load_from_dict", _saved_wanted_data.duplicate(true))
			if wm.has_method("get_heat"):
				_wanted_heat_mirror = maxi(int(wm.call("get_heat")), 0)
		elif _wanted_heat_mirror >= 0 and wm.has_method("set_heat"):
			wm.call("set_heat", float(_wanted_heat_mirror))
	var wpm := _weapon_manager()
	if wpm != null and wpm != _applied_weapon:
		_applied_weapon = wpm
		if not _weapons_save_applied:
			_weapons_save_applied = true
			if wpm.has_method("load_from_dict"):
				wpm.call("load_from_dict", _saved_weapons_data.duplicate(true))
		apply_pending_unlocks()


## Default weapons state for a save with no "weapons" section (v0.7
## save or fresh install). The key is "current" (the manager's field
## name, not "equipped"). The "mags" / "reserves" keys are
## deliberately ABSENT — WeaponManager.load_from_dict fills its own
## start values for any mag/reserve it is not given.
func _default_weapons_data() -> Dictionary:
	return {"owned": ["pistol", "rifle"], "current": "rifle"}


## Add XP. Returns true only when a rank threshold was crossed
## (the new rank also arrives via the rank_up signal).
func add_xp(amount: int) -> bool:
	if amount <= 0:
		return false
	xp += amount
	var new_rank := _rank_for_xp(xp)
	var ranked_up := new_rank > rank
	rank = new_rank
	_dirty = true
	xp_changed.emit(xp, rank)
	if ranked_up:
		var rank_name := rank_name(rank)
		rank_up.emit(rank, rank_name)
		show_rank_up(rank_name)
	return ranked_up


func get_saved_money() -> int:
	return saved_money


func get_xp() -> int:
	return xp


func get_rank() -> int:
	return rank


## Translated full rank name ("Sergeant" / "رقيب" / ...).
func rank_name(rank_index: int) -> String:
	var i := clampi(rank_index, 0, RANK_KEYS.size() - 1)
	return LanguageManager.t(RANK_KEYS[i])


## Short language-neutral code for the HUD chip ("SGT").
func rank_short(rank_index: int) -> String:
	var i := clampi(rank_index, 0, RANK_SHORT.size() - 1)
	return RANK_SHORT[i]


func chapter_title(chapter: int) -> String:
	return LanguageManager.t("chapter_%d_title" % chapter)


func chapter_story(chapter: int) -> String:
	return LanguageManager.t("chapter_%d_story" % chapter)


## Centred gold "RANK UP" banner, shown for 3 s. Called by add_xp
## and available to other workers (e.g. a results screen).
func show_rank_up(new_rank_name: String) -> void:
	if _banner_layer == null or _banner_label == null:
		return
	_banner_label.text = "%s\n%s" % [LanguageManager.t("rank_up"), new_rank_name]
	LanguageManager.apply_font_to(_banner_label)
	_banner_layer.visible = true
	get_tree().create_timer(3.0).timeout.connect(_hide_rank_banner)


func _hide_rank_banner() -> void:
	if _banner_layer != null:
		_banner_layer.visible = false


func _rank_for_xp(total_xp: int) -> int:
	var r := 0
	for i in RANK_THRESHOLDS.size():
		if total_xp >= RANK_THRESHOLDS[i]:
			r = i
	return r


func _on_game_money_changed(new_money: int) -> void:
	# The single source of truth for campaign money. reset_game()
	# restores the saved value before emitting, so a reset never
	# lands here as 0 — only real earns/spends do.
	saved_money = maxi(new_money, 0)
	_dirty = true


func _build_rank_banner() -> void:
	_banner_layer = CanvasLayer.new()
	_banner_layer.name = "RankUpBanner"
	_banner_layer.layer = 100
	_banner_layer.visible = false
	add_child(_banner_layer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.02, 0.92)
	style.border_color = Color(1.0, 0.85, 0.5, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.content_margin_left = 48
	style.content_margin_right = 48
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	_banner_label = Label.new()
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", 44)
	_banner_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5, 1.0))
	_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_banner_label)


func _load() -> void:
	current_chapter = 1
	xp = 0
	rank = 0
	saved_money = 0
	completed_chapters.clear()
	_highest_unlocked = 1
	_saved_weapons_data = _default_weapons_data()
	_saved_wanted_data = {"heat": 0}
	_pending_unlocks.clear()
	_pre_chapter_heat = -1
	_stored_chapter = 0
	_wanted_heat_mirror = -1
	_applied_weapon = null
	_applied_wanted = null
	_weapons_save_applied = false
	_wanted_save_applied = false
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	_highest_unlocked = clampi(int(cfg.get_value("campaign", "highest_unlocked", 1)), 1, CHAPTER_COUNT)
	xp = maxi(int(cfg.get_value("campaign", "xp", 0)), 0)
	saved_money = maxi(int(cfg.get_value("campaign", "money", 0)), 0)
	current_chapter = clampi(int(cfg.get_value("campaign", "current_chapter", _highest_unlocked)), 1, CHAPTER_COUNT)
	var done: Array = cfg.get_value("campaign", "completed", [])
	for v in done:
		var n := int(v)
		if n >= 1 and n <= CHAPTER_COUNT and n not in completed_chapters:
			completed_chapters.append(n)
	completed_chapters.sort()
	# v0.8: weapons + wanted persistence (same file, own sections).
	# Old v0.7 saves have neither section: the defaults above apply
	# (owned [pistol, rifle], rifle equipped, heat 0). A present but
	# empty dict is treated the same as absent. The loaded heat is
	# passed RAW to WantedManager.load_from_dict() — that manager
	# halves saved heat on load; this file never halves it.
	var wdata: Variant = cfg.get_value("weapons", "data", {})
	if wdata is Dictionary and not (wdata as Dictionary).is_empty():
		_saved_weapons_data = (wdata as Dictionary).duplicate(true)
	var wtdata: Variant = cfg.get_value("wanted", "data", {})
	if wtdata is Dictionary and not (wtdata as Dictionary).is_empty():
		_saved_wanted_data = (wtdata as Dictionary).duplicate(true)
	var pend: Array = cfg.get_value("weapons", "pending_unlocks", [])
	for v in pend:
		var id := String(v)
		if id != "" and id not in _pending_unlocks:
			_pending_unlocks.append(id)
	# Rank is derived from XP (authoritative); the stored rank is
	# only a readability hint. Re-derive so an edited save cannot
	# desync rank from XP, and re-derive the unlock from completions.
	rank = _rank_for_xp(xp)
	if not completed_chapters.is_empty():
		_highest_unlocked = mini(completed_chapters.max() + 1, CHAPTER_COUNT)


func _save_now() -> void:
	var cfg := ConfigFile.new()
	# Preserve nothing else in save.cfg — this file is the
	# campaign's own. (Language lives in settings.cfg.)
	cfg.set_value("campaign", "highest_unlocked", _highest_unlocked)
	cfg.set_value("campaign", "completed", completed_chapters)
	cfg.set_value("campaign", "xp", xp)
	cfg.set_value("campaign", "money", saved_money)
	cfg.set_value("campaign", "rank", rank)
	cfg.set_value("campaign", "current_chapter", current_chapter)
	# v0.8: weapons + wanted (same file, own sections). Live manager
	# state wins when a manager is present; otherwise the last-known
	# dict is re-written so a throttled flush never wipes it.
	var wpm := _weapon_manager()
	if wpm != null and wpm.has_method("to_dict"):
		var d: Variant = wpm.call("to_dict")
		if d is Dictionary:
			_saved_weapons_data = (d as Dictionary).duplicate(true)
	if not _saved_weapons_data.is_empty():
		cfg.set_value("weapons", "data", _saved_weapons_data)
	if not _pending_unlocks.is_empty():
		cfg.set_value("weapons", "pending_unlocks", _pending_unlocks)
	var wm := _wanted_manager()
	if wm != null and wm.has_method("to_dict"):
		var wd: Variant = wm.call("to_dict")
		if wd is Dictionary:
			_saved_wanted_data = (wd as Dictionary).duplicate(true)
			var h: Variant = _saved_wanted_data.get("heat", null)
			if h != null:
				_wanted_heat_mirror = maxi(int(h), 0)
	if not _saved_wanted_data.is_empty():
		cfg.set_value("wanted", "data", _saved_wanted_data)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("CampaignManager: could not save %s (err %d)." % [SAVE_PATH, err])
