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

# v0.7: XP lives in CampaignManager, never here. add_xp forwards
# to it (missions, kills, helping citizens) and returns true only
# when a rank threshold was crossed. Safe when CampaignManager is
# absent (e.g. a bare scene test): returns false, nothing lost.
func add_xp(amount: int) -> bool:
	var cm := get_node_or_null("/root/CampaignManager")
	if cm != null and cm.has_method("add_xp"):
		return bool(cm.call("add_xp", amount))
	return false

func reset_game():
	score = 0
	kills = 0
	money = 0
	# v0.7 SAVE TRAP: reset_game() runs on every game start
	# (player._ready, RETRY, menu), but campaign money is persistent
	# — it must survive the reset. Restore the saved amount here,
	# BEFORE money_changed is emitted, so no listener ever sees the
	# zeroed value. Fresh save = 0, so this is a no-op then.
	var cm := get_node_or_null("/root/CampaignManager")
	if cm != null and cm.has_method("get_saved_money"):
		money = int(cm.get_saved_money())
	score_changed.emit(score, kills)
	money_changed.emit(money)
