## Manages readable interaction.
class_name ReadableComponent extends Node3D

## Object to receive the input
var target_object: DialogueUI
## ReadableEntry array used by the component
@export var entries: Array[ReadableEntry]

func _ready() -> void:
	# Avoid execution in editor environment.
	if Engine.is_editor_hint():
		return
	# Bind target callable for 
	target_object = get_tree().current_scene.find_child("DialogueUI")

## Method that will be called when interacting
func trigger() -> void:
	var readable_current: ReadableEntry = filter_entries()
	# Checks if a readable is available
	if readable_current == null:
		return
	# Triggers method
	target_object.display_dialogue(readable_current)

## Filters entries by unlocked keys and priority
func filter_entries() -> ReadableEntry:
	var valid_entries: Array[ReadableEntry]
	for readable in entries:
		if KeyManager.check_keys(readable.key_whitelist, readable.key_blacklist):
			valid_entries.append(readable)
	if valid_entries.is_empty():
		return null
	valid_entries.sort_custom(func(a, b): return a.priority > b.priority)
	return valid_entries[0]
