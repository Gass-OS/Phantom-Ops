extends Node3D
class_name KasserineCityGenerator

@export var city_size: Vector2 = Vector2(120, 120)
@export var building_count: int = 25

var mat_sand = StandardMaterial3D.new()
var mat_wall = StandardMaterial3D.new()

func _ready():
    randomize()

    mat_sand.albedo_color = Color(0.82, 0.72, 0.55)
    mat_wall.albedo_color = Color(0.78, 0.68, 0.55)

    _build_city()

func _build_city():
    # Ground
    var ground = StaticBody3D.new()
    ground.name = "Ground"

    var ground_mesh = MeshInstance3D.new()
    var plane = PlaneMesh.new()
    plane.size = city_size * 2.0
    plane.material = mat_sand
    ground_mesh.mesh = plane
    ground.add_child(ground_mesh)

    var ground_collision = CollisionShape3D.new()
    var ground_shape = BoxShape3D.new()
    ground_shape.size = Vector3(
        city_size.x * 2.0, 0.2, city_size.y * 2.0
    )
    ground_collision.shape = ground_shape
    ground_collision.position.y = -0.1
    ground.add_child(ground_collision)

    add_child(ground)

    # Buildings
    for i in range(building_count):
        _create_building(i)

    # Sun
    var sun = DirectionalLight3D.new()
    sun.name = "Sun"
    sun.rotation_degrees = Vector3(-45, 30, 0)
    sun.shadow_enabled = true
    sun.light_energy = 1.0
    add_child(sun)

func _create_building(index: int):
    var building = StaticBody3D.new()
    building.name = "Building_%02d" % index

    var mesh_instance = MeshInstance3D.new()
    var box = BoxMesh.new()

    var sx = randf_range(6.0, 14.0)
    var sy = randf_range(4.0, 12.0)
    var sz = randf_range(6.0, 14.0)

    box.size = Vector3(sx, sy, sz)
    box.material = mat_wall

    mesh_instance.mesh = box
    mesh_instance.position.y = sy / 2.0
    building.add_child(mesh_instance)

    var collision = CollisionShape3D.new()
    var shape = BoxShape3D.new()
    shape.size = box.size
    collision.shape = shape
    collision.position.y = sy / 2.0
    building.add_child(collision)

    # Keep the central spawn area clear.
    var position := Vector3.ZERO

    for attempt in range(30):
        position = Vector3(
            randf_range(-45, 45),
            0,
            randf_range(-45, 45)
        )

        if position.length() > 18.0:
            break

    building.position = position
    add_child(building)
