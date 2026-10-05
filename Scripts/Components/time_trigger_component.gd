@tool
## Triggers a method if the current time is inside the target window.
class_name TimeTriggerComponent extends Node3D

@export var one_shot: bool = true
@export var time_start: Vector2i = Vector2i.ZERO:
	set(value):
		time_start = value
		time_start_minutes = time_start.x * 60 + time_start.y
var time_start_minutes: int
@export var time_end: Vector2i = Vector2i.ZERO:
	set(value):
		time_end = value
		time_end_minutes = time_end.x * 60 + time_end.y
var time_end_minutes: int

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

func _process(delta: float) -> void:
	# Avoid execution in editor environment.
	if Engine.is_editor_hint():
		return
	if time_start_minutes > TimeManager.get_current_time():
		return
	if TimeManager.get_current_time() > time_end_minutes and not time_end_minutes == 0:
		return
	if not target_method_callable.is_valid():
		return
	target_method_callable.call()
	if one_shot:
		self.queue_free()

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
