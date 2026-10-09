## Raycasts from the origin object and checks if the hit object is interactable
class_name InteractionController extends Node3D

## Object from which the ray is cast
@export var origin_object: Node3D
## Reach distance for the interaction
@export var reach: float = 0
## If true, targets areas
@export var target_areas: bool = true
## If true, targets bodies
@export var target_bodies: bool = false

func try_interaction() -> void:
	var space_state = get_world_3d().direct_space_state
	var start_pos = origin_object.global_position
	var end_pos = origin_object.global_position - origin_object.global_transform.basis.z * reach
	var query = PhysicsRayQueryParameters3D.create(start_pos, end_pos)
	query.collide_with_areas = target_areas
	query.collide_with_bodies = target_bodies
	var exclude_list: Array[RID] = []
	while true:
		var result = space_state.intersect_ray(query)
		if result.is_empty():
			return
		var object: Node = result.collider
		if object.has_method("trigger_interaction"):
			object.trigger_interaction()
			return
		exclude_list.append(result.rid)
		query.exclude = exclude_list
