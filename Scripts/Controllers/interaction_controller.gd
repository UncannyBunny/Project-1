class_name InteractionController extends Node3D

@export var camera_object: Camera3D
@export var reach: float = 0

func trigger_interaction() -> void:
	var space_state = get_world_3d().direct_space_state
	var start_pos = camera_object.global_position
	var end_pos = camera_object.global_position - camera_object.global_transform.basis.z * reach
	var query = PhysicsRayQueryParameters3D.create(start_pos, end_pos)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var result = space_state.intersect_ray(query)
	if result:
		var object: Node = result.collider
		if object is InteractionComponent:
			print("INTERACTED")
			object.trigger_interaction()
