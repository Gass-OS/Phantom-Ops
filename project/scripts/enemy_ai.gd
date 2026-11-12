extends CharacterBody3D
class_name EnemyAI

signal enemy_died(enemy)

@export var max_health := 85.0
@export var speed := 2.8
@export var damage := 12.0
@export var detection_range := 48.0
@export var attack_range := 1.8
@export var attack_cooldown := 1.25

var current_health := 85.0
var target: Node3D
var is_dead := false
var gravity := 18.0
var attack_timer := 0.0
var hit_flash := 0.0

func _ready() -> void:
	current_health = max_health
	add_to_group("hostiles")

func _physics_process(delta: float) -> void:
	if is_dead: return
	attack_timer = maxf(0.0, attack_timer - delta)
	if not is_on_floor(): velocity.y -= gravity * delta
	if not is_instance_valid(target):
		velocity.x = move_toward(velocity.x, 0.0, speed*delta*3.0)
		velocity.z = move_toward(velocity.z, 0.0, speed*delta*3.0)
		move_and_slide()
		return
	var offset := target.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance <= detection_range and distance > attack_range:
		var direction := offset.normalized()
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		look_at(Vector3(target.global_position.x, global_position.y, target.global_position.z), Vector3.UP)
	elif distance <= attack_range:
		velocity.x = move_toward(velocity.x,0.0,speed*delta*4.0)
		velocity.z = move_toward(velocity.z,0.0,speed*delta*4.0)
		if attack_timer <= 0.0 and target.has_method("take_damage"):
			target.take_damage(damage)
			attack_timer = attack_cooldown
	else:
		velocity.x = move_toward(velocity.x,0.0,speed*delta)
		velocity.z = move_toward(velocity.z,0.0,speed*delta)
	move_and_slide()

func take_damage(amount: float) -> void:
	if is_dead: return
	current_health = maxf(0.0,current_health-amount)
	var visual := get_node_or_null("Visual")
	if visual is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.65,0.12,0.09)
		visual.material_override = material
	if current_health <= 0.0:
		is_dead = true
		enemy_died.emit(self)
		GameManager.add_kill()
		queue_free()
