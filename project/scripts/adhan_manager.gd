extends Node
class_name AdhanManager
## SYSTEM 5 — ADHAN (Phantom-Ops v0.6 "Kasserine Police").
##
## Plays a REAL human adhan, in full, once, from the mosque, at the dusk
## transition of the day/night cycle. Respectful handling: never looped,
## never truncated, never synthesised, never played twice at once, never
## played while paused or after the player has died.
##
## RECORDING (verified 2026-11-14):
##   File:     "Beautiful adhan" — full adhan, 2 min 34 s, Ogg Vorbis
##             stereo 44.1 kHz, 1,229,032 bytes.
##   Source:   https://commons.wikimedia.org/wiki/File:Beautiful_adhan.ogg
##   Direct:   https://upload.wikimedia.org/wikipedia/commons/b/b0/Beautiful_adhan.ogg
##   Author:   Adam-synagda (Wikimedia Commons user, own work, 2022-04-29)
##   Licence:  CC0 1.0 Universal — Public Domain Dedication
##             https://creativecommons.org/publicdomain/zero/1.0/
##             No attribution required; credit kept here for provenance.
##   SHA-1 (Wikimedia record): a1fa4fd942401922c5c3301816384aae86956522
##   Local copy: res://assets/audio/adhan.ogg
##
## WIRING (for the coordinator):
##   1. Add one AdhanManager node to the main_game scene (or as a child of
##      any node that lives for the whole match). It finds the mosque and
##      the DayNight node by itself — no manual paths needed.
##   2. Menu toggle: call set_enabled(v) / is_enabled(). The ADHAN toggle
##      in the menu should call AdhanManager.set_enabled(); the value is
##      persisted in user://settings.cfg (section "audio", key
##      "adhan_enabled") and survives restarts.
##   3. Dusk trigger: AdhanManager auto-connects to a `dusk_reached`
##      signal on any node in the current scene (scripts/day_night.gd).
##      If that node does not exist yet when this node is ready, the
##      coordinator can simply call play_adhan() when dusk starts.
##   4. Sound on/off: playback follows SoundManager.sound_on (static).
##      Turning sound off mid-adhan stops it; turning it back on does
##      NOT restart it (the adhan is not repeated).

const ADHAN_PATH := "res://assets/audio/adhan.ogg"
const SETTINGS_PATH := "user://settings.cfg"
## Mosque plot (see kasserine_city_generator.gd _build_mosque): the
## "Mosque" node sits at (-75, 0, 75). Used only as a fallback if the
## node cannot be found in the scene tree.
const MOSQUE_POSITION := Vector3(-75, 0, 75)
## Player height above the mosque courtyard (minaret-speaker height).
const MOSQUE_PLAYER_HEIGHT := 18.0
## Base loudness. The recording is a full, dynamic vocal take; -6 dB
## keeps it clear on a phone speaker without clipping over gunfire.
const VOLUME_DB := -6.0

var _enabled := true
var _player: Node = null # AudioStreamPlayer3D (mosque found) or AudioStreamPlayer
var _stream: AudioStream = null
var _wired := false


func _ready() -> void:
	_load_settings()
	# The city generator builds the mosque and the day/night node may be
	# added after this node, so wire up deferred (and re-try lazily in
	# play_adhan() if the first attempt found nothing).
	call_deferred("_wire_up")


func _wire_up() -> void:
	if _wired:
		return
	_wired = true
	_ensure_player()
	_connect_dusk_signal()


func _ensure_player() -> void:
	if _player != null:
		return
	if not FileAccess.file_exists(ADHAN_PATH):
		push_warning("[Adhan] audio file missing: %s — adhan will stay silent." % ADHAN_PATH)
		return
	if _stream == null:
		_stream = load(ADHAN_PATH)
	if _stream == null:
		push_warning("[Adhan] could not load audio stream: %s" % ADHAN_PATH)
		return
	# Never loop the adhan, whatever the stream type.
	if "loop" in _stream:
		_stream.set("loop", false)
	var mosque := _find_mosque()
	if mosque != null:
		var p3d := AudioStreamPlayer3D.new()
		p3d.name = "AdhanPlayer3D"
		p3d.stream = _stream
		p3d.volume_db = VOLUME_DB
		# Audible across the whole 300 m city, fading with distance so
		# it feels like it is coming from the mosque, not the UI.
		p3d.unit_size = 12.0
		p3d.max_distance = 320.0
		p3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3d.position = Vector3(0, MOSQUE_PLAYER_HEIGHT, 0)
		mosque.add_child(p3d)
		_player = p3d
	else:
		# Fallback: mosque node not in this scene (menu / test scene).
		# Still play, non-positionally, rather than crashing.
		var p := AudioStreamPlayer.new()
		p.name = "AdhanPlayer"
		p.stream = _stream
		p.volume_db = VOLUME_DB
		add_child(p)
		_player = p


func _find_mosque() -> Node3D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var mosque := scene.find_child("Mosque", true, false)
	if mosque is Node3D:
		return mosque
	return null


func _connect_dusk_signal() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for node in scene.find_children("*", "Node", true, false):
		if node.has_signal("dusk_reached"):
			if not node.is_connected("dusk_reached", _on_dusk_reached):
				node.connect("dusk_reached", _on_dusk_reached)
			return


func _on_dusk_reached() -> void:
	play_adhan()


## Play the full adhan once. Safe to call any time: every guard below
## makes it a silent no-op instead of an error or a bad playback.
func play_adhan() -> void:
	if not _enabled:
		return
	if not _sound_on():
		return
	if get_tree().paused:
		return
	if _player_is_dead():
		return
	_ensure_player()
	if _player == null or _stream == null:
		push_warning("[Adhan] cannot play: audio unavailable.")
		return
	if _player.playing:
		return # Never play twice at once.
	_player.play()
	print("[Adhan] playing full adhan from the mosque.")


## Stop a playing adhan (e.g. when the player opens the menu mid-adhan).
func stop_adhan() -> void:
	if _player != null and _player.playing:
		_player.stop()


func is_playing() -> bool:
	return _player != null and _player.playing


## ON/OFF toggle for the menu. Persisted immediately so a restart keeps
## the player's choice. Disabling mid-adhan stops it at once.
func set_enabled(v: bool) -> void:
	_enabled = v
	if not _enabled:
		stop_adhan()
	_save_settings()


func is_enabled() -> bool:
	return _enabled


func _sound_on() -> bool:
	# SoundManager is a static-var class (scripts/sound_manager.gd).
	# Guarded via load() so this script still works if that file is ever
	# moved or removed — default is sound ON.
	var sm_script := load("res://scripts/sound_manager.gd")
	if sm_script == null:
		return true
	return bool(sm_script.get("sound_on")) if "sound_on" in sm_script else true


func _player_is_dead() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	for node in scene.find_children("*", "Node", true, false):
		if "is_dead" in node and bool(node.get("is_dead")):
			return true
	return false


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return # No settings yet: default ON.
	_enabled = bool(cfg.get_value("audio", "adhan_enabled", true))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # Keep any other sections other systems saved.
	cfg.set_value("audio", "adhan_enabled", _enabled)
	if cfg.save(SETTINGS_PATH) != OK:
		push_warning("[Adhan] could not save settings to %s" % SETTINGS_PATH)


func _process(_delta: float) -> void:
	# Respect a sound/adhan toggle flipped while the adhan is playing.
	# (Turning sound back on does NOT restart it — the adhan is not repeated.)
	if _player != null and _player.playing:
		if not _enabled or not _sound_on():
			_player.stop()
