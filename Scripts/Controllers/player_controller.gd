## First-person Player Controller consolidating movement input, mouse look, crouching, leaning, and raycast interaction.
class_name PlayerController extends CharacterController3D

signal interaction_target_changed(interactable: Node)

@export_group("Nodes")
@export var camera: Camera3D
@export var collision_shape: CollisionShape3D

@export_group("Mouse Look")
@export var mouse_sensitivity: float = 0.002
@export var vertical_angle_limit: float = 80.0
@export var invert_x_axis: bool = false
@export var invert_y_axis: bool = false

@export_group("Interaction")
@export var interaction_reach: float = 1.5
@export var interact_with_areas: bool = true
@export var interact_with_bodies: bool = false
@export_flags_3d_physics var interaction_collision_mask: int = 0xFFFFFFFF

@export_group("Crouch & Lean")
@export var enable_crouch: bool = true
@export var speed_crouching: float = 1.5
@export var crouch_height_offset: float = -0.6
@export var enable_lean: bool = true
@export var lean_angle_degrees: float = 12.0
@export var lean_offset_distance: float = 0.35
@export var posture_lerp_speed: float = 10.0

var _is_crouching: bool = false
var _base_camera_pos: Vector3 = Vector3.ZERO
var _current_hovered_interactable: Node = null

func _ready() -> void:
	super._ready()
	add_to_group(&"player")
	if not camera:
		camera = get_node_or_null("Camera3D") as Camera3D
	if not collision_shape:
		collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if camera:
		_base_camera_pos = camera.position

func _unhandled_input(event: InputEvent) -> void:
	# Mouse Look
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: Vector2 = event.relative * mouse_sensitivity
		if invert_x_axis:
			motion.x *= -1.0
		if invert_y_axis:
			motion.y *= -1.0
			
		rotate_y(-motion.x)
		if camera:
			var limit_rad: float = deg_to_rad(vertical_angle_limit)
			camera.rotation.x = clampf(camera.rotation.x - motion.y, -limit_rad, limit_rad)
			
	# Discrete Action Inputs
	if event.is_action_pressed(&"move_jump"):
		set_jump()
	elif event.is_action_pressed(&"move_sprint"):
		set_running(not _movement_run)
	elif event.is_action_pressed(&"interact"):
		try_interaction()
	elif enable_crouch and InputMap.has_action(&"move_crouch") and event.is_action_pressed(&"move_crouch"):
		_is_crouching = not _is_crouching

func _physics_process(delta: float) -> void:
	_process_movement_input()
	_process_posture(delta)
	_update_interaction_hover()
	super._physics_process(delta)

func _process_movement_input() -> void:
	var input_vec: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_backward")
	var local_dir := Vector3(input_vec.x, 0.0, input_vec.y)
	var world_dir: Vector3 = (global_basis * local_dir).normalized()
	set_direction(world_dir)
	
	if _is_crouching:
		movement_speed = speed_crouching
	else:
		movement_speed = speed_running if _movement_run else speed_walking

func _process_posture(delta: float) -> void:
	if not camera:
		return
	var target_y: float = _base_camera_pos.y + (crouch_height_offset if _is_crouching else 0.0)
	var lean_input: float = 0.0
	if enable_lean and InputMap.has_action(&"lean_left") and InputMap.has_action(&"lean_right"):
		lean_input = Input.get_axis(&"lean_left", &"lean_right")
		
	var target_x: float = _base_camera_pos.x + (lean_input * lean_offset_distance)
	var target_roll: float = deg_to_rad(-lean_input * lean_angle_degrees)
	
	camera.position.x = lerpf(camera.position.x, target_x, posture_lerp_speed * delta)
	camera.position.y = lerpf(camera.position.y, target_y, posture_lerp_speed * delta)
	camera.rotation.z = lerpf(camera.rotation.z, target_roll, posture_lerp_speed * delta)

#region Raycast Interaction
func try_interaction() -> void:
	var target: Node = _cast_interaction_ray()
	if target and target.has_method(&"trigger_interaction"):
		target.trigger_interaction()

func _update_interaction_hover() -> void:
	var target: Node = _cast_interaction_ray()
	if target != _current_hovered_interactable:
		_current_hovered_interactable = target
		interaction_target_changed.emit(_current_hovered_interactable)

func _cast_interaction_ray() -> Node:
	if not camera:
		return null
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var start_pos: Vector3 = camera.global_position
	var end_pos: Vector3 = start_pos - camera.global_transform.basis.z * interaction_reach
	
	var query := PhysicsRayQueryParameters3D.create(start_pos, end_pos, interaction_collision_mask)
	query.collide_with_areas = interact_with_areas
	query.collide_with_bodies = interact_with_bodies
	
	var exclude_list: Array[RID] = [get_rid()]
	query.exclude = exclude_list
	
	# Max 8 pierces to safely skip non-interactable triggers in the way
	for _i: int in range(8):
		var result: Dictionary = space_state.intersect_ray(query)
		if result.is_empty():
			return null
		var collider: Object = result["collider"]
		if collider is Node and collider.has_method(&"trigger_interaction"):
			return collider as Node
		exclude_list.append(result["rid"])
		query.exclude = exclude_list
	return null
#endregion
