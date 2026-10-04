@tool
class_name TimeTriggerComponent extends Node3D

@export var target_time: Vector2i = Vector2i.ZERO:
	set(value):
		target_time = value
		target_time_minutes = TimeManager.time_from_vector(target_time)
var target_time_minutes: int
@export var key_whitelist: Array[String]
@export var key_blacklist: Array[String]
## The keys unlocked by triggering the entry
@export var keys_unlocked: Array[String]
## The keys lost by triggering the entry
@export var keys_taken: Array[String]

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
	if TimeManager.get_current_time() >= target_time_minutes and check_keys():
		KeyManager.add_keys(keys_unlocked)
		KeyManager.remove_keys(keys_taken)

func check_keys() -> bool:
	if not KeyManager.search_keys(key_whitelist):
		return false
	if KeyManager.search_keys(key_blacklist) and not key_blacklist.is_empty():
		return false
	return true

func trigger() -> void:
	if not target_method_callable.is_valid():
		return
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
