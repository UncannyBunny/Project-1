@tool
## Manages readable interaction.
class_name ReadableComponent extends Node3D

## Object to receive the input
@export var target_object: Node:
	set(value):
		target_object = value
		notify_property_list_changed()
## Method that will be called with the input
@export var target_method_string: String = ""
var target_method_callable: Callable
@export var entries: Array[ReadableEntry]

func _ready() -> void:
	# Avoid execution in editor environment.
	if Engine.is_editor_hint():
		return
	# Bind target callable for 
	if target_object and not target_method_string.is_empty():
		target_method_callable = Callable(target_object, target_method_string)

## Method that will be called when interacting
func trigger_interaction() -> void:
	var readable_current: ReadableEntry = filter_entries()
	if readable_current == null:
		return
	target_method_callable.call(readable_current)

## Filters entries by unlocked keys and priority
func filter_entries() -> ReadableEntry:
	var valid_entries: Array[ReadableEntry]
	for readable in entries:
		if check_keys(readable):
			valid_entries.append(readable)
	if valid_entries.is_empty():
		return null
	valid_entries.sort_custom(func(a, b): return a.priority > b.priority)
	return valid_entries[0]

func check_keys(readable: ReadableEntry) -> bool:
	if not KeyManager.search_keys(readable.key_whitelist):
		return false
	if KeyManager.search_keys(readable.key_blacklist) and not readable.key_blacklist.is_empty():
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
