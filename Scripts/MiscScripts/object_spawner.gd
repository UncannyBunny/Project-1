class_name ObjectSpawner extends Node3D

@export var target_object: PackedScene

func spawn_object() -> void:
	var spawned_object: Node = target_object.instantiate()
	spawned_object.position.y = spawned_object.position.y + 0.1
	self.add_child(spawned_object)
