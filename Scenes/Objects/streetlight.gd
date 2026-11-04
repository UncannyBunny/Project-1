class_name Streetlight extends SpotLight3D

@export_group("Light")
@export var off_time: Vector2 = Vector2(6, 0)
@export var on_time: Vector2 = Vector2(18, 0)
var default_energy: float
@export_group("Flicker")
@export var flicker: bool = false
@export var flicker_min: int = 10
@export var flicker_avg: int = 20
var time_to_flicker: float = 0

func _ready() -> void:
	default_energy = light_energy
	TimeManager.time_changed.connect(_time_changed)

func _time_changed(time: int) -> void:
	if time > TimeManager.time_from_vector(off_time) and time < TimeManager.time_from_vector(on_time):
		light_energy = 0
	else:
		if flicker and time >= time_to_flicker:
			time_to_flicker = time + randi_range(flicker_min, flicker_avg + flicker_min)
			var tween: Tween = create_tween()
			for i in range(randi_range(2, 6)):
				var flicker_time: float = randf_range(0.05, 0.1)
				tween.tween_property(self, "light_energy", default_energy, flicker_time)
				tween.tween_property(self, "light_energy", 0, flicker_time)
			tween.tween_property(self, "light_energy", default_energy, 0.1)
		elif time < time_to_flicker:
			pass 
		else:
			light_energy = default_energy
