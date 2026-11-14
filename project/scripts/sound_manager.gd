extends Node
class_name SoundManager
## v0.3 — all sound is generated procedurally at runtime (AudioStreamWAV,
## 16-bit PCM, 22050 Hz). No .wav/.mp3 assets in the repo.
## Mute state is a static var so the pause-menu toggle, the player and
## the main menu all share it, even though each scene owns its own
## SoundManager node (no new autoload).

const MIX_RATE := 22050
static var sound_on := true
## v0.4: spoken greetings are best-effort only (see greet()).
static var voices_on := true
static var _cache: Dictionary = {}
static var _last_greet_msec := 0
var _wind_player: AudioStreamPlayer = null
var _murmur_player: AudioStreamPlayer = null

# ---------------------------------------------------------------- helpers
static func _pack(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v := clampf(samples[i], -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream

static func _tone(freq: float, dur: float, vol: float, decay: float, freq_end: float = -1.0) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / MIX_RATE
		var f := freq if freq_end < 0.0 else lerpf(freq, freq_end, t / dur)
		phase += TAU * f / MIX_RATE
		var env := exp(-decay * t)
		samples[i] = sin(phase) * vol * env
	return _pack(samples)

static func _noise(dur: float, vol: float, decay: float, smooth: float = 0.0) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var last := 0.0
	for i in range(n):
		var t := float(i) / MIX_RATE
		var white := rng.randf_range(-1.0, 1.0)
		last = lerpf(white, last, smooth)
		samples[i] = last * vol * exp(-decay * t)
	return _pack(samples)

static func _mix(a: AudioStreamWAV, b: AudioStreamWAV) -> AudioStreamWAV:
	var da := a.data
	var db := b.data
	var n := maxi(da.size(), db.size()) / 2
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in range(n):
		var va := 0.0
		var vb := 0.0
		if i * 2 + 1 < da.size():
			va = float(da.decode_s16(i * 2)) / 32767.0
		if i * 2 + 1 < db.size():
			vb = float(db.decode_s16(i * 2)) / 32767.0
		samples[i] = va + vb
	return _pack(samples)

static func _concat(parts: Array) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	for part in parts:
		var d: PackedByteArray = (part as AudioStreamWAV).data
		for i in range(d.size() / 2):
			samples.append(float(d.decode_s16(i * 2)) / 32767.0)
	return _pack(samples)

static func _silence(dur: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	return _pack(samples)

static func _cached_stream(key: String, builder: Callable) -> AudioStreamWAV:
	if not _cache.has(key):
		_cache[key] = builder.call()
	return _cache[key]

# ---------------------------------------------------------------- sounds
static func shot_stream() -> AudioStreamWAV:
	return _cached_stream("shot", func() -> AudioStreamWAV:
		return _mix(_noise(0.16, 0.9, 55.0, 0.25), _tone(95.0, 0.14, 0.7, 30.0, 55.0)))

static func reload_stream() -> AudioStreamWAV:
	return _cached_stream("reload", func() -> AudioStreamWAV:
		var click := _noise(0.05, 0.55, 120.0, 0.1)
		var clack := _mix(_noise(0.06, 0.65, 100.0, 0.1), _tone(900.0, 0.05, 0.25, 90.0))
		return _concat([click, _silence(0.14), clack, _silence(0.12), click]))

static func reload_done_stream() -> AudioStreamWAV:
	return _cached_stream("reload_done", func() -> AudioStreamWAV:
		return _mix(_noise(0.05, 0.5, 120.0, 0.1), _tone(1300.0, 0.06, 0.3, 80.0)))

static func hit_stream() -> AudioStreamWAV:
	return _cached_stream("hit", func() -> AudioStreamWAV:
		return _tone(1800.0, 0.07, 0.45, 70.0))

static func kill_stream() -> AudioStreamWAV:
	return _cached_stream("kill", func() -> AudioStreamWAV:
		return _concat([_tone(660.0, 0.12, 0.5, 12.0), _tone(880.0, 0.16, 0.5, 12.0)]))

static func enemy_death_stream() -> AudioStreamWAV:
	return _cached_stream("enemy_death", func() -> AudioStreamWAV:
		return _mix(_tone(300.0, 0.3, 0.5, 8.0, 110.0), _noise(0.25, 0.3, 18.0, 0.5)))

static func hurt_stream() -> AudioStreamWAV:
	return _cached_stream("hurt", func() -> AudioStreamWAV:
		return _tone(180.0, 0.18, 0.6, 22.0, 90.0))

static func click_stream() -> AudioStreamWAV:
	return _cached_stream("click", func() -> AudioStreamWAV:
		return _tone(1000.0, 0.06, 0.4, 90.0))

static func horn_stream() -> AudioStreamWAV:
	return _cached_stream("horn", func() -> AudioStreamWAV:
		var a := _tone(220.0, 0.6, 0.35, 2.5)
		var b := _tone(330.0, 0.6, 0.25, 2.5)
		return _mix(a, b))

static func step_stream() -> AudioStreamWAV:
	return _cached_stream("step", func() -> AudioStreamWAV:
		return _noise(0.08, 0.28, 55.0, 0.6))

static func wind_stream() -> AudioStreamWAV:
	return _cached_stream("wind", func() -> AudioStreamWAV:
		var s := _noise(2.0, 0.22, 0.0, 0.92)
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(MIX_RATE * 2.0)
		return s)

## v0.4: soft market murmur — low smoothed noise with quiet voice-like
## tone blips, looped. No real speech, no prayer audio.
static func murmur_stream() -> AudioStreamWAV:
	return _cached_stream("murmur", func() -> AudioStreamWAV:
		var base := _noise(3.0, 0.10, 0.0, 0.96)
		var voices := _concat([
			_tone(190.0, 0.25, 0.10, 6.0), _silence(0.3),
			_tone(240.0, 0.2, 0.08, 6.0), _silence(0.5),
			_tone(160.0, 0.3, 0.09, 6.0), _silence(0.4),
			_tone(280.0, 0.18, 0.07, 6.0), _silence(0.6),
			_tone(210.0, 0.22, 0.08, 6.0), _silence(0.32)])
		var s := _mix(base, voices)
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(MIX_RATE * 3.0)
		return s)

## v0.4: drone whoosh — a rising/falling noise sweep for the intro.
static func whoosh_stream() -> AudioStreamWAV:
	return _cached_stream("whoosh", func() -> AudioStreamWAV:
		return _noise(1.4, 0.5, 2.0, 0.55))

# ---------------------------------------------------------------- playback
func _play(stream: AudioStreamWAV, vol_db: float = 0.0) -> void:
	if not sound_on:
		return
	if not is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol_db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

func play_shot() -> void:
	_play(shot_stream(), -4.0)

func play_reload() -> void:
	_play(reload_stream(), -6.0)

func play_reload_done() -> void:
	_play(reload_done_stream(), -6.0)

func play_hit() -> void:
	_play(hit_stream(), -8.0)

func play_kill() -> void:
	_play(kill_stream(), -6.0)

func play_enemy_death() -> void:
	_play(enemy_death_stream(), -8.0)

func play_hurt() -> void:
	_play(hurt_stream(), -6.0)

func play_click() -> void:
	_play(click_stream(), -8.0)

func play_horn() -> void:
	_play(horn_stream(), -8.0)

func play_step() -> void:
	_play(step_stream(), -12.0)

func play_whoosh() -> void:
	_play(whoosh_stream(), -8.0)

func start_murmur() -> void:
	if not is_inside_tree():
		return
	if _murmur_player != null:
		if sound_on and not _murmur_player.playing:
			_murmur_player.play()
		return
	_murmur_player = AudioStreamPlayer.new()
	_murmur_player.stream = murmur_stream()
	_murmur_player.volume_db = -20.0
	add_child(_murmur_player)
	if sound_on:
		_murmur_player.play()

func stop_murmur() -> void:
	if _murmur_player != null:
		_murmur_player.queue_free()
		_murmur_player = null

## v0.4: Tunisian greeting via the OS text-to-speech, best-effort only.
## Guarded by has_feature() so a device / headless run without TTS
## simply stays silent — it can never crash the game. Throttled to one
## greeting every 8 seconds. Lines are plain greetings only.
static func greet() -> void:
	if not sound_on or not voices_on:
		return
	if Time.get_ticks_msec() - _last_greet_msec < 8000:
		return
	_last_greet_msec = Time.get_ticks_msec()
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return
	var lines := ["Salam", "Marhaba", "Salam alaykum", "Ahla wa sahla"]
	# Godot 4.2 names the call tts_speak (tts() does not exist).
	DisplayServer.tts_speak(lines[randi() % lines.size()], "", 50, 1.0, 1.0, 0, false)

static func set_voices_on(v: bool) -> void:
	voices_on = v

func start_wind() -> void:
	if not is_inside_tree():
		return
	if _wind_player != null:
		if sound_on and not _wind_player.playing:
			_wind_player.play()
		return
	_wind_player = AudioStreamPlayer.new()
	_wind_player.stream = wind_stream()
	_wind_player.volume_db = -18.0
	add_child(_wind_player)
	if sound_on:
		_wind_player.play()

func stop_wind() -> void:
	if _wind_player != null:
		_wind_player.queue_free()
		_wind_player = null

static func set_sound_on(v: bool) -> void:
	sound_on = v
