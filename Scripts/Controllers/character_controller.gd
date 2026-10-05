class_name CharacterController3D extends CharacterBody3D

@export_group("Movement")
var movement_speed: float = 0
@export var speed_walking: float = 0
@export var speed_running: float = 0
var _movement_run: bool = false
@export var jump_force: float = 0
@export var weight: float = 1
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _movement_direction: Vector3 = Vector3.ZERO
var _movement_jump: bool = false

func _ready() -> void:
	movement_speed = speed_walking

func _physics_process(delta: float) -> void:
	_move_character()

func set_direction(new_direction: Vector3) -> void:
	_movement_direction = new_direction.normalized()

func set_movement(new_direction: Vector3, is_running: bool = false) -> void:
	_movement_direction = new_direction.normalized()
	movement_speed = speed_running if is_running else speed_walking

func set_orientation(new_rotation: float) -> void:
	rotation.y = new_rotation

func set_jump() -> void:
	if not is_on_floor():
		return
	_movement_jump = true

func set_running() -> void:
	_movement_run = not _movement_run
	if _movement_run:
		movement_speed = speed_running
	else:
		movement_speed = speed_walking

func _move_character() -> void:
	if not is_on_floor():
		velocity.y -= _gravity * weight
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

func remove_character() -> void:
	self.queue_free()
