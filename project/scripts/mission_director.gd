extends Node3D
class_name PhantomMissionDirector

var missions := [
	{"title": "SUPPLY RUN", "detail": "Recover the field medical crate", "point": Vector3(28, 0, -34), "reward": 250},
	{"title": "CIVILIAN RESCUE", "detail": "Reach the shelter district", "point": Vector3(-112, 0, 96), "reward": 400},
	{"title": "EXTRACTION", "detail": "Secure the extraction checkpoint", "point": Vector3(150, 0, -150), "reward": 600}
]
var current_index := 0
var objective: Area3D
var mission_label: Label
var status_label: Label

func _ready() -> void:
	_build_mission_hud()
	_start_current_mission()

func _build_mission_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MissionHUD"
	layer.layer = 8
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.custom_minimum_size = Vector2(340, 94)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	mission_label = Label.new()
	mission_label.add_theme_font_size_override("font_size", 21)
	mission_label.add_theme_color_override("font_color", Color(0.95, 0.76, 0.34))
	column.add_child(mission_label)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status_label)

func _start_current_mission() -> void:
	if current_index >= missions.size():
		mission_label.text = "ALL OBJECTIVES COMPLETE"
		status_label.text = "Return to the safe zone. New operations incoming."
		return
	var data: Dictionary = missions[current_index]
	mission_label.text = "OP %02d  //  %s" % [current_index + 1, data.title]
	status_label.text = data.detail + "  •  Reward: %d XP" % data.reward
	_create_objective(data.point)

func _create_objective(point: Vector3) -> void:
	objective = Area3D.new()
	objective.name = "MissionObjective_%02d" % current_index
	objective.position = point
	objective.collision_layer = 0
	objective.collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 3.0
	shape.shape = sphere
	objective.add_child(shape)
	var beacon := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.32
	mesh.bottom_radius = 0.75
	mesh.height = 2.8
	beacon.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.55, 0.12, 0.65)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(1.0, 0.38, 0.06)
	material.emission_energy_multiplier = 2.4
	beacon.material_override = material
	beacon.position.y = 1.4
	objective.add_child(beacon)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 1.4
	ring_mesh.outer_radius = 1.58
	ring.mesh = ring_mesh
	ring.position.y = 0.12
	ring.material_override = material
	objective.add_child(ring)
	add_child(objective)
	objective.body_entered.connect(_on_objective_reached)

func _on_objective_reached(body: Node3D) -> void:
	if not body.is_in_group("player") or objective == null:
		return
	objective.queue_free()
	objective = null
	var reward := int(missions[current_index].reward)
	GameManager.add_score(reward)
	current_index += 1
	_start_current_mission()
