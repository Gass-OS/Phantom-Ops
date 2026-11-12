extends CharacterBody3D
@export var speed: float = 5.0
@export var jump_velocity: float = 4.5
var gravity: float = 9.8
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()
