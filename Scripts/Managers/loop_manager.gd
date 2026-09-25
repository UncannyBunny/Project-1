extends Node

var _loop_count: int = 0

func get_loop_count() -> int:
	return _loop_count

func trigger_loop_reset() -> void:
	_loop_count += 1
	get_tree().reload_current_scene()
