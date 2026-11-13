extends Node3D
class_name KasserineCityGenerator

@export var city_size := Vector2(150.0, 150.0)
@export_range(8, 40) var building_count := 24
@export_range(2, 14) var zombie_count := 7
@export var weather_cycle := true

var player: Node3D
var weather_timer := 0.0
var weather_mode := 0
var sun: DirectionalLight3D
var world_environment: WorldEnvironment
var rain_particles: GPUParticles3D

var sand := StandardMaterial3D.new()
var asphalt := StandardMaterial3D.new()
var sidewalk := StandardMaterial3D.new()
var wall_materials: Array[StandardMaterial3D] = []
var window_glass := StandardMaterial3D.new()
var window_frame := StandardMaterial3D.new()
var door_material := StandardMaterial3D.new()
var lamp_glow := StandardMaterial3D.new()

func _ready() -> void:
	seed(20261112)
	player = get_tree().get_first_node_in_group("player")
	_setup_materials()
	_build_environment()
	_build_ground_and_roads()
	_build_city_blocks()
	_build_street_lighting()
	_build_vegetation()
	call_deferred("_spawn_hostiles")
	_build_weather()
	print("PHANTOM OPS: world generation complete")

func _process(delta: float) -> void:
	if not weather_cycle: return
	weather_timer += delta
	if weather_timer >= 95.0:
		weather_timer = 0.0
		weather_mode = (weather_mode + 1) % 4
		_apply_weather()

func _setup_materials() -> void:
	sand.albedo_color = Color(0.30,0.34,0.32)
	sand.roughness = 0.94
	asphalt.albedo_color = Color(0.075,0.09,0.105)
	asphalt.roughness = 0.82
	sidewalk.albedo_color = Color(0.37,0.38,0.36)
	sidewalk.roughness = 0.9
	for c in [Color(0.42,0.39,0.34), Color(0.34,0.38,0.39), Color(0.43,0.42,0.37), Color(0.31,0.34,0.34)]:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		wall_materials.append(m)
	window_glass.albedo_color = Color(0.055,0.15,0.20)
	window_glass.metallic = 0.35
	window_glass.roughness = 0.2
	window_frame.albedo_color = Color(0.12,0.14,0.15)
	door_material.albedo_color = Color(0.19,0.12,0.08)
	lamp_glow.albedo_color = Color(1.0,0.72,0.38)
	lamp_glow.emission_enabled = true
	lamp_glow.emission = Color(1.0,0.56,0.22)
	lamp_glow.emission_energy_multiplier = 2.0

func _box(parent: Node, name: String, size: Vector3, pos: Vector3, mat: Material, collision := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.position = pos
	parent.add_child(instance)
	if collision and parent is StaticBody3D:
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		shape.position = pos
		parent.add_child(shape)
	return instance

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.12,0.20,0.29)
	sky_mat.sky_horizon_color = Color(0.58,0.55,0.47)
	sky_mat.ground_bottom_color = Color(0.07,0.08,0.09)
	sky_mat.ground_horizon_color = Color(0.28,0.29,0.27)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.43,0.48,0.54)
	env.ambient_light_energy = 0.72
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.43,0.47,0.48)
	env.fog_density = 0.0018
	world_environment = WorldEnvironment.new()
	world_environment.environment = env
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.name = "SunMoon"
	sun.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)

func _build_ground_and_roads() -> void:
	var ground := StaticBody3D.new()
	ground.name = "GroundCollision"
	_box(ground, "Terrain", Vector3(city_size.x*2.0,0.2,city_size.y*2.0), Vector3(0,-0.1,0), sand, true)
	add_child(ground)
	# Main asphalt cross and secondary streets.
	_box(self, "MainRoadNorthSouth", Vector3(15,0.08,city_size.y*2.0), Vector3(0,0.015,0), asphalt)
	_box(self, "MainRoadEastWest", Vector3(city_size.x*2.0,0.08,15), Vector3(0,0.016,0), asphalt)
	for x in [-90.0,-60.0,-30.0,30.0,60.0,90.0]:
		_box(self, "RoadX_%d" % int(x), Vector3(9,0.06,city_size.y*2.0), Vector3(x,0.02,0), asphalt)
	for z in [-90.0,-60.0,-30.0,30.0,60.0,90.0]:
		_box(self, "RoadZ_%d" % int(z), Vector3(city_size.x*2.0,0.06,9), Vector3(0,0.02,z), asphalt)
	# Sidewalk ribbons, broken white lane markers and crossings.
	for z in [-8.6,8.6]:
		_box(self, "MainSidewalkZ_%d" % int(z), Vector3(city_size.x*2.0,0.12,2.0), Vector3(0,0.07,z), sidewalk)
	for x in [-8.6,8.6]:
		_box(self, "MainSidewalkX_%d" % int(x), Vector3(2.0,0.12,city_size.y*2.0), Vector3(x,0.07,0), sidewalk)
	var marking := StandardMaterial3D.new()
	marking.albedo_color = Color(0.74,0.76,0.70)
	for i in range(-8,9):
		_box(self, "LaneMark_%d" % i, Vector3(0.22,0.025,3.2), Vector3(0,0.07,i*9.0), marking)
		_box(self, "CrossMark_%d" % i, Vector3(3.2,0.025,0.22), Vector3(i*9.0,0.071,0), marking)

func _build_city_blocks() -> void:
	var plots := [Vector2(-45,-45),Vector2(45,-45),Vector2(-45,45),Vector2(45,45),Vector2(-80,-45),Vector2(80,-45),Vector2(-80,45),Vector2(80,45),Vector2(-45,-80),Vector2(45,-80),Vector2(-45,80),Vector2(45,80),Vector2(-105,-45),Vector2(105,-45),Vector2(-105,45),Vector2(105,45),Vector2(-45,-105),Vector2(45,-105),Vector2(-45,105),Vector2(45,105),Vector2(-105,-105),Vector2(105,-105),Vector2(-105,105),Vector2(105,105)]
	for i in range(building_count):
		var p: Vector2 = plots[i % plots.size()]
		var offset := Vector2(randf_range(-8,8),randf_range(-8,8))
		_create_building(i, p + offset)

func _create_building(index: int, p: Vector2) -> void:
	var body := StaticBody3D.new()
	body.name = "Building_%02d" % index
	var sx := randf_range(10.0,17.0)
	var sy := randf_range(7.0,14.0)
	var sz := randf_range(10.0,17.0)
	var wall: Material = wall_materials[index % wall_materials.size()]
	_box(body,"Facade",Vector3(sx,sy,sz),Vector3(0,sy*0.5,0),wall,true)
	# Roof parapet and front entrance.
	_box(body,"RoofLip",Vector3(sx+0.5,0.45,sz+0.5),Vector3(0,sy+0.2,0),wall)
	_box(body,"EntranceDoor",Vector3(1.7,2.8,0.16),Vector3(0,1.4,-sz*0.501),door_material)
	_box(body,"DoorTop",Vector3(2.2,0.22,0.28),Vector3(0,2.9,-sz*0.51),window_frame)
	# Two floors of visible framed windows on the front and rear.
	for floor in range(2):
		for side in [-1.0,1.0]:
			var wx := side*sx*0.27
			var wy := 3.0 + floor*3.6
			_box(body,"WindowFrame",Vector3(1.65,1.65,0.18),Vector3(wx,wy,-sz*0.505),window_frame)
			_box(body,"WindowGlass",Vector3(1.28,1.28,0.08),Vector3(wx,wy,-sz*0.515),window_glass)
			_box(body,"WindowSill",Vector3(1.9,0.16,0.28),Vector3(wx,wy-0.88,-sz*0.52),window_frame)
	# A few side windows create a lived-in silhouette.
	for side in [-1.0,1.0]:
		for floor in range(2):
			_box(body,"SideWindow",Vector3(0.12,1.3,1.5),Vector3(side*sx*0.505,3.1+floor*3.6,0),window_glass)
	body.position = Vector3(p.x,0,p.y)
	add_child(body)

func _build_street_lighting() -> void:
	for i in range(-4,5):
		for side in [-1.0,1.0]:
			var pole := Node3D.new()
			pole.name = "StreetLamp"
			pole.position = Vector3(side*11.0,0,i*28.0)
			add_child(pole)
			_box(pole,"Pole",Vector3(0.18,5.4,0.18),Vector3(0,2.7,0),window_frame)
			_box(pole,"Arm",Vector3(1.4,0.12,0.12),Vector3(-0.55,5.25,0),window_frame)
			_box(pole,"LampHead",Vector3(0.55,0.18,0.42),Vector3(-1.1,5.15,0),lamp_glow)
			var light := OmniLight3D.new()
			light.position = Vector3(-1.1,4.95,0)
			light.light_color = Color(1.0,0.70,0.42)
			light.light_energy = 1.15
			light.omni_range = 13.0
			pole.add_child(light)

func _build_vegetation() -> void:
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.22,0.16,0.11)
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.12,0.23,0.17)
	for i in range(18):
		var x := randf_range(-100,100)
		var z := randf_range(-100,100)
		if absf(x) < 18 or absf(z) < 18: continue
		var tree := Node3D.new()
		tree.name = "StreetTree"
		tree.position = Vector3(x,0,z)
		add_child(tree)
		_box(tree,"Trunk",Vector3(0.55,2.6,0.55),Vector3(0,1.3,0),trunk_mat)
		var crown := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 1.7
		mesh.height = 3.4
		mesh.material = leaf_mat
		crown.mesh = mesh
		crown.position.y = 3.2
		tree.add_child(crown)

func _spawn_hostiles() -> void:
	# Player._ready runs after this generator's _ready; resolve it now, not earlier.
	player = get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("PHANTOM OPS: player node missing; infected spawn skipped")
		return
	for i in range(zombie_count):
		var enemy := CharacterBody3D.new()
		enemy.name = "Infected_%02d" % i
		enemy.set_script(load("res://scripts/enemy_ai.gd"))
		enemy.set("target", player)
		enemy.position = Vector3(randf_range(-95,95),1.0,randf_range(-95,95))
		if Vector2(enemy.position.x,enemy.position.z).length() < 28.0:
			enemy.position.x += 48.0
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.48
		capsule.height = 1.9
		var collision := CollisionShape3D.new()
		collision.shape = capsule
		enemy.add_child(collision)
		var visual := MeshInstance3D.new()
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.48
		mesh.height = 1.9
		var skin := StandardMaterial3D.new()
		skin.albedo_color = Color(0.24,0.34,0.25)
		mesh.material = skin
		visual.mesh = mesh
		visual.position.y = 0.0
		enemy.add_child(visual)
		var eyes := MeshInstance3D.new()
		var eye_mesh := BoxMesh.new()
		eye_mesh.size = Vector3(0.42,0.10,0.10)
		var eye_mat := StandardMaterial3D.new()
		eye_mat.albedo_color = Color(0.8,0.08,0.035)
		eye_mat.emission_enabled = true
		eye_mat.emission = Color(0.8,0.04,0.01)
		eyes.mesh = eye_mesh
		eyes.material_override = eye_mat
		eyes.position = Vector3(0,0.42,-0.43)
		enemy.add_child(eyes)
		add_child(enemy)

func _build_weather() -> void:
	rain_particles = GPUParticles3D.new()
	rain_particles.name = "Rain"
	rain_particles.amount = 900
	rain_particles.lifetime = 1.8
	rain_particles.emitting = false
	rain_particles.position = Vector3(0,14,0)
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.05,-1.0,0.02)
	process.initial_velocity_min = 20.0
	process.initial_velocity_max = 28.0
	process.gravity = Vector3(0,-9.8,0)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(90,8,90)
	rain_particles.process_material = process
	var draw := BoxMesh.new()
	draw.size = Vector3(0.025,0.7,0.025)
	var rain_mat := StandardMaterial3D.new()
	rain_mat.albedo_color = Color(0.55,0.68,0.78,0.55)
	rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.material = rain_mat
	rain_particles.draw_pass_1 = draw
	add_child(rain_particles)
	_apply_weather()

func _apply_weather() -> void:
	if world_environment == null: return
	var env := world_environment.environment
	match weather_mode:
		0: # clear
			rain_particles.emitting = false
			env.fog_density = 0.0018
			env.ambient_light_energy = 0.72
			sun.light_energy = 1.15
		1: # overcast
			rain_particles.emitting = false
			env.fog_density = 0.0032
			env.ambient_light_energy = 0.62
			sun.light_energy = 0.75
		2: # rain
			rain_particles.emitting = true
			env.fog_density = 0.005
			env.ambient_light_energy = 0.55
			sun.light_energy = 0.55
		3: # night storm
			rain_particles.emitting = true
			env.fog_density = 0.007
			env.ambient_light_energy = 0.38
			sun.light_energy = 0.18
