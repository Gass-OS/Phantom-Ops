extends Node3D
class_name PhantomPSXWorldDressing

const WINDOW := "res://assets/psx/modular/window_2_1_single.glb"
const BARRED_WINDOW := "res://assets/psx/modular/window_metal_bars_single.glb"
const DOOR := "res://assets/psx/modular/door_1_loose.glb"

const SUPPLY_CRATE := "res://assets/psx/large_props/supply_crate_1.glb"
const WOOD_CRATE := "res://assets/psx/large_props/wooden_crate_1.glb"
const BARREL := "res://assets/psx/large_props/metal_barrel_mp_1.glb"
const CARDBOARD := "res://assets/psx/large_props/cardboard_box_1.glb"

const AMMO := "res://assets/psx/items/ammo_box_1.glb"
const BANDAGE := "res://assets/psx/items/bandage_mp_1.glb"
const FOOD := "res://assets/psx/items/canned_food_mp_1.glb"
const FLASHLIGHT := "res://assets/psx/items/flashlight_1.glb"
const BATTERY := "res://assets/psx/items/battery_mp_1.glb"

const LAMP := "res://assets/psx/lighting/lamp_1_on.glb"

const MAX_BUILDINGS := 100

var rng := RandomNumberGenerator.new()


func _ready() -> void:
    rng.seed = 13112026
    call_deferred("_dress_world")


func _dress_world() -> void:
    var world := get_parent()
    if world == null:
        return

    var buildings := world.find_children("*", "StaticBody3D", true, false)
    var decorated := 0

    for candidate in buildings:
        var building := candidate as StaticBody3D

        if not building.name.begins_with("Building_") \
        and not building.name.begins_with("DistrictBuilding_"):
            continue

        _decorate_building(building)
        decorated += 1

        if decorated >= MAX_BUILDINGS:
            break

    _dress_street_lamps(world)

    print("PHANTOM OPS: PSX dressing complete; buildings decorated: ", decorated, " / ", buildings.size())


func _decorate_building(body: StaticBody3D) -> void:
    var facade := body.get_node_or_null("Facade") as MeshInstance3D

    if facade == null:
        facade = body.get_node_or_null("ConcreteFacade") as MeshInstance3D

    if facade == null or not (facade.mesh is BoxMesh):
        return

    var dimensions := (facade.mesh as BoxMesh).size
    var width := dimensions.x
    var height := dimensions.y
    var depth := dimensions.z

    var floors := maxi(1, int(height / 3.2) - 1)

    for floor in range(floors):
        var y := 3.0 + float(floor) * 3.2

        if y > height - 0.6:
            continue

        for side in [-1.0, 1.0]:
            var x := side * width * 0.27
            var path := WINDOW

            if is_district and int(floor) == 0 and side > 0.0:
                path = BARRED_WINDOW

            _add_fitted(
                body,
                path,
                "PSX_Window",
                Vector3(x, y, -depth * 0.5 - 0.18),
                Vector3(1.65, 1.65, 0.20)
            )

    _add_fitted(
        body,
        DOOR,
        "PSX_EntranceDoor",
        Vector3(0.0, 1.4, -depth * 0.5 - 0.20),
        Vector3(1.7, 2.7, 0.20)
    )

    var front_z := -depth * 0.5 - 1.0
    var left_x := -width * 0.62
    var right_x := width * 0.62

    _add_fitted(
        body,
        SUPPLY_CRATE,
        "PSX_SupplyCrate",
        Vector3(left_x, 0.65, front_z),
        Vector3(1.25, 1.3, 1.25)
    )

    _add_fitted(
        body,
        BARREL,
        "PSX_MetalBarrel",
        Vector3(right_x, 0.60, front_z),
        Vector3(0.85, 1.2, 0.85)
    )

    if rng.randf() > 0.45:
        _add_fitted(
            body,
            WOOD_CRATE,
            "PSX_WoodCrate",
            Vector3(left_x - 1.0, 0.55, front_z - 0.8),
            Vector3(1.0, 1.0, 1.0)
        )
    else:
        _add_fitted(
            body,
            CARDBOARD,
            "PSX_CardboardBox",
            Vector3(right_x + 0.9, 0.45, front_z - 0.5),
            Vector3(0.9, 0.9, 0.9)
        )

    var loot_paths := [AMMO, BANDAGE, FOOD, FLASHLIGHT, BATTERY]
    var loot_path: String = loot_paths[rng.randi_range(0, loot_paths.size() - 1)]

    _add_fitted(
        body,
        loot_path,
        "PSX_SurvivalLoot",
        Vector3(left_x, 1.35, front_z),
        Vector3(0.30, 0.22, 0.30)
    )


func _dress_street_lamps(world: Node3D) -> void:
    var nodes := world.find_children("*", "Node3D", true, false)
    var index := 0

    for node in nodes:
        if node.name != "StreetLamp":
            continue

        if index % 3 == 0:
            _add_fitted(
                node,
                LAMP,
                "PSX_StreetLamp",
                Vector3(-1.1, 5.15, 0.0),
                Vector3(0.65, 0.40, 0.55)
            )

        index += 1


func _add_fitted(
    parent: Node3D,
    resource_path: String,
    node_name: String,
    at: Vector3,
    target_size: Vector3
) -> Node3D:
    var packed := load(resource_path) as PackedScene

    if packed == null:
        push_warning("PSX asset could not load: " + resource_path)
        return null

    var holder := Node3D.new()
    holder.name = node_name
    holder.position = at
    parent.add_child(holder)

    var model := packed.instantiate() as Node3D

    if model == null:
        holder.queue_free()
        return null

    holder.add_child(model)

    var data := {
        "found": false,
        "bounds": AABB()
    }

    _collect_bounds(model, model, data)

    if not data["found"]:
        return holder

    var bounds: AABB = data["bounds"]

    if bounds.size.x <= 0.001 \
    or bounds.size.y <= 0.001 \
    or bounds.size.z <= 0.001:
        return holder

    var factor := Vector3(
        target_size.x / bounds.size.x,
        target_size.y / bounds.size.y,
        target_size.z / bounds.size.z
    )

    model.scale = factor

    var center := bounds.get_center()
    model.position = Vector3(
        -center.x * factor.x,
        -center.y * factor.y,
        -center.z * factor.z
    )

    return holder


func _collect_bounds(node: Node, root: Node3D, data: Dictionary) -> void:
    if node is MeshInstance3D:
        var mesh_node := node as MeshInstance3D

        if mesh_node.mesh != null:
            var relative := root.global_transform.affine_inverse() \
                * mesh_node.global_transform

            var transformed: AABB = relative * mesh_node.get_aabb()

            if data["found"]:
                var previous: AABB = data["bounds"]
                data["bounds"] = previous.merge(transformed)
            else:
                data["bounds"] = transformed
                data["found"] = true

    for child in node.get_children():
        _collect_bounds(child, root, data)
