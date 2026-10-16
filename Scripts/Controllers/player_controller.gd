## First-person Player Controller consolidating movement input, mouse look, crouching, leaning, and raycast interaction.
class_name PlayerController extends CharacterController3D

signal interaction_target_changed(interactable: Node)
signal crouch_changed(is_crouching: bool)
signal lean_changed(lean_direction: float)

@export_group("Nodes")
@export var camera: Camera3D
@export var collision_shape: CollisionShape3D
@export var animation_tree: AnimationTree

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
@export var speed_crouching: float = 0.5
@export var anim_blend_speed: float = 2.0

var _is_crouching: bool = false
var _lean_direction: float = 0.0
var _current_hovered_interactable: Node = null

var _crouch_blend: float = 0.0
var _lean_blend: float = 0.0
var _move_blend: float = 0.0

func _ready() -> void:
	super._ready()
	add_to_group(&"player")
	if not camera:
		camera = get_node_or_null("Camera3D") as Camera3D
	if not collision_shape:
		collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if animation_tree:
		animation_tree.active = true

func _input(event: InputEvent) -> void:
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
		if _is_crouching:
			_set_crouching(false)
		else:
			set_jump()
	elif event.is_action_pressed(&"interact"):
		try_interaction()
	elif event.is_action_pressed(&"move_crouch"):
		if not _movement_run:
			_set_crouching(not _is_crouching)

func _physics_process(delta: float) -> void:
	_process_movement_and_posture_input()
	_update_interaction_hover()
	super._physics_process(delta)
	_update_animation_tree(delta)

func _process_movement_and_posture_input() -> void:
	var input_vec: Vector2 = Input.get_vector(&"move_right", &"move_left", &"move_backward", &"move_forward")
	var local_dir := Vector3(input_vec.x, 0.0, input_vec.y)
	var world_dir: Vector3 = (global_basis * local_dir).normalized()
	set_direction(world_dir)
	
	var is_trying_to_move: bool = input_vec != Vector2.ZERO
	var wants_to_run: bool = false
	wants_to_run = Input.is_action_pressed(&"move_sprint") and is_trying_to_move
		
	if wants_to_run:
		set_running(true)
		if _is_crouching:
			_set_crouching(false)
		if _lean_direction != 0.0:
			_set_leaning(0.0)
	else:
		set_running(false)
		if not is_trying_to_move and not _is_crouching and is_on_floor():
			var raw_lean: float = Input.get_axis(&"lean_left", &"lean_right")
			_set_leaning(raw_lean)
	
	if _is_crouching:
		movement_speed = speed_crouching
	else:
		movement_speed = speed_running if _movement_run else speed_walking

func _set_crouching(crouching: bool) -> void:
	if _is_crouching == crouching:
		return
	_is_crouching = crouching
	if _is_crouching and _lean_direction != 0.0:
		_set_leaning(0.0)
	crouch_changed.emit(_is_crouching)

func _set_leaning(lean_dir: float) -> void:
	if is_equal_approx(_lean_direction, lean_dir):
		return
	_lean_direction = lean_dir
	lean_changed.emit(_lean_direction)

#region AnimationTree Integration
func _update_animation_tree(delta: float) -> void:
	if not animation_tree:
		return
	var target_move: float = 0.0
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.2:
		target_move = 2.0 if _movement_run else 1.0
	
	_move_blend = move_toward(_move_blend, target_move, anim_blend_speed * delta)
	_crouch_blend = move_toward(_crouch_blend, 1.0 if _is_crouching else 0.0, anim_blend_speed * delta)
	_lean_blend = move_toward(_lean_blend, _lean_direction, anim_blend_speed * delta)
	
	animation_tree.set(&"parameters/locomotion_stand/blend_position", _move_blend)
	animation_tree.set(&"parameters/locomotion_stand/BlendSpace1D/blend_position", _lean_blend)
	animation_tree.set(&"parameters/locomotion_crouch/blend_position", clampf(_move_blend, 0.0, 1.0))
	animation_tree.set(&"parameters/crouch_blend/blend_amount", _crouch_blend)
	animation_tree.set(&"parameters/in_air/transition_request", "air" if not is_on_floor() else "grounded")
#endregion

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
