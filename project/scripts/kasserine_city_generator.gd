extends Node3D
class_name KasserineCityGenerator
## Phantom Ops v0.2 — procedural Kasserine, ~300x300 m.
## Grid streets, central plaza / market square, four districts:
##   west  = old medina (dense, low, small footprints)
##   east  = modern blocks (tall, large footprints)
##   centre= market around the plaza
##   north edge = checkpoint / military edge
## Seeded (export `seed`) so every run builds the same city.
## Shared meshes / materials only — no per-building unique materials.

@export var seed: int = 20261114
@export var city_half: float = 150.0
@export var road_width: float = 10.0

const ROAD_POS: Array[float] = [-100.0, -50.0, 0.0, 50.0, 100.0]
const PLAZA_HALF: float = 23.0
const SPAWN_CLEAR: float = 14.0

var rng := RandomNumberGenerator.new()
var occupied: Array[Rect2] = []
var spawn_points: Array[Vector3] = []

# Shared unit meshes — props scale the instance, not the mesh.
var _unit_box := BoxMesh.new()
var _unit_cyl := CylinderMesh.new()
var _unit_sphere := SphereMesh.new()
var _cone := CylinderMesh.new()

var mat_asphalt: StandardMaterial3D
var mat_sand: StandardMaterial3D
var mat_sidewalk: StandardMaterial3D
var mat_plaza: StandardMaterial3D
var mat_line: StandardMaterial3D
var mat_dark: StandardMaterial3D
var mat_metal: StandardMaterial3D
var mat_trunk: StandardMaterial3D
var mat_palm: StandardMaterial3D
var mat_rock: StandardMaterial3D
var mat_sandbag: StandardMaterial3D
var mat_barrier: StandardMaterial3D
var mat_lamp_glow: StandardMaterial3D
var mat_mountain: StandardMaterial3D
var mat_skyline: StandardMaterial3D
var mat_car_paints: Array[StandardMaterial3D] = []
var mat_canopy: Array[StandardMaterial3D] = []

func _ready() -> void:
	rng.seed = seed
	_unit_box.size = Vector3.ONE
	_unit_cyl.top_radius = 0.5
	_unit_cyl.bottom_radius = 0.5
	_unit_cyl.height = 1.0
	_unit_sphere.radius = 0.5
	_unit_sphere.height = 1.0
	_cone.top_radius = 0.0
	_cone.bottom_radius = 0.5
	_cone.height = 1.0
	_setup_materials()
	_build_city()

func _setup_materials() -> void:
	mat_asphalt = ProceduralTextures.asphalt_material()
	mat_sand = ProceduralTextures.sand_material()
	mat_sidewalk = ProceduralTextures.sidewalk_material()
	mat_plaza = ProceduralTextures.plaza_material()
	mat_line = ProceduralTextures.flat_material(Color(0.85, 0.75, 0.35), 0.8)
	mat_dark = ProceduralTextures.flat_material(Color(0.16, 0.17, 0.19), 0.85)
	mat_metal = ProceduralTextures.flat_material(Color(0.35, 0.37, 0.40), 0.55)
	mat_trunk = ProceduralTextures.flat_material(Color(0.45, 0.33, 0.20), 0.95)
	mat_palm = ProceduralTextures.flat_material(Color(0.22, 0.45, 0.20), 0.95)
	mat_rock = ProceduralTextures.flat_material(Color(0.55, 0.50, 0.44), 0.95)
	mat_sandbag = ProceduralTextures.flat_material(Color(0.62, 0.55, 0.38), 1.0)
	mat_barrier = ProceduralTextures.flat_material(Color(0.85, 0.45, 0.15), 0.9)
	mat_lamp_glow = ProceduralTextures.flat_material(Color(1.0, 0.85, 0.55), 0.4)
	mat_lamp_glow.emission_enabled = true
	mat_lamp_glow.emission = Color(1.0, 0.80, 0.45)
	mat_lamp_glow.emission_energy_multiplier = 1.5
	mat_mountain = ProceduralTextures.flat_material(Color(0.55, 0.42, 0.32), 1.0)
	mat_skyline = ProceduralTextures.flat_material(Color(0.48, 0.38, 0.30), 1.0)
	for c in [Color(0.55, 0.12, 0.10), Color(0.15, 0.25, 0.45), Color(0.70, 0.65, 0.55), Color(0.20, 0.35, 0.25)]:
		mat_car_paints.append(ProceduralTextures.flat_material(c, 0.5))
	for c in [Color(0.75, 0.30, 0.20), Color(0.20, 0.55, 0.55), Color(0.85, 0.65, 0.25), Color(0.55, 0.30, 0.45)]:
		mat_canopy.append(ProceduralTextures.flat_material(c, 0.9))

# ---------------------------------------------------------------- build

func _build_city() -> void:
	_build_ground()
	_build_roads()
	_build_blocks_and_buildings()
	_build_plaza_and_market()
	_build_props()
	_build_checkpoint()
	_build_landmark_and_horizon()
	_build_sun()
	_collect_spawn_points()

func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(city_half * 2.0, city_half * 2.0)
	plane.material = mat_sand
	mi.mesh = plane
	ground.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(city_half * 2.0, 0.2, city_half * 2.0)
	col.shape = shape
	col.position.y = -0.1
	ground.add_child(col)
	add_child(ground)

func _flat_box(parent: Node, box_name: String, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = box_name
	mi.mesh = _unit_box
	mi.scale = size
	mi.position = pos
	if mat != null:
		mi.material_override = mat
	parent.add_child(mi)
	return mi

func _build_roads() -> void:
	var roads := Node3D.new()
	roads.name = "Roads"
	add_child(roads)
	for x in ROAD_POS:
		_flat_box(roads, "RoadX_%d" % int(x), Vector3(x, 0.04, 0), Vector3(road_width, 0.08, city_half * 2.0), mat_asphalt)
		_flat_box(roads, "RoadZ_%d" % int(x), Vector3(0, 0.04, x), Vector3(city_half * 2.0, 0.08, road_width), mat_asphalt)
		# Centre line, split around the plaza so it does not cross the square.
		_flat_box(roads, "LineXa_%d" % int(x), Vector3(x, 0.09, -95), Vector3(0.4, 0.02, 130), mat_line)
		_flat_box(roads, "LineXb_%d" % int(x), Vector3(x, 0.09, 95), Vector3(0.4, 0.02, 130), mat_line)
		_flat_box(roads, "LineZa_%d" % int(x), Vector3(-95, 0.09, x), Vector3(130, 0.02, 0.4), mat_line)
		_flat_box(roads, "LineZb_%d" % int(x), Vector3(95, 0.09, x), Vector3(130, 0.02, 0.4), mat_line)

func _block_centres() -> Array[Vector2]:
	var centres: Array[Vector2] = []
	var edges: Array[float] = [-150.0, -100.0, -50.0, 0.0, 50.0, 100.0, 150.0]
	for i in range(edges.size() - 1):
		for j in range(edges.size() - 1):
			centres.append(Vector2((edges[i] + edges[i + 1]) * 0.5, (edges[j] + edges[j + 1]) * 0.5))
	return centres

func _build_blocks_and_buildings() -> void:
	var blocks := Node3D.new()
	blocks.name = "Blocks"
	add_child(blocks)
	var buildings := Node3D.new()
	buildings.name = "Buildings"
	add_child(buildings)
	var count := 0
	for centre in _block_centres():
		# Pavement slab for the whole block.
		_flat_box(blocks, "Slab", Vector3(centre.x, 0.06, centre.y), Vector3(44, 0.12, 44), mat_sidewalk)
		var district := "central"
		if centre.x < -50.0:
			district = "medina"
		elif centre.x > 50.0:
			district = "modern"
		var per_block := 2
		if district == "medina":
			per_block = 3
		elif district == "modern":
			per_block = 2
		for k in range(per_block):
			if _try_building(buildings, centre, district, k):
				count += 1
	print("Phantom Ops: city built with %d buildings" % count)

func _try_building(parent: Node, block_centre: Vector2, district: String, slot: int) -> bool:
	var w := 10.0
	var h := 8.0
	var d := 10.0
	if district == "medina":
		w = rng.randf_range(6.0, 9.5)
		h = rng.randf_range(3.5, 6.5)
		d = rng.randf_range(6.0, 9.5)
	elif district == "modern":
		w = rng.randf_range(12.0, 18.0)
		h = rng.randf_range(10.0, 22.0)
		d = rng.randf_range(12.0, 18.0)
	else:
		w = rng.randf_range(8.0, 13.0)
		h = rng.randf_range(5.0, 12.0)
		d = rng.randf_range(8.0, 13.0)
	# Grid-ish slots inside the block so buildings never overlap each other.
	var off := Vector2.ZERO
	if slot == 0:
		off = Vector2(-8, -8)
	elif slot == 1:
		off = Vector2(8, -8)
	elif slot == 2:
		off = Vector2(-8, 8)
	else:
		off = Vector2(8, 8)
	off += Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
	var pos := Vector3(block_centre.x + off.x, 0, block_centre.y + off.y)
	# Keep the plaza / spawn clear, and stay inside the block.
	if Vector2(pos.x, pos.z).length() < 30.0:
		return false
	if absf(pos.x) > 142.0 or absf(pos.z) > 142.0:
		return false
	var rect := Rect2(pos.x - w * 0.5, pos.z - d * 0.5, w, d)
	for other in occupied:
		if rect.intersects(other):
			return false
	occupied.append(rect)
	_create_building(parent, pos, Vector3(w, h, d))
	return true

func _create_building(parent: Node, pos: Vector3, size: Vector3) -> void:
	var idx := parent.get_child_count()
	var body := StaticBody3D.new()
	body.name = "Building_%02d" % idx
	body.position = pos
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = ProceduralTextures.facade_material(rng.randi_range(0, 3))
	mi.mesh = box
	mi.position.y = size.y * 0.5
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position.y = size.y * 0.5
	body.add_child(col)
	# Parapet / roof slab.
	_flat_box(body, "RoofSlab", Vector3(0, size.y + 0.15, 0), Vector3(size.x + 0.6, 0.3, size.z + 0.6), ProceduralTextures.flat_material(Color(0.55, 0.48, 0.40), 0.95))
	# Rooftop clutter: AC unit or water tank on about half the roofs.
	if rng.randf() < 0.55:
		var rw := rng.randf_range(0.8, 1.6)
		var rh := rng.randf_range(0.6, 1.4)
		var rd := rng.randf_range(0.8, 1.6)
		var roof_mat := mat_metal if rng.randf() < 0.5 else ProceduralTextures.flat_material(Color(0.30, 0.45, 0.55), 0.8)
		_flat_box(body, "RoofBox", Vector3(rng.randf_range(-size.x * 0.25, size.x * 0.25), size.y + 0.3 + rh * 0.5, rng.randf_range(-size.z * 0.25, size.z * 0.25)), Vector3(rw, rh, rd), roof_mat)
	# Awning over the street-facing door on low buildings.
	if size.y < 9.0 and rng.randf() < 0.6:
		_flat_box(body, "Awning", Vector3(0, 2.6, size.z * 0.5 + 0.7), Vector3(3.2, 0.15, 1.4), mat_canopy[rng.randi_range(0, mat_canopy.size() - 1)])
	parent.add_child(body)

func _build_plaza_and_market() -> void:
	var plaza := Node3D.new()
	plaza.name = "Plaza"
	add_child(plaza)
	_flat_box(plaza, "PlazaFloor", Vector3(0, 0.06, 0), Vector3(PLAZA_HALF * 2.0, 0.12, PLAZA_HALF * 2.0), mat_plaza)
	# Market stalls in a ring around the square, spawn (0, 10) kept clear.
	for i in range(10):
		var ang := TAU * float(i) / 10.0 + 0.3
		var r := 18.5
		var pos := Vector3(cos(ang) * r, 0, sin(ang) * r)
		if pos.distance_to(Vector3(0, 0, 10)) < 6.0:
			continue
		_stall(plaza, pos, ang, mat_canopy[i % mat_canopy.size()])
	# Benches facing the square.
	for i in range(8):
		var ang := TAU * float(i) / 8.0
		var pos := Vector3(cos(ang) * 12.0, 0, sin(ang) * 12.0)
		if pos.distance_to(Vector3(0, 0, 10)) < 5.0:
			continue
		var bench := StaticBody3D.new()
		bench.name = "Bench_%d" % i
		bench.position = pos
		bench.rotation.y = -ang + PI * 0.5
		_flat_box(bench, "Seat", Vector3(0, 0.45, 0), Vector3(2.2, 0.12, 0.6), mat_trunk)
		_flat_box(bench, "Back", Vector3(0, 0.85, -0.28), Vector3(2.2, 0.6, 0.1), mat_trunk)
		var bcol := CollisionShape3D.new()
		var bshape := BoxShape3D.new()
		bshape.size = Vector3(2.2, 1.0, 0.7)
		bcol.shape = bshape
		bcol.position.y = 0.5
		bench.add_child(bcol)
		plaza.add_child(bench)

func _stall(parent: Node, pos: Vector3, ang: float, canopy_mat: Material) -> void:
	var stall := StaticBody3D.new()
	stall.name = "Stall"
	stall.position = pos
	stall.rotation.y = -ang
	_flat_box(stall, "Counter", Vector3(0, 0.55, 0), Vector3(2.4, 1.1, 1.3), mat_trunk)
	_flat_box(stall, "Goods", Vector3(0, 1.2, 0), Vector3(2.0, 0.25, 1.0), ProceduralTextures.flat_material(Color(0.85, 0.60, 0.25), 0.9))
	_flat_box(stall, "Canopy", Vector3(0, 2.3, 0), Vector3(2.8, 0.12, 1.8), canopy_mat)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.4, 2.3, 1.3)
	col.shape = shape
	col.position.y = 1.15
	stall.add_child(col)
	parent.add_child(stall)

# ---------------------------------------------------------------- props

func _prop_box(parent: Node, prop_name: String, pos: Vector3, size: Vector3, mat: Material, collide: bool, rot_y: float = 0.0) -> Node3D:
	var node: Node3D
	if collide:
		var body := StaticBody3D.new()
		node = body
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		col.position.y = size.y * 0.5
		body.add_child(col)
	else:
		node = Node3D.new()
	node.name = prop_name
	node.position = pos
	node.rotation.y = rot_y
	_flat_box(node, "Mesh", Vector3(0, size.y * 0.5, 0), size, mat)
	parent.add_child(node)
	return node

func _palm(parent: Node, pos: Vector3) -> void:
	var palm := StaticBody3D.new()
	palm.name = "Palm"
	palm.position = pos
	var trunk := MeshInstance3D.new()
	trunk.mesh = _unit_cyl
	trunk.scale = Vector3(0.36, 4.2, 0.36)
	trunk.position.y = 2.1
	trunk.material_override = mat_trunk
	palm.add_child(trunk)
	var canopy := MeshInstance3D.new()
	canopy.mesh = _unit_sphere
	canopy.scale = Vector3(4.4, 1.4, 4.4)
	canopy.position.y = 4.5
	canopy.material_override = mat_palm
	palm.add_child(canopy)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.3
	shape.height = 4.2
	col.shape = shape
	col.position.y = 2.1
	palm.add_child(col)
	parent.add_child(palm)

func _lamp(parent: Node, pos: Vector3) -> void:
	var lamp := StaticBody3D.new()
	lamp.name = "Lamp"
	lamp.position = pos
	var pole := MeshInstance3D.new()
	pole.mesh = _unit_cyl
	pole.scale = Vector3(0.16, 5.0, 0.16)
	pole.position.y = 2.5
	pole.material_override = mat_dark
	lamp.add_child(pole)
	_flat_box(lamp, "Arm", Vector3(0.6, 4.9, 0), Vector3(1.3, 0.12, 0.12), mat_dark)
	_flat_box(lamp, "Head", Vector3(1.2, 4.8, 0), Vector3(0.5, 0.18, 0.3), mat_lamp_glow)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.2
	shape.height = 5.0
	col.shape = shape
	col.position.y = 2.5
	lamp.add_child(col)
	parent.add_child(lamp)

func _car(parent: Node, pos: Vector3, rot_y: float, paint: Material) -> void:
	var car := StaticBody3D.new()
	car.name = "Car"
	car.position = pos
	car.rotation.y = rot_y
	_flat_box(car, "Body", Vector3(0, 0.65, 0), Vector3(1.9, 0.7, 4.4), paint)
	_flat_box(car, "Cabin", Vector3(0, 1.25, -0.2), Vector3(1.7, 0.6, 2.2), mat_dark)
	for wx in [-0.85, 0.85]:
		for wz in [-1.4, 1.4]:
			var wheel := MeshInstance3D.new()
			wheel.mesh = _unit_cyl
			wheel.scale = Vector3(0.65, 0.25, 0.65)
			wheel.rotation_degrees = Vector3(0, 0, 90)
			wheel.position = Vector3(wx, 0.35, wz)
			wheel.material_override = mat_dark
			car.add_child(wheel)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.9, 1.6, 4.4)
	col.shape = shape
	col.position.y = 0.8
	car.add_child(col)
	parent.add_child(car)

func _build_props() -> void:
	var props := Node3D.new()
	props.name = "Props"
	add_child(props)
	# Lamps + palms along the main roads, alternating sides.
	for i in range(12):
		var road_x: float = ROAD_POS[i % ROAD_POS.size()]
		var z := -130.0 + float(i) * 24.0 + rng.randf_range(-4.0, 4.0)
		_lamp(props, Vector3(road_x + 6.8, 0, z))
		_palm(props, Vector3(road_x - 7.5, 0, z + 12.0))
	for i in range(6):
		var road_z: float = ROAD_POS[i % ROAD_POS.size()]
		var x := -110.0 + float(i) * 44.0
		_lamp(props, Vector3(x, 0, road_z + 6.8))
	# Parked / wrecked cars along streets.
	var car_spots: Array[Vector3] = [
		Vector3(-57.5, 0, -30), Vector3(-42.5, 0, 40), Vector3(57.5, 0, -70),
		Vector3(42.5, 0, 90), Vector3(-7.5, 0, -60), Vector3(7.5, 0, 70),
		Vector3(-107.5, 0, 20), Vector3(107.5, 0, -20),
	]
	for i in range(car_spots.size()):
		_car(props, car_spots[i], rng.randf_range(-0.15, 0.15) + (PI * 0.5 if i % 2 == 0 else 0.0), mat_car_paints[i % mat_car_paints.size()])
	# Crates, sandbags and rocks scattered near blocks (never on roads / spawn).
	for i in range(20):
		var p := _random_off_road_point()
		_prop_box(props, "Crate", p, Vector3(rng.randf_range(0.8, 1.3), rng.randf_range(0.8, 1.3), rng.randf_range(0.8, 1.3)), mat_trunk, true, rng.randf() * TAU)
	for i in range(14):
		var p := _random_off_road_point()
		var rock := MeshInstance3D.new()
		rock.name = "Rock"
		rock.mesh = _unit_sphere
		rock.scale = Vector3(rng.randf_range(0.8, 2.0), rng.randf_range(0.4, 0.8), rng.randf_range(0.8, 2.0))
		rock.position = p + Vector3(0, 0.2, 0)
		rock.material_override = mat_rock
		props.add_child(rock)

func _random_off_road_point() -> Vector3:
	for attempt in range(20):
		var p := Vector3(rng.randf_range(-140, 140), 0, rng.randf_range(-140, 140))
		if Vector2(p.x, p.z).length() < 26.0:
			continue
		if _on_road(p.x, p.z):
			continue
		var r := Rect2(p.x - 1, p.z - 1, 2, 2)
		var hit := false
		for other in occupied:
			if r.intersects(other):
				hit = true
				break
		if not hit:
			return p
	return Vector3(60, 0, 60)

func _on_road(x: float, z: float) -> bool:
	for r in ROAD_POS:
		if absf(x - r) < road_width * 0.5 + 1.0:
			return true
		if absf(z - r) < road_width * 0.5 + 1.0:
			return true
	return false

func _build_checkpoint() -> void:
	var cp := Node3D.new()
	cp.name = "Checkpoint"
	add_child(cp)
	# Military edge across the north road (x = 0, z = -110).
	_prop_box(cp, "Booth", Vector3(9, 0, -110), Vector3(3, 3, 3), mat_dark, true)
	_flat_box(cp, "BoothRoof", Vector3(9, 3.1, -110), Vector3(3.6, 0.25, 3.6), mat_barrier)
	for i in range(6):
		_prop_box(cp, "Sandbag", Vector3(-12 + float(i) * 2.2, 0, -108), Vector3(2.0, 0.9, 1.0), mat_sandbag, true)
		_prop_box(cp, "Sandbag2", Vector3(-12 + float(i) * 2.2, 0, -112), Vector3(2.0, 0.9, 1.0), mat_sandbag, true)
	for i in range(4):
		_prop_box(cp, "Barrier", Vector3(-4 + float(i) * 2.6, 0, -110), Vector3(2.2, 1.0, 0.4), mat_barrier, true)
	# A few sandbag nests elsewhere on the medina side.
	for i in range(4):
		_prop_box(cp, "SandbagNest", Vector3(-120 + float(i) * 3.0, 0, -40), Vector3(2.0, 0.9, 1.0), mat_sandbag, true)

func _build_landmark_and_horizon() -> void:
	# Minaret / landmark tower on the plaza's north-east corner.
	var minaret := Node3D.new()
	minaret.name = "Minaret"
	minaret.position = Vector3(26, 0, -26)
	add_child(minaret)
	var shaft := MeshInstance3D.new()
	shaft.mesh = _unit_cyl
	shaft.scale = Vector3(2.4, 24.0, 2.4)
	shaft.position.y = 12.0
	shaft.material_override = ProceduralTextures.flat_material(Color(0.92, 0.88, 0.78), 0.95)
	minaret.add_child(shaft)
	var balcony := MeshInstance3D.new()
	balcony.mesh = _unit_cyl
	balcony.scale = Vector3(3.6, 0.8, 3.6)
	balcony.position.y = 19.0
	balcony.material_override = mat_dark
	minaret.add_child(balcony)
	var cap := MeshInstance3D.new()
	cap.mesh = _cone
	cap.scale = Vector3(3.2, 4.0, 3.2)
	cap.position.y = 26.0
	cap.material_override = ProceduralTextures.flat_material(Color(0.25, 0.45, 0.35), 0.8)
	minaret.add_child(cap)
	# Distant skyline silhouette ring — the city reads from afar.
	var skyline := Node3D.new()
	skyline.name = "Skyline"
	add_child(skyline)
	for i in range(18):
		var ang := TAU * float(i) / 18.0 + rng.randf_range(-0.08, 0.08)
		var r := 185.0
		var w := rng.randf_range(10.0, 22.0)
		var h := rng.randf_range(8.0, 20.0)
		_flat_box(skyline, "Distant_%d" % i, Vector3(cos(ang) * r, h * 0.5, sin(ang) * r), Vector3(w, h, w), mat_skyline)
	# Mountain ring (Jebel Chambi silhouette) beyond the city.
	var mountains := Node3D.new()
	mountains.name = "Mountains"
	add_child(mountains)
	for i in range(12):
		var ang := TAU * float(i) / 12.0 + rng.randf_range(-0.1, 0.1)
		var r := rng.randf_range(260.0, 310.0)
		var h := rng.randf_range(45.0, 95.0)
		var base_r := rng.randf_range(45.0, 75.0)
		var m := MeshInstance3D.new()
		m.mesh = _cone
		m.scale = Vector3(base_r * 2.0, h, base_r * 2.0)
		m.position = Vector3(cos(ang) * r, h * 0.5 - 4.0, sin(ang) * r)
		m.material_override = mat_mountain
		mountains.add_child(m)

func _build_sun() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52, 38, 0)
	sun.light_color = Color(1.0, 0.86, 0.66)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	add_child(sun)

func _collect_spawn_points() -> void:
	# Street / plaza positions away from the player spawn (0, 10).
	var candidates: Array[Vector3] = []
	for x in ROAD_POS:
		for z in [-120.0, -80.0, -40.0, 40.0, 80.0, 120.0]:
			candidates.append(Vector3(x, 0, z))
			candidates.append(Vector3(z, 0, x))
	candidates.append(Vector3(18, 0, -18))
	candidates.append(Vector3(-18, 0, 18))
	candidates.append(Vector3(20, 0, 20))
	for c in candidates:
		if Vector2(c.x, c.z).distance_to(Vector2(0, 10)) > 25.0:
			spawn_points.append(c)
	spawn_points.shuffle()
