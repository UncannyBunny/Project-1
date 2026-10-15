## Monitors TimeManager and triggers a target node or signal when the current time enters the specified window.
class_name TimeTriggerComponent extends Node3D

signal triggered

@export_group("Time Window")
@export var one_shot: bool = true
@export var time_start: Vector2i = Vector2i.ZERO:
	set(value):
		time_start = value
		time_start_minutes = value.x * 60 + value.y
var time_start_minutes: int = 0

@export var time_end: Vector2i = Vector2i.ZERO:
	set(value):
		time_end = value
		time_end_minutes = value.x * 60 + value.y
var time_end_minutes: int = 0

@export_group("Target")
## Optional node to call .trigger() on when the time window is active
@export var target_object: Node

func _ready() -> void:
	TimeManager.time_changed.connect(_on_time_changed)
	_on_time_changed.call_deferred(TimeManager.get_current_time())

func _on_time_changed(current_time: int) -> void:
	if current_time < time_start_minutes:
		return
	if time_end_minutes != 0 and current_time > time_end_minutes:
		return
		
	if target_object and target_object.has_method(&"trigger"):
		target_object.call(&"trigger")
	triggered.emit()
	
	if one_shot:
		queue_free()
