extends Node3D
class_name CitizenSpawner
## v0.4 — spawns respectful Tunisian civilians using citizen.gd as-is.
## Deliberately simple: no GameManager dependencies (the old
## world_spawner.gd used GameManager.wave / stats_changed /
## random_road_point(), which do not exist in the current GameManager).
## ~24 citizens, half men / half women, varied variants. citizen.gd
## places each one on a sidewalk lane and walks it; men wear a long
## jebba + chechia (some bearded), women a long dress + hijab.
## Civilians are in group "civilian" and have NO take_damage — the
## player fire code explicitly skips that group (see player.gd).
## v0.6 — the trait rates live here as exports and are handed to each
## citizen before it enters the tree (citizen.gd rolls its hidden
## is_criminal / is_poor / is_funny flags in _ready from these):
##   ~15% of men are criminals in disguise, ~20% are poor/begging,
##   ~25% are funny. Rates are chances, not guarantees.

@export var citizen_count: int = 24
@export var criminal_chance: float = 0.15
@export var poor_chance: float = 0.20
@export var funny_chance: float = 0.25

func _ready() -> void:
	# Deferred: add_child during scene setup fails.
	call_deferred("_spawn_all")

func _spawn_all() -> void:
	var citizen_script: Script = load("res://scripts/citizen.gd") as Script
	if citizen_script == null:
		push_warning("CitizenSpawner: citizen.gd not found, no citizens spawned")
		return
	for i in range(citizen_count):
		var c := CharacterBody3D.new()
		c.name = "Citizen_%02d" % i
		c.set_script(citizen_script)
		c.set("is_female", i % 2 == 1)
		c.set("variant", i)
		c.set("criminal_chance", criminal_chance)
		c.set("poor_chance", poor_chance)
		c.set("funny_chance", funny_chance)
		add_child(c)
	print("Phantom Ops: %d citizens in the city" % citizen_count)
