extends Node

var _loop_count: int = 0

func get_loop_count() -> int:
	return _loop_count

func trigger_loop_reset() -> void:
	_loop_count += 1
	KeyManager.remove_all_keys()
	TimeManager.force_time(TimeManager._day_start_current)
	get_tree().call_deferred("reload_current_scene")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_die"):
		trigger_loop_reset()
