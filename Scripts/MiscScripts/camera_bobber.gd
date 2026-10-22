## Applies a procedural sine-wave view bob to a Camera3D's h_offset and v_offset while the character moves on the floor.
class_name CameraBobber extends Node

@export var camera_object: Camera3D
@export var player_object: CharacterController3D

@export_group("Bob Settings")
@export var bob_speed: float = 0.25
@export var bob_height: float = 0.1
@export var bob_width: float = 0.05

var is_bobbing: bool = false
var bob_tween: Tween

func _ready() -> void:
	if not camera_object and get_parent() is Camera3D:
		camera_object = get_parent() as Camera3D
	if not player_object and owner is CharacterController3D:
		player_object = owner as CharacterController3D

func _physics_process(_delta: float) -> void:
	if not camera_object or not player_object:
		return
	_bob_camera()

func _bob_camera() -> void:
	var horizontal_velocity := Vector2(player_object.velocity.x, player_object.velocity.z)
	if is_bobbing and bob_tween and bob_tween.is_valid():
		var base_speed: float = maxf(player_object.speed_walking, 0.01)
		var speed_scale: float = clampf(horizontal_velocity.length() / base_speed, 0.5, 1.5)
		bob_tween.set_speed_scale(speed_scale)
		
	var is_moving: bool = horizontal_velocity.length() > 0.5 and player_object.is_on_floor()
	if is_moving and not is_bobbing:
		is_bobbing = true
		if bob_tween:
			bob_tween.kill()
		bob_tween = create_tween().set_loops()
		bob_tween.tween_method(_set_camera_offset, Vector2.ZERO, Vector2(bob_width, bob_height), bob_speed) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bob_tween.tween_method(_set_camera_offset, Vector2(bob_width, bob_height), Vector2.ZERO, bob_speed) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bob_tween.tween_method(_set_camera_offset, Vector2.ZERO, Vector2(-bob_width, bob_height), bob_speed) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bob_tween.tween_method(_set_camera_offset, Vector2(-bob_width, bob_height), Vector2.ZERO, bob_speed) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif not is_moving and is_bobbing:
		is_bobbing = false
		if bob_tween:
			bob_tween.kill()
		var current_offset := Vector2(camera_object.h_offset, camera_object.v_offset)
		bob_tween = create_tween()
		bob_tween.tween_method(_set_camera_offset, current_offset, Vector2.ZERO, 0.2) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _set_camera_offset(offset: Vector2) -> void:
	if camera_object:
		camera_object.h_offset = offset.x
		camera_object.v_offset = offset.y
