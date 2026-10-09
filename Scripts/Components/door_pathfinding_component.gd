class_name DoorPathfindingComponent extends Area3D

@export var door: DoorComponent
@export var toggle_door: bool = true
var valid_bodies: Array[Node3D] = []

func _ready() -> void:
	body_entered.connect(on_trigger_enter)
	body_exited.connect(on_trigger_exit)

func on_trigger_enter(body: Node3D) -> void:
	if not body is CharacterController3D:
		return
	body = body as CharacterController3D
	var pathfinders = body.find_children("*", "PathfindingComponent")
	if pathfinders.is_empty():
		return
	var body_pathfinder: PathfindingComponent = pathfinders[0]
	if not valid_bodies.has(body):
		valid_bodies.append(body)
	if not door.is_open and door.check_lock(body.private_keys):
		if toggle_door: print(body.name + " has opened " + door.name)
		if toggle_door: door.trigger(body.private_keys)
		await get_tree().physics_frame
	if door.door_tween and door.door_tween.is_valid() and door.check_lock(body.private_keys):
		print(body.name + " is waiting for " + door.name)
		body_pathfinder.pause_navigation(true)
		body.set_collision_mask_value(2, false)
		body.set_collision_layer_value(2, false)
		await door.door_tween.finished
	if is_instance_valid(body_pathfinder):
		body_pathfinder.pause_navigation(false)
		body.set_collision_mask_value(2, true)
		body.set_collision_layer_value(2, false)

func on_trigger_exit(body: Node3D) -> void:
	if not body is CharacterController3D:
		return
	var pathfinders = body.find_children("*", "PathfindingComponent")
	if pathfinders.is_empty():
		return
	valid_bodies.erase(body)
	if valid_bodies.is_empty() and door.is_open:
		if toggle_door: print(body.name + " is closing " + door.name)
		if toggle_door: door.trigger()
