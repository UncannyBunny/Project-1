## Filters ReadableEntry resources by active keys and priority, sending the highest priority entry to DialogueUI.
class_name ReadableComponent extends Node3D

signal readable_triggered(entry: ReadableEntry)

@export var entries: Array[ReadableEntry] = []

var _dialogue_ui: DialogueUI = null

func _ready() -> void:
	_find_dialogue_ui.call_deferred()

## Evaluates available entries and opens the dialogue UI
func trigger() -> void:
	var readable_current: ReadableEntry = filter_entries()
	if not readable_current:
		return
	if not is_instance_valid(_dialogue_ui):
		_find_dialogue_ui()
	if is_instance_valid(_dialogue_ui):
		_dialogue_ui.display_dialogue(readable_current)
		readable_triggered.emit(readable_current)

## Returns the highest-priority ReadableEntry whose key conditions are currently met
func filter_entries() -> ReadableEntry:
	var best_entry: ReadableEntry = null
	for readable: ReadableEntry in entries:
		if not readable:
			continue
		if KeyManager.check_keys(readable.key_whitelist, readable.key_blacklist):
			if best_entry == null or readable.priority > best_entry.priority:
				best_entry = readable
	return best_entry

func _find_dialogue_ui() -> void:
	_dialogue_ui = get_tree().get_first_node_in_group(&"dialogue_ui") as DialogueUI
	if not _dialogue_ui and get_tree().current_scene:
		_dialogue_ui = get_tree().current_scene.find_child("DialogueUI", true, false) as DialogueUI
