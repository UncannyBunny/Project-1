## Controls a hinged door behaviour
class_name HingeDoorComponent extends Node3D

## Angle to which the door can open
@export var door_angle: float
## Time it takes for the door to open
@export var door_time: float
# Keys that the door require
@export var key_whitelist: Array[String]
# Keys that the door rejects
@export var key_blacklist: Array[String]
var is_open: bool = false
var is_locked: bool = false
var door_tween: Tween

## Function to trigger on interaction
func trigger() -> void:
	# Check keys
	is_locked = not KeyManager.check_keys(key_whitelist, key_blacklist)
	# If locked and closed cant open
	if is_locked and not is_open:
		pass
	# If unlocked can open/close, if locked and open can close
	elif not (door_tween and door_tween.is_valid()):
		door_toggle()

## Function that toggles the door state
func door_toggle() -> void:
	# Toggle open state
	is_open = not is_open
	# Set target rotation
	var rotation_target: float = deg_to_rad(door_angle) if is_open else 0.0
	# Create and execute tween
	door_tween = create_tween()
	door_tween.tween_property(self, "rotation:y", rotation_target, door_time)
