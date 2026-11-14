extends CharacterBody3D
## Phantom Ops v0.6 — citizens upgrade (SYSTEM 3).
## Rebuilt model: pelvis + torso, head on a look-around pivot,
## two-segment arms (upper arm / forearm + hand) and legs
## (thigh / shin + foot), varied heights (0.9–1.1) and builds
## (slim/wide). Men wear a long jebba + chechia (some bearded);
## women a long dress + hijab. Primitive meshes only, materials
## shared through a static cache, so 24 citizens stay cheap.
##
## Behaviour states: WALK / IDLE / CHAT / SUSPICIOUS / BEG / FLEE.
## Hidden traits, rolled in _ready (rates come from CitizenSpawner):
##   is_criminal  ~15% of MEN — walks SUSPICIOUS (looks around, fast
##                  walk, runs if the player gets close).
##   is_poor      ~20% — BEG: approaches the player slowly asking for
##                  help/money; stops begging once helped.
##   is_funny     ~25% — tells jokes in bubbles, occasional laugh-spin.
##   is_suspicious — criminals, plus ~10% of innocent men who just
##                  look nervous. CHECK in the InteractionManager tells
##                  them apart: criminals flee, innocents greet.
## Citizens stay in group "civilian" and have NO take_damage — the
## player fire code already skips that group (v0.4 rule, unchanged).
##
## Speech bubbles: a Label3D above the head. Lines go through
## LanguageManager.translate() (static API — a static tr() is
## impossible in Godot 4.2, Object.tr() is non-static). Keys that
## LanguageManager does not have yet fall back to the English text
## in the pools below. Chat greetings call SoundManager.greet()
## (static, exists, internally throttled to one TTS line per 8 s).
##
## Public API for the coordinator / mission worker / InteractionManager:
##   state, is_criminal, is_poor, is_funny, is_suspicious, is_in_need,
##   helped, exposed, chat_partner
##   set_in_need(v), mark_helped(), expose_as_criminal(),
##   start_flee(from_pos, speed, duration), start_chat_with(other),
##   say(key, fallback, duration), say_text(text, duration),
##   say_random(pool, duration), say_greeting()
##   signals: citizen_helped(citizen), criminal_exposed(citizen)

enum State { WALK, IDLE, CHAT, SUSPICIOUS, BEG, FLEE }

signal citizen_helped(citizen: Node)
signal criminal_exposed(citizen: Node)

const CRIMINAL_CHANCE := 0.15
const POOR_CHANCE := 0.20
const FUNNY_CHANCE := 0.25
const NERVOUS_CHANCE := 0.10

# Line pools: [translation key, English fallback]. Keys that exist in
# LanguageManager (greeting_*, citizen_help, citizen_thanks,
# citizen_joke_1/2) translate to FR/AR; the rest fall back to the
# English text below until the languages worker adds them.
const GREET_LINES: Array = [
	["greeting_salam", "Salam!"],
	["greeting_marhaba", "Marhaba!"],
	["greeting_salam_alaykum", "Salam alaykum!"],
	["greeting_ahla", "Ahla wa sahla!"],
]
const JOKE_LINES: Array = [
	["citizen_joke_1", "I told my wife I joined the police... now she arrests me every time I leave dishes in the sink!"],
	["citizen_joke_2", "In Kasserine, even the pigeons know the patrol routes — they fly away before the siren!"],
	["citizen_joke_3", "I told a zombie a joke — he died laughing. Again."],
	["citizen_joke_4", "Kasserine traffic! Even the zombies walk."],
]
const HELP_LINES: Array = [
	["citizen_help", "Please help!"],
	["citizen_help_2", "Please, some money for bread..."],
	["citizen_help_3", "Ya khuya, help me, please!"],
]
const THANKS_LINES: Array = [
	["citizen_thanks", "Thank you, officer!"],
	["citizen_thanks_2", "Shukran! Thank you, officer!"],
	["citizen_thanks_3", "Barakallahu fik!"],
]
const CHAT_LINES: Array = [
	["citizen_chat_1", "Did you hear? The police are back!"],
	["citizen_chat_2", "The market is busy today."],
	["citizen_chat_3", "My cousin saw a zombie near the mosque!"],
	["citizen_chat_4", "Did you try the new bakery?"],
]
const SUSPICIOUS_LINES: Array = [
	["citizen_suspicious_1", "I... I was just walking!"],
	["citizen_suspicious_2", "Nothing to see here, officer."],
]
const SAD_LINES: Array = [
	["citizen_sad_1", "No money... maybe next time."],
	["citizen_sad_2", "Ah... I understand."],
]

# Shared materials: one StandardMaterial3D per colour for all citizens.
static var _mat_cache: Dictionary = {}

static func _mat(color: Color) -> StandardMaterial3D:
	if _mat_cache.has(color):
		return _mat_cache[color] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	_mat_cache[color] = m
	return m

var is_female: bool = false
var variant: int = 0
# Trait rates — CitizenSpawner overrides these before add_child.
var criminal_chance: float = CRIMINAL_CHANCE
var poor_chance: float = POOR_CHANCE
var funny_chance: float = FUNNY_CHANCE

var state: int = State.WALK
var is_criminal: bool = false
var is_poor: bool = false
var is_funny: bool = false
var is_suspicious: bool = false
var is_in_need: bool = false
var helped: bool = false
var exposed: bool = false
var chat_partner: Node = null

var axis: int = 0
var city_extent: float = 220.0
var lane: float = 0.0
var target: Vector3 = Vector3.ZERO
var wait_time: float = 0.0
var idle_timer: float = 0.0
var gravity: float = 14.0
var walk_phase: float = 0.0
var flee_timer: float = 0.0
var flee_dir: Vector3 = Vector3.ZERO
var flee_speed: float = 4.2
var threat_dir: Vector3 = Vector3.ZERO
var chat_timer: float = 0.0
var chat_cooldown: float = 0.0
var _chat_turn: bool = false
var _chat_line_t: float = 0.0
var _chat_scan_t: float = 0.0
var _scan_t: float = 0.0
var _player: Node3D = null
var _player_dist: float = -1.0
var _beg_say_t: float = 0.0
var _funny_t: float = 6.0
var _laugh_t: float = 0.0
var _moving: bool = false
var _bubble_t: float = 0.0

# Skeleton pivots.
var model: Node3D
var torso_pivot: Node3D
var head_pivot: Node3D
var arm_l_up: Node3D
var arm_l_fore: Node3D
var arm_r_up: Node3D
var arm_r_fore: Node3D
var leg_l_thigh: Node3D
var leg_l_shin: Node3D
var leg_r_thigh: Node3D
var leg_r_shin: Node3D
var bubble: Label3D

var skins = [Color(0.87, 0.70, 0.52), Color(0.76, 0.58, 0.42), Color(0.68, 0.50, 0.36)]
var robe_colors = [
	Color(0.93, 0.90, 0.82), Color(0.80, 0.78, 0.72),
	Color(0.55, 0.42, 0.30), Color(0.35, 0.40, 0.50)
]
var dress_colors = [
	Color(0.20, 0.25, 0.40), Color(0.45, 0.20, 0.30), Color(0.15, 0.40, 0.40),
	Color(0.30, 0.30, 0.30), Color(0.55, 0.35, 0.50)
]
var hijab_colors = [
	Color(0.95, 0.95, 0.95), Color(0.85, 0.40, 0.55), Color(0.20, 0.55, 0.60),
	Color(0.50, 0.30, 0.60), Color(0.15, 0.20, 0.40)
]
var poor_colors = [
	Color(0.45, 0.42, 0.38), Color(0.35, 0.33, 0.30), Color(0.50, 0.45, 0.35)
]

func _ready():
	add_to_group("civilian")

	axis = randi() % 2
	lane = [-160.0, -80.0, 0.0, 80.0, 160.0][randi() % 5] + [-3.2, 3.2][randi() % 2]
	floor_snap_length = 0.42
	floor_stop_on_slope = true
	position = _lane_point(randf_range(-city_extent, city_extent))
	target = _lane_point(randf_range(-100.0, 100.0))

	# Hidden traits (rolled before the model is built: poor citizens
	# wear duller clothes; criminals look exactly like anyone else).
	is_poor = randf() < poor_chance
	is_funny = randf() < funny_chance
	if not is_female and randf() < criminal_chance:
		is_criminal = true
		is_suspicious = true
	elif not is_female and randf() < NERVOUS_CHANCE:
		is_suspicious = true
	state = State.SUSPICIOUS if is_suspicious else State.WALK
	_funny_t = randf_range(4.0, 12.0)

	var col = CollisionShape3D.new()
	var cap = CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	col.shape = cap
	add_child(col)

	_build_model()
	_build_bubble()

func _lane_point(along: float) -> Vector3:
	if axis == 0:
		return Vector3(along, 0.9, lane)
	return Vector3(lane, 0.9, along)

func _part(mesh: PrimitiveMesh, color: Color, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	# v0.4: set the material on the PrimitiveMesh itself, not
	# material_override on the instance. material_override makes the
	# headless dummy rendering server query a surface count on a mesh
	# whose RID does not exist yet (one engine error per part). On a
	# real phone it renders the same. Materials are shared via _mat().
	mesh.material = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi

func _build_model():
	var skin = skins[variant % skins.size()]
	var cloth = robe_colors[variant % robe_colors.size()]
	if is_female:
		cloth = dress_colors[variant % dress_colors.size()]
	if is_poor:
		cloth = poor_colors[variant % poor_colors.size()]

	# Varied height (0.9–1.1, women slightly shorter) and build.
	var height_scale := randf_range(0.9, 1.1)
	if is_female:
		height_scale = randf_range(0.88, 1.04)
	var build_scale := randf_range(0.9, 1.15)

	model = Node3D.new()
	model.name = "Model"
	model.scale = Vector3(build_scale, height_scale, build_scale)
	add_child(model)

	# Robe / long dress. Men: hem at mid-shin so shins + feet show.
	# Women: ankle-length dress, only the feet poke out.
	var robe = CylinderMesh.new()
	if is_female:
		robe.top_radius = 0.27
		robe.bottom_radius = 0.37
		robe.height = 1.35
		_part(robe, cloth, Vector3(0, -0.175, 0), model)
	else:
		robe.top_radius = 0.25
		robe.bottom_radius = 0.34
		robe.height = 1.05
		_part(robe, cloth, Vector3(0, -0.05, 0), model)

	# Pelvis.
	var pelvis = BoxMesh.new()
	pelvis.size = Vector3(0.34, 0.18, 0.22)
	_part(pelvis, cloth, Vector3(0, 0.02, 0), model)

	# Torso pivot (lean + sway live here; arms and head follow it).
	torso_pivot = Node3D.new()
	torso_pivot.name = "Torso"
	torso_pivot.position = Vector3(0, 0.10, 0)
	model.add_child(torso_pivot)
	var torso = BoxMesh.new()
	torso.size = Vector3(0.38, 0.44, 0.24)
	_part(torso, cloth, Vector3(0, 0.20, 0), torso_pivot)
	# Chest shading strip (a slightly darker band across the chest).
	var chest = BoxMesh.new()
	chest.size = Vector3(0.39, 0.10, 0.25)
	_part(chest, cloth.darkened(0.15), Vector3(0, 0.34, 0), torso_pivot)

	# Head on its own pivot so the citizen can look around.
	head_pivot = Node3D.new()
	head_pivot.name = "Head"
	head_pivot.position = Vector3(0, 0.46, 0)
	torso_pivot.add_child(head_pivot)
	var head = SphereMesh.new()
	head.radius = 0.14
	head.height = 0.28
	_part(head, skin, Vector3(0, 0.08, 0), head_pivot)

	if is_female:
		var hijab_color = hijab_colors[int(variant / 2) % hijab_colors.size()]
		var hood = SphereMesh.new()
		hood.radius = 0.19
		hood.height = 0.40
		_part(hood, hijab_color, Vector3(0, 0.08, 0.02), head_pivot)
		var cape = CylinderMesh.new()
		cape.top_radius = 0.28
		cape.bottom_radius = 0.31
		cape.height = 0.5
		_part(cape, hijab_color, Vector3(0, -0.18, 0), head_pivot)
	else:
		var cap_mesh = CylinderMesh.new()
		cap_mesh.top_radius = 0.11
		cap_mesh.bottom_radius = 0.13
		cap_mesh.height = 0.16
		var cap_color = Color(0.7, 0.1, 0.1)
		if variant % 3 == 1:
			cap_color = Color(0.95, 0.95, 0.95)
		_part(cap_mesh, cap_color, Vector3(0, 0.22, 0), head_pivot)
		if variant % 3 == 2:
			var beard = SphereMesh.new()
			beard.radius = 0.08
			beard.height = 0.16
			_part(beard, Color(0.12, 0.1, 0.1), Vector3(0, 0.02, -0.10), head_pivot)

	# Two-segment arms and legs.
	var arms_l = _make_arm(-0.24, cloth, skin)
	arm_l_up = arms_l[0]
	arm_l_fore = arms_l[1]
	var arms_r = _make_arm(0.24, cloth, skin)
	arm_r_up = arms_r[0]
	arm_r_fore = arms_r[1]
	var legs_l = _make_leg(-0.13, cloth, skin)
	leg_l_thigh = legs_l[0]
	leg_l_shin = legs_l[1]
	var legs_r = _make_leg(0.13, cloth, skin)
	leg_r_thigh = legs_r[0]
	leg_r_shin = legs_r[1]

func _make_arm(x: float, cloth: Color, skin: Color) -> Array:
	var up = Node3D.new()
	up.position = Vector3(x, 0.36, 0)
	torso_pivot.add_child(up)
	var upper = CapsuleMesh.new()
	upper.radius = 0.06
	upper.height = 0.32
	_part(upper, cloth, Vector3(0, -0.15, 0), up)

	var fore = Node3D.new()
	fore.position = Vector3(0, -0.30, 0)
	up.add_child(fore)
	var farm = CapsuleMesh.new()
	farm.radius = 0.055
	farm.height = 0.28
	_part(farm, cloth, Vector3(0, -0.13, 0), fore)
	var hand = SphereMesh.new()
	hand.radius = 0.055
	hand.height = 0.11
	_part(hand, skin, Vector3(0, -0.29, 0), fore)
	return [up, fore]

func _make_leg(x: float, cloth: Color, skin: Color) -> Array:
	var thigh = Node3D.new()
	thigh.position = Vector3(x, -0.08, 0)
	model.add_child(thigh)
	var thigh_mesh = CapsuleMesh.new()
	thigh_mesh.radius = 0.085
	thigh_mesh.height = 0.36
	_part(thigh_mesh, cloth, Vector3(0, -0.18, 0), thigh)

	var shin = Node3D.new()
	shin.position = Vector3(0, -0.38, 0)
	thigh.add_child(shin)
	var shin_mesh = CapsuleMesh.new()
	shin_mesh.radius = 0.075
	shin_mesh.height = 0.36
	_part(shin_mesh, cloth, Vector3(0, -0.18, 0), shin)
	var foot = BoxMesh.new()
	foot.size = Vector3(0.10, 0.05, 0.22)
	_part(foot, skin.darkened(0.2), Vector3(0, -0.38, -0.05), shin)
	return [thigh, shin]

func _build_bubble():
	bubble = Label3D.new()
	bubble.name = "Bubble"
	bubble.position = Vector3(0, 1.18, 0)
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	bubble.pixel_size = 0.008
	bubble.font_size = 48
	bubble.outline_size = 8
	bubble.outline_modulate = Color(0, 0, 0, 0.9)
	bubble.modulate = Color(1, 1, 1)
	bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble.visible = false
	add_child(bubble)

# ---------------------------------------------------------------- speech

# Translated line if LanguageManager has the key, else the English
# fallback. The dictionary is checked first so keys the languages
# worker has not added yet do not spam its "missing key" warning on
# every bubble. (translate() itself falls back to EN, then the key.)
func _tr(key: String, fallback: String) -> String:
	var strings: Dictionary = LanguageManager.STRINGS
	var lang: Dictionary = strings.get(LanguageManager.current(), {})
	var en: Dictionary = strings.get("en", {})
	if lang.has(key) or en.has(key):
		return LanguageManager.translate(key)
	return fallback

func say(key: String, fallback: String, duration: float = 3.0) -> void:
	say_text(_tr(key, fallback), duration)

func say_text(text: String, duration: float = 3.0) -> void:
	if bubble == null:
		return
	# Arabic needs the Noto Naskh font or the bubble shows disconnected
	# glyphs; font_for_current() returns null for FR/EN (default font).
	bubble.font = LanguageManager.font_for_current()
	bubble.text = text
	bubble.visible = true
	_bubble_t = duration

func say_random(pool: Array, duration: float = 3.0) -> void:
	if pool.is_empty():
		return
	var line: Array = pool[randi() % pool.size()]
	say(str(line[0]), str(line[1]), duration)

func say_greeting() -> void:
	say_random(GREET_LINES, 3.0)
	SoundManager.greet()

# ------------------------------------------------------- public API (v0.6)

# Mission worker: mark this citizen as the one who needs HELP.
func set_in_need(v: bool) -> void:
	is_in_need = v
	if v:
		helped = false
		say_random(HELP_LINES, 4.0)
		if state == State.WALK:
			state = State.IDLE
			idle_timer = 6.0

# Called by InteractionManager after a HELP or GIVE: the citizen
# stops begging / asking and thanks the player.
func mark_helped() -> void:
	helped = true
	is_in_need = false
	if state == State.BEG or state == State.IDLE:
		state = State.WALK
	say_random(THANKS_LINES, 3.5)
	citizen_helped.emit(self)

# Called by InteractionManager after a CHECK catches a criminal:
# he runs away fast (the mission worker can treat it as a chase).
func expose_as_criminal() -> void:
	exposed = true
	start_flee(_player_pos_or_random(), 5.5, 4.0)
	say_random(SUSPICIOUS_LINES, 2.5)
	criminal_exposed.emit(self)

func start_flee(from_pos: Vector3, speed: float, duration: float) -> void:
	if state == State.CHAT:
		_end_chat()
	var away := global_position - from_pos
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))
	flee_dir = away.normalized()
	flee_speed = speed
	flee_timer = duration
	state = State.FLEE

func start_chat_with(other: Node) -> void:
	if state != State.WALK:
		return
	state = State.CHAT
	chat_partner = other
	chat_timer = randf_range(3.5, 6.0)
	_chat_turn = false
	_chat_line_t = 0.5

func get_state_name() -> String:
	return ["WALK", "IDLE", "CHAT", "SUSPICIOUS", "BEG", "FLEE"][state]

func _player_pos_or_random() -> Vector3:
	if _player != null and is_instance_valid(_player):
		return _player.global_position
	return global_position + Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))

func _end_chat() -> void:
	var p := chat_partner
	chat_partner = null
	_chat_turn = false
	if state == State.CHAT:
		state = State.WALK
		chat_cooldown = randf_range(8.0, 15.0)
	if p != null and is_instance_valid(p) and int(p.get("state")) == State.CHAT:
		p.call("_end_chat")

# ---------------------------------------------------------------- process

func _process(delta: float) -> void:
	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0 and bubble != null:
			bubble.visible = false

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y = maxf(velocity.y - gravity * delta, -28.0)
	elif velocity.y < 0.0:
		velocity.y = 0.0

	chat_cooldown = maxf(0.0, chat_cooldown - delta)
	_funny_t -= delta
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.4
		_scan_threat()
		_scan_player()

	# Zombies override everything: flee.
	if threat_dir != Vector3.ZERO and state != State.FLEE:
		start_flee(global_position - threat_dir * 10.0, 4.2, 1.5)

	match state:
		State.FLEE:
			_tick_flee(delta)
		State.CHAT:
			_tick_chat(delta)
		State.IDLE:
			_tick_idle(delta)
		State.SUSPICIOUS:
			_tick_suspicious(delta)
		State.BEG:
			_tick_beg(delta)
		_:
			_tick_walk(delta)

	_update_pose(delta)
	_update_head(delta)

func _scan_threat() -> void:
	threat_dir = Vector3.ZERO
	for z in get_tree().get_nodes_in_group("zombie"):
		var d = global_position - (z as Node3D).global_position
		d.y = 0.0
		if d.length() < 14.0:
			threat_dir += d.normalized()

func _scan_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player != null:
		_player_dist = global_position.distance_to(_player.global_position)
	else:
		_player_dist = -1.0

func _tick_flee(delta: float) -> void:
	flee_timer -= delta
	if flee_timer <= 0.0:
		state = State.SUSPICIOUS if is_suspicious else State.WALK
		threat_dir = Vector3.ZERO
		_stand(delta)
		return
	_walk_toward(global_position + flee_dir, flee_speed, delta)

func _tick_chat(delta: float) -> void:
	_stand(delta)
	if chat_partner == null or not is_instance_valid(chat_partner) or int(chat_partner.get("state")) != State.CHAT:
		_end_chat()
		return
	# Face each other.
	var to_partner: Vector3 = (chat_partner as Node3D).global_position - global_position
	to_partner.y = 0.0
	if to_partner.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-to_partner.x, -to_partner.z), delta * 6.0)
	chat_timer -= delta
	if chat_timer <= 0.0:
		_end_chat()
		return
	# Take turns exchanging 2–3 lines.
	if _chat_turn:
		_chat_line_t -= delta
		if _chat_line_t <= 0.0:
			say_random(CHAT_LINES, 2.6)
			_chat_line_t = randf_range(1.6, 2.4)
			_chat_turn = false
			chat_partner.set("_chat_turn", true)
			chat_partner.set("_chat_line_t", 0.5)

func _tick_idle(delta: float) -> void:
	_stand(delta)
	idle_timer -= delta
	if is_funny and _funny_t <= 0.0:
		_funny_t = randf_range(6.0, 14.0)
		_laugh_t = 0.9
		say_random(JOKE_LINES, 3.0)
	if idle_timer <= 0.0:
		if is_in_need and not helped:
			# A citizen in need waits where he is and keeps asking.
			idle_timer = randf_range(3.0, 5.0)
			say_random(HELP_LINES, 3.0)
		else:
			state = State.WALK

func _tick_suspicious(delta: float) -> void:
	# Nervous fast walk along the lane; runs if the player gets close.
	if _player_dist >= 0.0 and _player_dist < 3.0:
		start_flee(_player.global_position, 5.5, 3.0)
		return
	var diff = target - global_position
	diff.y = 0.0
	if diff.length() < 1.2:
		target = _lane_point(randf_range(-100.0, 100.0))
	else:
		_walk_toward(target, 2.6, delta)

func _tick_beg(delta: float) -> void:
	if helped or _player == null or _player_dist < 0.0 or _player_dist > 12.0:
		state = State.WALK
		return
	if _player_dist > 2.0:
		# Approach the player slowly, asking for help.
		_walk_toward(_player.global_position, 1.0, delta)
	else:
		_stand(delta)
		var to_player: Vector3 = _player.global_position - global_position
		to_player.y = 0.0
		if to_player.length() > 0.1:
			rotation.y = lerp_angle(rotation.y, atan2(-to_player.x, -to_player.z), delta * 6.0)
	_beg_say_t -= delta
	if _beg_say_t <= 0.0:
		_beg_say_t = 6.0
		say_random(HELP_LINES, 3.0)

func _tick_walk(delta: float) -> void:
	# A poor citizen who spots the player nearby starts begging.
	if is_poor and not helped and _player_dist >= 0.0 and _player_dist < 9.0:
		state = State.BEG
		_beg_say_t = 0.0
		return
	var diff = target - global_position
	diff.y = 0.0
	if wait_time > 0.0:
		wait_time -= delta
		_stand(delta)
	elif diff.length() < 1.2:
		if randf() < 0.3:
			state = State.IDLE
			idle_timer = randf_range(1.0, 4.0)
			_stand(delta)
		else:
			target = _lane_point(randf_range(-100.0, 100.0))
	else:
		_walk_toward(target, 1.5, delta)
	# Two citizens who meet stop and chat for a few seconds.
	_chat_scan_t -= delta
	if _chat_scan_t <= 0.0:
		_chat_scan_t = 0.5
		_try_start_chat()

func _try_start_chat() -> void:
	if chat_cooldown > 0.0 or state != State.WALK:
		return
	var best: Node = null
	var best_d := 1.7
	for c in get_tree().get_nodes_in_group("civilian"):
		if c == self:
			continue
		if int(c.get("state")) != State.WALK:
			continue
		if float(c.get("chat_cooldown")) > 0.0:
			continue
		var d = global_position.distance_to((c as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = c
	if best != null and randf() < 0.7:
		state = State.CHAT
		chat_partner = best
		chat_timer = randf_range(3.5, 6.0)
		_chat_turn = true
		_chat_line_t = 0.6
		best.call("start_chat_with", self)
		SoundManager.greet()

# ------------------------------------------------------------ locomotion

func _walk_toward(dest: Vector3, speed: float, delta: float) -> void:
	var diff = dest - global_position
	diff.y = 0.0
	if diff.length() < 0.05:
		_stand(delta)
		return
	var dir = diff.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), delta * 6.0)
	walk_phase += delta * speed * 3.0
	_moving = true
	_pose_walk()

func _stand(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()
	_moving = false
	_pose_idle(delta)

func _pose_walk() -> void:
	var s = sin(walk_phase)
	# Thighs swing opposite; shins bend when the leg lifts.
	leg_l_thigh.rotation.x = s * 0.55
	leg_r_thigh.rotation.x = -s * 0.55
	leg_l_shin.rotation.x = -maxf(0.0, sin(walk_phase - 0.9)) * 0.85
	leg_r_shin.rotation.x = -maxf(0.0, sin(walk_phase + PI - 0.9)) * 0.85
	# Arms counter-swing; forearms keep a slight bend.
	arm_l_up.rotation.x = -s * 0.5
	arm_r_up.rotation.x = s * 0.5
	arm_l_fore.rotation.x = 0.25 + maxf(0.0, s) * 0.15
	arm_r_fore.rotation.x = 0.25 + maxf(0.0, -s) * 0.15
	torso_pivot.rotation.x = 0.06
	torso_pivot.rotation.z = s * 0.03

func _pose_idle(delta: float) -> void:
	var k = delta * 5.0
	leg_l_thigh.rotation.x = lerpf(leg_l_thigh.rotation.x, 0.0, k)
	leg_r_thigh.rotation.x = lerpf(leg_r_thigh.rotation.x, 0.0, k)
	leg_l_shin.rotation.x = lerpf(leg_l_shin.rotation.x, -0.08, k)
	leg_r_shin.rotation.x = lerpf(leg_r_shin.rotation.x, -0.08, k)
	arm_l_up.rotation.x = lerpf(arm_l_up.rotation.x, 0.0, k)
	arm_r_up.rotation.x = lerpf(arm_r_up.rotation.x, 0.0, k)
	arm_l_fore.rotation.x = lerpf(arm_l_fore.rotation.x, 0.15, k)
	arm_r_fore.rotation.x = lerpf(arm_r_fore.rotation.x, 0.15, k)
	torso_pivot.rotation.x = lerpf(torso_pivot.rotation.x, 0.0, k)
	torso_pivot.rotation.z = lerpf(torso_pivot.rotation.z, 0.0, k)

func _update_pose(delta: float) -> void:
	if model == null:
		return
	if _laugh_t > 0.0:
		# Funny citizen laugh: little bounce + a full dance spin.
		_laugh_t -= delta
		model.rotation.y += delta * TAU / 0.9
		model.position.y = absf(sin(_laugh_t * 14.0)) * 0.07
		if _laugh_t <= 0.0:
			model.rotation.y = 0.0
			model.position.y = 0.0
	elif _moving:
		model.position.y = absf(cos(walk_phase)) * 0.04
		model.rotation.y = lerpf(model.rotation.y, 0.0, delta * 5.0)
	else:
		# Breathing bob while standing.
		model.position.y = lerpf(model.position.y, sin(Time.get_ticks_msec() / 700.0) * 0.008, delta * 3.0)
		model.rotation.y = lerpf(model.rotation.y, 0.0, delta * 5.0)

func _update_head(delta: float) -> void:
	if head_pivot == null:
		return
	var target_yaw := 0.0
	if state == State.IDLE or state == State.SUSPICIOUS:
		# Look around nervously / curiously.
		target_yaw = sin(Time.get_ticks_msec() / 1000.0 * 0.9 + float(variant)) * 0.7
	head_pivot.rotation.y = lerpf(head_pivot.rotation.y, target_yaw, delta * 3.0)
