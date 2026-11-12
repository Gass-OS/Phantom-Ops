extends Node3D

const PlayerScript = preload("res://scripts/player.gd")
const CityScript = preload("res://scripts/kasserine_city_generator.gd")
const WeatherScript = preload("res://scripts/weather.gd")
const SpawnerScript = preload("res://scripts/world_spawner.gd")
const HudScript = preload("res://scripts/hud.gd")

func _ready():
    GameManager.reset_game()

    var city = CityScript.new()
    city.name = "City"
    add_child(city)

    var player = PlayerScript.new()
    player.name = "Player"
    player.position = Vector3(0, 1.0, 12)
    add_child(player)

    var weather = WeatherScript.new()
    weather.name = "Weather"
    add_child(weather)

    var spawner = SpawnerScript.new()
    spawner.name = "Spawner"
    spawner.player = player
    add_child(spawner)

    var hud = HudScript.new()
    hud.name = "HUD"
    hud.player = player
    add_child(hud)
