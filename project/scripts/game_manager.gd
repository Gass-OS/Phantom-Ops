extends Node

var score: int = 0
var kills: int = 0

func add_score(points: int):
    score += points

func add_kill():
    kills += 1

func reset_game():
    score = 0
    kills = 0
