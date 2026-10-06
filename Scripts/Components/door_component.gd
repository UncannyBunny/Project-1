class_name DoorComponent extends Node3D

## Property
@export var property: String:
	set(value):
		property = value
		property_path = NodePath(value)
var property_path: NodePath
@export var value: float
@export var time: float
var value_initial: float
var is_open: bool = false
var is_locked: bool = false
var door_tween: Tween
## Keys that the door require
@export var key_whitelist: Array[String]
## Keys that the door rejects
@export var key_blacklist: Array[String]
## Optional Navigation Link to use for door lock/unlock.
@export var navlink: NavigationLink3D

func _ready() -> void:
	value_initial = self.get_indexed(property_path)
	KeyManager.keys_changed.connect(on_keys_changed)
	is_locked = not KeyManager.check_keys(key_whitelist, key_blacklist)
	if navlink:
		navlink.enabled = not is_locked

func trigger() -> void:
	if is_locked and not is_open:
		return
	toggle()

func on_keys_changed() -> void:
	is_locked = not KeyManager.check_keys(key_whitelist, key_blacklist)
	if navlink:
		navlink.enabled = not is_locked

func toggle() -> void:
	is_open = not is_open
	var time_current: float = time
	var value_target: float = value_initial + value if is_open else value_initial
	if door_tween and door_tween.is_running():
		var time_step: float = abs(value) / time
		var distance: float = abs(value_target - self.get_indexed(property_path))
		time_current = distance / time_step
		door_tween.kill()
	door_tween = create_tween()
	door_tween.tween_property(self, property_path, value_target, time_current)
