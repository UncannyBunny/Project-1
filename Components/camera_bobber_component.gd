class_name CameraBobberComponent extends Node3D

@export var camera_object: Camera3D
@export var player_object: CharacterController3D
var is_bobbing: bool = false
var bob_tween: Tween
@export var bob_speed: float = 0
@export var bob_height: float = 0
@export var bob_width: float = 0
var camera_position: Vector3 = Vector3.ZERO

func _ready() -> void:
	camera_position = camera_object.position

func _physics_process(delta: float) -> void:
	_bob_camera()

func _bob_camera() -> void:
	var horizontal_velocity = Vector2(player_object.velocity.x, player_object.velocity.z)
	if is_bobbing and bob_tween and bob_tween.is_valid():
		var speed_scale = clamp(horizontal_velocity.length() / player_object.speed_walking, 0.5, 1.5)
		bob_tween.set_speed_scale(speed_scale)
	var is_moving = horizontal_velocity.length() > 0.5 and player_object.is_on_floor()
	if is_moving and not is_bobbing:
		is_bobbing = true
		if bob_tween:
			bob_tween.kill()
		bob_tween = create_tween().set_loops()
		bob_tween.tween_property(camera_object, "position", camera_position + Vector3(bob_width, bob_height, 0), bob_speed) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bob_tween.tween_property(camera_object, "position", camera_position, bob_speed) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bob_tween.tween_property(camera_object, "position", camera_position + Vector3(-bob_width, bob_height, 0), bob_speed) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bob_tween.tween_property(camera_object, "position", camera_position, bob_speed) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif not is_moving and is_bobbing:
		is_bobbing = false
		if bob_tween:
			bob_tween.kill()
		bob_tween = create_tween()
		bob_tween.tween_property(camera_object, "position", camera_position, 0.2) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
