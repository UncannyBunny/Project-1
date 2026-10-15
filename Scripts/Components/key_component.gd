## Modifies active or persistent keys in KeyManager when triggered.
class_name KeyComponent extends Node3D

signal keys_modified

@export_group("Conditions")
## Keys required for this component to execute when triggered
@export var key_whitelist: Array[StringName] = []
## Keys that prevent this component from executing when triggered
@export var key_blacklist: Array[StringName] = []

@export_group("Key Changes")
## Keys unlocked when triggered
@export var keys_unlocked: Array[StringName] = []
## Keys removed when triggered
@export var keys_taken: Array[StringName] = []
## If true, affects persistent keys across loops
@export var persistent: bool = false

## Evaluates key conditions and applies key modifications
func trigger() -> void:
	if not KeyManager.check_keys(key_whitelist, key_blacklist):
		return
	if not keys_unlocked.is_empty():
		KeyManager.add_keys(keys_unlocked, persistent)
	if not keys_taken.is_empty():
		KeyManager.remove_keys(keys_taken, persistent)
	keys_modified.emit()
