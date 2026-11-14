extends Node

signal score_changed(score: int, kills: int)
# v0.6: player money in Tunisian dinars. Earned by missions (the
# mission worker awards it via add_money); spent on GIVE interactions
# via spend_money(). InteractionManager shows it in its own HUD label.
signal money_changed(money: int)

var score: int = 0
var kills: int = 0
var money: int = 0

func add_score(points: int):
	score += points
	score_changed.emit(score, kills)

func add_kill():
	kills += 1
	score_changed.emit(score, kills)

func add_money(amount: int):
	if amount <= 0:
		return
	money += amount
	money_changed.emit(money)

# Returns true and deducts only when the player can afford it.
func spend_money(amount: int) -> bool:
	if amount <= 0:
		return true
	if money < amount:
		return false
	money -= amount
	money_changed.emit(money)
	return true

func reset_game():
	score = 0
	kills = 0
	money = 0
	score_changed.emit(score, kills)
	money_changed.emit(money)
