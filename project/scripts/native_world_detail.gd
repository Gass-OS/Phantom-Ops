extends Node3D
class_name PhantomNativeWorldDetail

var glass := StandardMaterial3D.new()
var lit_glass := StandardMaterial3D.new()
var trim := StandardMaterial3D.new()
var concrete := StandardMaterial3D.new()
var metal := StandardMaterial3D.new()
var awnings: Array[StandardMaterial3D] = []

func _ready() -> void:
    _materials()
    call_deferred("_dress")

func _materials() -> void:
    glass.albedo_color = Color(0.025, 0.12, 0.17)
    glass.metallic = 0.35
    glass.roughness = 0.16
    lit_glass.albedo_color = Color(0.48, 0.30, 0.13)
    lit_glass.emission_enabled = true
    lit_glass.emission = Color(0.28, 0.12, 0.035)
    lit_glass.emission_energy_multiplier = 0.5
    trim.albedo_color = Color(0.10, 0.12, 0.13)
    concrete.albedo_color = Color(0.42, 0.39, 0.33)
    concrete.roughness = 0.96
    metal.albedo_color = Color(0.19, 0.21, 0.21)
    metal.metallic = 0.65
    for c in [Color(0.62,0.13,0.08), Color(0.10,0.25,0.38), Color(0.70,0.58,0.36)]:
        var m := StandardMaterial3D.new()
        m.albedo_color = c
        awnings.append(m)

func _dress() -> void:
    var world := get_parent()
    if world == null:
        return
    var count := 0
    for item in world.find_children("*", "StaticBody3D", true, false):
        var body := item as StaticBody3D
        if not (body.name.begins_with("Building_") or body.name.begins_with("DistrictBuilding_")):
            continue
        _building(body)
        count += 1
    _street_lamps(world)
    print("PHANTOM OPS: native procedural architecture detail applied: ", count)

func _building(body: StaticBody3D) -> void:
    var facade := body.get_node_or_null("Facade") as MeshInstance3D
    if facade == null:
        facade = body.get_node_or_null("ConcreteFacade") as MeshInstance3D
    if facade == null or not (facade.mesh is BoxMesh):
        return
    var s := (facade.mesh as BoxMesh).size
    var front := -s.z * 0.5 - 0.14
    var floors := maxi(1, int(s.y / 3.2) - 1)
    for floor in range(floors):
        var y := 3.0 + float(floor) * 3.2
        if y > s.y - 0.55:
            continue
        for side in [-1.0, 1.0]:
            var x := side * s.x * 0.27
            var pane: Material = lit_glass if (abs(body.name.hash()) + floor + int(side)) % 5 == 0 else glass
            _box(body, "NativeWindowFrame", Vector3(2.0,1.95,0.16), Vector3(x,y,front), trim)
            _box(body, "NativeWindowPane", Vector3(1.62,1.56,0.07), Vector3(x,y,front-0.10), pane)
            _box(body, "NativeWindowVerticalMullion", Vector3(0.07,1.55,0.09), Vector3(x,y,front-0.15), metal)
            _box(body, "NativeWindowHorizontalMullion", Vector3(1.6,0.07,0.09), Vector3(x,y,front-0.15), metal)
            _box(body, "NativeWindowSill", Vector3(2.2,0.18,0.42), Vector3(x,y-1.05,front-0.12), concrete)
            _box(body, "NativeWindowLintel", Vector3(2.2,0.16,0.30), Vector3(x,y+1.05,front-0.08), concrete)
            if floor == 0 and abs(body.name.hash()) % 3 == 0:
                _balcony(body,x,y-0.95,front-0.72)
    _box(body, "NativeDoorFrame", Vector3(2.15,3.0,0.24), Vector3(0,1.48,front-0.04), concrete)
    _box(body, "NativeDoor", Vector3(1.55,2.72,0.10), Vector3(0,1.40,front-0.19), trim)
    _box(body, "NativeDoorInset", Vector3(1.22,2.35,0.045), Vector3(0,1.42,front-0.25), metal)
    _box(body, "NativeDoorHandle", Vector3(0.07,0.18,0.08), Vector3(0.52,1.35,front-0.31), lit_glass)
    _box(body, "NativeShopCanopy", Vector3(minf(s.x*0.72,12.0),0.20,1.65), Vector3(0,3.05,front-0.78), awnings[abs(body.name.hash()) % awnings.size()])
    _box(body, "NativeRoofCoping", Vector3(s.x+0.5,0.22,s.z+0.5), Vector3(0,s.y+0.12,0), concrete)
    if abs(body.name.hash()) % 3 == 0:
        _cylinder(body,"NativeRooftopWaterTank",0.78,1.45,Vector3(s.x*0.25,s.y+0.92,s.z*0.22),metal)
        _cylinder(body,"NativeWaterTankCap",0.82,0.12,Vector3(s.x*0.25,s.y+1.68,s.z*0.22),trim)

func _balcony(parent: Node3D,x: float,y: float,z: float) -> void:
    _box(parent,"NativeBalconySlab",Vector3(2.5,0.14,1.1),Vector3(x,y,z),concrete)
    _box(parent,"NativeBalconyTopRail",Vector3(2.5,0.08,0.08),Vector3(x,y+0.85,z-0.48),metal)
    for i in range(6):
        _box(parent,"NativeBalconyBar",Vector3(0.055,0.82,0.055),Vector3(x-1.18+float(i)*0.47,y+0.43,z-0.48),metal)

func _street_lamps(world: Node3D) -> void:
    for item in world.find_children("*","Node3D",true,false):
        var n := item as Node3D
        if n.name == "StreetLamp":
            _box(n,"NativeLampHousing",Vector3(0.75,0.16,0.45),Vector3(-1.1,5.12,0),trim)

func _box(parent: Node3D,label: String,size: Vector3,at: Vector3,mat: Material) -> void:
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = mat
    var node := MeshInstance3D.new()
    node.name = label
    node.mesh = mesh
    node.position = at
    parent.add_child(node)

func _cylinder(parent: Node3D,label: String,radius: float,height: float,at: Vector3,mat: Material) -> void:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.material = mat
    var node := MeshInstance3D.new()
    node.name = label
    node.mesh = mesh
    node.position = at
    parent.add_child(node)
