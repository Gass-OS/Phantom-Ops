extends Node3D

const WeatherScript = preload("res://scripts/weather.gd")
const SpawnerScript = preload("res://scripts/world_spawner.gd")

var player: Node3D
var weather: Node
var spawner: Node

func _ready() -> void:
    player = get_node_or_null("Player")

    if player == null:
        push_error("Phantom Ops: Player node missing from MainGame scene.")
        return

    if not get_node_or_null("Weather"):
        weather = WeatherScript.new()
        weather.name = "Weather"
        add_child(weather)

    if not get_node_or_null("WorldSpawner"):
        spawner = SpawnerScript.new()
        spawner.name = "WorldSpawner"
        spawner.player = player
        add_child(spawner)
