## Autoload Manager that controls the in-game clock, sun rotation, and time-warping.
extends Node

signal time_changed(current_time_minutes: int)
signal time_warping_started
signal time_warping_finished

@export_group("UI")
@export var loading_screen: Control

@export_group("Time Settings")
## Multiplier for how fast in-game minutes pass relative to real seconds (60 = 1 in-game minute per real second)
@export var time_scale: float = 60.0
## Default start time of the loop in minutes from midnight (360 = 06:00)
@export var day_start: int = 360
## End time of the loop in minutes from midnight (1440 = 24:00)
@export var day_end: int = 1440

var _time_current: int = 0
var _time_passed: float = 0.0
var _day_start_current: int = 360
var _is_warping: bool = false
var _cached_sun: DirectionalLight3D = null

func _ready() -> void:
	_day_start_current = day_start
	force_time(day_start)
	get_tree().node_added.connect(_on_node_added)
	_find_sun_in_scene.call_deferred()

func _process(delta: float) -> void:
	_time_pass(delta)

#region Time Progression
func _time_pass(delta: float) -> void:
	_time_passed += delta / 60.0
	var time_calc: int = floori(_time_passed * time_scale)
	
	if _time_current != time_calc:
		_time_current = time_calc
		time_changed.emit(_time_current)
		
	if _time_current >= day_end:
		LoopManager.trigger_loop_reset()
		return
		
	_update_sun_rotation()

func _update_sun_rotation() -> void:
	if not is_instance_valid(_cached_sun):
		return
	var current_minutes_float: float = _time_passed * time_scale
	_cached_sun.rotation.x = deg_to_rad((current_minutes_float * 0.25) + 90.0)

func _on_node_added(node: Node) -> void:
	if node is DirectionalLight3D and not node.editor_only:
		if node.is_in_group(&"sun") or not is_instance_valid(_cached_sun):
			_cached_sun = node

func _find_sun_in_scene() -> void:
	if not get_tree().current_scene:
		return
	var suns: Array[Node] = get_tree().get_nodes_in_group(&"sun")
	if not suns.is_empty() and suns[0] is DirectionalLight3D:
		_cached_sun = suns[0] as DirectionalLight3D
		return
	var lights: Array[Node] = get_tree().current_scene.find_children("*", "DirectionalLight3D")
	for light: Node in lights:
		if light is DirectionalLight3D and not light.editor_only:
			_cached_sun = light
			return
#endregion

#region Getters & Setters
func get_current_time() -> int:
	return _time_current

func get_day_start() -> int:
	return day_start

func get_day_start_current() -> int:
	return _day_start_current

func get_day_end() -> int:
	return day_end

func is_warping() -> bool:
	return _is_warping

func force_time(time_minutes: int) -> void:
	if day_start <= time_minutes and time_minutes <= day_end:
		_time_passed = float(time_minutes) / time_scale
		_time_current = time_minutes
		time_changed.emit(_time_current)

func set_day_start(time_minutes: int) -> void:
	if day_start <= time_minutes and time_minutes <= day_end:
		_day_start_current = time_minutes
#endregion

var time_warp_key: Array[StringName] = [&"time_warp"]
#region Time Warping
func warp_time_until(target_time_minutes: int) -> void:
	if target_time_minutes <= _time_current:
		return
	_is_warping = true
	time_warping_started.emit()
	if loading_screen:
		loading_screen.visible = true
	KeyManager.add_keys(time_warp_key)
	
	var base_time_scale: float = Engine.time_scale
	var base_physics_ticks: int = Engine.physics_ticks_per_second
	Engine.time_scale = base_time_scale * 32.0
	Engine.physics_ticks_per_second = base_physics_ticks * 8
	
	while get_current_time() < target_time_minutes:
		await get_tree().physics_frame
		
	Engine.time_scale = base_time_scale
	Engine.physics_ticks_per_second = base_physics_ticks
	KeyManager.remove_keys(time_warp_key)
	if loading_screen:
		loading_screen.visible = false
	_is_warping = false
	time_warping_finished.emit()
#endregion

#region Static Formatting Helpers
static func time_as_string(time_minutes: int) -> String:
	var hours: int = time_minutes / 60
	var minutes: int = time_minutes % 60
	return "%02d:%02d" % [hours, minutes]

static func time_as_vector(time_minutes: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(time_minutes / 60, time_minutes % 60)

static func time_from_vector(time_vec: Vector2i) -> int:
	return time_vec.x * 60 + time_vec.y
#endregion
