## Autoload Manager that tracks active, persistent, and default StringName keys, as well as loop currency.
extends Node

signal keys_changed
signal key_added(key: StringName)
signal key_removed(key: StringName)

@export_group("Default State")
## Keys active at the start of every loop
@export var default_keys: Array[StringName] = [&"neutral"]

## Stores all currently active keys in the loop
var _keys_stored: Array[StringName] = []
## Keys that persist through loop resets (e.g., major discoveries/notebook unlocks)
var _keys_persistent: Array[StringName] = []

func _ready() -> void:
	reset()

#region Key Management
## Returns true if all keys in keys_searched are present in key_chain
func search_keys(keys_searched: Array[StringName], key_chain: Array[StringName] = _keys_stored) -> bool:
	if keys_searched.is_empty():
		return true
	for key: StringName in keys_searched:
		if not key_chain.has(key):
			return false
	return true

## Returns true if ANY key in keys_searched is present in key_chain
func search_any_key(keys_searched: Array[StringName], key_chain: Array[StringName] = _keys_stored) -> bool:
	if keys_searched.is_empty():
		return false
	for key: StringName in keys_searched:
		if key_chain.has(key):
			return true
	return false

## Checks key values against both a whitelist (all required) and a blacklist (none allowed)
func check_keys(key_whitelist: Array[StringName], key_blacklist: Array[StringName], key_chain: Array[StringName] = _keys_stored) -> bool:
	if not search_keys(key_whitelist, key_chain):
		return false
	if not key_blacklist.is_empty() and search_any_key(key_blacklist, key_chain):
		return false
	return true

## Adds an array of keys to the stored values without repetition
func add_keys(keys_added: Array[StringName], persistent: bool = false) -> void:
	var changed: bool = false
	for key: StringName in keys_added:
		if key == &"":
			continue
		if not _keys_stored.has(key):
			_keys_stored.append(key)
			changed = true
			key_added.emit(key)
		if persistent and not _keys_persistent.has(key):
			_keys_persistent.append(key)
	if changed:
		keys_changed.emit()

## Removes an array of keys from the stored values. If aggressive is true, also removes from persistent keys.
func remove_keys(keys_removed: Array[StringName], aggressive: bool = false) -> void:
	var changed: bool = false
	for key: StringName in keys_removed:
		if _keys_stored.has(key):
			_keys_stored.erase(key)
			changed = true
			key_removed.emit(key)
		if aggressive and _keys_persistent.has(key):
			_keys_persistent.erase(key)
	if changed:
		keys_changed.emit()

## Resets active keys back to default + persistent state for a new loop
func reset() -> void:
	_keys_stored.clear()
	for key: StringName in default_keys:
		if not _keys_stored.has(key):
			_keys_stored.append(key)
	for key: StringName in _keys_persistent:
		if not _keys_stored.has(key):
			_keys_stored.append(key)
	keys_changed.emit()

## Returns a read-only duplicate of currently active keys
func get_active_keys() -> Array[StringName]:
	return _keys_stored.duplicate()

## Returns a copy of persistent keys for saving
func get_persistent_keys() -> Array[StringName]:
	return _keys_persistent.duplicate()

## Restores persistent keys from a loaded save and resets active loop keys
func set_persistent_keys(loaded_keys: Array[StringName]) -> void:
	_keys_persistent = loaded_keys.duplicate()
	reset()
#endregion
