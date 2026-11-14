extends RefCounted
class_name HeroAymen
## v0.4 — Aymen himself, as the hero of Phantom Ops.
## v0.6 — high-detail PBR scan (aymen_pbr.glb, 32,768 verts, 4K PBR
## textures) tried first, LowPoly scan (aymen.glb) kept as fallback.
## Both scans are the same half-body photogrammetry mesh: head +
## torso, ~0.96 m tall, centred on origin, no legs, no skeleton.
## Used ONLY as the hero — never as an enemy, never as a shootable
## target, never as a generic civilian.
## The figure is completed below with a procedural long jebba robe,
## which hides the missing legs (same trick as the citizens).
## If both GLBs fail to load, a procedural fallback hero is built
## instead so the game never breaks.

const PBR_PATH := "res://assets/characters/aymen_pbr.glb"
const GLB_PATH := "res://assets/characters/aymen.glb"
# Mesh spans y -0.48..+0.48 around its origin; place the origin at
# 1.32 m so the head sits at ~1.8 m and the torso meets the robe.
const MESH_Y := 1.32

static func build(parent: Node, pos: Vector3, rot_y: float = 0.0) -> Node3D:
	var hero := Node3D.new()
	hero.name = "AymenHero"
	hero.position = pos
	hero.rotation.y = rot_y
	parent.add_child(hero)
	# v0.6 — try the high-detail PBR scan first, fall back to LowPoly.
	# ORIENTATION (verified headless, Godot 4.2.2): the PBR file stores
	# the mesh head-down with height along local Z and carries a +90
	# deg X node rotation. Godot's glTF importer applies that rotation
	# to the MeshInstance3D, so the figure arrives UPRIGHT (head +Y,
	# face +Z) with the same ~0.96 m height and same origin as the
	# LowPoly scan. Do NOT add a rotation fix here: setting
	# rotation.x = -PI/2 on the root would undo the importer's
	# correction and lay the figure on its back (verified in test).
	var scan: PackedScene = load(PBR_PATH) as PackedScene
	var used_pbr := scan != null
	if scan == null:
		scan = load(GLB_PATH) as PackedScene
	if scan != null:
		var mesh_node := scan.instantiate()
		mesh_node.position = Vector3(0, MESH_Y, 0)
		hero.add_child(mesh_node)
		if used_pbr:
			print("Phantom Ops: Aymen hero scan loaded: PBR")
		else:
			print("Phantom Ops: Aymen hero scan loaded: LowPoly fallback")
	else:
		print("Phantom Ops: Aymen scan missing, procedural fallback hero used")
		_build_fallback(hero)
	# Long jebba robe, ground to chest — completes the figure.
	var robe_mat := StandardMaterial3D.new()
	robe_mat.albedo_color = Color(0.93, 0.90, 0.82)
	robe_mat.roughness = 1.0
	var robe := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.30
	cyl.bottom_radius = 0.44
	cyl.height = 1.0
	# Material on the mesh itself (see citizen.gd _part): avoids a
	# headless dummy-server error per part from material_override.
	cyl.material = robe_mat
	robe.mesh = cyl
	robe.position = Vector3(0, 0.5, 0)
	hero.add_child(robe)
	# Belt / sash.
	var sash := MeshInstance3D.new()
	var sash_cyl := CylinderMesh.new()
	sash_cyl.top_radius = 0.32
	sash_cyl.bottom_radius = 0.32
	sash_cyl.height = 0.12
	var sash_mat := StandardMaterial3D.new()
	sash_mat.albedo_color = Color(0.45, 0.30, 0.18)
	sash_mat.roughness = 0.95
	sash_cyl.material = sash_mat
	sash.mesh = sash_cyl
	sash.position = Vector3(0, 0.95, 0)
	hero.add_child(sash)
	return hero

static func _build_fallback(hero: Node3D) -> void:
	# Procedural stand-in: head + torso in a jebba, used only if the
	# GLB cannot be loaded. The robe below still completes the figure.
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.76, 0.58, 0.42)
	skin.roughness = 0.9
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.35, 0.40, 0.50)
	cloth.roughness = 1.0
	var torso := MeshInstance3D.new()
	var torso_cyl := CylinderMesh.new()
	torso_cyl.top_radius = 0.26
	torso_cyl.bottom_radius = 0.34
	torso_cyl.height = 0.75
	torso_cyl.material = cloth
	torso.mesh = torso_cyl
	torso.position = Vector3(0, 1.35, 0)
	hero.add_child(torso)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.14
	head_mesh.height = 0.28
	head_mesh.material = skin
	head.mesh = head_mesh
	head.position = Vector3(0, 1.85, 0)
	hero.add_child(head)
	var cap := MeshInstance3D.new()
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.11
	cap_mesh.bottom_radius = 0.13
	cap_mesh.height = 0.14
	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.70, 0.10, 0.10)
	cap_mat.roughness = 0.9
	cap_mesh.material = cap_mat
	cap.mesh = cap_mesh
	cap.position = Vector3(0, 1.98, 0)
	hero.add_child(cap)

static func add_name_label(hero: Node3D) -> void:
	var label := Label3D.new()
	label.text = "AYMEN — PHANTOM"
	label.font_size = 96
	label.pixel_size = 0.01
	label.modulate = Color(1.0, 0.85, 0.45)
	label.outline_size = 12
	label.outline_modulate = Color(0.05, 0.05, 0.08)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 2.25, 0)
	hero.add_child(label)
