extends Node

var _time_current: int = 0
var _time_scale: float = 60
var _time_passed: float = 0

func get_current_time() -> int:
	return _time_current

func _process(delta: float) -> void:
	_time_pass(delta)

func _time_pass(delta: float) -> void:
	var _time_prev: int = _time_current
	_time_passed += delta / 60
	_time_current = _time_passed * _time_scale
