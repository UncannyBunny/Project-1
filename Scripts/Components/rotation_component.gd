class_name RotationComponent extends Node3D

## Node to apply rotation changes
@export var target_object: Node3D
## If true, applies rotation locally
@export var is_local: bool = false
enum Axis {X, Y, Z}
## If using modify_rotation_axis_euler(), defines which axis to use
@export var single_axis: Axis = Axis.X
## If on will limit rotation in all axis to set values
@export var is_limited: bool = false
## Upper limit in degrees
@export var rotation_limit_upper: float = 90.0
## Lower limit in degrees
@export var rotation_limit_lower: float = -90.0

func _ready() -> void:
	if not target_object:
		push_warning("Target for " + str(self) + " not defined")

## Modifies the target rotation in a single axis
func modify_rotation_axis_euler(input: float) -> void:
	if not target_object:
		return
		
	var rad_input = deg_to_rad(input)
	var upper_rad = deg_to_rad(rotation_limit_upper)
	var lower_rad = deg_to_rad(rotation_limit_lower)
	
	match single_axis:
		Axis.X:
			var target_rot = target_object.rotation.x + rad_input
			if is_limited:
				target_rot = clamp(target_rot, lower_rad, upper_rad)
				rad_input = target_rot - target_object.rotation.x
			apply_rotation_delta(Vector3(rad_input, 0, 0))
			
		Axis.Y:
			var target_rot = target_object.rotation.y + rad_input
			if is_limited:
				target_rot = clamp(target_rot, lower_rad, upper_rad)
				rad_input = target_rot - target_object.rotation.y
			apply_rotation_delta(Vector3(0, rad_input, 0))
			
		Axis.Z:
			var target_rot = target_object.rotation.z + rad_input
			if is_limited:
				target_rot = clamp(target_rot, lower_rad, upper_rad)
				rad_input = target_rot - target_object.rotation.z
			apply_rotation_delta(Vector3(0, 0, rad_input))

## Modifies rotation in all axes with limits applied independently
func modify_rotation_euler(input: Vector3) -> void:
	if not target_object:
		return
		
	var rad_input = Vector3(deg_to_rad(input.x), deg_to_rad(input.y), deg_to_rad(input.z))
	
	if is_limited:
		var upper_rad = deg_to_rad(rotation_limit_upper)
		var lower_rad = deg_to_rad(rotation_limit_lower)
		
		var target_x = clamp(target_object.rotation.x + rad_input.x, lower_rad, upper_rad)
		var target_y = clamp(target_object.rotation.y + rad_input.y, lower_rad, upper_rad)
		var target_z = clamp(target_object.rotation.z + rad_input.z, lower_rad, upper_rad)
		
		rad_input.x = target_x - target_object.rotation.x
		rad_input.y = target_y - target_object.rotation.y
		rad_input.z = target_z - target_object.rotation.z
		
	apply_rotation_delta(rad_input)

## Helper function to apply local or global rotation delta safely
func apply_rotation_delta(rad_delta: Vector3) -> void:
	if is_local:
		if rad_delta.x != 0.0: target_object.rotate_object_local(Vector3.RIGHT, rad_delta.x)
		if rad_delta.y != 0.0: target_object.rotate_object_local(Vector3.UP, rad_delta.y)
		if rad_delta.z != 0.0: target_object.rotate_object_local(Vector3.FORWARD, rad_delta.z)
	else:
		if rad_delta.x != 0.0: target_object.rotate(Vector3.RIGHT, rad_delta.x)
		if rad_delta.y != 0.0: target_object.rotate(Vector3.UP, rad_delta.y)
		if rad_delta.z != 0.0: target_object.rotate(Vector3.FORWARD, rad_delta.z)
