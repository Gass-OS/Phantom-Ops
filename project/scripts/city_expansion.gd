extends Node3D
class_name PhantomCityExpansion

const TrafficCar = preload("res://scripts/traffic_car.gd")
const Citizen = preload("res://scripts/citizen.gd")

@export_range(1, 4) var district_radius := 2
@export var block_spacing := 80.0
@export var traffic_count := 14
@export var extra_citizens := 30

var rng := RandomNumberGenerator.new()
var wall_mats: Array[StandardMaterial3D] = []
var glass_mat: StandardMaterial3D
var trim_mat: StandardMaterial3D

func _ready() -> void:
	rng.seed = 13112026
	_make_materials()
	_expand_ground()
	_build_city_grid()
	_build_traffic()
	_build_street_props()
	_spawn_residents()
	print("PHANTOM OPS: expanded districts, traffic and city life ready")

func _make_materials() -> void:
	for color in [
		Color(0.55, 0.48, 0.38), Color(0.39, 0.44, 0.46),
		Color(0.68, 0.61, 0.49), Color(0.34, 0.39, 0.36),
		Color(0.49, 0.40, 0.34), Color(0.62, 0.58, 0.50)
	]:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.88
		wall_mats.append(m)
	glass_mat = StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.025, 0.12, 0.17)
	glass_mat.metallic = 0.42
	glass_mat.roughness = 0.18
	trim_mat = StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.12, 0.14, 0.15)
	trim_mat.roughness = 0.7

func _expand_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "ExpandedDistrictGround"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(640, 0.5, 640)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.27, 0.25)
	material.roughness = 1.0
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position.y = -0.30
	ground.add_child(visual)
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = -0.30
	ground.add_child(collision)
	add_child(ground)

func _build_city_grid() -> void:
	for grid in range(-district_radius, district_radius + 1):
		var road := StandardMaterial3D.new()
		road.albedo_color = Color(0.055, 0.065, 0.073)
		road.roughness = 0.96
		_add_box("DistrictRoadX_%d" % grid, Vector3(640, 0.035, 13), Vector3(0, 0.012, grid * block_spacing), road)
		_add_box("DistrictRoadZ_%d" % grid, Vector3(13, 0.035, 640), Vector3(grid * block_spacing, 0.013, 0), road)
	for gx in range(-district_radius, district_radius):
		for gz in range(-district_radius, district_radius):
			var center := Vector3((gx + 0.5) * block_spacing, 0, (gz + 0.5) * block_spacing)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var offset := Vector3(sx * 18.0, 0, sz * 18.0)
					_create_building(center + offset, (gx * 17 + gz * 7 + int(sx + 2) + int(sz + 2)) & 0x7fffffff)

func _create_building(at: Vector3, seed_value: int) -> void:
	var height := rng.randf_range(9.0, 23.0)
	var width := rng.randf_range(13.0, 20.0)
	var depth := rng.randf_range(13.0, 20.0)
	var body := StaticBody3D.new()
	body.name = "DistrictBuilding_%d" % seed_value
	body.position = at
	add_child(body)
	var wall := wall_mats[seed_value % wall_mats.size()]
	_add_box_to(body, "ConcreteFacade", Vector3(width, height, depth), Vector3(0, height * 0.5, 0), wall)
	var collision := CollisionShape3D.new()
	var collision_box := BoxShape3D.new()
	collision_box.size = Vector3(width, height, depth)
	collision.shape = collision_box
	collision.position.y = height * 0.5
	body.add_child(collision)
	_add_box_to(body, "RoofParapet", Vector3(width + 0.5, 0.55, depth + 0.5), Vector3(0, height + 0.25, 0), trim_mat)
	_add_box_to(body, "ShopFront", Vector3(width * 0.72, 2.6, 0.14), Vector3(0, 1.3, -depth * 0.505), glass_mat)
	var floors := int(height / 3.2)
	for floor in range(1, floors):
		for side in [-1.0, 1.0]:
			var wx: float = float(side) * width * 0.27
			var wy := floor * 3.0
			_add_box_to(body, "WindowFrame", Vector3(2.0, 1.65, 0.18), Vector3(wx, wy, -depth * 0.505), trim_mat)
			_add_box_to(body, "WindowGlass", Vector3(1.65, 1.34, 0.08), Vector3(wx, wy, -depth * 0.515), glass_mat)
			_add_box_to(body, "SideGlass", Vector3(0.10, 1.4, 1.8), Vector3(width * 0.505, wy, 0), glass_mat)
	_add_box_to(body, "Balcony", Vector3(width * 0.78, 0.16, 1.15), Vector3(0, 3.0, -depth * 0.55), trim_mat)
	if seed_value % 4 == 0:
		_add_box_to(body, "ShopAwning", Vector3(width * 0.9, 0.22, 1.8), Vector3(0, 3.0, -depth * 0.58), _awning_material(seed_value))

func _awning_material(seed_value: int) -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = [Color(0.65,0.12,0.08), Color(0.12,0.28,0.42), Color(0.72,0.61,0.35)][seed_value % 3]
	m.roughness = 0.8
	return m

func _add_box_to(parent: Node3D, label: String, dimensions: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	visual.material_override = material
	visual.position = at
	parent.add_child(visual)

func _add_box(label: String, dimensions: Vector3, at: Vector3, material: Material) -> void:
	_add_box_to(self, label, dimensions, at, material)

func _build_traffic() -> void:
	var colors := [Color(0.72,0.12,0.08), Color(0.08,0.24,0.55), Color(0.72,0.68,0.55), Color(0.10,0.12,0.13), Color(0.52,0.53,0.52)]
	var extent := float(district_radius) * block_spacing
	var loop: Array[Vector3] = [
		Vector3(-extent, 0, -extent), Vector3(extent, 0, -extent),
		Vector3(extent, 0, extent), Vector3(-extent, 0, extent)
	]
	for i in range(traffic_count):
		var car = TrafficCar.new()
		car.configure(loop, colors[i % colors.size()], rng.randf_range(5.5, 10.0))
		add_child(car)
		var phase := float(i) / float(maxi(1, traffic_count))
		car.position = loop[0].lerp(loop[1], phase)
		car.position.y = 0.0

func _build_street_props() -> void:
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.10, 0.11, 0.12)
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.72, 0.38)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.55, 0.2)
	lamp_mat.emission_energy_multiplier = 2.0
	for i in range(-district_radius, district_radius + 1):
		for side in [-1.0, 1.0]:
			var pole := Node3D.new()
			pole.position = Vector3(side * 10.0, 0, i * block_spacing)
			add_child(pole)
			_add_box_to(pole, "LampPost", Vector3(0.16, 5.2, 0.16), Vector3(0, 2.6, 0), pole_mat)
			_add_box_to(pole, "LampHead", Vector3(0.8, 0.16, 0.3), Vector3(-0.35, 5.05, 0), lamp_mat)
			var light := OmniLight3D.new()
			light.position = Vector3(-0.35, 4.9, 0)
			light.light_color = Color(1.0, 0.68, 0.4)
			light.light_energy = 0.8
			light.omni_range = 11.0
			pole.add_child(light)

func _spawn_residents() -> void:
	for i in range(extra_citizens):
		var person = Citizen.new()
		person.is_female = (i % 2 == 1)
		person.variant = i + 20
		add_child(person)
		person.position = Vector3(rng.randf_range(-210, 210), 0.9, rng.randf_range(-210, 210))
