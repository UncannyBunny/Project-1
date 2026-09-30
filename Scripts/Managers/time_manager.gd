extends Node

var _time_current: int = 0
var _time_scale: float = 600
var _time_passed: float = 0

var _day_start: int = 360
var _day_end: int = 1440

func _process(delta: float) -> void:
	_time_pass(delta)

func get_current_time() -> int:
	return _time_current

func _time_pass(delta: float) -> void:
	_time_passed += delta / 60
	_time_current = floori(_time_passed * _time_scale)
	if _time_current < _day_start:
		_time_passed = _day_start / _time_scale
	if _time_current >= _day_end:
		_time_passed = 0
		_time_current = 0
		LoopManager.trigger_loop_reset()
	var sun: DirectionalLight3D = get_tree().current_scene.find_children("*", "DirectionalLight3D")[0]
	if sun:
		sun.rotation.x = deg_to_rad((float(_time_current) * 0.25) + 90)

func force_time(time: int) -> void:
	if _day_start <= time and time <= _day_end:
		_time_passed = time / _time_scale
