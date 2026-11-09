## Autoload Manager that handles loop resets, loop counting, and progressive world corruption.
extends Node

signal loop_reset_triggered(new_loop_count: int)
signal corruption_updated(corruption_factor: float)

@export_group("Loop Progression")
## Number of loops required to reach 100% (1.0) corruption intensity
@export var max_corruption_loops: int = 10

@export_group("Audio & Presentation")
## Optional sound played when the player dies / loop resets
@export var reset_audio_stream: AudioStream
var _audio_player: AudioStreamPlayer

var _loop_count: int = 0
var _is_resetting: bool = false
var _preloaded_scene_path: String = ""


func _ready() -> void:
	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_die"):
		trigger_loop_reset()


## Called by WorldGenerationManager once the world finishes generating and unpauses the game
func preload_current_loop_scene(scene_path: String = "") -> void:
	var target_path: String = scene_path
	if target_path.is_empty():
		var current_scene: Node = get_tree().current_scene
		if current_scene:
			target_path = current_scene.scene_file_path

	if target_path.is_empty() or not ResourceLoader.exists(target_path):
		return

	_preloaded_scene_path = target_path
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(target_path)
	if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS and status != ResourceLoader.THREAD_LOAD_LOADED:
		ResourceLoader.load_threaded_request(target_path, "PackedScene")


## Returns the total number of loops elapsed
func get_loop_count() -> int:
	return _loop_count


## Sets the loop count directly (used by SaveManager when loading a save)
func set_loop_count(count: int) -> void:
	_loop_count = maxi(count, 0)
	corruption_updated.emit(get_corruption_factor())


## Returns a normalized 0.0 to 1.0 value representing world corruption based on loop count
func get_corruption_factor() -> float:
	if max_corruption_loops <= 0:
		return 0.0
	return clampf(float(_loop_count) / float(max_corruption_loops), 0.0, 1.0)


## Resets the current loop, clearing non-persistent keys, saving progress, releasing nav layers, and warping to alarm time
func trigger_loop_reset() -> void:
	if _is_resetting:
		return
	_is_resetting = true
	_loop_count += 1

	if reset_audio_stream and _audio_player:
		_audio_player.stream = reset_audio_stream
		_audio_player.play()

	loop_reset_triggered.emit(_loop_count)
	corruption_updated.emit(get_corruption_factor())

	# Release all dynamically claimed navigation layers and reset non-persistent keys
	NavigationLayerManager.reset_layers()
	if KeyManager.has_method(&"reset_for_new_loop"):
		KeyManager.call(&"reset_for_new_loop")
	elif KeyManager.has_method(&"reset"):
		KeyManager.call(&"reset")

	# Save progress before switching the scene while UIController is still in the tree
	if SaveManager.has_method(&"save_data"):
		SaveManager.call(&"save_data")
	elif SaveManager.has_method(&"save_game"):
		SaveManager.call(&"save_game")

	_reload_with_preloaded_scene()

	# Wait for the scene tree to finish switching scenes before warping time
	await get_tree().process_frame
	await get_tree().process_frame

	TimeManager.force_time(TimeManager.get_day_start())
	await TimeManager.warp_time_until(TimeManager.get_day_start_current())
	_is_resetting = false


func _reload_with_preloaded_scene() -> void:
	var target_path: String = _preloaded_scene_path
	if target_path.is_empty() and get_tree().current_scene:
		target_path = get_tree().current_scene.scene_file_path

	var packed_scene: PackedScene = null
	if not target_path.is_empty():
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(target_path)
		if status == ResourceLoader.THREAD_LOAD_LOADED or status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			packed_scene = ResourceLoader.load_threaded_get(target_path) as PackedScene

	if packed_scene:
		get_tree().call_deferred(&"change_scene_to_packed", packed_scene)
	else:
		get_tree().call_deferred(&"reload_current_scene")
