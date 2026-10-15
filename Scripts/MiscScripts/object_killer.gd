## Frees a target node when triggered.
class_name ObjectKiller extends Node3D

signal object_killed

@export var target_object: Node

func trigger() -> void:
	trigger_kill()

func trigger_kill() -> void:
	if is_instance_valid(target_object):
		target_object.queue_free()
		object_killed.emit()
