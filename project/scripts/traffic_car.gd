extends Node3D
class_name PhantomTrafficCar

var route: Array[Vector3] = []
var route_index := 0
var speed := 8.0
var wheel_nodes: Array[Node3D] = []
var body_color := Color(0.12, 0.28, 0.42)
# v0.6 (System 4): headlights + collision, driven by TrafficManager.
var headlights_on := false
var _lamp_mat: StandardMaterial3D = null
var _taillight_mat: StandardMaterial3D = null
var _spotlights: Array[SpotLight3D] = []

func configure(points: Array[Vector3], tint: Color, cruise_speed: float) -> void:
	route = points
	body_color = tint
	speed = cruise_speed

func _ready() -> void:
	_build_vehicle()
	_build_collision()

## v0.6: one box collider so the player's police car (move_and_slide)
## bumps into traffic instead of driving through it. The body is
## static and rides along as the parent Node3D moves (teleported each
## frame — fine at 6-10 m/s on flat roads).
func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "TrafficCollision"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 1.6, 4.0)
	col.shape = shape
	col.position.y = 0.8
	body.add_child(col)
	add_child(body)

## v0.6: headlights on/off (dusk/night). Emissive boxes are always
## cheap; the two real SpotLights stay disabled unless the manager
## enables them (only for the nearest cars — see traffic_manager.gd).
func set_headlights(on: bool) -> void:
	headlights_on = on
	if _lamp_mat != null:
		_lamp_mat.emission_energy_multiplier = 2.6 if on else 0.25
	if _taillight_mat != null:
		_taillight_mat.emission_energy_multiplier = 2.2 if on else 0.8
	for s in _spotlights:
		s.visible = on
		s.light_energy = 2.5 if on else 0.0

## v0.6: the manager enables real spotlights only on the closest cars.
func set_spotlights_enabled(on: bool) -> void:
	for s in _spotlights:
		s.visible = on and headlights_on
		s.light_energy = 2.5 if (on and headlights_on) else 0.0

func get_current_speed() -> float:
	return speed

func _build_vehicle() -> void:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = body_color
	paint.metallic = 0.48
	paint.roughness = 0.28
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.025, 0.09, 0.12)
	glass.metallic = 0.25
	glass.roughness = 0.16
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.018, 0.02, 0.023)
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1.0, 0.82, 0.52)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.62, 0.25)
	lamp.emission_energy_multiplier = 0.25
	_lamp_mat = lamp
	# v0.6: red taillights (faint by day, bright with the headlights).
	var tail := StandardMaterial3D.new()
	tail.albedo_color = Color(0.55, 0.05, 0.04)
	tail.emission_enabled = true
	tail.emission = Color(0.85, 0.08, 0.05)
	tail.emission_energy_multiplier = 0.8
	_taillight_mat = tail
	_box("Chassis", Vector3(2.0, 0.62, 4.0), Vector3(0, 0.72, 0), paint)
	_box("Cabin", Vector3(1.68, 0.78, 2.0), Vector3(0, 1.34, -0.18), glass)
	_box("Bonnet", Vector3(1.82, 0.24, 1.05), Vector3(0, 1.02, -1.38), paint)
	_box("FrontBumper", Vector3(2.02, 0.18, 0.16), Vector3(0, 0.48, -2.02), rubber)
	for side in [-1.0, 1.0]:
		for axle in [-1.25, 1.28]:
			var wheel := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.37
			cylinder.bottom_radius = 0.37
			cylinder.height = 0.22
			wheel.mesh = cylinder
			wheel.material_override = rubber
			wheel.position = Vector3(side * 1.02, 0.42, axle)
			wheel.rotation.z = PI * 0.5
			add_child(wheel)
			wheel_nodes.append(wheel)
		_box("Headlight", Vector3(0.34, 0.18, 0.08), Vector3(side * 0.68, 0.82, -2.04), lamp)
		_box("Taillight", Vector3(0.34, 0.16, 0.08), Vector3(side * 0.68, 0.82, 2.04), tail)
		# v0.6: real headlight beam, created disabled — the manager
		# switches it on only for the nearest cars (Mobile light budget).
		var spot := SpotLight3D.new()
		spot.name = "HeadlightBeam"
		spot.position = Vector3(side * 0.68, 0.82, -2.0)
		spot.rotation_degrees = Vector3(-6, 0, 0)
		spot.light_color = Color(1.0, 0.9, 0.65)
		spot.light_energy = 0.0
		spot.spot_range = 22.0
		spot.spot_angle = 32.0
		spot.shadow_enabled = false
		spot.visible = false
		add_child(spot)
		_spotlights.append(spot)
	_box("Roof", Vector3(1.7, 0.12, 1.92), Vector3(0, 1.76, -0.18), paint)

func _box(label: String, dimensions: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	add_child(instance)

func _process(delta: float) -> void:
	if route.size() < 2:
		return
	var destination := route[route_index]
	var offset := destination - global_position
	offset.y = 0.0
	if offset.length() < 2.5:
		route_index = (route_index + 1) % route.size()
		destination = route[route_index]
		offset = destination - global_position
		offset.y = 0.0
	var direction := offset.normalized()
	global_position += direction * speed * delta
	if direction.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), delta * 3.5)
	for wheel in wheel_nodes:
		wheel.rotate_x(speed * delta * 1.8)
