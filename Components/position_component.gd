class_name PositionComponent extends Node3D

## Node to apply position changes
@export var target_object: Node3D
## If true, applies position locally
@export var is_local: bool = false
enum Axis {X, Y, Z}
## If using modify_axis_euler(), defines which axis to use
@export var single_axis: Axis = Axis.X

func _ready() -> void:
	if not target_object:
		push_warning("Target for " + str(self) + " not defined")

## Modifies the target position in a single axis, defined by single_axis
func modify_position_axis(input: float) -> void:
	if not target_object:
		return
	match single_axis:
		Axis.X:
			if is_local:
				target_object.translate_object_local(Vector3.RIGHT * input)
			else:
				target_object.global_translate(Vector3.RIGHT * input)
		Axis.Y:
			if is_local:
				target_object.translate_object_local(Vector3.UP * input)
			else:
				target_object.global_translate(Vector3.UP * input)
		Axis.Z:
			if is_local:
				target_object.translate_object_local(Vector3.FORWARD * input)
			else:
				target_object.global_translate(Vector3.FORWARD * input)

## Modifies position in all axis
func modify_position(input: Vector3) -> void:
	if not target_object:
		return
	if is_local:
		target_object.translate_object_local(input)
	else:
		target_object.global_translate(input)
