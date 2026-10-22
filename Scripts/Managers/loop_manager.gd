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

func _ready() -> void:
	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_die"):
		trigger_loop_reset()

## Returns the total number of loops elapsed
func get_loop_count() -> int:
	return _loop_count

## Sets the loop count directly
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
	
	NavigationLayerManager.reset_layers()
	KeyManager.reset()
	
	SaveManager.save_data()
	
	get_tree().call_deferred(&"reload_current_scene")
	
	await get_tree().process_frame
	await get_tree().process_frame
	
	TimeManager.force_time(TimeManager.get_day_start())
	await TimeManager.warp_time_until(TimeManager.get_day_start_current())
	_is_resetting = false
