class_name ObjectSpawner extends Node

@export var target_object: PackedScene

func spawn_object() -> void:
	var spawned_object: Node = target_object.instantiate()
	get_tree().current_scene.add_child(spawned_object)
