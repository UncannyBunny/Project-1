class_name KeyComponent extends Node3D

@export var key_whitelist: Array[String]
@export var key_blacklist: Array[String]
## The keys unlocked by triggering the entry
@export var keys_unlocked: Array[String]
## The keys lost by triggering the entry
@export var keys_taken: Array[String]

func trigger_interaction() -> void:
	if not check_keys():
		return
	KeyManager.add_keys(keys_unlocked)
	KeyManager.remove_keys(keys_taken)

func check_keys() -> bool:
	if not KeyManager.search_keys(key_whitelist):
		return false
	if KeyManager.search_keys(key_blacklist) and not key_blacklist.is_empty():
		return false
	return true
