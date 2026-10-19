## Filters ReadableEntry resources by active keys and priority, sending the highest priority entry to DialogueUI.
class_name ReadableComponent extends Node3D

signal readable_triggered(entry: ReadableEntry)

@export var entries: Array[ReadableEntry] = []
@export var look_turn_duration: float = 0.5
var _is_transitioning: bool = false
var _saved_npc_rotation_y: float = 0.0
var _was_npc_nav_paused: bool = true

var _dialogue_ui: DialogueUI = null

func _ready() -> void:
	_find_dialogue_ui.call_deferred()

## Evaluates available entries and opens the dialogue UI
func trigger() -> void:
	if _is_transitioning:
		return
	var readable_current: ReadableEntry = filter_entries()
	if not readable_current:
		return
	if not is_instance_valid(_dialogue_ui):
		_find_dialogue_ui()
	if not is_instance_valid(_dialogue_ui):
		return
		
	_is_transitioning = true
	var player := get_tree().get_first_node_in_group(&"player") as PlayerController
	var npc := _get_npc_controller()
	var npc_pathfinder := _get_npc_pathfinder(npc)
	
	var player_tween: Tween = null
	if player:
		player_tween = player.look_at_target(self, look_turn_duration)
	
	var look_target_pos: Vector3 = global_position
	var npc_tween: Tween = null
	if npc and player:
		var to_player: Vector3 = player.global_position - npc.global_position
		if Vector2(to_player.x, to_player.z).length_squared() > 0.0001:
			var start_yaw: float = npc.rotation.y
			var target_yaw: float = atan2(to_player.x, to_player.z)
			var yaw_delta: float = angle_difference(start_yaw, target_yaw)
			var offset_from_npc: Vector3 = global_position - npc.global_position
			look_target_pos = npc.global_position + offset_from_npc.rotated(Vector3.UP, yaw_delta)
		
		_saved_npc_rotation_y = npc.rotation.y
		if npc_pathfinder:
			_was_npc_nav_paused = npc_pathfinder.nav_paused
			npc_pathfinder.pause_navigation(true)
		
		if Vector2(to_player.x, to_player.z).length_squared() > 0.0001:
			var start_yaw: float = npc.rotation.y
			var target_yaw: float = atan2(to_player.x, to_player.z)
			npc_tween = create_tween()
			npc_tween.tween_method(
				func(w: float) -> void: npc.rotation.y = lerp_angle(start_yaw, target_yaw, w),
				0.0, 1.0, look_turn_duration
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	if player_tween:
		await player_tween.finished
	elif npc_tween:
		await npc_tween.finished
	
	_is_transitioning = false
	
	if is_instance_valid(_dialogue_ui):
		if npc and not _dialogue_ui.dialogue_closed.is_connected(_on_dialogue_closed):
			_dialogue_ui.dialogue_closed.connect(_on_dialogue_closed.bind(npc, npc_pathfinder), CONNECT_ONE_SHOT)
		_dialogue_ui.display_dialogue(readable_current)
		readable_triggered.emit(readable_current)

func _on_dialogue_closed(npc: CharacterController3D, npc_pathfinder: PathfindingComponent) -> void:
	if not is_instance_valid(npc):
		return
	var start_yaw: float = npc.rotation.y
	var restore_tween: Tween = create_tween()
	restore_tween.tween_method(
		func(w: float) -> void: npc.rotation.y = lerp_angle(start_yaw, _saved_npc_rotation_y, w),
		0.0, 1.0, look_turn_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	await restore_tween.finished
	if is_instance_valid(npc_pathfinder) and not _was_npc_nav_paused:
		npc_pathfinder.pause_navigation(false)

## Returns the highest-priority ReadableEntry whose key conditions are currently met
func filter_entries() -> ReadableEntry:
	var best_entry: ReadableEntry = null
	for readable: ReadableEntry in entries:
		if not readable:
			continue
		if KeyManager.check_keys(readable.key_whitelist, readable.key_blacklist):
			if best_entry == null or readable.priority > best_entry.priority:
				best_entry = readable
	return best_entry

func _find_dialogue_ui() -> void:
	_dialogue_ui = get_tree().get_first_node_in_group(&"dialogue_ui") as DialogueUI
	if not _dialogue_ui and get_tree().current_scene:
		_dialogue_ui = get_tree().current_scene.find_child("DialogueUI", true, false) as DialogueUI

func _get_npc_controller() -> CharacterController3D:
	var parent: Node = get_parent()
	if parent is CharacterController3D and not parent.is_in_group(&"player"):
		return parent as CharacterController3D
	if owner is CharacterController3D and not owner.is_in_group(&"player"):
		return owner as CharacterController3D
	return null

func _get_npc_pathfinder(npc: CharacterController3D) -> PathfindingComponent:
	if not npc:
		return null
	for child: Node in npc.find_children("*", "PathfindingComponent", true, false):
		if child is PathfindingComponent:
			return child as PathfindingComponent
	return null
