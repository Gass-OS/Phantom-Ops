extends Node3D
class_name PhantomCityExpansion

const TrafficCar = preload("res://scripts/traffic_car.gd")
const Citizen = preload("res://scripts/citizen.gd")

@export_range(2, 5) var district_radius := 3
@export var block_spacing := 56.0
@export var traffic_count := 18
@export var extra_citizens := 64

var rng := RandomNumberGenerator.new()
var wall_mats: Array[StandardMaterial3D] = []
var glass_mat: StandardMaterial3D
var trim_mat: StandardMaterial3D
var road_mat: StandardMaterial3D
var sidewalk_mat: StandardMaterial3D
var line_mat: StandardMaterial3D

func _ready() -> void:
	rng.seed = 13112026
	_make_materials()
	_expand_ground()
	_build_city_grid()
	_build_traffic()
	_build_street_props()
	_spawn_residents()
	print("PHANTOM OPS: dense city generated; buildings, pedestrians and traffic active")

func _make_materials() -> void:
	for color in [
		Color(0.61, 0.54, 0.43), Color(0.43, 0.48, 0.49),
		Color(0.73, 0.66, 0.54), Color(0.38, 0.44, 0.39),
		Color(0.54, 0.43, 0.35), Color(0.66, 0.62, 0.54)
	]:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.92
		wall_mats.append(m)
	glass_mat = StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.025, 0.12, 0.17)
	glass_mat.metallic = 0.35
	glass_mat.roughness = 0.2
	trim_mat = StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.12, 0.14, 0.15)
	trim_mat.roughness = 0.78
	road_mat = StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.065, 0.073, 0.078)
	road_mat.roughness = 0.98
	sidewalk_mat = StandardMaterial3D.new()
	sidewalk_mat.albedo_color = Color(0.48, 0.47, 0.42)
	sidewalk_mat.roughness = 1.0
	line_mat = StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.82, 0.79, 0.67)

func _expand_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "ExpandedDistrictGround"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(680, 0.5, 680)
	mesh.material = _ground_material()
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

func _ground_material() -> Material:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.29, 0.31, 0.28)
	material.roughness = 1.0
	return material

func _build_city_grid() -> void:
	var extent := float(district_radius) * block_spacing
	for grid in range(-district_radius, district_radius + 1):
		var road_z := float(grid) * block_spacing
		var road_x := float(grid) * block_spacing
		_add_box("DistrictRoadX_%d" % grid, Vector3(680, 0.07, 13), Vector3(0, 0.025, road_z), road_mat)
		_add_box("DistrictRoadZ_%d" % grid, Vector3(13, 0.07, 680), Vector3(road_x, 0.026, 0), road_mat)
		_add_box("SidewalkNorth_%d" % grid, Vector3(680, 0.12, 2.4), Vector3(0, 0.11, road_z - 8.0), sidewalk_mat)
		_add_box("SidewalkSouth_%d" % grid, Vector3(680, 0.12, 2.4), Vector3(0, 0.11, road_z + 8.0), sidewalk_mat)
		_add_box("SidewalkWest_%d" % grid, Vector3(2.4, 0.12, 680), Vector3(road_x - 8.0, 0.11, 0), sidewalk_mat)
		_add_box("SidewalkEast_%d" % grid, Vector3(2.4, 0.12, 680), Vector3(road_x + 8.0, 0.11, 0), sidewalk_mat)
		_add_box("RoadDashX_%d" % grid, Vector3(680, 0.025, 0.18), Vector3(0, 0.075, road_z), line_mat)
		_add_box("RoadDashZ_%d" % grid, Vector3(0.18, 0.025, 680), Vector3(road_x, 0.076, 0), line_mat)

	for gx in range(-district_radius, district_radius):
		for gz in range(-district_radius, district_radius):
			var center := Vector3((float(gx) + 0.5) * block_spacing, 0, (float(gz) + 0.5) * block_spacing)
			# Four close-packed buildings per block, with varied heights and footprints.
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var offset := Vector3(sx * 9.2, 0, sz * 9.2)
					var seed_value := (gx * 97 + gz * 31 + int(sx + 2) * 11 + int(sz + 2) * 7) & 0x7fffffff
					_create_building(center + offset, seed_value)
	# Continuous outer boulevard defines a readable city boundary.
	_add_box("OuterBoulevardNorth", Vector3(680, 0.08, 14), Vector3(0, 0.02, -extent - 16), road_mat)
	_add_box("OuterBoulevardSouth", Vector3(680, 0.08, 14), Vector3(0, 0.02, extent + 16), road_mat)
	_add_box("OuterBoulevardWest", Vector3(14, 0.08, 680), Vector3(-extent - 16, 0.02, 0), road_mat)
	_add_box("OuterBoulevardEast", Vector3(14, 0.08, 680), Vector3(extent + 16, 0.02, 0), road_mat)

func _create_building(at: Vector3, seed_value: int) -> void:
	var height := rng.randf_range(8.5, 22.0)
	var width := rng.randf_range(14.0, 16.8)
	var depth := rng.randf_range(14.0, 18.5)
	var body := StaticBody3D.new()
	body.name = "DistrictBuilding_%d" % seed_value
	body.add_to_group("city_building")
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
	_add_box_to(body, "ShopDoor", Vector3(1.25, 2.45, 0.12), Vector3(width * 0.29, 1.23, -depth * 0.52), trim_mat)
	var floors := int(height / 3.2)
	for floor in range(1, floors):
		for side in [-1.0, 1.0]:
			var wx: float = float(side) * width * 0.27
			var wy := float(floor) * 3.0
			_add_box_to(body, "WindowFrame", Vector3(2.0, 1.7, 0.18), Vector3(wx, wy, -depth * 0.505), trim_mat)
			_add_box_to(body, "WindowGlass", Vector3(1.65, 1.36, 0.08), Vector3(wx, wy, -depth * 0.515), glass_mat)
			_add_box_to(body, "SideGlass", Vector3(0.10, 1.4, 1.8), Vector3(width * 0.505, wy, 0), glass_mat)
	_add_box_to(body, "ShopSign", Vector3(width * 0.76, 0.42, 0.22), Vector3(0, 2.85, -depth * 0.54), _awning_material(seed_value))
	_add_box_to(body, "Balcony", Vector3(width * 0.78, 0.16, 1.0), Vector3(0, 3.0, -depth * 0.55), trim_mat)
	if seed_value % 3 == 0:
		_add_box_to(body, "ShopAwning", Vector3(width * 0.9, 0.22, 1.7), Vector3(0, 3.15, -depth * 0.60), _awning_material(seed_value + 1))

func _awning_material(seed_value: int) -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = [Color(0.65,0.12,0.08), Color(0.12,0.28,0.42), Color(0.72,0.61,0.35), Color(0.18,0.38,0.23)][posmod(seed_value, 4)]
	m.roughness = 0.85
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
	for i in range(traffic_count):
		var lane := -extent + float(i % (district_radius * 2 + 1)) * block_spacing
		var route: Array[Vector3] = []
		if i % 2 == 0:
			route = [Vector3(-extent, 0, lane - 2.4), Vector3(extent, 0, lane - 2.4)]
		else:
			route = [Vector3(lane + 2.4, 0, -extent), Vector3(lane + 2.4, 0, extent)]
		var car = TrafficCar.new()
		car.configure(route, colors[i % colors.size()], rng.randf_range(6.0, 10.0))
		add_child(car)
		var t := float(i / 2) / float(maxi(1, traffic_count / 2))
		car.position = route[0].lerp(route[1], t)
		car.position.y = 0.0

func _build_street_props() -> void:
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.10, 0.11, 0.12)
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.72, 0.38)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.55, 0.2)
	lamp_mat.emission_energy_multiplier = 1.6
	for grid in range(-district_radius, district_radius + 1):
		for axis in range(2):
			var pole := Node3D.new()
			pole.name = "StreetLamp"
			pole.position = Vector3(-float(district_radius) * block_spacing + float(grid + district_radius) * block_spacing, 0, -float(district_radius) * block_spacing + 18.0) if axis == 0 else Vector3(-float(district_radius) * block_spacing + 18.0, 0, -float(district_radius) * block_spacing + float(grid + district_radius) * block_spacing)
			add_child(pole)
			_add_box_to(pole, "LampPost", Vector3(0.16, 5.2, 0.16), Vector3(0, 2.6, 0), pole_mat)
			_add_box_to(pole, "LampHead", Vector3(0.8, 0.16, 0.3), Vector3(-0.35, 5.05, 0), lamp_mat)
			var light := OmniLight3D.new()
			light.position = Vector3(-0.35, 4.9, 0)
			light.light_color = Color(1.0, 0.68, 0.4)
			light.light_energy = 0.7
			light.omni_range = 10.0
			pole.add_child(light)

func _spawn_residents() -> void:
	for i in range(extra_citizens):
		var person = Citizen.new()
		person.is_female = (i % 2 == 1)
		person.variant = i + 20
		person.spawn_near_center = true
		person.spawn_center = Vector3.ZERO
		person.spawn_radius = 155.0
		person.axis = i % 2
		person.lane = float(rng.randi_range(-district_radius, district_radius)) * block_spacing + (9.2 if i % 3 == 0 else -9.2)
		add_child(person)
		person.position.y = 0.92
