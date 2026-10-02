extends Node3D

## Keys active at the start of a loop
var _keys_default: Array[String] = ["neutral"]
## Stores all active keys
var _keys_stored: Array[String]
## Keys that persist through resets
var _keys_persistent: Array[String]

func _ready() -> void:
	_keys_stored = _keys_default + _keys_persistent

## Returns true if the array of keys is active, false otherwise
func search_keys(keys_searched: Array[String]) -> bool:
	if keys_searched.is_empty():
		return true
	for key in keys_searched:
		if not _keys_stored.has(key):
			return false
	return true

## Adds the array of keys to the stored values without repetition
func add_keys(keys_added: Array[String], persistent: bool = false) -> void:
	for key in keys_added:
		if search_keys([key]):
			continue
		_keys_stored.append(key)
		if persistent:
			_keys_persistent.append(key)

## Removes the array of keys from the stored values
func remove_keys(keys_removed: Array[String], aggresive: bool = false) -> void:
	for key in keys_removed:
		_keys_stored.erase(key)
		if aggresive:
			_keys_persistent.erase(key)

func remove_all_keys() -> void:
	_keys_stored = _keys_default + _keys_persistent
