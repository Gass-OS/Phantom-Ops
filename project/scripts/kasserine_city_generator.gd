extends Node3D

const ROAD_LINES = [-45.0, 0.0, 45.0]
const CELLS = [-60.0, -30.0, 30.0, 60.0]

var wall_colors = [
    Color(0.85, 0.76, 0.60),
    Color(0.92, 0.88, 0.80),
    Color(0.80, 0.62, 0.45),
    Color(0.88, 0.82, 0.70),
    Color(0.75, 0.68, 0.58)
]
var glass_mat: StandardMaterial3D
var lit_mat: StandardMaterial3D

func _ready():
    randomize()

    glass_mat = StandardMaterial3D.new()
    glass_mat.albedo_color = Color(0.12, 0.18, 0.26)
    glass_mat.roughness = 0.2
    glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

    lit_mat = StandardMaterial3D.new()
    lit_mat.albedo_color = Color(1.0, 0.85, 0.45)
    lit_mat.emission_enabled = true
    lit_mat.emission = Color(1.0, 0.8, 0.35)
    lit_mat.emission_energy_multiplier = 1.4
    lit_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

    _build_ground()
    _build_roads()
    _build_buildings()
    _build_minaret()
    _build_palms()
    _build_walls()

# ---------- ground ----------
func _build_ground():
    var ground = StaticBody3D.new()
    ground.name = "Ground"

    var grad = Gradient.new()
    grad.set_color(0, Color(0.90, 0.80, 0.62))
    grad.set_color(1, Color(0.68, 0.56, 0.38))

    var noise = FastNoiseLite.new()
    noise.frequency = 0.04

    var tex = NoiseTexture2D.new()
    tex.width = 512
    tex.height = 512
    tex.seamless = true
    tex.noise = noise
    tex.color_ramp = grad

    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(1, 1, 1)
    mat.albedo_texture = tex
    mat.uv1_scale = Vector3(25, 25, 1)
    mat.roughness = 1.0

    var plane = PlaneMesh.new()
    plane.size = Vector2(260, 260)
    plane.material = mat

    var mesh_instance = MeshInstance3D.new()
    mesh_instance.mesh = plane
    ground.add_child(mesh_instance)

    var col = CollisionShape3D.new()
    var shape = BoxShape3D.new()
    shape.size = Vector3(260, 1.0, 260)
    col.shape = shape
    col.position.y = -0.5
    ground.add_child(col)

    add_child(ground)

# ---------- roads ----------
func _add_flat_box(size: Vector3, pos: Vector3, mat: Material):
    var mi = MeshInstance3D.new()
    var box = BoxMesh.new()
    box.size = size
    box.material = mat
    mi.mesh = box
    mi.position = pos
    add_child(mi)

func _build_roads():
    var road_mat = StandardMaterial3D.new()
    road_mat.albedo_color = Color(0.22, 0.22, 0.24)
    road_mat.roughness = 0.9

    var line_mat = StandardMaterial3D.new()
    line_mat.albedo_color = Color(0.95, 0.85, 0.3)
    line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

    for line in ROAD_LINES:
        _add_flat_box(Vector3(10, 0.06, 240), Vector3(line, 0.03, 0), road_mat)
        _add_flat_box(Vector3(240, 0.06, 10), Vector3(0, 0.03, line), road_mat)
        _add_flat_box(Vector3(0.25, 0.02, 240), Vector3(line, 0.07, 0), line_mat)
        _add_flat_box(Vector3(240, 0.02, 0.25), Vector3(0, 0.07, line), line_mat)

# ---------- buildings ----------
func _build_buildings():
    var index = 0
    for cx in CELLS:
        for cz in CELLS:
            var pos = Vector3(
                cx + randf_range(-3.0, 3.0), 0.0, cz + randf_range(-3.0, 3.0)
            )
            _create_building(index, pos)
            index += 1

func _create_building(index: int, pos: Vector3):
    var sx = randf_range(9.0, 14.0)
    var sy = randf_range(7.0, 16.0)
    var sz = randf_range(9.0, 14.0)

    var building = StaticBody3D.new()
    building.name = "Building_%02d" % index
    building.position = pos

    var wall = StandardMaterial3D.new()
    wall.albedo_color = wall_colors[randi() % wall_colors.size()]
    wall.roughness = 1.0

    var box = BoxMesh.new()
    box.size = Vector3(sx, sy, sz)
    box.material = wall

    var mesh_instance = MeshInstance3D.new()
    mesh_instance.mesh = box
    mesh_instance.position.y = sy / 2.0
    building.add_child(mesh_instance)

    var collision = CollisionShape3D.new()
    var shape = BoxShape3D.new()
    shape.size = box.size
    collision.shape = shape
    collision.position.y = sy / 2.0
    building.add_child(collision)

    # Roof parapet
    var roof_mat = StandardMaterial3D.new()
    roof_mat.albedo_color = Color(0.95, 0.93, 0.88)
    var roof = BoxMesh.new()
    roof.size = Vector3(sx + 0.4, 0.5, sz + 0.4)
    roof.material = roof_mat
    var roof_instance = MeshInstance3D.new()
    roof_instance.mesh = roof
    roof_instance.position.y = sy + 0.25
    building.add_child(roof_instance)

    _add_windows(building, sx, sy, sz)
    add_child(building)

func _add_windows(building: Node3D, sx: float, sy: float, sz: float):
    var dark = SurfaceTool.new()
    dark.begin(Mesh.PRIMITIVE_TRIANGLES)
    dark.set_material(glass_mat)

    var lit = SurfaceTool.new()
    lit.begin(Mesh.PRIMITIVE_TRIANGLES)
    lit.set_material(lit_mat)

    var dark_count = 0
    var lit_count = 0

    var normals = [
        Vector3(0, 0, 1), Vector3(0, 0, -1),
        Vector3(1, 0, 0), Vector3(-1, 0, 0)
    ]

    for n in normals:
        var half_depth = sz / 2.0
        var width = sx
        if absf(n.x) > 0.5:
            half_depth = sx / 2.0
            width = sz

        var right = Vector3.UP.cross(n)
        var cols = int((width - 1.5) / 3.0)
        var rows = int((sy - 2.5) / 3.2)

        for row in range(rows):
            for col in range(cols):
                var offset = (col - (cols - 1) / 2.0) * 3.0
                var y = 2.8 + row * 3.2
                var center = n * (half_depth + 0.03) + right * offset + Vector3(0, y, 0)
                if randf() < 0.3:
                    _add_quad(lit, center, right, n, 1.2, 1.6)
                    lit_count += 1
                else:
                    _add_quad(dark, center, right, n, 1.2, 1.6)
                    dark_count += 1

    if dark_count > 0:
        var dark_instance = MeshInstance3D.new()
        dark_instance.mesh = dark.commit()
        building.add_child(dark_instance)
    if lit_count > 0:
        var lit_instance = MeshInstance3D.new()
        lit_instance.mesh = lit.commit()
        building.add_child(lit_instance)

func _add_quad(st: SurfaceTool, center: Vector3, right: Vector3, normal: Vector3, w: float, h: float):
    var rx = right * (w / 2.0)
    var uy = Vector3.UP * (h / 2.0)
    var a = center - rx - uy
    var b = center + rx - uy
    var c = center + rx + uy
    var d = center - rx + uy
    for v in [a, b, c, a, c, d]:
        st.set_normal(normal)
        st.add_vertex(v)

# ---------- minaret in the middle of the crossroads ----------
func _build_minaret():
    var tower = StaticBody3D.new()
    tower.name = "Minaret"

    var white = StandardMaterial3D.new()
    white.albedo_color = Color(0.95, 0.94, 0.9)
    var green = StandardMaterial3D.new()
    green.albedo_color = Color(0.1, 0.5, 0.35)

    var shaft_mesh = CylinderMesh.new()
    shaft_mesh.top_radius = 1.5
    shaft_mesh.bottom_radius = 2.0
    shaft_mesh.height = 26.0
    shaft_mesh.material = white
    var shaft = MeshInstance3D.new()
    shaft.mesh = shaft_mesh
    shaft.position.y = 13.0
    tower.add_child(shaft)

    var balcony_mesh = CylinderMesh.new()
    balcony_mesh.top_radius = 2.4
    balcony_mesh.bottom_radius = 2.4
    balcony_mesh.height = 0.6
    balcony_mesh.material = green
    var balcony = MeshInstance3D.new()
    balcony.mesh = balcony_mesh
    balcony.position.y = 22.0
    tower.add_child(balcony)

    var cap_mesh = CylinderMesh.new()
    cap_mesh.top_radius = 0.0
    cap_mesh.bottom_radius = 2.2
    cap_mesh.height = 4.5
    cap_mesh.material = green
    var cap = MeshInstance3D.new()
    cap.mesh = cap_mesh
    cap.position.y = 28.3
    tower.add_child(cap)

    var col = CollisionShape3D.new()
    var shape = CylinderShape3D.new()
    shape.radius = 2.0
    shape.height = 26.0
    col.shape = shape
    col.position.y = 13.0
    tower.add_child(col)

    add_child(tower)

# ---------- palm trees along the two main roads ----------
func _build_palms():
    var trunk_mat = StandardMaterial3D.new()
    trunk_mat.albedo_color = Color(0.45, 0.32, 0.2)
    var leaf_mat = StandardMaterial3D.new()
    leaf_mat.albedo_color = Color(0.2, 0.5, 0.22)
    leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

    for i in range(-7, 8):
        var along = i * 14.0
        if absf(along) < 9.0 or absf(absf(along) - 45.0) < 8.0:
            continue
        for side in [-6.2, 6.2]:
            _make_palm(Vector3(side, 0, along), trunk_mat, leaf_mat)
            _make_palm(Vector3(along, 0, side), trunk_mat, leaf_mat)

func _make_palm(pos: Vector3, trunk_mat: Material, leaf_mat: Material):
    var palm = Node3D.new()
    palm.position = pos

    var trunk_mesh = CylinderMesh.new()
    trunk_mesh.top_radius = 0.18
    trunk_mesh.bottom_radius = 0.28
    trunk_mesh.height = 6.5
    trunk_mesh.material = trunk_mat
    var trunk = MeshInstance3D.new()
    trunk.mesh = trunk_mesh
    trunk.position.y = 3.25
    palm.add_child(trunk)

    for i in range(6):
        var pivot = Node3D.new()
        pivot.position = Vector3(0, 6.4, 0)
        pivot.rotation_degrees.y = i * 60.0
        palm.add_child(pivot)

        var frond_mesh = BoxMesh.new()
        frond_mesh.size = Vector3(0.6, 0.06, 3.4)
        frond_mesh.material = leaf_mat
        var frond = MeshInstance3D.new()
        frond.mesh = frond_mesh
        frond.position = Vector3(0, -0.3, -1.5)
        frond.rotation_degrees.x = -18.0
        pivot.add_child(frond)

    add_child(palm)

# ---------- invisible walls at the edge of the map ----------
func _build_walls():
    _add_wall(Vector3(0, 5, 125), Vector3(260, 10, 2))
    _add_wall(Vector3(0, 5, -125), Vector3(260, 10, 2))
    _add_wall(Vector3(125, 5, 0), Vector3(2, 10, 260))
    _add_wall(Vector3(-125, 5, 0), Vector3(2, 10, 260))

func _add_wall(pos: Vector3, size: Vector3):
    var body = StaticBody3D.new()
    body.position = pos
    var col = CollisionShape3D.new()
    var shape = BoxShape3D.new()
    shape.size = size
    col.shape = shape
    body.add_child(col)
    add_child(body)
