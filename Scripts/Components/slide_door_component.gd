## Controls a hinged door behaviour
class_name SlideDoorComponent extends Node3D

## Distance that the door slides
@export var door_slide: Vector3
## Time it takes for the door to open
@export var door_time: float
@export var key_whitelist: Array[String]
@export var key_blacklist: Array[String]
var is_open: bool = false
var is_locked: bool = false
var door_tween: Tween
var initial_position: Vector3

func _ready() -> void:
	initial_position = global_position

func trigger_interaction() -> void:
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
	var slide_target: Vector3 = initial_position + door_slide if is_open else initial_position
	door_tween = create_tween()
	door_tween.tween_property(self, "global_position", slide_target, door_time)
