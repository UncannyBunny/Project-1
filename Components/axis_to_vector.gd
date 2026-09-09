@tool
class_name AxisToVector3D extends Node3D

## Object to receive the input
@export var target_object: Node3D:
	set(value):
		target_object = value
		notify_property_list_changed()
## Method that will be called with the input
@export var target_method_string: String = ""
var target_method_callable: Callable
var component_x: float
var component_y: float
var component_z: float

func _ready() -> void:
	# Avoid execution in editor environment.
	if Engine.is_editor_hint():
		return
	# Bind target callable for 
	if target_object and not target_method_string.is_empty():
		target_method_callable = Callable(target_object, target_method_string)

func set_component_x(value: float) -> void:
	component_x = value
func set_component_y(value: float) -> void:
	component_y = value
func set_component_z(value: float) -> void:
	component_z = value

func _process(delta: float) -> void:
	if not target_method_callable.is_valid():
		return
	var output_vector: Vector3 = Vector3(component_x, component_y, component_z)
	target_method_callable.call(output_vector)

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
