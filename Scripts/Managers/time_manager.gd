extends Node

var _time_current: int = 0
var _time_scale: float = 600
var _time_passed: float = 0

var _day_start: int = 360
var _day_start_current: int
var _day_end: int = 1440

func _ready() -> void:
	_day_start_current = _day_start
	force_time(_day_start)

func _process(delta: float) -> void:
	_time_pass(delta)

func get_current_time() -> int:
	return _time_current

func _time_pass(delta: float) -> void:
	_time_passed += delta / 60
	_time_current = floori(_time_passed * _time_scale)
	if _time_current >= _day_end:
		LoopManager.trigger_loop_reset()
	if get_tree().current_scene:
		var sun: DirectionalLight3D = get_tree().current_scene.find_children("*", "DirectionalLight3D")[0]
		if sun:
			sun.rotation.x = deg_to_rad((float(_time_current) * 0.25) + 90)

func force_time(time: int) -> void:
	if _day_start <= time and time <= _day_end:
		_time_passed = time / _time_scale

func set_day_start(time: int) -> void:
	if _day_start <= time and time <= _day_end:
		_day_start_current = time

func time_as_string(time: int) -> String:
	var hours: int = time / 60
	var hours_string: String = "0" + str(hours) if hours < 10 else str(hours)
	var minutes: int = time % 60
	var minutes_string: String = "0" + str(minutes) if minutes < 10 else str(minutes)
	return str(hours_string) + ":" + str(minutes_string)

func time_as_vector(time: int) -> Vector2i:
	var hours: int = time / 60
	var minutes: int = time % 60
	return Vector2i(hours, minutes)

func time_from_vector(time: Vector2i) -> int:
	return time.x * 60 + time.y
