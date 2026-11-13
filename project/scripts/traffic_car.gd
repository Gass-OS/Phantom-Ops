extends CharacterBody3D
class_name PhantomTrafficCar

var route: Array[Vector3] = []
var route_index := 0
var speed := 8.0
var wheel_nodes: Array[Node3D] = []
var body_color := Color(0.12, 0.28, 0.42)

func configure(points: Array[Vector3], tint: Color, cruise_speed: float) -> void:
	route = points
	body_color = tint
	speed = cruise_speed

func _ready() -> void:
	add_to_group("traffic")
	collision_layer = 4
	collision_mask = 1 | 2
	safe_margin = 0.08
	var vehicle_shape := BoxShape3D.new()
	vehicle_shape.size = Vector3(2.05, 1.45, 4.15)
	var vehicle_collision := CollisionShape3D.new()
	vehicle_collision.name = "VehicleCollision"
	vehicle_collision.shape = vehicle_shape
	vehicle_collision.position.y = 0.85
	add_child(vehicle_collision)
	_build_vehicle()

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
	lamp.emission_energy_multiplier = 1.8
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

func _physics_process(delta: float) -> void:
	if route.size() < 2:
		velocity = Vector3.ZERO
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
	velocity = direction * speed
	velocity.y = 0.0
	move_and_slide()
	if direction.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), delta * 3.5)
	for wheel in wheel_nodes:
		wheel.rotate_x(speed * delta * 1.8)
