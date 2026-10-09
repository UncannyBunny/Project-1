@tool
## Triggers a method depending on existing keys
class_name KeyTriggerComponent extends Node3D

# Keys that the door requires
@export var key_whitelist: Array[StringName]
# Keys that the door rejects
@export var key_blacklist: Array[StringName]
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
	KeyManager.keys_changed.connect(on_keys_changed)

func on_keys_changed() -> void:
	if check_keys():
		target_method_callable.call()

func check_keys() -> bool:
	if not KeyManager.search_keys(key_whitelist):
		return false
	if KeyManager.search_keys(key_blacklist) and not key_blacklist.is_empty():
		return false
	return true

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
