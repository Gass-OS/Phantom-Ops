extends Node3D
class_name PhantomNativeWorldDetail

var glass := StandardMaterial3D.new()
var lit_glass := StandardMaterial3D.new()
var dark_trim := StandardMaterial3D.new()
var plaster := StandardMaterial3D.new()
var stone := StandardMaterial3D.new()
var metal := StandardMaterial3D.new()
var wood := StandardMaterial3D.new()
var awnings: Array[StandardMaterial3D] = []

func _ready() -> void:
    _make_materials()
    call_deferred("_upgrade_city")

func _make_materials() -> void:
    glass.albedo_color = Color(0.018,0.075,0.105)
    glass.metallic = 0.28
    glass.roughness = 0.12
    lit_glass.albedo_color = Color(0.68,0.43,0.19)
    lit_glass.emission_enabled = true
    lit_glass.emission = Color(0.32,0.15,0.045)
    lit_glass.emission_energy_multiplier = 0.8
    dark_trim.albedo_color = Color(0.075,0.085,0.09)
    plaster.albedo_color = Color(0.67,0.61,0.49)
    plaster.roughness = 0.96
    stone.albedo_color = Color(0.36,0.34,0.29)
    stone.roughness = 0.98
    metal.albedo_color = Color(0.16,0.19,0.20)
    metal.metallic = 0.68
    wood.albedo_color = Color(0.20,0.105,0.055)
    for c in [Color(0.62,0.12,0.07),Color(0.08,0.23,0.34),Color(0.72,0.58,0.34),Color(0.20,0.34,0.22)]:
        var m := StandardMaterial3D.new()
        m.albedo_color = c
        m.roughness = 0.88
        awnings.append(m)

func _upgrade_city() -> void:
    var world := get_parent()
    if world == null:
        return
    var upgraded := 0
    var skipped := 0
    for item in world.find_children("*","StaticBody3D",true,false):
        var body := item as StaticBody3D
        if not (body.name.begins_with("Building_") or body.name.begins_with("DistrictBuilding_")):
            continue
        if body.get_node_or_null("NativeArchitectureV2") != null:
            continue
        if _upgrade_building(body):
            upgraded += 1
        else:
            skipped += 1
    _add_city_props(world)
    print("PHANTOM OPS: native architecture V2 upgraded ",upgraded," buildings; skipped ",skipped)

func _upgrade_building(body: StaticBody3D) -> bool:
    var dimensions := Vector3.ZERO
    for child in body.get_children():
        if child is CollisionShape3D and child.shape is BoxShape3D:
            dimensions = (child.shape as BoxShape3D).size
            break
    if dimensions == Vector3.ZERO:
        var facade := body.get_node_or_null("Facade") as MeshInstance3D
        if facade == null:
            facade = body.get_node_or_null("ConcreteFacade") as MeshInstance3D
        if facade != null and facade.mesh is BoxMesh:
            dimensions = (facade.mesh as BoxMesh).size
    if dimensions == Vector3.ZERO:
        return false

    var root := Node3D.new()
    root.name = "NativeArchitectureV2"
    body.add_child(root)
    var w := dimensions.x
    var h := dimensions.y
    var d := dimensions.z
    var front := -d*0.5-0.22
    var rear := d*0.5+0.18
    var floors := maxi(1,int(h/3.15))
    var window_width := clampf(w*0.16,1.35,2.15)
    var window_height := 1.72

    # Corner pilasters and strong floor courses break up the plain cube silhouette.
    for x in [-w*0.47,w*0.47]:
        _box(root,"FacadeCornerPier",Vector3(0.34,h,0.34),Vector3(x,h*0.5,front-0.04),plaster)
        _box(root,"FacadeCornerCap",Vector3(0.52,0.22,0.48),Vector3(x,h-0.16,front-0.05),stone)
    for floor in range(1,floors+1):
        var band_y := minf(float(floor)*3.15,h-0.16)
        _box(root,"ContinuousFloorBand",Vector3(w+0.32,0.20,0.38),Vector3(0,band_y,front-0.06),stone)
        _box(root,"SideFloorBand",Vector3(0.34,0.20,d+0.2),Vector3(-w*0.5-0.06,band_y,0),stone)
        _box(root,"SideFloorBand",Vector3(0.34,0.20,d+0.2),Vector3(w*0.5+0.06,band_y,0),stone)

    # Front and rear windows: deep reveals, sill, lintel, shutters and crossbars.
    for face in [front,rear]:
        var direction := -1.0 if face == front else 1.0
        for floor in range(floors):
            var cy := 2.85+float(floor)*3.15
            if cy+window_height*0.5 > h-0.45:
                continue
            for col in [-1.0,0.0,1.0]:
                if col == 0.0 and w < 12.5:
                    continue
                var x := col*w*0.29
                _window(root,x,cy,face,direction,window_width,window_height)
                if floor == 0 and col != 0.0 and (abs(body.name.hash())%3==0):
                    _balcony(root,x,cy-1.03,face,direction,window_width+0.48)
    
    # Side elevations get real window frames too, not just flat dark rectangles.
    for side in [-1.0,1.0]:
        var side_x := side*(w*0.5+0.16)
        for floor in range(floors):
            var cy := 2.85+float(floor)*3.15
            if cy+0.86 > h:
                continue
            for col in [-1.0,0.0,1.0]:
                var z := col*d*0.27
                _box(root,"SideWindowReveal",Vector3(0.20,1.95,1.72),Vector3(side_x,cy,z),dark_trim)
                _box(root,"SideWindowGlass",Vector3(0.075,1.58,1.34),Vector3(side*(w*0.5+0.275),cy,z),glass)
                _box(root,"SideWindowCrossbar",Vector3(0.08,0.07,1.32),Vector3(side*(w*0.5+0.33),cy,z),metal)
                _box(root,"SideWindowSill",Vector3(0.34,0.16,1.88),Vector3(side*(w*0.5+0.27),cy-0.91,z),stone)

    # Street-level shopfront, recessed entrance, steps and sign fascia.
    _box(root,"ShopSignFascia",Vector3(w*0.76,0.48,0.24),Vector3(0,3.15,front-0.42),dark_trim)
    _box(root,"ShopGlassFront",Vector3(w*0.52,2.45,0.10),Vector3(-w*0.17,1.35,front-0.30),glass)
    _box(root,"ShopMetalFrame",Vector3(0.12,2.55,0.18),Vector3(-w*0.17,1.35,front-0.39),metal)
    _box(root,"EntranceRecess",Vector3(1.95,2.95,0.22),Vector3(w*0.25,1.47,front-0.34),dark_trim)
    _box(root,"EntranceDoorWood",Vector3(1.55,2.66,0.10),Vector3(w*0.25,1.38,front-0.49),wood)
    _box(root,"EntranceDoorInset",Vector3(1.20,2.25,0.045),Vector3(w*0.25,1.40,front-0.55),stone)
    _box(root,"DoorHandle",Vector3(0.07,0.18,0.08),Vector3(w*0.25+0.48,1.36,front-0.62),metal)
    _box(root,"EntryStep",Vector3(2.6,0.18,0.85),Vector3(w*0.25,0.08,front-0.72),stone)
    _box(root,"ShopAwning",Vector3(w*0.82,0.20,1.65),Vector3(0,3.42,front-0.95),awnings[abs(body.name.hash())%awnings.size()])

    # Parapet, roof utility structures, vents and water tank.
    _box(root,"RoofParapetFront",Vector3(w+0.6,0.72,0.42),Vector3(0,h+0.30,-d*0.5),plaster)
    _box(root,"RoofParapetRear",Vector3(w+0.6,0.72,0.42),Vector3(0,h+0.30,d*0.5),plaster)
    _box(root,"RoofParapetLeft",Vector3(0.42,0.72,d),Vector3(-w*0.5,h+0.30,0),plaster)
    _box(root,"RoofParapetRight",Vector3(0.42,0.72,d),Vector3(w*0.5,h+0.30,0),plaster)
    _box(root,"RooftopUtilityRoom",Vector3(minf(w*0.32,4.8),1.65,minf(d*0.30,4.5)),Vector3(-w*0.22,h+1.0,d*0.18),stone)
    _cylinder(root,"RooftopWaterTank",0.72,1.55,Vector3(w*0.24,h+1.0,d*0.18),metal)
    _cylinder(root,"WaterTankLid",0.76,0.12,Vector3(w*0.24,h+1.82,d*0.18),dark_trim)
    for i in range(3):
        _box(root,"RoofVent",Vector3(0.55,0.85,0.55),Vector3(-w*0.32+float(i)*0.8,h+0.45,-d*0.2),metal)
    # Air conditioners and drain pipes on the side elevation.
    for floor in range(mini(floors,4)):
        var y := 2.1+float(floor)*3.15
        _box(root,"ExteriorACUnit",Vector3(0.55,0.48,0.75),Vector3(w*0.5+0.42,y,0),metal)
    _box(root,"FacadeDrainPipe",Vector3(0.12,h,0.12),Vector3(w*0.5+0.32,h*0.5, -d*0.35),dark_trim)
    return true

func _window(parent: Node3D,x: float,y: float,z: float,direction: float,w: float,h: float) -> void:
    _box(parent,"WindowDeepReveal",Vector3(w+0.34,h+0.34,0.22),Vector3(x,y,z),dark_trim)
    _box(parent,"WindowGlassPane",Vector3(w,h,0.075),Vector3(x,y,z+direction*0.14),glass)
    _box(parent,"WindowVerticalMullion",Vector3(0.075,h,0.10),Vector3(x,y,z+direction*0.20),metal)
    _box(parent,"WindowHorizontalMullion",Vector3(w,0.075,0.10),Vector3(x,y,z+direction*0.20),metal)
    _box(parent,"WindowStoneSill",Vector3(w+0.55,0.20,0.48),Vector3(x,y-h*0.60,z+direction*0.16),stone)
    _box(parent,"WindowStoneLintel",Vector3(w+0.55,0.18,0.38),Vector3(x,y+h*0.60,z+direction*0.12),plaster)
    for side in [-1.0,1.0]:
        _box(parent,"WindowShutter",Vector3(0.16,h*0.90,0.12),Vector3(x+side*(w*0.5+0.16),y,z+direction*0.18),wood)

func _balcony(parent: Node3D,x: float,y: float,z: float,direction: float,width: float) -> void:
    _box(parent,"BalconyConcreteSlab",Vector3(width,0.18,1.15),Vector3(x,y,z+direction*0.55),stone)
    _box(parent,"BalconyTopRail",Vector3(width,0.10,0.10),Vector3(x,y+0.88,z+direction*0.08),metal)
    for i in range(7):
        var px := x-width*0.46+float(i)*width*0.153
        _box(parent,"BalconyRailingBar",Vector3(0.065,0.82,0.08),Vector3(px,y+0.45,z+direction*0.08),metal)

func _add_city_props(world: Node3D) -> void:
    var index := 0
    for item in world.find_children("*","StaticBody3D",true,false):
        var body := item as StaticBody3D
        if not (body.name.begins_with("Building_") or body.name.begins_with("DistrictBuilding_")):
            continue
        if index >= 18:
            break
        var side := -1.0 if index%2==0 else 1.0
        var planter := Node3D.new()
        planter.name = "NativeStreetPlanter"
        planter.position = Vector3(side*9.5,0,7.0)
        body.add_child(planter)
        _box(planter,"PlanterStone",Vector3(1.5,0.65,1.1),Vector3.ZERO,stone)
        _box(planter,"PlanterShrub",Vector3(1.1,0.8,0.75),Vector3(0,0.65,0),awnings[3])
        _box(body,"WallMountedSign",Vector3(2.1,0.8,0.12),Vector3(0,4.0,-7.0),awnings[index%awnings.size()])
        index += 1

func _box(parent: Node3D,label: String,size: Vector3,at: Vector3,material: Material) -> void:
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    var visual := MeshInstance3D.new()
    visual.name = label
    visual.mesh = mesh
    visual.position = at
    parent.add_child(visual)

func _cylinder(parent: Node3D,label: String,radius: float,height: float,at: Vector3,material: Material) -> void:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.material = material
    var visual := MeshInstance3D.new()
    visual.name = label
    visual.mesh = mesh
    visual.position = at
    parent.add_child(visual)
