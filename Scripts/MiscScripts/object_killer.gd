class_name ObjectKiller extends Node3D

@export var target_object: Node

func trigger_kill() -> void:
	target_object.queue_free()
