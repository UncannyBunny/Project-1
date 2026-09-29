@tool
## Outputs a direction torwards a set point using godot’s pathfinding agents.
class_name PathfindingComponent extends Node3D

## Object to receive the input
@export var target_object: Node3D:
	set(value):
		target_object = value
		notify_property_list_changed()
## Method that will be called with the input
@export var target_method_string: String = ""
var target_method_callable: Callable
@export var nav_agent: NavigationAgent3D

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
	if not target_object or not nav_agent:
		return
	_navigation()

func _navigation() -> void:
	if nav_agent.is_navigation_finished():
		target_method_callable.call(Vector3.ZERO)
		return
	var pos_current: Vector3 = target_object.global_position
	var pos_next: Vector3 = nav_agent.get_next_path_position()
	var direction: Vector3 = pos_current.direction_to(pos_next)
	target_method_callable.call(direction)

func set_target_position(target_pos: Vector3) -> void:
	if nav_agent:
		nav_agent.target_position = target_pos

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
