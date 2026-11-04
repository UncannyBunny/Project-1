@tool
## Root controller for light poles that combines CableConnectorComponent baking with SpotLight3D scheduling and flickering.
class_name LightPoleController extends CableConnectorComponent

@export_group("Streetlight")
## The SpotLight3D child node controlled by this pole (auto-detected if left empty)
@export var spot_light: SpotLight3D
@export var off_time: Vector2i = Vector2i(7, 0)
@export var on_time: Vector2i = Vector2i(18, 0)

@export_group("Flicker")
@export var flicker: bool = false
@export var flicker_min: int = 10
@export var flicker_avg: int = 20

var default_energy: float = 1.0
var time_to_flicker: int = 0

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
		
	if not is_instance_valid(spot_light):
		spot_light = get_node_or_null("SpotLight3D") as SpotLight3D
		
	if is_instance_valid(spot_light):
		default_energy = spot_light.light_energy
		
	TimeManager.time_changed.connect(_time_changed)
	_time_changed.call_deferred(TimeManager.get_current_time())

func _time_changed(time: int) -> void:
	if not is_instance_valid(spot_light):
		return
		
	var off_minutes: int = TimeManager.time_from_vector(off_time)
	var on_minutes: int = TimeManager.time_from_vector(on_time)
	
	if time > off_minutes and time < on_minutes:
		spot_light.light_energy = 0.0
	else:
		if flicker and time >= time_to_flicker:
			time_to_flicker = time + randi_range(flicker_min, flicker_avg + flicker_min)
			var tween: Tween = create_tween()
			for i: int in range(randi_range(2, 6)):
				var flicker_time: float = randf_range(0.05, 0.1)
				tween.tween_property(spot_light, "light_energy", default_energy, flicker_time)
				tween.tween_property(spot_light, "light_energy", 0.0, flicker_time)
			tween.tween_property(spot_light, "light_energy", default_energy, 0.1)
		elif not flicker:
			spot_light.light_energy = default_energy
