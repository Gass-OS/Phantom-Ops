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
func start_chapter(chapter: int) -> bool:
	if not is_unlocked(chapter):
		return false
	current_chapter = chapter
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
	_save_now()
	chapter_completed.emit(chapter, xp_reward, money_reward)


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
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("CampaignManager: could not save %s (err %d)." % [SAVE_PATH, err])
