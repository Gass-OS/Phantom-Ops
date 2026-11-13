extends Node3D

const SpawnerScript = preload("res://scripts/world_spawner.gd")
const ExpansionScript = preload("res://scripts/city_expansion.gd")
const MissionScript = preload("res://scripts/mission_director.gd")

var player: CharacterBody3D
var city: Node3D

func _ready() -> void:
    city = get_node_or_null("City") as Node3D
    player = get_node_or_null("Player") as CharacterBody3D

    if city == null:
        city = Node3D.new()
        city.name = "City"
        add_child(city)

    if player == null:
        push_error("PHANTOM OPS: Player node missing.")
        return

    _ensure_ground()
    _ensure_roads()
    _ensure_buildings()
    _ensure_lighting()

    if city.get_node_or_null("CityExpansion") == null:
        var expansion = ExpansionScript.new()
        expansion.name = "CityExpansion"
        city.add_child(expansion)

    # Native Godot geometry only; no imported model pack dependency.
    if city.get_node_or_null("NativeWorldDetail") == null:
        var detail = load("res://scripts/native_world_detail.gd").new()
        detail.name = "NativeWorldDetail"
        city.add_child(detail)

    if get_node_or_null("MissionDirector") == null:
        var missions = MissionScript.new()
        missions.name = "MissionDirector"
        add_child(missions)

    player.floor_snap_length = 0.6
    player.up_direction = Vector3.UP
    player.velocity = Vector3.ZERO
    player.position.y = maxf(player.position.y, 1.2)

    # Weather is owned by the city generator. Avoid a second WorldEnvironment,
    # sun and particle system being layered over the same world.

    if get_node_or_null("CityLifeVoice") == null:
        var city_voice = load("res://scripts/city_life_voice.gd").new()
        city_voice.name = "CityLifeVoice"
        add_child(city_voice)

    if get_node_or_null("WorldSpawner") == null:
        var spawner = SpawnerScript.new()
        spawner.name = "WorldSpawner"
        spawner.player = player
        add_child(spawner)

    print("PHANTOM OPS: safety world ready")


var _leaving_game := false

func _safe_return_to_menu() -> void:
    if _leaving_game:
        return
    _leaving_game = true
    var tree := get_tree()
    var old_scene := tree.current_scene as Node3D
    var menu_pack := load("res://scenes/main_menu.tscn") as PackedScene
    if menu_pack == null:
        push_error("PHANTOM OPS: unable to load main menu during safe exit")
        _leaving_game = false
        return
    var menu := menu_pack.instantiate()
    tree.root.add_child(menu)
    tree.current_scene = menu
    # Freeze gameplay and hide the old 3D scene immediately, then free it gradually.
    if is_instance_valid(old_scene):
        old_scene.process_mode = Node.PROCESS_MODE_DISABLED
        old_scene.visible = false
    var hud := tree.root.get_node_or_null("MobileHUDLayer")
    if is_instance_valid(hud):
        hud.process_mode = Node.PROCESS_MODE_DISABLED
    for effect in tree.root.find_children("*", "GPUParticles3D", true, false):
        effect.emitting = false
    for effect in tree.root.find_children("*", "CPUParticles3D", true, false):
        effect.emitting = false
    DisplayServer.tts_stop()
    if is_instance_valid(old_scene):
        var pending: Array[Node] = []
        _collect_nodes_postorder(old_scene, pending)
        var freed := 0
        for item in pending:
            if is_instance_valid(item):
                item.free()
            freed += 1
            if freed % 96 == 0:
                await tree.process_frame
    if is_instance_valid(hud):
        hud.free()
    print("PHANTOM OPS: world unloaded in batches; returned safely to menu")
    if is_instance_valid(old_scene):
        old_scene.queue_free()

func _collect_nodes_postorder(parent: Node, result: Array[Node]) -> void:
    for child in parent.get_children():
        _collect_nodes_postorder(child, result)
        result.append(child)


func _has_ground_collision() -> bool:
    var ground = city.get_node_or_null("GroundCollision")
    if ground == null:
        return false

    for child in ground.get_children():
        if child is CollisionShape3D and child.shape != null:
            return true

    return false


func _ensure_ground() -> void:
    if _has_ground_collision():
        return

    var ground = StaticBody3D.new()
    ground.name = "SafetyGround"

    var size = Vector3(360.0, 0.4, 360.0)

    var mesh = BoxMesh.new()
    mesh.size = size

    var material = StandardMaterial3D.new()
    material.albedo_color = Color(0.30, 0.32, 0.29)
    material.roughness = 1.0
    mesh.material = material

    var visual = MeshInstance3D.new()
    visual.name = "TerrainSurface"
    visual.mesh = mesh
    visual.position.y = -0.2
    ground.add_child(visual)

    var shape = BoxShape3D.new()
    shape.size = size

    var collision = CollisionShape3D.new()
    collision.name = "GroundCollisionShape"
    collision.shape = shape
    collision.position.y = -0.2
    ground.add_child(collision)

    city.add_child(ground)
    print("PHANTOM OPS: safety floor created")


func _add_box(parent: Node3D, box_name: String,
        size: Vector3, pos: Vector3, material: Material) -> void:
    var mesh = BoxMesh.new()
    mesh.size = size
    mesh.material = material

    var visual = MeshInstance3D.new()
    visual.name = box_name
    visual.mesh = mesh
    visual.position = pos
    parent.add_child(visual)


func _ensure_roads() -> void:
    if city.get_node_or_null("MainRoadNorthSouth") != null:
        return

    var road = StandardMaterial3D.new()
    road.albedo_color = Color(0.075, 0.085, 0.09)
    road.roughness = 0.95

    var line = StandardMaterial3D.new()
    line.albedo_color = Color(0.78, 0.76, 0.65)

    _add_box(city, "MainRoadNorthSouth",
        Vector3(15, 0.035, 300), Vector3(0, 0.015, 0), road)
    _add_box(city, "MainRoadEastWest",
        Vector3(300, 0.035, 15), Vector3(0, 0.016, 0), road)

    for i in range(-9, 10):
        _add_box(city, "RoadMark_%d" % i,
            Vector3(0.20, 0.025, 3.0),
            Vector3(0, 0.04, i * 9.0), line)


func _ensure_buildings() -> void:
    var count = 0

    for child in city.get_children():
        if str(child.name).begins_with("Building_"):
            count += 1

    if count >= 4:
        return

    var positions = [
        Vector2(-43, -43),
        Vector2(43, -43),
        Vector2(-43, 43),
        Vector2(43, 43),
        Vector2(-82, -43),
        Vector2(82, -43),
        Vector2(-82, 43),
        Vector2(82, 43)
    ]

    for i in range(positions.size()):
        _create_fallback_building(i, positions[i])

    print("PHANTOM OPS: fallback buildings created")


func _create_fallback_building(index: int, p: Vector2) -> void:
    var body = StaticBody3D.new()
    body.name = "Building_Fallback_%02d" % index
    body.position = Vector3(p.x, 0, p.y)
    city.add_child(body)

    var wall = StandardMaterial3D.new()
    var colors = [
        Color(0.48, 0.40, 0.31),
        Color(0.39, 0.42, 0.43),
        Color(0.52, 0.47, 0.38),
        Color(0.35, 0.39, 0.37)
    ]
    wall.albedo_color = colors[index % colors.size()]
    wall.roughness = 0.95

    var glass = StandardMaterial3D.new()
    glass.albedo_color = Color(0.035, 0.14, 0.20)
    glass.metallic = 0.25
    glass.roughness = 0.2

    var frame = StandardMaterial3D.new()
    frame.albedo_color = Color(0.12, 0.13, 0.13)

    var facade_size = Vector3(14, 8, 14)

    _add_box(body, "Facade", facade_size,
        Vector3(0, 4, 0), wall)

    var collision_shape = BoxShape3D.new()
    collision_shape.size = facade_size

    var collision = CollisionShape3D.new()
    collision.shape = collision_shape
    collision.position.y = 4
    body.add_child(collision)

    _add_box(body, "Roof", Vector3(14.5, 0.35, 14.5),
        Vector3(0, 8.15, 0), frame)

    _add_box(body, "Entrance", Vector3(1.7, 2.7, 0.16),
        Vector3(0, 1.35, -7.08), frame)

    for floor in range(2):
        for side in [-1.0, 1.0]:
            var x = side * 3.7
            var y = 3.0 + floor * 3.5

            _add_box(body, "WindowFrame",
                Vector3(1.9, 1.9, 0.16),
                Vector3(x, y, -7.08), frame)

            _add_box(body, "WindowGlass",
                Vector3(1.55, 1.55, 0.08),
                Vector3(x, y, -7.18), glass)

            _add_box(body, "SideWindow",
                Vector3(0.10, 1.5, 1.6),
                Vector3(7.08, y, 0), glass)


func _ensure_lighting() -> void:
    var has_light = false
    var has_environment = false

    for child in city.get_children():
        if child is DirectionalLight3D:
            has_light = true
        if child is WorldEnvironment:
            has_environment = true

    if not has_environment:
        var environment = Environment.new()
        environment.background_mode = Environment.BG_COLOR
        environment.background_color = Color(0.38, 0.49, 0.59)
        environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
        environment.ambient_light_color = Color(0.65, 0.68, 0.72)
        environment.ambient_light_energy = 0.8

        var world = WorldEnvironment.new()
        world.environment = environment
        city.add_child(world)

    if not has_light:
        var sun = DirectionalLight3D.new()
        sun.name = "SafetySun"
        sun.rotation_degrees = Vector3(-48, -28, 0)
        sun.light_energy = 1.2
        sun.shadow_enabled = true
        city.add_child(sun)
