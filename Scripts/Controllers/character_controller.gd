## Base class for all moving characters (Player and NPCs). Handles velocity, gravity, jumping, and orientation.
class_name CharacterController3D extends CharacterBody3D

signal movement_state_changed(is_moving: bool, is_running: bool)
signal jumped
signal landed
signal footstep_triggered

@export_group("Movement")
@export var speed_walking: float = 1.0
@export var speed_running: float = 4.0
@export var _movement_run: bool = false
@export var acceleration_ratio: float = 0.25
@export var jump_force: float = 15.0
@export var weight: float = 1.0
@export var freeze_while_warping: bool = false

@export_group("Orientation")
## Enable for NPCs so they automatically rotate toward their horizontal velocity
@export var rotate_with_movement: bool = false
@export var rotation_speed: float = 5.0

@export_group("Properties")
## Local keys held by this specific character (e.g., &"staff_code" for locked doors)
@export var private_keys: Array[StringName] = []

@export_group("Footsteps")
## Distance traveled on the floor before emitting footstep_triggered
@export var step_distance: float = 1.8

var movement_speed: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _movement_direction: Vector3 = Vector3.ZERO
var _movement_jump: bool = false
var _was_on_floor: bool = true
var _was_moving: bool = false
var _was_running: bool = false
var _distance_since_last_step: float = 0.0

func _ready() -> void:
	movement_speed = speed_running if _movement_run else speed_walking

func _physics_process(delta: float) -> void:
	if freeze_while_warping and KeyManager.search_keys([&"time_warp"]):
		return
	_move_character(delta)
	if rotate_with_movement:
		_update_movement_rotation(delta)
	_update_movement_signals(delta)

## Sets the normalized movement direction vector
func set_direction(new_direction: Vector3) -> void:
	_movement_direction = new_direction.normalized()

## Sets both the movement direction and running state at once (used by AI and Player)
func set_movement(new_direction: Vector3, is_running: bool = false) -> void:
	set_direction(new_direction)
	_movement_run = is_running
	movement_speed = speed_running if _movement_run else speed_walking

## Directly sets the character's Y-axis rotation in radians
func set_orientation(new_rotation_y: float) -> void:
	rotation.y = new_rotation_y

## Queues a jump on the next physics frame if on the floor
func set_jump() -> void:
	if is_on_floor():
		_movement_jump = true

## Toggles or sets the running state
func set_running(is_running: bool = not _movement_run) -> void:
	_movement_run = is_running
	movement_speed = speed_running if _movement_run else speed_walking

func _move_character(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * weight * delta
		
	if _movement_direction != Vector3.ZERO:
		var accel_step: float = movement_speed * acceleration_ratio
		velocity.x = move_toward(velocity.x, _movement_direction.x * movement_speed, accel_step)
		velocity.z = move_toward(velocity.z, _movement_direction.z * movement_speed, accel_step)
	else:
		velocity.x = move_toward(velocity.x, 0.0, movement_speed)
		velocity.z = move_toward(velocity.z, 0.0, movement_speed)
		
	if _movement_jump and is_on_floor():
		velocity.y = jump_force
		_movement_jump = false
		jumped.emit()
		
	move_and_slide()

func _update_movement_rotation(delta: float) -> void:
	var horizontal_velocity := Vector2(velocity.x, velocity.z)
	if horizontal_velocity.length() >= 0.1:
		var target_angle: float = atan2(velocity.x, velocity.z)
		rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)

func _update_movement_signals(delta: float) -> void:
	var on_floor_now: bool = is_on_floor()
	if on_floor_now and not _was_on_floor:
		landed.emit()
	_was_on_floor = on_floor_now
	
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var is_moving_now: bool = horizontal_speed > 0.2 and on_floor_now
	if is_moving_now != _was_moving or _movement_run != _was_running:
		_was_moving = is_moving_now
		_was_running = _movement_run
		movement_state_changed.emit(is_moving_now, _movement_run)
	
	if is_moving_now and step_distance > 0.0:
		_distance_since_last_step += horizontal_speed * delta
		if _distance_since_last_step >= step_distance:
			_distance_since_last_step = 0.0
			footstep_triggered.emit()
	elif not is_moving_now:
		_distance_since_last_step = 0.0
