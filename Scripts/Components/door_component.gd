## Animatable door that supports key locks, NavigationLink3D layers, and automatic NPC opening/closing.
class_name DoorComponent extends AnimatableBody3D

signal door_toggled(is_open: bool)
signal door_locked_attempt
signal door_finished_moving(is_open: bool)

@export_group("Animation Properties")
## Property path to tween (e.g., "rotation:y" or "position:x")
@export var property: String = "rotation:y":
	set(val):
		property = val
		property_path = NodePath(val)
var property_path: NodePath = ^"rotation:y"
## Offset added to the initial property value when opened
@export var open_value_offset: float = 1.5708
## Duration in seconds for the door to open or close
@export var animation_time: float = 0.5

@export_group("Lock Settings")
## Keys required to unlock and open this door
@export var key_whitelist: Array[StringName] = []
## Keys that lock this door if active
@export var key_blacklist: Array[StringName] = []

@export_group("Navigation & NPC Detection")
## Optional NavigationLink3D used by NPCs to pathfind through the doorway
@export var navlink: NavigationLink3D
## Optional Area3D to automatically open/close the door for approaching NPCs
@export var npc_detection_area: Area3D
## If true, NPCs entering npc_detection_area will automatically open and close the door
@export var auto_toggle_for_npcs: bool = true

@export_group("Audio Hooks")
@export var audio_player: AudioStreamPlayer3D
@export var open_sound: AudioStream
@export var close_sound: AudioStream
@export var locked_sound: AudioStream

var value_initial: float = 0.0
var is_open: bool = false
var is_locked: bool = false
var door_tween: Tween
var _valid_npcs_in_area: Array[CharacterController3D] = []

func _ready() -> void:
	add_to_group(&"doors")
	property_path = NodePath(property)
	value_initial = get_indexed(property_path)
	
	if not navlink:
		navlink = get_node_or_null("NavigationLink3D") as NavigationLink3D
	navlink.top_level = true
	if not npc_detection_area:
		npc_detection_area = get_node_or_null("Area3D") as Area3D
	npc_detection_area.top_level = true
		
	if not key_whitelist.is_empty() or not key_blacklist.is_empty():
		if navlink:
			navlink.navigation_layers &= ~NavigationLayerManager.PUBLIC_LAYER
			
	if npc_detection_area:
		npc_detection_area.body_entered.connect(_on_npc_area_entered)
		npc_detection_area.body_exited.connect(_on_npc_area_exited)
		
	KeyManager.keys_changed.connect(_on_keys_changed)
	_on_keys_changed()

func trigger_interaction() -> void:
	trigger()

## Attempts to toggle the door using global keys plus any provided private keys
func trigger(private_keys: Array[StringName] = []) -> void:
	if not private_keys.is_empty() and check_lock(private_keys):
		toggle()
		return
	if is_locked and not is_open:
		_play_sound(locked_sound)
		door_locked_attempt.emit()
		return
	toggle()

## Returns true if the combined private_keys and global keys satisfy the door's lock
func check_lock(private_keys: Array[StringName] = []) -> bool:
	var all_keys: Array[StringName] = private_keys + KeyManager.get_active_keys()
	return KeyManager.check_keys(key_whitelist, key_blacklist, all_keys)

func _on_keys_changed() -> void:
	is_locked = not KeyManager.check_keys(key_whitelist, key_blacklist)
	if navlink:
		if is_locked:
			navlink.navigation_layers &= ~NavigationLayerManager.PUBLIC_LAYER
		else:
			navlink.navigation_layers |= NavigationLayerManager.PUBLIC_LAYER

## Opens or closes the door via Tween
func toggle() -> void:
	is_open = not is_open
	_play_sound(open_sound if is_open else close_sound)
	door_toggled.emit(is_open)
	
	var time_current: float = animation_time
	var value_target: float = value_initial + open_value_offset if is_open else value_initial
	
	if door_tween and door_tween.is_running():
		var speed: float = absf(open_value_offset) / maxf(animation_time, 0.001)
		var distance: float = absf(value_target - float(get_indexed(property_path)))
		time_current = distance / maxf(speed, 0.001)
		door_tween.kill()
		
	door_tween = create_tween()
	door_tween.tween_property(self, property_path, value_target, time_current)
	door_tween.finished.connect(func() -> void: door_finished_moving.emit(is_open))

#region Navigation Layer Helpers
func add_nav_layer(layer: int) -> void:
	if navlink:
		navlink.navigation_layers |= layer

func remove_nav_layer(layer: int) -> void:
	if navlink:
		navlink.navigation_layers &= ~layer
#endregion

#region Automatic NPC Door Handling
func _on_npc_area_entered(body: Node3D) -> void:
	var npc := body as CharacterController3D
	if not npc or npc.is_in_group(&"player"):
		return
	var pathfinder := _get_npc_pathfinder(npc)
	if not pathfinder:
		return
		
	if not _valid_npcs_in_area.has(npc):
		_valid_npcs_in_area.append(npc)
	if not is_open and check_lock(npc.private_keys):
		if auto_toggle_for_npcs:
			trigger(npc.private_keys)
		await get_tree().physics_frame
	
	if door_tween and door_tween.is_running() and check_lock(npc.private_keys):
		pathfinder.pause_navigation(true)
		add_collision_exception_with(npc)
		await door_tween.finished
		
	if is_instance_valid(pathfinder) and is_instance_valid(npc):
		pathfinder.pause_navigation(false)
		remove_collision_exception_with(npc)

func _on_npc_area_exited(body: Node3D) -> void:
	var npc := body as CharacterController3D
	if not npc or not _valid_npcs_in_area.has(npc):
		return
	_valid_npcs_in_area.erase(npc)
	if _valid_npcs_in_area.is_empty() and is_open and auto_toggle_for_npcs:
		trigger()

func _get_npc_pathfinder(npc: CharacterController3D) -> PathfindingComponent:
	for child: Node in npc.find_children("*", "PathfindingComponent", true, false):
		if child is PathfindingComponent:
			return child as PathfindingComponent
	return null
#endregion

func _play_sound(stream: AudioStream) -> void:
	if audio_player and stream:
		audio_player.stream = stream
		audio_player.play()
