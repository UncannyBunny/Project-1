## Controls a hinged door behaviour
class_name DoorComponent extends Node3D

@export var is_locked: bool = false
@export var door_name: String = "Mysterious Door"
@export var door_pivot: Node3D
@export var open_angle_degrees: float = 90.0
@export var animation_duration: float = 0.5

var is_open: bool = false
var _closed_rotation_y: float
var _door_tween: Tween

func _ready() -> void:
	if door_pivot == null:
		push_error("DoorComponent: asigna el nodo Hinge en el Inspector.")
		return

	_closed_rotation_y = door_pivot.rotation.y

func interact() -> void:
	if is_locked:
		print("The door '", door_name, "' is locked. You need a clue.")
		return

	if door_pivot == null:
		push_error("DoorComponent: no hay un pivote asignado.")
		return

	is_open = not is_open
	var target_rotation := _closed_rotation_y
	if is_open:
		target_rotation += deg_to_rad(open_angle_degrees)

	if _door_tween and _door_tween.is_running():
		_door_tween.kill()

	_door_tween = create_tween()
	_door_tween.tween_property(
		door_pivot,
		"rotation:y",
		target_rotation,
		animation_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
