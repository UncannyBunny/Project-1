@tool
class_name DoorPathfindingComponent extends Area3D

@export var door: DoorComponent
## Object to receive the input
@export var target_object: Node3D:
	set(value):
		target_object = value
		notify_property_list_changed()
## Method that will be called with the input
@export var target_method_string: String = ""
var target_method_callable: Callable

func _ready() -> void:
	# Avoid execution in editor environment.
	if Engine.is_editor_hint():
		return
	# Bind target callable for 
	if target_object and not target_method_string.is_empty():
		target_method_callable = Callable(target_object, target_method_string)
	body_entered.connect(on_trigger_enter)

func on_trigger_enter(body: Node3D) -> void:
	if not body is CharacterController3D:
		return
	var body_pathfinder: PathfindingComponent = body.find_children("*", "PathfindingComponent")[0]
	if not door.is_open and not door.is_locked:
		door.trigger()
	while door.door_tween.is_valid() and not door.is_locked:
		body_pathfinder.pause_navigation()
	body_pathfinder.pause_navigation(false)

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
