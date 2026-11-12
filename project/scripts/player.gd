extends CharacterBody3D

signal health_changed(current, maximum)
signal player_died

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var jump_velocity: float = 4.5
@export var max_health: float = 100.0

var current_health: float = 100.0
var is_dead: bool = false
var gravity: float = 9.8
var mobile_move: Vector2 = Vector2.ZERO

@onready var camera: Camera3D = $Head/Camera3D

func _ready():
    current_health = max_health

func _physics_process(delta):
    if is_dead:
        return

    if not is_on_floor():
        velocity.y -= gravity * delta

    var input_dir = mobile_move

    if OS.get_name() not in ["Android", "iOS"]:
        input_dir = Input.get_vector(
            "ui_left", "ui_right", "ui_up", "ui_down"
        )

    var direction = (
        transform.basis * Vector3(input_dir.x, 0, input_dir.y)
    ).normalized()

    var speed = walk_speed

    if Input.is_action_pressed("ui_accept"):
        speed = sprint_speed

    velocity.x = direction.x * speed
    velocity.z = direction.z * speed

    if Input.is_action_just_pressed("ui_select") and is_on_floor():
        velocity.y = jump_velocity

    move_and_slide()

func take_damage(damage: float):
    if is_dead:
        return

    current_health = maxf(0.0, current_health - damage)
    health_changed.emit(current_health, max_health)

    if current_health <= 0:
        is_dead = true
        player_died.emit()
