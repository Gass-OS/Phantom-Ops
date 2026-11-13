extends Node

const CitizenScript = preload("res://scripts/citizen.gd")
const ZombieScript = preload("res://scripts/enemy_ai.gd")

var player = null
var spawn_timer: float = 4.0
var max_zombies: int = 8

func _ready():
    call_deferred("_spawn_initial")

func _spawn_initial():
    for i in range(28):
        var c = CitizenScript.new()
        c.is_female = (i % 2 == 1)
        c.variant = i
        get_parent().add_child(c)
    for i in range(3):
        _spawn_zombie()

func _process(delta):
    if not is_instance_valid(player) or player.is_dead:
        return

    var new_wave = 1 + int(GameManager.kills / 8.0)
    if new_wave != GameManager.wave:
        GameManager.wave = new_wave
        max_zombies = 6 + new_wave * 2
        GameManager.stats_changed.emit()

    spawn_timer -= delta
    if spawn_timer <= 0.0:
        spawn_timer = maxf(2.0, 7.0 - GameManager.wave * 0.4)
        if get_tree().get_nodes_in_group("zombie").size() < max_zombies:
            _spawn_zombie()

func _spawn_zombie():
    var p = GameManager.random_road_point()
    if is_instance_valid(player):
        for i in range(10):
            if p.distance_to(player.global_position) > 28.0:
                break
            p = GameManager.random_road_point()
    var z = ZombieScript.new()
    z.max_health = 50.0 + GameManager.wave * 10.0
    z.position = p
    get_parent().add_child(z)
