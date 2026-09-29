@tool
## Triggers a target method with the projection of a float onto a vector axis.
class_name AxisProjectorComponent extends Node3D

## Node to follow
@export var follow_target_object: Node3D
## Object to receive the input
@export var target_object: Node3D:
	set(value):
		target_object = value
		notify_property_list_changed()
## Method that will be called with the input
@export var target_method_string: String = ""
var target_method_callable: Callable
@export_group("Properties")
enum TargetAxis {X_Y, X_Z, Y_Z}
## Axis pair to convert the XY input to
@export var target_axis: TargetAxis = TargetAxis.X_Z
## If true, swaps the axis of the input, applied BEFORE axis inversion
@export var swap_axis: bool = false

func _ready() -> void:
	# Avoid execution in editor environment.
	if Engine.is_editor_hint():
		return
	# Bind target callable for 
	if target_object and not target_method_string.is_empty():
		target_method_callable = Callable(target_object, target_method_string)

func project_axis(input: float) -> void:
	if not target_method_callable.is_valid():
		return
	var raw_input: Vector2
	if swap_axis:
		raw_input = Vector2(0, input)
	else:
		raw_input = Vector2(input, 0)
	var projected_vector: Vector3
	var projected_basis: Vector3
	match target_axis:
		TargetAxis.X_Y:
			projected_vector = Vector3(raw_input.x, raw_input.y, 0)
			projected_basis = follow_target_object.global_transform.basis.orthonormalized().get_euler()
			projected_vector = projected_vector * Basis.from_euler(Vector3(0, 0, projected_basis.z))
			target_method_callable.call(projected_vector)
		TargetAxis.X_Z:
			projected_vector = Vector3(raw_input.x, 0, raw_input.y)
			projected_basis = follow_target_object.global_transform.basis.orthonormalized().get_euler()
			projected_vector = projected_vector * Basis.from_euler(Vector3(0, projected_basis.y, 0))
			target_method_callable.call(projected_vector)
		TargetAxis.Y_Z:
			projected_vector = Vector3(0, raw_input.x, raw_input.y)
			projected_basis = follow_target_object.global_transform.basis.orthonormalized().get_euler()
			projected_vector = projected_vector * Basis.from_euler(Vector3(projected_basis.x, 0, 0))
			target_method_callable.call(projected_vector)

func _validate_property(property: Dictionary) -> void:
	if property.name == "target_method_string":
		var target_method_options: String = ""
		
		if target_object and target_object.get_script():
			var methods: Array = target_object.get_script().get_script_method_list()
			var method_names: Array[String] = []
			
			for method in methods:
				if not method["name"].begins_with("_"):
					method_names.append(method["name"])
					
			target_method_options = ",".join(method_names)
			
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = target_method_options
