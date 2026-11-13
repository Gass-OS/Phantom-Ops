extends Node

@export var enabled := true
@export var minimum_interval := 18.0
@export var maximum_interval := 30.0

var timer := 5.0
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
	# Prefer French for the Tunisian city ambience, then Arabic, then English.
	for wanted in ["fr", "ar", "en"]:
		for voice in voices:
			var locale := str(voice.get("locale", "")).to_lower()
			if locale.begins_with(wanted):
				voice_id = str(voice.get("id", ""))
				voice_locale = wanted
				break
		if not voice_id.is_empty():
			break
	if voice_id.is_empty():
		voice_id = str(voices[0].get("id", ""))
	timer = randf_range(minimum_interval, maximum_interval)

func _process(delta: float) -> void:
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
				"بالكم، كرهبة جاية."
			]
		_:
			phrases = [
				"Welcome to the neighborhood.",
				"Fresh fruit and vegetables today.",
				"The pharmacy is open.",
				"Watch out, a car is coming."
			]
	var phrase := phrases[randi() % phrases.size()]
	DisplayServer.tts_speak(phrase, voice_id, 1.0, 1.0, 0.95, 1)
	print("PHANTOM OPS: ambient voice requested: ", voice_locale)
	timer = randf_range(minimum_interval, maximum_interval)

func _exit_tree() -> void:
	if not voice_id.is_empty():
		DisplayServer.tts_stop()
