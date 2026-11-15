class_name AmmoPickup
extends Node3D
## v0.8 — ammo pickup dropped by dead enemies (25% chance, via
## WeaponManager) or by the WeaponManager fallback timer.
## Small glowing olive ammo box, bobs + spins. Collected when the
## player (group "player") comes within 2.0 m: emits `collected`
## and frees itself. Despawns after 60 s so the scene never fills
## with stale pickups.

signal collected(weapon_id: String, amount: int)

const COLLECT_RADIUS := 2.0
const LIFETIME := 60.0

var weapon_id := "rifle"
var amount := 30
var _collected := false
var _base_y := 0.6
var _age := 0.0
var _phase := 0.0
var _glow: OmniLight3D


func _ready() -> void:
	_phase = randf() * TAU
	_build()


func _build() -> void:
	var olive := StandardMaterial3D.new()
	olive.albedo_color = Color(0.25, 0.32, 0.12)
	olive.roughness = 0.7
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.14, 0.08)
	dark.roughness = 0.8
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.4, 0.9, 0.25)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.35, 0.85, 0.2)
	glow_mat.emission_energy_multiplier = 2.0
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var box := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.45, 0.28, 0.32)
	box_mesh.material = olive
	box.mesh = box_mesh
	add_child(box)
	var lid := MeshInstance3D.new()
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(0.47, 0.08, 0.34)
	lid_mesh.material = dark
	lid.mesh = lid_mesh
	lid.position = Vector3(0, 0.17, 0)
	add_child(lid)
	var stripe := MeshInstance3D.new()
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(0.46, 0.06, 0.33)
	stripe_mesh.material = glow_mat
	stripe.mesh = stripe_mesh
	stripe.position = Vector3(0, 0.0, 0)
	add_child(stripe)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(0.5, 1.0, 0.3)
	_glow.light_energy = 0.8
	_glow.omni_range = 4.0
	_glow.position = Vector3(0, 0.3, 0)
	add_child(_glow)


## `position` is the world position to spawn at. Uses
## global_position (not the shadowed `position` property name).
func setup(p_weapon_id: String, p_amount: int, position: Vector3) -> void:
	weapon_id = p_weapon_id
	amount = maxi(p_amount, 1)
	global_position = position
	_base_y = position.y


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	rotation.y += delta * 1.5
	position.y = _base_y + sin(_age * 2.5 + _phase) * 0.15
	var tree := get_tree()
	if tree == null:
		return
	var player := tree.get_first_node_in_group("player") as Node3D
	if player == null:
		return
	if global_position.distance_to(player.global_position) < COLLECT_RADIUS:
		# Guard: queue_free() is deferred to end-of-frame, so a
		# second _process tick before the free must not pay out twice.
		if _collected:
			return
		_collected = true
		collected.emit(weapon_id, amount)
		queue_free()
