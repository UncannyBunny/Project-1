class_name CharacterController3D extends CharacterBody3D

@export_group("Movement")
@export var movement_speed: float = 0
@export var jump_force: float = 0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _movement_direction: Vector3 = Vector3.ZERO
var _movement_jump: bool = false

func _physics_process(delta: float) -> void:
	_move_character()

func set_direction(new_direction: Vector3) -> void:
	_movement_direction = new_direction.normalized()

func set_jump() -> void:
	if not is_on_floor():
		return
	_movement_jump = true

func _move_character() -> void:
	if not is_on_floor():
		velocity.y -= _gravity
	if _movement_direction != Vector3.ZERO:
		velocity.x = move_toward(velocity.x, _movement_direction.x * movement_speed, movement_speed / 4)
		velocity.z = move_toward(velocity.z, _movement_direction.z * movement_speed, movement_speed / 4)
	else:
		velocity.x = move_toward(velocity.x, 0, movement_speed)
		velocity.z = move_toward(velocity.z, 0, movement_speed)
	
	if _movement_jump and is_on_floor():
		velocity.y = jump_force
		_movement_jump = false
	
	move_and_slide()
