@tool
## Trigfgers a method when the tracked object enters an area
class_name AreaTriggerComponent extends Area3D

## If true, the method is triggered on entry
@export var trigger_on_enter: bool = true
## If true, the method is triggered on exit
@export var trigger_on_exit: bool = false
## Object to track entry/exit of
@export var trigger_object: Node3D
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
	# Subscribe to signal depending on trigger conditions
	if trigger_on_enter:
		body_entered.connect(trigger)
	if trigger_on_exit:
		body_exited.connect(trigger)

## Triggers on entrance
func trigger(body) -> void:
	# If not tracked body, return
	if not body == trigger_object:
		return
	# If method invalid, return
	if not target_method_callable.is_valid():
		return
	# Method trigger
	target_method_callable.call()

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
