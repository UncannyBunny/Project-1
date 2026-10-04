## Controls a hinged door behaviour
class_name HingeDoorComponent extends Node3D

## Angle to which the door can open
@export var door_angle: float
## Time it takes for the door to open
@export var door_time: float
@export var key_whitelist: Array[String]
@export var key_blacklist: Array[String]
var is_open: bool = false
var is_locked: bool = false
var door_tween: Tween

func trigger_interaction() -> void:
	print("Door interacted")
	is_locked = not check_keys()
	if is_locked and not is_open:
		pass
	elif not (door_tween and door_tween.is_valid()):
		door_toggle()

func check_keys() -> bool:
	if not KeyManager.search_keys(key_whitelist):
		return false
	if KeyManager.search_keys(key_blacklist) and not key_blacklist.is_empty():
		return false
	return true

func door_toggle() -> void:
	is_open = not is_open
	var rotation_target: float = deg_to_rad(door_angle) if is_open else 0.0
	door_tween = create_tween()
	door_tween.tween_property(self, "rotation:y", rotation_target, door_time)
