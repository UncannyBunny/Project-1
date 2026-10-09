## Modifies active keys
class_name KeyComponent extends Node3D

# Keys that the door requires
@export var key_whitelist: Array[StringName]
# Keys that the door rejects
@export var key_blacklist: Array[StringName]
## The keys unlocked by triggering the entry
@export var keys_unlocked: Array[StringName]
## The keys lost by triggering the entry
@export var keys_taken: Array[StringName]
# If true, affects persistent keys
@export var aggresive: bool = false

## Function called when the object is triggered
func trigger() -> void:
	if not KeyManager.check_keys(key_whitelist, key_blacklist):
		return
	KeyManager.add_keys(keys_unlocked, aggresive)
	KeyManager.remove_keys(keys_taken, aggresive)
