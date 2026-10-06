@tool
## Triggers a method when the tracked object enters an area
class_name AreaTriggerComponent extends Area3D

## If true, the method is triggered on entry
@export var trigger_on_enter: bool = true
## If true, the method is triggered on exit
@export var trigger_on_exit: bool = false
## If true, triggers only on the first body entering or the last body exiting
@export var check_occupied: bool = false
var valid_bodies: Array[Node3D]
## Object to track entry/exit of, in the format of "pattern", "type" similar to find_children()
@export var trigger_objects: Dictionary[String, StringName]
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
		body_entered.connect(on_trigger_enter)
	if trigger_on_exit:
		body_exited.connect(on_trigger_exit)

## Triggers on entrance
func on_trigger_enter(body: Node3D) -> void:
	# If method invalid, return
	if not target_method_callable.is_valid():
		return
	if not validate_body(body):
		return
	if not trigger_on_enter:
		return
	if check_occupied:
		if valid_bodies.is_empty():
			target_method_callable.call()
		if not valid_bodies.has(body):
			valid_bodies.append(body)
	else:
		target_method_callable.call()

## Triggers on exit
func on_trigger_exit(body: Node3D) -> void:
	# If method invalid, return
	if not target_method_callable.is_valid():
		return
	if not validate_body(body):
		return
	if not trigger_on_exit:
		return
	if check_occupied:
		valid_bodies.erase(body)
		if valid_bodies.is_empty():
			target_method_callable.call()
	else:
		target_method_callable.call()

func trigger(body: Node3D) -> void:
	# If method invalid, return
	if not target_method_callable.is_valid():
		return
	# If not a tracked body, return
	for pattern in trigger_objects:
		var type: StringName = trigger_objects.get(pattern)
		var script = body.get_script()
		if script and script.get_global_name() == type:
			if body.name.matchn(pattern):
				target_method_callable.call()
				return
		elif body.is_class(type):
			if body.name.matchn(pattern):
				target_method_callable.call()
				return

func validate_body(body: Node3D) -> bool:
	for pattern in trigger_objects:
		var type: StringName = trigger_objects.get(pattern)
		var script = body.get_script()
		if script and script.get_global_name() == type:
			if body.name.matchn(pattern):
				return true
		elif body.is_class(type):
			if body.name.matchn(pattern):
				return true
	return false

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
