@tool
class_name MouseMovementComponent3D extends Node3D

## Object to receive the input
@export var target_object: Node3D:
	set(value):
		target_object = value
		notify_property_list_changed()
## Method that will be called with the input
@export var target_method_string: String = ""
var target_method_callable: Callable
@export_group("Properties")
enum TargetAxis {X, Y, Z, X_Y, X_Z, Y_Z}
## Multiplier for each input axis
@export var sensitivity: float = 0.0
## Axis pair to convert the XY input to
@export var target_axis: TargetAxis = TargetAxis.X
## If true, swaps the axis of the input, applied BEFORE axis inversion
@export var swap_axis: bool = false
## If true, inverts the value of the x axis
@export var invert_x_axis: bool = false
## If true, inverts the value of the y axis
@export var invert_y_axis: bool = false

func _ready() -> void:
	# Avoid execution in editor environment.
	if Engine.is_editor_hint():
		return
	# Bind target callable for 
	if target_object and not target_method_string.is_empty():
		target_method_callable = Callable(target_object, target_method_string)

func _process(delta: float) -> void:
	if not Engine.is_editor_hint() and false:
		if get_tree().paused:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	# Avoid execution in editor environment.
	if Engine.is_editor_hint():
		return
	# Process mouse 
	if not target_method_callable.is_valid():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var raw_input: Vector2 = event.relative * sensitivity
		if swap_axis:
			raw_input = Vector2(raw_input.y, raw_input.x)
		if invert_x_axis:
			raw_input.x *= -1
		if invert_y_axis:
			raw_input.y *= -1
		match target_axis:
			TargetAxis.X_Y:
				target_method_callable.call(Vector3(raw_input.x, raw_input.y, 0))
			TargetAxis.X_Z:
				target_method_callable.call(Vector3(raw_input.x, 0, raw_input.y))
			TargetAxis.Y_Z:
				target_method_callable.call(Vector3(0, raw_input.x, raw_input.y))
			TargetAxis.X:
				target_method_callable.call(Vector3(raw_input.x, 0, 0))
			TargetAxis.Y:
				target_method_callable.call(Vector3(0, raw_input.x, 0))
			TargetAxis.Z:
				target_method_callable.call(Vector3(0, 0, raw_input.x))

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
