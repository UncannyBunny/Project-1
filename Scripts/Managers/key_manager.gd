extends Node3D

## Stores all active keys
var _keys_stored: Array[String]

## Returns true if the array of keys is active, false otherwise
func search_keys(keys_searched: Array[String]) -> bool:
	for key in keys_searched:
		if not _keys_stored.has(key):
			return false
	return true

## Adds the array of keys to the stored values without repetition
func add_keys(keys_added: Array[String]) -> void:
	for key in keys_added:
		if search_keys([key]):
			continue
		_keys_stored.append(key)

## Removes the array of keys from the stored values
func remove_keys(keys_removed: Array[String]) -> void:
	for key in keys_removed:
		_keys_stored.erase(key)
