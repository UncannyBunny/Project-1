extends Node3D

signal keys_changed

## Keys active at the start of a loop
var _keys_default: Array[StringName] = ["neutral"]
## Stores all active keys
var _keys_stored: Array[StringName]
## Keys that persist through resets
var _keys_persistent: Array[StringName]

func _ready() -> void:
	_keys_stored = _keys_default + _keys_persistent

## Returns true if the array of keys is active, false otherwise
func search_keys(keys_searched: Array[StringName], key_chain: Array[StringName] = _keys_stored) -> bool:
	if keys_searched.is_empty():
		return true
	for key in keys_searched:
		if not key_chain.has(key):
			return false
	return true

## Adds the array of keys to the stored values without repetition
func add_keys(keys_added: Array[StringName], persistent: bool = false) -> void:
	for key in keys_added:
		if search_keys([key]):
			continue
		_keys_stored.append(key)
		if persistent:
			_keys_persistent.append(key)
		keys_changed.emit()

## Removes the array of keys from the stored values
func remove_keys(keys_removed: Array[StringName], aggresive: bool = false) -> void:
	for key in keys_removed:
		_keys_stored.erase(key)
		if aggresive:
			_keys_persistent.erase(key)
		keys_changed.emit()

func remove_all_keys() -> void:
	_keys_stored = _keys_default + _keys_persistent
	keys_changed.emit()

## Function that checks key values agains a white/black list
func check_keys(key_whitelist: Array[StringName], key_blacklist: Array[StringName], key_chain: Array[StringName] = _keys_stored) -> bool:
	if not search_keys(key_whitelist, key_chain):
		return false
	if search_keys(key_blacklist, key_chain) and not key_blacklist.is_empty():
		return false
	return true
