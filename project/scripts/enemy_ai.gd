extends CharacterBody3D
class_name EnemyAI

signal enemy_died(enemy)

@export var max_health: float = 60.0
@export var speed: float = 3.5
@export var damage: float = 10.0

var current_health: float = 60.0
var target: Node3D = null
var is_dead: bool = false
var gravity: float = 9.8

func _ready():
    current_health = max_health

func _physics_process(delta):
    if is_dead:
        return

    if not is_on_floor():
        velocity.y -= gravity * delta

    if not is_instance_valid(target):
        velocity.x = 0
        velocity.z = 0
        move_and_slide()
        return

    var difference = target.global_position - global_position
    var distance = difference.length()

    if distance > 0.1:
        var direction = difference.normalized()
        velocity.x = direction.x * speed
        velocity.z = direction.z * speed

    if distance < 2.0 and target.has_method("take_damage"):
        target.take_damage(damage * delta)

    move_and_slide()

func take_damage(amount: float):
    if is_dead:
        return

    current_health -= amount

    if current_health <= 0:
        is_dead = true
        enemy_died.emit(self)
        queue_free()
