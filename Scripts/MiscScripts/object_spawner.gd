## Instantiates a PackedScene as a child of this node when triggered.
class_name ObjectSpawner extends Node3D

signal object_spawned(instance: Node)

@export var target_scene: PackedScene
@export var spawn_offset: Vector3 = Vector3(0.0, 0.1, 0.0)

func trigger() -> void:
	spawn_object()

func spawn_object() -> void:
	if not target_scene:
		return
	var spawned_object: Node = target_scene.instantiate()
	if spawned_object is Node3D:
		(spawned_object as Node3D).position += spawn_offset
	add_child(spawned_object)
	object_spawned.emit(spawned_object)
