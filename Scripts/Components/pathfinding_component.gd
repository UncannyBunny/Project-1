@tool
## Outputs a direction torwards a received point using godot’s pathfinding.
class_name PathfindingComponent extends Node3D

## Agent used to calculate the pathfinding
@export var nav_agent: NavigationAgent3D
var on_link: bool = false
var link_target: Vector3
## Object to receive the input
@export var target_object: CharacterController3D:
	set(value):
		target_object = value
		notify_property_list_changed()
## Method that will be called with the input
@export var target_method_string: String = ""
var target_method_callable: Callable
var nav_paused: bool = false
var nav_layer: int = 1
var accessible_doors: Array[DoorComponent]

var last_pos: Vector3
var stuck_time: float
var is_clipping: bool
var unstuck_timer: float

func _ready() -> void:
	# Avoid execution in editor environment.
	if Engine.is_editor_hint():
		return
	# Bind target callable for 
	if target_object and not target_method_string.is_empty():
		target_method_callable = Callable(target_object, target_method_string)
	nav_agent.link_reached.connect(on_nav_link)
	nav_agent.path_changed.connect(path_changed)

func path_changed() -> void:
	print(target_object.name + " is using path " + str(nav_agent.get_current_navigation_path()))

func _physics_process(delta: float) -> void:
	# Avoid execution in editor environment.
	if Engine.is_editor_hint():
		return
	if not target_object or not nav_agent:
		return
	_navigation()
	_check_if_stuck(delta)

func _check_if_stuck(delta: float) -> void:
	if nav_paused:
		return
	if target_object.global_position.distance_to(last_pos) < 0.1:
		stuck_time += delta
		if stuck_time > 1.0 and not is_clipping:
			_enable_clipping()
	else:
		stuck_time = 0.0
		if is_clipping:
			unstuck_timer += delta
			if unstuck_timer >= 0.5:
				_reset_clipping()
	last_pos = target_object.global_position

func _enable_clipping() -> void:
	is_clipping = true
	stuck_time = 0.0
	target_object.set_collision_layer_value(2, false)
	target_object.set_collision_mask_value(2, false)

func _reset_clipping() -> void:
	is_clipping = false
	unstuck_timer = 0.0
	target_object.set_collision_layer_value(2, true)
	target_object.set_collision_mask_value(2, true)

func on_nav_link(details: Dictionary) -> void:
	print(target_object.name + " has entered a link")
	on_link = true
	link_target = details["link_exit_position"]

## Function used to calculate pathfinding
func _navigation() -> void:
	if nav_paused: 
		target_method_callable.call(Vector3.ZERO)
		return
	if nav_agent.is_navigation_finished():
		var distance_to_target: float = target_object.global_position.distance_to(nav_agent.target_position)
		if distance_to_target < nav_agent.path_desired_distance + 1.5:
			print(target_object.name + " reached its final waypoint safely")
			if nav_layer != 1:
				for door in accessible_doors:
					door.remove_nav_layer(nav_layer)
				NavigationLayerManager.release_layer(nav_layer)
				nav_agent.navigation_layers = 1
				print(target_object.name + " has released the layer " + str(nav_layer))
				nav_layer = 1
			nav_paused = true
		else:
			print(target_object.name + " path ended prematurely! Distance remaining: " + str(distance_to_target))
			set_target_position(nav_agent.target_position)
			return
		target_method_callable.call(Vector3.ZERO)
		return
	if on_link and global_position.distance_to(link_target) < nav_agent.path_desired_distance:
		on_link = false
	var pos_current: Vector3 = target_object.global_position
	var pos_next: Vector3 = link_target if on_link else nav_agent.get_next_path_position()
	var direction: Vector3 = pos_current.direction_to(pos_next)
	target_method_callable.call(direction, false)

func pause_navigation(value: bool = true) -> void:
	nav_paused = value

## Function called to set the target position
func set_target_position(target_pos: Vector3) -> void:
	if not nav_agent: return
	print(target_object.name + " received position " + str(target_pos))
	nav_paused = false
	check_doors()
	if nav_layer == 1:
		nav_layer = NavigationLayerManager.claim_layer()
		print(target_object.name + " has claimed the layer " + str(nav_layer))
	for door in accessible_doors:
		door.add_nav_layer(nav_layer)
	nav_agent.navigation_layers = 1 | nav_layer
	NavigationServer3D.map_force_update(get_world_3d().navigation_map)
	nav_agent.target_position = target_pos

func check_doors() -> void:
	accessible_doors.clear()
	if not get_tree().current_scene:
		return
	var doors: Array[Node] = get_tree().current_scene.find_children("*", "DoorComponent")
	for door in doors:
		door = door as DoorComponent
		if not door.key_whitelist.is_empty() or not door.key_blacklist.is_empty():
			if KeyManager.check_keys(door.key_whitelist, door.key_blacklist, target_object.private_keys + KeyManager._keys_stored):
				if not accessible_doors.has(door): accessible_doors.append(door)
	print(target_object.name + " has found a total of " + str(accessible_doors.size()) + " locked doors on it's way")

func _validate_property(property: Dictionary) -> void:
	if property.name == "target_method_string":
		var target_method_options: String = ""
		
		if target_object and target_object.get_script():
			var methods: Array = target_object.get_script().get_script_method_list()
			var method_names: Array[String] = []
			
			for method in methods:
				if not method["name"].begins_with("_"):
					method_names.append(method["name"])
					
			target_method_options = ",".join(method_names)
			
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = target_method_options
