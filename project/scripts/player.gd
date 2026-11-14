extends CharacterBody3D
signal health_changed(current, maximum)
signal player_died
@export var walk_speed := 5.0
@export var sprint_speed := 8.5
@export var jump_velocity := 4.5
@export var max_health := 100.0
@export var look_sensitivity := 0.0035
@export var mag_size := 30
@export var reload_time := 1.4
@export var fire_cooldown := 0.12
var current_health := 100.0
var is_dead := false
# v0.6: true while driving the police car (set by police_car.gd
# enter/exit via set()). While driving, on-foot input is ignored —
# the traffic manager forwards the joystick to the car instead.
var is_driving := false
var gravity := 9.8
var mobile_move := Vector2.ZERO
var mobile_sprinting := false
var mobile_hud
var is_paused := false
var ammo := 30
var reloading := false
var _reload_timer := 0.0
var _cooldown_timer := 0.0
var _flash_timer := 0.0
var _recoil := 0.0
var _viewmodel: Node3D
var _muzzle_flash: MeshInstance3D
var _muzzle_light: OmniLight3D
var _sound: SoundManager
var _firing := false
var _step_timer := 0.0
var _greet_timer := 2.0
var _pending_death := false
var _tracer_mat: StandardMaterial3D
@onready var camera: Camera3D = $Head/Camera3D
func _ready() -> void:
	current_health = max_health
	ammo = mag_size
	_sound = SoundManager.new()
	_sound.name = "SoundManager"
	add_child(_sound)
	_sound.start_wind()
	_sound.start_murmur()
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.albedo_color = Color(1.0, 0.85, 0.4)
	_tracer_mat.emission_enabled = true
	_tracer_mat.emission = Color(1.0, 0.8, 0.3)
	_tracer_mat.emission_energy_multiplier = 2.0
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_create_viewmodel()
	# v0.5: death was a dead end — player_died was emitted but nothing
	# listened, so the player froze with no screen and no way out.
	player_died.connect(_on_player_died)
	# Deferred: adding the HUD layer to the root during scene setup
	# fails ("parent node is busy setting up children").
	call_deferred("_create_mobile_hud")
	if is_instance_valid(GameManager):
		GameManager.reset_game()
		GameManager.score_changed.connect(_on_score_changed)
	_update_hud_all()
func _create_mobile_hud() -> void:
	# Fix: the HUD layer lives on the root, outside the scene, so a scene
	# reload used to leave the old HUD behind and stack a second one.
	var old := get_tree().root.get_node_or_null("MobileHUDLayer")
	if old != null:
		old.queue_free()
	var layer := CanvasLayer.new()
	layer.name = "MobileHUDLayer"
	layer.layer = 10
	get_tree().root.add_child(layer)
	mobile_hud = Control.new()
	mobile_hud.name = "MobileHUD"
	mobile_hud.set_script(load("res://scripts/mobile_hud.gd"))
	layer.add_child(mobile_hud)
	mobile_hud.move_changed.connect(_on_mobile_move)
	mobile_hud.look_delta.connect(_on_mobile_look)
	mobile_hud.jump_pressed.connect(_on_mobile_jump)
	mobile_hud.fire_pressed.connect(_on_mobile_fire)
	if mobile_hud.has_signal("fire_held_changed"):
		mobile_hud.fire_held_changed.connect(_on_fire_held_changed)
	mobile_hud.pause_pressed.connect(_on_pause)
	mobile_hud.resume_pressed.connect(_on_resume)
	mobile_hud.menu_pressed.connect(_on_menu)
	if mobile_hud.has_signal("retry_pressed"):
		mobile_hud.retry_pressed.connect(_on_retry)
	if mobile_hud.has_signal("death_menu_pressed"):
		mobile_hud.death_menu_pressed.connect(_on_menu)
	mobile_hud.sprint_changed.connect(_on_sprint)
	if _pending_death:
		_pending_death = false
		_show_death_overlay()
	mobile_hud.sound_toggled.connect(_on_sound_toggled)
	if mobile_hud.has_signal("voices_toggled"):
		mobile_hud.voices_toggled.connect(_on_voices_toggled)
	if mobile_hud.has_method("set_sound_on"):
		mobile_hud.set_sound_on(SoundManager.sound_on)
	if mobile_hud.has_method("set_voices_on"):
		mobile_hud.set_voices_on(SoundManager.voices_on)
	_update_hud_all()

func _on_fire_held_changed(v: bool) -> void:
	# Hold-to-fire: the HUD emits this while FIRE is held; _process
	# re-fires through the normal cooldown-gated path (~8 shots/s).
	_firing = v

func _on_sound_toggled(v: bool) -> void:
	SoundManager.set_sound_on(v)
	if _sound != null and not v:
		_sound.stop_wind()
		_sound.stop_murmur()
	elif _sound != null and v:
		_sound.start_wind()
		_sound.start_murmur()

func _on_voices_toggled(v: bool) -> void:
	SoundManager.set_voices_on(v)
func _on_score_changed(score: int, kills: int) -> void:
	if mobile_hud != null and mobile_hud.has_method("set_score"):
		mobile_hud.set_score(score, kills)
func _create_viewmodel() -> void:
	# Simple procedural rifle, attached to the camera. No external assets.
	_viewmodel = Node3D.new()
	_viewmodel.name = "Viewmodel"
	_viewmodel.position = Vector3(0.28, -0.24, -0.5)
	camera.add_child(_viewmodel)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.13, 0.13, 0.15)
	metal.roughness = 0.45
	metal.metallic = 0.6
	var grip_mat := StandardMaterial3D.new()
	grip_mat.albedo_color = Color(0.20, 0.16, 0.12)
	grip_mat.roughness = 0.9
	var tan_mat := StandardMaterial3D.new()
	tan_mat.albedo_color = Color(0.45, 0.38, 0.26)
	tan_mat.roughness = 0.85
	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.72, 0.55, 0.42)
	skin_mat.roughness = 0.9
	var parts: Array = [
		[Vector3(0, 0, 0), Vector3(0.09, 0.13, 0.55), metal],
		[Vector3(0, 0.02, -0.38), Vector3(0.05, 0.05, 0.30), metal],
		# Sight post + red-dot housing on top.
		[Vector3(0, 0.09, -0.05), Vector3(0.03, 0.05, 0.04), metal],
		[Vector3(0, 0.125, -0.05), Vector3(0.05, 0.03, 0.09), metal],
		# Handguard (tan) around the barrel + foregrip.
		[Vector3(0, 0.0, -0.42), Vector3(0.11, 0.11, 0.22), tan_mat],
		[Vector3(0, -0.09, -0.38), Vector3(0.05, 0.09, 0.06), grip_mat],
		# Magazine (tan, angled) + stock.
		[Vector3(0, -0.13, 0.02), Vector3(0.06, 0.20, 0.09), tan_mat],
		[Vector3(0, -0.01, 0.36), Vector3(0.08, 0.11, 0.16), grip_mat],
		# Pistol grip + trigger guard.
		[Vector3(0, -0.10, 0.12), Vector3(0.07, 0.14, 0.10), grip_mat],
		[Vector3(0, -0.06, -0.18), Vector3(0.06, 0.10, 0.08), grip_mat],
		# Suppressor on the muzzle.
		[Vector3(0, 0.02, -0.66), Vector3(0.06, 0.06, 0.14), metal],
		# Left hand on the handguard.
		[Vector3(0, -0.08, -0.42), Vector3(0.07, 0.06, 0.10), skin_mat],
		# v0.5: top rail with slots, charging handle, front sight post,
		# butt pad, magazine release — the rifle stops reading flat.
		[Vector3(0, 0.075, -0.30), Vector3(0.06, 0.02, 0.42), metal],
		[Vector3(0.05, 0.03, 0.10), Vector3(0.04, 0.02, 0.08), metal],
		[Vector3(0, 0.10, -0.55), Vector3(0.02, 0.06, 0.02), metal],
		[Vector3(0, -0.01, 0.45), Vector3(0.09, 0.13, 0.03), grip_mat],
		[Vector3(0.045, -0.06, 0.0), Vector3(0.02, 0.04, 0.05), metal],
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = p[1]
		box.material = p[2]
		mi.mesh = box
		mi.position = p[0]
		_viewmodel.add_child(mi)
	var barrel := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.025
	cyl.height = 0.30
	cyl.material = metal
	barrel.mesh = cyl
	barrel.rotation_degrees = Vector3(90, 0, 0)
	barrel.position = Vector3(0, 0.02, -0.55)
	_viewmodel.add_child(barrel)
	# Muzzle flash: emissive quad + a short-lived light, hidden by default.
	var flash_mat := StandardMaterial3D.new()
	flash_mat.albedo_color = Color(1.0, 0.8, 0.35)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.75, 0.25)
	flash_mat.emission_energy_multiplier = 3.0
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_muzzle_flash = MeshInstance3D.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.09
	flash_mesh.height = 0.18
	flash_mesh.material = flash_mat
	_muzzle_flash.mesh = flash_mesh
	_muzzle_flash.position = Vector3(0, 0.02, -0.72)
	_muzzle_flash.visible = false
	_viewmodel.add_child(_muzzle_flash)
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color(1.0, 0.8, 0.45)
	_muzzle_light.light_energy = 0.0
	_muzzle_light.omni_range = 6.0
	_muzzle_light.position = Vector3(0, 0.02, -0.72)
	_viewmodel.add_child(_muzzle_light)
func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
	if _firing and not is_paused and not is_dead:
		_on_mobile_fire()
	# v0.4: greet a nearby civilian (best-effort TTS, throttled inside
	# SoundManager.greet(); silent when TTS is unavailable).
	_greet_timer -= delta
	if _greet_timer <= 0.0:
		_greet_timer = 1.0
		_check_citizen_greeting()
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_muzzle_flash.visible = false
			_muzzle_light.light_energy = 0.0
	if reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			reloading = false
			ammo = mag_size
			if _sound != null:
				_sound.play_reload_done()
			_update_hud_all()
	if _recoil > 0.0:
		_recoil = maxf(0.0, _recoil - delta * 0.6)
		_viewmodel.position.z = -0.5 + _recoil * 0.12
	if mobile_hud != null and mobile_hud.has_method("set_compass"):
		mobile_hud.set_compass(rotation.y)
func _check_citizen_greeting() -> void:
	if is_paused or is_dead:
		return
	var tree := get_tree()
	if tree == null:
		return
	for c in tree.get_nodes_in_group("civilian"):
		var civ := c as Node3D
		if civ == null:
			continue
		if civ.global_position.distance_to(global_position) < 6.0:
			SoundManager.greet()
			return

func _on_mobile_move(v: Vector2) -> void:
	mobile_move = v
func _on_mobile_look(v: Vector2) -> void:
	if is_paused or is_dead or is_driving:
		return
	rotate_y(-v.x * look_sensitivity)
	camera.rotation.x = clampf(camera.rotation.x - v.y * look_sensitivity, deg_to_rad(-80), deg_to_rad(80))
func _on_mobile_jump() -> void:
	if is_paused or is_dead or is_driving:
		return
	if is_on_floor():
		velocity.y = jump_velocity
func _on_mobile_fire() -> void:
	if is_paused or is_dead or is_driving or reloading:
		return
	if _cooldown_timer > 0.0:
		return
	if ammo <= 0:
		_start_reload()
		return
	_cooldown_timer = fire_cooldown
	ammo -= 1
	if _sound != null:
		_sound.play_shot()
	_flash_timer = 0.06
	_muzzle_flash.visible = true
	_muzzle_flash.scale = Vector3(randf_range(0.8, 1.3), randf_range(0.8, 1.3), randf_range(0.8, 1.3))
	_muzzle_light.light_energy = 2.0
	_recoil = 1.0
	camera.rotation.x = clampf(camera.rotation.x + 0.012, deg_to_rad(-80), deg_to_rad(80))
	var target := camera.global_position - camera.global_transform.basis.z * 100.0
	var q := PhysicsRayQueryParameters3D.create(camera.global_position, target)
	q.exclude = [self]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end_point := target
	# v0.4: civilians are NEVER targets. They are in group "civilian"
	# and have no take_damage, but check the group explicitly: a hit
	# on a civilian deals no damage, plays no hit sound, shows no
	# hitmarker and leaves no impact puff — the shot simply passes.
	var hit_civilian := false
	if not hit.is_empty():
		var collider := hit.collider as Node
		if collider != null and collider.is_in_group("civilian"):
			hit_civilian = true
		else:
			end_point = hit.position
			_spawn_impact_puff(end_point)
	_spawn_tracer(camera.global_position - camera.global_transform.basis.z * 0.8, end_point)
	if not hit_civilian and not hit.is_empty() and hit.collider.has_method("take_damage"):
		hit.collider.take_damage(25.0)
		if _sound != null:
			_sound.play_hit()
		if mobile_hud != null and mobile_hud.has_method("show_hitmarker"):
			mobile_hud.show_hitmarker()
	if ammo <= 0:
		_start_reload()
	else:
		_update_hud_all()
func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var dist := from.distance_to(to)
	if dist < 0.5:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.025, 0.025, dist)
	box.material = _tracer_mat
	mi.mesh = box
	mi.position = (from + to) * 0.5
	scene.add_child(mi)
	mi.look_at(to, Vector3.UP)
	var timer := get_tree().create_timer(0.07)
	timer.timeout.connect(mi.queue_free)

func _spawn_impact_puff(at: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mesh.material = _tracer_mat
	mi.mesh = mesh
	mi.position = at
	scene.add_child(mi)
	var timer := get_tree().create_timer(0.15)
	timer.timeout.connect(mi.queue_free)

func _start_reload() -> void:
	if reloading or ammo == mag_size:
		return
	reloading = true
	_reload_timer = reload_time
	if _sound != null:
		_sound.play_reload()
	_update_hud_all()
func _on_sprint(v: bool) -> void:
	mobile_sprinting = v
func _on_pause() -> void:
	is_paused = true
	set_physics_process(false)
	if mobile_hud != null:
		mobile_hud.set_paused(true)
func _on_resume() -> void:
	is_paused = false
	set_physics_process(true)
	if mobile_hud != null:
		mobile_hud.set_paused(false)
func _on_menu() -> void:
	if mobile_hud != null:
		var layer: Node = mobile_hud.get_parent()
		if layer != null:
			layer.queue_free()
	if is_instance_valid(GameManager):
		GameManager.reset_game()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# v0.5 death flow: stop firing, stop the waves, play the death sting,
# show YOU DIED with the final score. Enemies stop attacking the
# corpse via the is_dead check in enemy_ai.gd.
func _on_player_died() -> void:
	_firing = false
	if _sound != null:
		_sound.play_death()
	var spawner := get_parent().get_node_or_null("EnemySpawner")
	if spawner != null and spawner.has_method("stop_waves"):
		spawner.stop_waves()
	_show_death_overlay()

func _show_death_overlay() -> void:
	if mobile_hud == null:
		_pending_death = true
		return
	if not mobile_hud.has_method("show_death"):
		return
	var wave := 1
	var spawner := get_parent().get_node_or_null("EnemySpawner")
	if spawner != null:
		wave = int(spawner.get("wave"))
	var final_score := 0
	var final_kills := 0
	if is_instance_valid(GameManager):
		final_score = GameManager.score
		final_kills = GameManager.kills
	mobile_hud.show_death(final_score, final_kills, wave)

func _on_retry() -> void:
	# Reload the game cleanly. The root HUD layer is freed here (and
	# again in _exit_tree); the new Player rebuilds a fresh one, so no
	# stacked HUDs — the v0.3 fix still holds.
	if mobile_hud != null:
		var layer: Node = mobile_hud.get_parent()
		if layer != null:
			layer.queue_free()
	if is_instance_valid(GameManager):
		GameManager.reset_game()
	get_tree().change_scene_to_file("res://scenes/main_game.tscn")
func _update_hud_all() -> void:
	if mobile_hud == null:
		return
	if mobile_hud.has_method("set_health"):
		mobile_hud.set_health(current_health, max_health)
	if mobile_hud.has_method("set_ammo"):
		mobile_hud.set_ammo(ammo, mag_size, reloading)
	if mobile_hud.has_method("set_score") and is_instance_valid(GameManager):
		mobile_hud.set_score(GameManager.score, GameManager.kills)
func _physics_process(delta: float) -> void:
	if is_dead or is_paused:
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	var input_dir := mobile_move
	if OS.get_name() not in ["Android", "iOS"]:
		input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var speed := sprint_speed if mobile_sprinting or Input.is_action_pressed("ui_accept") else walk_speed
	if is_on_floor() and direction.length() > 0.1 and _sound != null:
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = 0.28 if speed > walk_speed else 0.38
			_sound.play_step()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if OS.get_name() not in ["Android", "iOS"] and Input.is_action_just_pressed("ui_select") and is_on_floor():
		velocity.y = jump_velocity
	move_and_slide()
func take_damage(damage: float) -> void:
	if is_dead:
		return
	current_health = maxf(0.0, current_health - damage)
	health_changed.emit(current_health, max_health)
	if _sound != null:
		_sound.play_hurt()
	_update_hud_all()
	if current_health <= 0:
		is_dead = true
		player_died.emit()
func _exit_tree() -> void:
	# Scene change must not leak the root-level HUD into the next scene.
	if get_tree() == null:
		return
	var old := get_tree().root.get_node_or_null("MobileHUDLayer")
	if old != null:
		old.queue_free()
