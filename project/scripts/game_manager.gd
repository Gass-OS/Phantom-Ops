extends Node

signal stats_changed

var score: int = 0
var kills: int = 0
var wave: int = 1

func add_score(points: int):
    score += points
    stats_changed.emit()

func add_kill():
    kills += 1
    add_score(100)

func reset_game():
    score = 0
    kills = 0
    wave = 1
    stats_changed.emit()

func random_road_point() -> Vector3:
    var lines = [-160.0, -80.0, 0.0, 80.0, 160.0]
    var line = lines[randi() % 3]
    var along = randf_range(-220.0, 220.0)
    var p = Vector3(line + randf_range(-3.2, 3.2), 0.9, along)
    if randi() % 2 == 0:
        p = Vector3(along, 0.9, line + randf_range(-3.2, 3.2))
    if Vector2(p.x, p.z).length() < 6.0:
        p.z += 12.0
    return p
