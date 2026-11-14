extends Node

signal score_changed(score: int, kills: int)

var score: int = 0
var kills: int = 0

func add_score(points: int):
	score += points
	score_changed.emit(score, kills)

func add_kill():
	kills += 1
	score_changed.emit(score, kills)

func reset_game():
	score = 0
	kills = 0
	score_changed.emit(score, kills)
