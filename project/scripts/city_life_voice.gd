extends Node

@export var enabled := true
@export var minimum_interval := 18.0
@export var maximum_interval := 30.0

var timer := 2.5
var prayer_timer := 180.0
var prayer_voice_id := ""
var voice_id := ""
var voice_locale := "en"

func _ready() -> void:
	if not enabled:
		return
	randomize()
	var voices: Array = DisplayServer.tts_get_voices()
	if voices.is_empty():
		print("PHANTOM OPS: Android TTS returned no installed voices; install/enable a system speech engine in Android settings")
		return
	# Select Arabic independently for respectful prayer reminders.
	for voice in voices:
		if str(voice.get("language", "")).to_lower().begins_with("ar"):
			prayer_voice_id = str(voice.get("id", ""))
			break
	# Prefer French for the Tunisian city ambience, then Arabic, then English.
	for wanted in ["fr", "ar", "en"]:
		for voice in voices:
			var locale := str(voice.get("language", "")).to_lower()
			if locale.begins_with(wanted):
				voice_id = str(voice.get("id", ""))
				voice_locale = wanted
				break
		if not voice_id.is_empty():
			break
	if voice_id.is_empty():
		voice_id = str(voices[0].get("id", ""))
	timer = 2.5

func _process(delta: float) -> void:
	prayer_timer -= delta
	if prayer_timer <= 0.0 and not prayer_voice_id.is_empty() and not DisplayServer.tts_is_speaking():
		prayer_timer = 300.0
		_announce_prayer_reminder.call_deferred()
	if not enabled or voice_id.is_empty():
		return
	timer -= delta
	if timer > 0.0:
		return
	if DisplayServer.tts_is_speaking():
		timer = 8.0
		return
	var phrases: Array[String] = []
	match voice_locale:
		"fr":
			phrases = [
				"Bonjour, bienvenue dans le quartier.",
				"Les fruits et les légumes sont frais aujourd'hui.",
				"La pharmacie est ouverte.",
				"Attention, une voiture arrive.",
				"Bonne journée, prenez soin de vous."
			]
		"ar":
			phrases = [
				"السلام عليكم، مرحبا بيكم في الحومة.",
				"الغلة والخضرة طازجة اليوم.",
				"الصيدلية محلولة.",
				"بالكم، كرهبة جاية.",
				"السلام عليكم، ربي يحفظكم.",
				"تذكير لطيف: لا تنسوا الصلاة، ربي يتقبل."
			]
		_:
			phrases = [
				"Welcome to the neighborhood.",
				"Fresh fruit and vegetables today.",
				"The pharmacy is open.",
				"Watch out, a car is coming."
			]
	var phrase := phrases[randi() % phrases.size()]
	DisplayServer.tts_speak(phrase, voice_id, 100, 1.0, 0.95, 1, true)
	print("PHANTOM OPS: ambient voice requested: ", voice_locale, " voice=", voice_id)
	timer = randf_range(minimum_interval, maximum_interval)

func _announce_prayer_reminder() -> void:
	_play_soft_chime()
	await get_tree().create_timer(0.32).timeout
	if is_inside_tree() and not prayer_voice_id.is_empty():
		DisplayServer.tts_speak("اللهم صل وسلم على نبينا محمد. تذكير لطيف: لا تنسوا الصلاة.", prayer_voice_id, 88, 1.0, 0.92, 1, true)

func _play_soft_chime() -> void:
	var player := AudioStreamPlayer.new()
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 22050
	stream.buffer_length = 0.35
	player.stream = stream
	player.volume_db = -15.0
	add_child(player)
	player.play()
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		player.queue_free()
		return
	var sample_rate := 22050.0
	for i in range(6200):
		var time := float(i) / sample_rate
		var frequency := 660.0 if time < 0.14 else 880.0
		var envelope := minf(time / 0.025, 1.0) * maxf(0.0, 1.0 - time / 0.29)
		var sample := sin(TAU * frequency * time) * envelope * 0.12
		if not playback.push_frame(Vector2(sample, sample)):
			break
	await get_tree().create_timer(0.4).timeout
	if is_instance_valid(player):
		player.queue_free()

func _exit_tree() -> void:
	if not voice_id.is_empty():
		DisplayServer.tts_stop()
