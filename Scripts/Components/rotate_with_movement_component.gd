@tool
## Points the negative Z axis (Forward) direction of a CharacterBody3D torwards the direction of their velocity.
class_name RotateWithMovementComponent extends Node3D

## Object to receive the input
@export var target_object: CharacterBody3D:
	set(value):
		target_object = value
		notify_property_list_changed()
## Method that will be called with the input
@export var target_method_string: String = ""
var target_method_callable: Callable
@export var rotation_speed: float = 0

func _ready() -> void:
	# Avoid execution in editor environment.
	if Engine.is_editor_hint():
		return
	# Bind target callable for 
	if target_object and not target_method_string.is_empty():
		target_method_callable = Callable(target_object, target_method_string)

func _physics_process(delta: float) -> void:
	# Avoid execution in editor environment.
	if Engine.is_editor_hint():
		return
	var velocity: Vector3 = target_object.velocity
	var velocity_hor: Vector2 = Vector2(velocity.x, velocity.y)
	if velocity_hor.length() >= 0.1:
		var target_angle: float = atan2(-velocity.x, -velocity.z)
		target_angle = lerp_angle(target_object.rotation.y, target_angle, rotation_speed * delta)
		target_method_callable.call(target_angle)

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
