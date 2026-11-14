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
var mat_white: StandardMaterial3D
var mat_dirt: StandardMaterial3D
var mat_cloud: StandardMaterial3D
var mat_sun_disc: StandardMaterial3D
var mat_sign_blue: StandardMaterial3D
var mat_tyre: StandardMaterial3D
var mat_bollard: StandardMaterial3D
var mat_cloth: Array[StandardMaterial3D] = []
var mat_fruit: Array[StandardMaterial3D] = []
var mat_dome: StandardMaterial3D
var mat_gold: StandardMaterial3D
var mat_mosque: StandardMaterial3D
var mat_window_glass: StandardMaterial3D
var mat_window_lit: StandardMaterial3D
var mat_headlight: StandardMaterial3D
var mat_pipe: StandardMaterial3D
var _dust: Array = []

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
	_ensure_mobile_environment()
	_build_city()

# v0.2.1 black-screen safety net: if the scene has no WorldEnvironment
# (deleted, or a scene variant), create the same Mobile-safe colour
# environment at runtime so the 3D view can never be black. Matches the
# WorldEnvironment in scenes/main_game.tscn and the fallback in
# scripts/main_game.gd. Does nothing when one already exists.
# v0.5: dusk colours (overcast blue-grey sky, dim warm ambient) for
# the GTA IV look — still BG_COLOR + COLOR ambient, no fog/Sky/ACES.
func _ensure_mobile_environment() -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root != null and not scene_root.find_children("*", "WorldEnvironment", true, false).is_empty():
		return
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.42, 0.44, 0.55)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.60, 0.58)
	environment.ambient_light_energy = 0.75
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = false
	environment.fog_enabled = false
	var world := WorldEnvironment.new()
	world.name = "MobileEnvironmentFallback"
	world.environment = environment
	add_child(world)

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
	mat_white = ProceduralTextures.flat_material(Color(0.92, 0.92, 0.88), 0.85)
	mat_dirt = ProceduralTextures.flat_material(Color(0.58, 0.47, 0.32), 1.0)
	mat_sign_blue = ProceduralTextures.flat_material(Color(0.12, 0.30, 0.55), 0.7)
	mat_tyre = ProceduralTextures.flat_material(Color(0.10, 0.10, 0.11), 0.95)
	mat_bollard = ProceduralTextures.flat_material(Color(0.85, 0.65, 0.15), 0.8)
	mat_cloud = StandardMaterial3D.new()
	mat_cloud.albedo_color = Color(0.68, 0.66, 0.70, 0.85)
	mat_cloud.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_cloud.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# v0.5 GTA detail materials (shared): dark glass + lit windows.
	mat_window_glass = ProceduralTextures.flat_material(Color(0.07, 0.09, 0.13), 0.15)
	mat_window_glass.metallic = 0.4
	mat_window_lit = ProceduralTextures.flat_material(Color(0.95, 0.70, 0.30), 0.4)
	mat_window_lit.emission_enabled = true
	mat_window_lit.emission = Color(1.0, 0.72, 0.28)
	mat_window_lit.emission_energy_multiplier = 1.6
	mat_headlight = ProceduralTextures.flat_material(Color(1.0, 0.95, 0.75), 0.3)
	mat_headlight.emission_enabled = true
	mat_headlight.emission = Color(1.0, 0.9, 0.6)
	mat_headlight.emission_energy_multiplier = 2.0
	mat_pipe = ProceduralTextures.flat_material(Color(0.20, 0.20, 0.22), 0.8)
	mat_sun_disc = StandardMaterial3D.new()
	mat_sun_disc.albedo_color = Color(1.0, 0.92, 0.65)
	mat_sun_disc.emission_enabled = true
	mat_sun_disc.emission = Color(1.0, 0.85, 0.45)
	mat_sun_disc.emission_energy_multiplier = 2.0
	mat_sun_disc.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for c in [Color(0.75, 0.30, 0.20), Color(0.20, 0.55, 0.55), Color(0.85, 0.65, 0.25), Color(0.92, 0.88, 0.80)]:
		mat_cloth.append(ProceduralTextures.flat_material(c, 0.95))
	for c in [Color(0.85, 0.45, 0.10), Color(0.45, 0.65, 0.20), Color(0.75, 0.20, 0.20)]:
		mat_fruit.append(ProceduralTextures.flat_material(c, 0.9))
	mat_dome = ProceduralTextures.flat_material(Color(0.15, 0.45, 0.40), 0.6)
	mat_gold = ProceduralTextures.flat_material(Color(0.88, 0.68, 0.28), 0.35)
	mat_gold.metallic = 0.6
	mat_mosque = ProceduralTextures.geometric_material()

# ---------------------------------------------------------------- build

func _build_city() -> void:
	_build_ground()
	_reserve_mosque()
	_build_roads()
	_build_blocks_and_buildings()
	_build_plaza_and_market()
	_build_props()
	_build_checkpoint()
	_build_landmark_and_horizon()
	_build_mosque()
	_build_sky_detail()
	_build_sun()
	_build_dust()
	_collect_spawn_points()

# v0.4: reserve the mosque plot (south-west block) before any building
# is placed, so no regular building overlaps the mosque or courtyard.
func _reserve_mosque() -> void:
	occupied.append(Rect2(-92.0, 49.0, 34.0, 42.0))

func _process(delta: float) -> void:
	# Drifting dust motes near the ground (cheap CPU quads, no particles).
	for d in _dust:
		var node: MeshInstance3D = d["node"]
		var base: Vector3 = d["base"]
		var t: float = d["t"] + delta * d["speed"]
		d["t"] = t
		node.position = base + Vector3(sin(t * 0.7) * 3.0, sin(t * 1.3) * 0.6 + 0.8, cos(t * 0.5) * 3.0)

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
		# Tyre tracks: two dark strips along each road (inside the loop).
		_flat_box(roads, "TrackX_%d" % int(x), Vector3(x - 1.8, 0.05, 0), Vector3(0.9, 0.02, city_half * 2.0), mat_dirt)
		_flat_box(roads, "TrackZ_%d" % int(x), Vector3(0, 0.05, x - 1.8), Vector3(city_half * 2.0, 0.02, 0.9), mat_dirt)
	# Crosswalks + stop lines at every intersection outside the plaza.
	# (Once, not per road — this block is outside the `for x` loop above.)
	for ix in ROAD_POS:
		for iz in ROAD_POS:
			if absf(ix) < 30.0 and absf(iz) < 30.0:
				continue
			for k in range(4):
				_flat_box(roads, "Cross_%d_%d_%d" % [int(ix), int(iz), k], Vector3(ix - 3.6 + float(k) * 2.4, 0.10, iz + 6.5), Vector3(1.1, 0.02, 3.2), mat_white)
			_flat_box(roads, "Stop_%d_%d" % [int(ix), int(iz)], Vector3(ix, 0.10, iz - 7.5), Vector3(8.0, 0.02, 0.5), mat_white)
	# Dirt patches on the sand between blocks.
	for i in range(16):
		var dp := Vector3(rng.randf_range(-140.0, 140.0), 0.02, rng.randf_range(-140.0, 140.0))
		if _on_road(dp.x, dp.z) or Vector2(dp.x, dp.z).length() < 26.0:
			continue
		_flat_box(roads, "Dirt_%d" % i, dp, Vector3(rng.randf_range(3.0, 7.0), 0.02, rng.randf_range(3.0, 7.0)), mat_dirt)

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
	_flat_box(body, "RoofSlab", Vector3(0, size.y + 0.15, 0), Vector3(size.x + 0.6, 0.3, size.z + 0.6), ProceduralTextures.flat_material(Color(0.48, 0.42, 0.35), 0.95))
	# v0.5: cornice trim just under the roof line — the box stops
	# reading as a plain slab.
	_flat_box(body, "Cornice", Vector3(0, size.y - 0.25, 0), Vector3(size.x + 0.35, 0.35, size.z + 0.35), mat_dark)
	# v0.5: 3D windows with real depth on the street face of taller
	# buildings — recessed dark glass, a few lit warm. The facade
	# texture alone made walls read flat.
	if size.y >= 8.0:
		var rows := 2 if size.y >= 12.0 else 1
		for wr in range(rows):
			var wy := 4.2 + float(wr) * 3.4
			if wy > size.y - 1.6:
				continue
			for wc in range(3):
				var wx := -size.x * 0.28 + float(wc) * size.x * 0.28
				_flat_box(body, "WinFrame_%d_%d" % [wr, wc], Vector3(wx, wy, size.z * 0.5 + 0.06), Vector3(1.7, 1.9, 0.14), mat_dark)
				var lit := rng.randf() < 0.22
				_flat_box(body, "WinGlass_%d_%d" % [wr, wc], Vector3(wx, wy, size.z * 0.5 + 0.12), Vector3(1.4, 1.6, 0.08), mat_window_lit if lit else mat_window_glass)
	# v0.5: drain pipe down a front corner on half the buildings.
	if rng.randf() < 0.5:
		_flat_box(body, "Pipe", Vector3(size.x * 0.5 - 0.15, size.y * 0.5, size.z * 0.5 + 0.12), Vector3(0.18, size.y, 0.18), mat_pipe)
	# Rooftop clutter: AC unit or water tank on about half the roofs.
	if rng.randf() < 0.55:
		var rw := rng.randf_range(0.8, 1.6)
		var rh := rng.randf_range(0.6, 1.4)
		var rd := rng.randf_range(0.8, 1.6)
		var roof_mat := mat_metal if rng.randf() < 0.5 else ProceduralTextures.flat_material(Color(0.30, 0.45, 0.55), 0.8)
		_flat_box(body, "RoofBox", Vector3(rng.randf_range(-size.x * 0.25, size.x * 0.25), size.y + 0.3 + rh * 0.5, rng.randf_range(-size.z * 0.25, size.z * 0.25)), Vector3(rw, rh, rd), roof_mat)
	# v0.5: rooftop water tank (cylinder) + TV antenna on some roofs.
	if rng.randf() < 0.35:
		var tank := MeshInstance3D.new()
		tank.name = "WaterTank"
		tank.mesh = _unit_cyl
		tank.scale = Vector3(1.3, 1.7, 1.3)
		tank.position = Vector3(rng.randf_range(-size.x * 0.3, size.x * 0.3), size.y + 1.15, rng.randf_range(-size.z * 0.3, size.z * 0.3))
		tank.material_override = mat_dark
		body.add_child(tank)
	if rng.randf() < 0.3:
		_flat_box(body, "Antenna", Vector3(rng.randf_range(-size.x * 0.3, size.x * 0.3), size.y + 1.8, rng.randf_range(-size.z * 0.3, size.z * 0.3)), Vector3(0.08, 3.6, 0.08), mat_pipe)
		_flat_box(body, "AntennaBar", Vector3(rng.randf_range(-size.x * 0.3, size.x * 0.3), size.y + 3.0, rng.randf_range(-size.z * 0.3, size.z * 0.3)), Vector3(1.2, 0.06, 0.06), mat_pipe)
	# Awning over the street-facing door on low buildings.
	if size.y < 9.0 and rng.randf() < 0.6:
		_flat_box(body, "Awning", Vector3(0, 2.6, size.z * 0.5 + 0.7), Vector3(3.2, 0.15, 1.4), mat_canopy[rng.randi_range(0, mat_canopy.size() - 1)])
	# Balcony on taller buildings (slab + railing).
	if size.y >= 8.0 and rng.randf() < 0.7:
		var by := rng.randf_range(3.5, size.y - 1.5)
		_flat_box(body, "Balcony", Vector3(0, by, size.z * 0.5 + 0.8), Vector3(3.4, 0.18, 1.6), mat_sidewalk)
		_flat_box(body, "BalconyRail", Vector3(0, by + 0.6, size.z * 0.5 + 1.5), Vector3(3.4, 0.9, 0.08), mat_dark)
		if size.y >= 14.0:
			var by2 := by + 3.4
			if by2 < size.y - 1.0:
				_flat_box(body, "Balcony2", Vector3(0, by2, size.z * 0.5 + 0.8), Vector3(3.4, 0.18, 1.6), mat_sidewalk)
				_flat_box(body, "BalconyRail2", Vector3(0, by2 + 0.6, size.z * 0.5 + 1.5), Vector3(3.4, 0.9, 0.08), mat_dark)
	# Satellite dish on the roof.
	if rng.randf() < 0.3:
		var dish := MeshInstance3D.new()
		dish.name = "Dish"
		dish.mesh = _unit_sphere
		dish.scale = Vector3(0.9, 0.25, 0.9)
		dish.position = Vector3(rng.randf_range(-size.x * 0.3, size.x * 0.3), size.y + 0.5, rng.randf_range(-size.z * 0.3, size.z * 0.3))
		dish.rotation_degrees = Vector3(-35, 0, 0)
		dish.material_override = mat_metal
		body.add_child(dish)
	# Laundry line with coloured cloth on low medina roofs.
	if size.y < 7.0 and rng.randf() < 0.35:
		var ly := size.y + 0.9
		_flat_box(body, "LaundryLine", Vector3(0, ly, 0), Vector3(size.x * 0.7, 0.04, 0.04), mat_dark)
		for ci in range(3):
			_flat_box(body, "Cloth_%d" % ci, Vector3(-size.x * 0.2 + float(ci) * size.x * 0.2, ly - 0.35, 0), Vector3(0.9, 0.7, 0.05), mat_cloth[rng.randi_range(0, mat_cloth.size() - 1)])
	# v0.4: Islamic-style low buildings — small dome + arched doorway.
	if size.y < 7.0 and rng.randf() < 0.35:
		var dome := MeshInstance3D.new()
		dome.name = "SmallDome"
		dome.mesh = _unit_sphere
		dome.scale = Vector3(size.x * 0.42, size.x * 0.26, size.x * 0.42)
		dome.position = Vector3(0, size.y + 0.3, 0)
		dome.material_override = mat_dome
		body.add_child(dome)
		var finial := MeshInstance3D.new()
		finial.name = "Finial"
		finial.mesh = _unit_sphere
		finial.scale = Vector3(0.3, 0.3, 0.3)
		finial.position = Vector3(0, size.y + 0.3 + size.x * 0.26, 0)
		finial.material_override = mat_gold
		body.add_child(finial)
	if size.y < 7.0 and rng.randf() < 0.4:
		var arch := MeshInstance3D.new()
		arch.name = "Arch"
		arch.mesh = _unit_sphere
		arch.scale = Vector3(2.0, 1.1, 0.5)
		arch.position = Vector3(0, 2.9, size.z * 0.5 + 0.05)
		arch.material_override = mat_dome
		body.add_child(arch)
	parent.add_child(body)

# v0.4: the mosque of Kasserine — prayer hall with geometric-pattern
# walls, big teal dome + small dome, two minarets, courtyard with
# colonnade and hanging lanterns. South-west block (-75, 75), reserved
# above; it never blocks a road or the player spawn.
func _build_mosque() -> void:
	var mosque := Node3D.new()
	mosque.name = "Mosque"
	mosque.position = Vector3(-75, 0, 75)
	add_child(mosque)
	# Courtyard floor (north side, facing the plaza) + colonnade.
	_flat_box(mosque, "Courtyard", Vector3(0, 0.06, -14), Vector3(30, 0.12, 20), mat_plaza)
	for cx in [-12.0, -6.0, 0.0, 6.0, 12.0]:
		var col := MeshInstance3D.new()
		col.name = "Column"
		col.mesh = _unit_cyl
		col.scale = Vector3(0.5, 3.5, 0.5)
		col.position = Vector3(cx, 1.75, -22)
		col.material_override = mat_white
		mosque.add_child(col)
	_flat_box(mosque, "Colonnade", Vector3(0, 3.7, -22), Vector3(27, 0.5, 0.9), mat_white)
	# Hanging lanterns along the colonnade (emissive, no lights).
	for lx in [-9.0, -3.0, 3.0, 9.0]:
		var cord := MeshInstance3D.new()
		cord.mesh = _unit_cyl
		cord.scale = Vector3(0.05, 0.8, 0.05)
		cord.position = Vector3(lx, 3.1, -22)
		cord.material_override = mat_dark
		mosque.add_child(cord)
		var lantern := MeshInstance3D.new()
		lantern.name = "Lantern"
		lantern.mesh = _unit_sphere
		lantern.scale = Vector3(0.5, 0.6, 0.5)
		lantern.position = Vector3(lx, 2.5, -22)
		lantern.material_override = mat_lamp_glow
		mosque.add_child(lantern)
	# Prayer hall.
	var hall := StaticBody3D.new()
	hall.name = "PrayerHall"
	hall.position = Vector3(0, 0, 4)
	mosque.add_child(hall)
	var hall_mesh := MeshInstance3D.new()
	var hall_box := BoxMesh.new()
	hall_box.size = Vector3(26, 9, 16)
	hall_box.material = mat_mosque
	hall_mesh.mesh = hall_box
	hall_mesh.position.y = 4.5
	hall.add_child(hall_mesh)
	var hall_col := CollisionShape3D.new()
	var hall_shape := BoxShape3D.new()
	hall_shape.size = Vector3(26, 9, 16)
	hall_col.shape = hall_shape
	hall_col.position.y = 4.5
	hall.add_child(hall_col)
	occupied.append(Rect2(-75 - 13, 75 + 4 - 8, 26, 16))
	# Arched doorway (front, facing the courtyard / plaza).
	_flat_box(hall, "Door", Vector3(0, 2.25, -8.1), Vector3(3.0, 4.5, 0.4), mat_dark)
	var arch := MeshInstance3D.new()
	arch.name = "DoorArch"
	arch.mesh = _unit_sphere
	arch.scale = Vector3(3.4, 1.8, 0.6)
	arch.position = Vector3(0, 4.5, -8.1)
	arch.material_override = mat_dome
	hall.add_child(arch)
	# Big dome + gold crescent finial (torus ring + sphere).
	var dome := MeshInstance3D.new()
	dome.name = "Dome"
	dome.mesh = _unit_sphere
	dome.scale = Vector3(10.0, 6.0, 10.0)
	dome.position = Vector3(0, 9.0, 4)
	dome.material_override = mat_dome
	mosque.add_child(dome)
	var finial := MeshInstance3D.new()
	finial.name = "Crescent"
	finial.mesh = _unit_sphere
	finial.scale = Vector3(0.6, 0.6, 0.6)
	finial.position = Vector3(0, 13.2, 4)
	finial.material_override = mat_gold
	mosque.add_child(finial)
	var ring := MeshInstance3D.new()
	ring.name = "CrescentRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.35
	torus.outer_radius = 0.6
	# Material on the mesh itself (see citizen.gd _part): avoids a
	# headless dummy-server error from material_override.
	torus.material = mat_gold
	ring.mesh = torus
	ring.position = Vector3(0, 12.4, 4)
	mosque.add_child(ring)
	# Small dome on the hall's east wing.
	var small_dome := MeshInstance3D.new()
	small_dome.name = "SmallDome"
	small_dome.mesh = _unit_sphere
	small_dome.scale = Vector3(5.0, 3.0, 5.0)
	small_dome.position = Vector3(10, 9.0, 4)
	small_dome.material_override = mat_dome
	mosque.add_child(small_dome)
	# Two minarets at the front corners.
	for mx in [-13.0, 13.0]:
		var minaret := Node3D.new()
		minaret.name = "Minaret"
		minaret.position = Vector3(mx, 0, -6)
		mosque.add_child(minaret)
		var shaft := MeshInstance3D.new()
		shaft.mesh = _unit_cyl
		shaft.scale = Vector3(2.0, 18.0, 2.0)
		shaft.position.y = 9.0
		shaft.material_override = mat_white
		minaret.add_child(shaft)
		var balcony := MeshInstance3D.new()
		balcony.mesh = _unit_cyl
		balcony.scale = Vector3(3.0, 0.7, 3.0)
		balcony.position.y = 15.0
		balcony.material_override = mat_dark
		minaret.add_child(balcony)
		var cap := MeshInstance3D.new()
		cap.mesh = _cone
		cap.scale = Vector3(2.6, 3.5, 2.6)
		cap.position.y = 19.5
		cap.material_override = mat_dome
		minaret.add_child(cap)
	print("Phantom Ops: mosque built at (-75, 75)")

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
	# v0.4: shop signs (Label3D, Latin names — the fallback font has
	# no Arabic glyphs for procedural text, so Latin only).
	var shop_names := ["SOUK", "CAFE", "BAKERY", "PHARMACIE", "BOULANGERIE", "EPICERIE"]
	for i in range(6):
		var ang2 := TAU * float(i) / 6.0 + 0.3
		var spos := Vector3(cos(ang2) * 18.5, 0, sin(ang2) * 18.5)
		if spos.distance_to(Vector3(0, 0, 10)) < 6.0:
			continue
		var sign := Label3D.new()
		sign.name = "ShopSign_%d" % i
		sign.text = shop_names[i]
		sign.font_size = 64
		sign.pixel_size = 0.01
		sign.modulate = Color(1.0, 0.85, 0.45)
		sign.outline_size = 10
		sign.outline_modulate = Color(0.05, 0.05, 0.08)
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sign.position = spos + Vector3(0, 3.1, 0)
		plaza.add_child(sign)
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
	for bi in range(3):
		var basket := MeshInstance3D.new()
		basket.name = "Basket_%d" % bi
		basket.mesh = _unit_cyl
		basket.scale = Vector3(0.55, 0.3, 0.55)
		basket.position = Vector3(-0.7 + float(bi) * 0.7, 1.45, 0)
		basket.material_override = mat_fruit[bi % mat_fruit.size()]
		stall.add_child(basket)
	# v0.5: more goods on the counter — stacked fruit piles + a crate.
	for gi in range(3):
		_flat_box(stall, "Pile_%d" % gi, Vector3(-0.7 + float(gi) * 0.7, 1.42, 0.35), Vector3(0.45, 0.3, 0.4), mat_fruit[(gi + 1) % mat_fruit.size()])
	_flat_box(stall, "Crate", Vector3(0.8, 1.35, -0.35), Vector3(0.6, 0.35, 0.5), mat_trunk)
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
	# Fronds: flattened spheres fanning out from the crown.
	for fi in range(5):
		var ang := TAU * float(fi) / 5.0
		var frond := MeshInstance3D.new()
		frond.name = "Frond_%d" % fi
		frond.mesh = _unit_sphere
		frond.scale = Vector3(2.6, 0.35, 0.9)
		frond.position = Vector3(cos(ang) * 1.6, 4.9, sin(ang) * 1.6)
		frond.rotation.y = -ang
		frond.rotation.z = 0.35
		frond.material_override = mat_palm
		palm.add_child(frond)
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
	# v0.5: real warm light pools at dusk — only for lamps near the
	# plaza / spawn, where the player actually walks. Six OmniLights
	# is cheap on a modern phone; lighting every lamp would not be.
	if Vector2(pos.x, pos.z).length() < 65.0:
		var light := OmniLight3D.new()
		light.name = "LampLight"
		light.position = Vector3(1.2, 4.6, 0)
		light.light_color = Color(1.0, 0.62, 0.30)
		light.light_energy = 1.4
		light.omni_range = 14.0
		lamp.add_child(light)
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
	# v0.5: windshield (lighter glass, raked), bumpers, headlights.
	_flat_box(car, "Windshield", Vector3(0, 1.32, 0.95), Vector3(1.6, 0.5, 0.08), mat_window_glass)
	_flat_box(car, "RearWindow", Vector3(0, 1.32, -1.32), Vector3(1.6, 0.5, 0.08), mat_window_glass)
	_flat_box(car, "BumperF", Vector3(0, 0.42, 2.22), Vector3(1.9, 0.18, 0.12), mat_dark)
	_flat_box(car, "BumperR", Vector3(0, 0.42, -2.22), Vector3(1.9, 0.18, 0.12), mat_dark)
	for hx in [-0.6, 0.6]:
		_flat_box(car, "Headlight", Vector3(hx, 0.72, 2.21), Vector3(0.4, 0.16, 0.06), mat_headlight)
		_flat_box(car, "Taillight", Vector3(hx, 0.72, -2.21), Vector3(0.4, 0.14, 0.06), ProceduralTextures.flat_material(Color(0.70, 0.12, 0.10), 0.5))
	for wx in [-0.85, 0.85]:
		for wz in [-1.4, 1.4]:
			var wheel := MeshInstance3D.new()
			wheel.mesh = _unit_cyl
			wheel.scale = Vector3(0.65, 0.25, 0.65)
			wheel.rotation_degrees = Vector3(0, 0, 90)
			wheel.position = Vector3(wx, 0.35, wz)
			wheel.material_override = mat_dark
			car.add_child(wheel)
			# Hubcap dot on the outer face.
			var hub := MeshInstance3D.new()
			hub.mesh = _unit_cyl
			hub.scale = Vector3(0.3, 0.27, 0.3)
			hub.rotation_degrees = Vector3(0, 0, 90)
			hub.position = Vector3(wx + (0.14 if wx > 0.0 else -0.14), 0.35, wz)
			hub.material_override = mat_metal
			car.add_child(hub)
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
	# Barrels, tyre stacks and bollards.
	for i in range(10):
		var bp := _random_off_road_point()
		var barrel := MeshInstance3D.new()
		barrel.name = "Barrel"
		barrel.mesh = _unit_cyl
		barrel.scale = Vector3(0.8, 1.1, 0.8)
		barrel.position = bp + Vector3(0, 0.55, 0)
		barrel.material_override = mat_barrier if i % 3 == 0 else mat_metal
		props.add_child(barrel)
	for i in range(8):
		var tp := _random_off_road_point()
		for ti in range(2):
			var tyre := MeshInstance3D.new()
			tyre.name = "Tyre"
			tyre.mesh = _unit_cyl
			tyre.scale = Vector3(0.9, 0.28, 0.9)
			tyre.position = tp + Vector3(0, 0.15 + float(ti) * 0.28, 0)
			tyre.material_override = mat_tyre
			props.add_child(tyre)
	for i in range(12):
		var ang := TAU * float(i) / 12.0
		var boll := MeshInstance3D.new()
		boll.name = "Bollard"
		boll.mesh = _unit_cyl
		boll.scale = Vector3(0.3, 0.9, 0.3)
		boll.position = Vector3(cos(ang) * 25.5, 0.45, sin(ang) * 25.5)
		boll.material_override = mat_bollard
		props.add_child(boll)
	# Street name signs on poles at 8 intersections.
	var sign_spots: Array[Vector3] = [Vector3(56, 0, 56), Vector3(-56, 0, 56), Vector3(56, 0, -56), Vector3(-56, 0, -56), Vector3(6, 0, 106), Vector3(-106, 0, 6), Vector3(106, 0, -6), Vector3(-6, 0, -106)]
	for sp in sign_spots:
		var pole := MeshInstance3D.new()
		pole.name = "SignPole"
		pole.mesh = _unit_cyl
		pole.scale = Vector3(0.14, 2.6, 0.14)
		pole.position = sp + Vector3(0, 1.3, 0)
		pole.material_override = mat_dark
		props.add_child(pole)
		_flat_box(props, "Sign", sp + Vector3(0, 2.5, 0), Vector3(1.6, 0.5, 0.08), mat_sign_blue)
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

func _build_sky_detail() -> void:
	# Sun disc + soft procedural clouds. BG_COLOR environment stays
	# (v0.2.1 black-screen fix) — these are plain unshaded meshes, so
	# the sky is no longer a flat colour but cannot render black.
	var sky := Node3D.new()
	sky.name = "SkyDetail"
	add_child(sky)
	var disc := MeshInstance3D.new()
	disc.name = "SunDisc"
	disc.mesh = _unit_sphere
	# v0.5: low, large dusk sun — the GTA IV dusk look.
	disc.scale = Vector3(20.0, 20.0, 2.0)
	disc.position = Vector3(190.0, 75.0, -110.0)
	disc.rotation_degrees = Vector3(0, -35, 0)
	disc.material_override = mat_sun_disc
	sky.add_child(disc)
	for i in range(11):
		var cloud := MeshInstance3D.new()
		cloud.name = "Cloud_%d" % i
		cloud.mesh = _unit_sphere
		cloud.scale = Vector3(rng.randf_range(18.0, 34.0), rng.randf_range(2.5, 4.5), rng.randf_range(7.0, 12.0))
		cloud.position = Vector3(rng.randf_range(-220.0, 220.0), rng.randf_range(80.0, 120.0), rng.randf_range(-220.0, 220.0))
		cloud.material_override = mat_cloud
		sky.add_child(cloud)

func _build_dust() -> void:
	var dust_mat := StandardMaterial3D.new()
	dust_mat.albedo_color = Color(0.85, 0.75, 0.55, 0.5)
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var dust_node := Node3D.new()
	dust_node.name = "Dust"
	add_child(dust_node)
	for i in range(60):
		var mote := MeshInstance3D.new()
		mote.name = "Mote_%d" % i
		mote.mesh = _unit_sphere
		mote.scale = Vector3(0.22, 0.22, 0.22)
		mote.material_override = dust_mat
		dust_node.add_child(mote)
		_dust.append({"node": mote, "base": Vector3(rng.randf_range(-70.0, 70.0), rng.randf_range(0.3, 3.0), rng.randf_range(-70.0, 70.0)), "t": rng.randf_range(0.0, 10.0), "speed": rng.randf_range(0.3, 0.8)})

func _build_sun() -> void:
	# v0.5: low dusk sun — longer shadows, warmer and dimmer light.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-32, 38, 0)
	sun.light_color = Color(1.0, 0.72, 0.45)
	sun.light_energy = 0.95
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
