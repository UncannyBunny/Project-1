## Manages NPC navigation for both scheduled routines and hostile player chasing.
class_name PathfindingComponent extends Node3D

signal destination_reached
signal player_caught
signal behavior_mode_changed(is_chasing: bool)

enum BehaviorMode {
	ROUTINE,
	CHASE
}

@export_group("References")
@export var character: CharacterController3D
@export var nav_agent: NavigationAgent3D

@export_group("Chase Behavior")
## If any of these keys are active in KeyManager, the NPC switches from Routine to Chase mode
@export var chase_trigger_keys: Array[StringName] = [&"aggresive"]
## Distance at which the chasing NPC catches the player and resets the loop
@export var catch_distance: float = 1.2
## Optional explicit chase target; if null, automatically finds the node in group "player"
@export var chase_target: Node3D

var is_running: bool = false
var current_mode: BehaviorMode = BehaviorMode.ROUTINE
var nav_paused: bool = true
var nav_layer: int = NavigationLayerManager.PUBLIC_LAYER
var accessible_doors: Array[DoorComponent] = []

var _on_link: bool = false
var _link_target: Vector3 = Vector3.ZERO
var _routine_target_position: Vector3 = Vector3.ZERO
var _has_routine_target: bool = false
var _arrival_rotation_y: float = 0.0
var _use_arrival_rotation: bool = false

var _last_pos: Vector3 = Vector3.ZERO
var _stuck_time: float = 0.0
var _is_clipping: bool = false
var _unstuck_timer: float = 0.0

func _ready() -> void:
	if not character and owner is CharacterController3D:
		character = owner as CharacterController3D
	if not nav_agent:
		nav_agent = get_node_or_null("../NavigationAgent3D") as NavigationAgent3D
		
	if nav_agent:
		nav_agent.link_reached.connect(_on_nav_link_reached)
		
	KeyManager.keys_changed.connect(_evaluate_behavior_mode)
	_evaluate_behavior_mode.call_deferred()

func _exit_tree() -> void:
	_release_private_nav_layer()

func _physics_process(delta: float) -> void:
	if not character or not nav_agent:
		return
	match current_mode:
		BehaviorMode.ROUTINE:
			_process_routine_navigation()
			_check_if_stuck(delta)
		BehaviorMode.CHASE:
			_process_chase_navigation()

#region Mode Switching
func _evaluate_behavior_mode() -> void:
	var should_chase: bool = KeyManager.search_any_key(chase_trigger_keys)
	var target_mode: BehaviorMode = BehaviorMode.CHASE if should_chase else BehaviorMode.ROUTINE
	if target_mode == current_mode:
		return
	
	current_mode = target_mode
	if current_mode == BehaviorMode.CHASE:
		_find_chase_target()
		nav_paused = false
		_on_link = false
		_update_accessible_doors()
		behavior_mode_changed.emit(true)
	else:
		behavior_mode_changed.emit(false)
		if _has_routine_target:
			set_target_position(_routine_target_position, _use_arrival_rotation, _arrival_rotation_y)
		else:
			nav_paused = true
			character.set_movement(Vector3.ZERO, false)

func _find_chase_target() -> void:
	if is_instance_valid(chase_target):
		return
	chase_target = get_tree().get_first_node_in_group(&"player") as Node3D
	if not chase_target and get_tree().current_scene:
		chase_target = get_tree().current_scene.find_child("PlayerController") as Node3D
#endregion

#region Routine Navigation
## Sets a new target destination for the NPC
func set_target_position(target_pos: Vector3, use_rotation: bool = false, target_rot_degrees: float = 0.0, running: bool = false) -> void:
	if not nav_agent or not character:
		return
	_routine_target_position = target_pos
	_has_routine_target = true
	_use_arrival_rotation = use_rotation
	_arrival_rotation_y = deg_to_rad(target_rot_degrees)
	is_running = running
	
	if current_mode == BehaviorMode.CHASE:
		return
	
	nav_paused = false
	_update_accessible_doors()
	nav_agent.target_position = target_pos

func pause_navigation(paused: bool = true) -> void:
	nav_paused = paused
	if nav_paused and character:
		character.set_movement(Vector3.ZERO, false)

func _process_routine_navigation() -> void:
	if nav_paused:
		character.set_movement(Vector3.ZERO, false)
		return
		
	if nav_agent.is_navigation_finished():
		var distance_to_target: float = character.global_position.distance_to(nav_agent.target_position)
		if distance_to_target < nav_agent.path_desired_distance + 1.5:
			_release_private_nav_layer()
			nav_paused = true
			character.set_movement(Vector3.ZERO, false)
			if _use_arrival_rotation:
				var rot_tween: Tween = create_tween()
				rot_tween.tween_property(character, "rotation:y", _arrival_rotation_y, 0.5)
			destination_reached.emit()
		else:
			set_target_position(nav_agent.target_position, _use_arrival_rotation, rad_to_deg(_arrival_rotation_y))
		return
		
	if _on_link and character.global_position.distance_to(_link_target) < nav_agent.path_desired_distance:
		_on_link = false
		
	var pos_current: Vector3 = character.global_position
	var pos_next: Vector3 = _link_target if _on_link else nav_agent.get_next_path_position()
	var direction: Vector3 = pos_current.direction_to(pos_next)
	character.set_movement(direction, is_running or current_mode == BehaviorMode.CHASE)

func _on_nav_link_reached(details: Dictionary) -> void:
	_on_link = true
	_link_target = details["link_exit_position"]
#endregion

#region Chase Navigation
func _process_chase_navigation() -> void:
	if not is_instance_valid(chase_target):
		_find_chase_target()
		if not is_instance_valid(chase_target):
			character.set_movement(Vector3.ZERO, false)
			return
			
	nav_agent.target_position = chase_target.global_position
	if character.global_position.distance_to(chase_target.global_position) <= catch_distance:
		player_caught.emit()
		LoopManager.trigger_loop_reset()
		return
		
	if nav_agent.is_navigation_finished():
		character.set_movement(Vector3.ZERO, false)
		return
		
	var pos_current: Vector3 = character.global_position
	var pos_next: Vector3 = nav_agent.get_next_path_position()
	var direction: Vector3 = pos_current.direction_to(pos_next)
	character.set_movement(direction, true)
#endregion

#region Door & Layer Management
func _update_accessible_doors() -> void:
	accessible_doors.clear()
	var doors: Array[Node] = get_tree().get_nodes_in_group(&"doors")
	if doors.is_empty() and get_tree().current_scene:
		doors = get_tree().current_scene.find_children("*", "DoorComponent")
		
	for node: Node in doors:
		var door := node as DoorComponent
		if not door:
			continue
		if not door.key_whitelist.is_empty() or not door.key_blacklist.is_empty():
			if door.check_lock(character.private_keys):
				accessible_doors.append(door)
				
	if not accessible_doors.is_empty():
		if nav_layer == NavigationLayerManager.PUBLIC_LAYER:
			nav_layer = NavigationLayerManager.claim_layer()
		for door: DoorComponent in accessible_doors:
			door.add_nav_layer(nav_layer)
		nav_agent.navigation_layers = NavigationLayerManager.PUBLIC_LAYER | nav_layer
		NavigationServer3D.map_force_update(get_world_3d().navigation_map)

func _release_private_nav_layer() -> void:
	if nav_layer != NavigationLayerManager.PUBLIC_LAYER:
		for door: DoorComponent in accessible_doors:
			if is_instance_valid(door):
				door.remove_nav_layer(nav_layer)
		NavigationLayerManager.release_layer(nav_layer)
		if is_instance_valid(nav_agent):
			nav_agent.navigation_layers = NavigationLayerManager.PUBLIC_LAYER
		nav_layer = NavigationLayerManager.PUBLIC_LAYER
#endregion

#region Anti-Stuck Clipping
func _check_if_stuck(delta: float) -> void:
	if nav_paused:
		return
	if character.global_position.distance_to(_last_pos) < 0.05:
		_stuck_time += delta
		if _stuck_time > 1.0 and not _is_clipping:
			_set_npc_collision_enabled(false)
	else:
		_stuck_time = 0.0
		if _is_clipping:
			_unstuck_timer += delta
			if _unstuck_timer >= 0.5:
				_set_npc_collision_enabled(true)
	_last_pos = character.global_position

func _set_npc_collision_enabled(enabled: bool) -> void:
	_is_clipping = not enabled
	_stuck_time = 0.0
	_unstuck_timer = 0.0
	character.set_collision_layer_value(2, enabled)
	character.set_collision_mask_value(2, enabled)
#endregion
