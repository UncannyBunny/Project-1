extends DirectionalLight3D

@export var environment: WorldEnvironment
@export var rotation_speed: float = 0.5
@export var sun_color_curve: Gradient
@export var max_energy: float = 1.0

func _process(delta: float) -> void:
	rotate_x(deg_to_rad(rotation_speed * delta))
	var light_dir: Vector3 = global_transform.basis.z
	var sun_altitude: float = light_dir.dot(Vector3.UP)
	var gradient_position: float = clampf(sun_altitude, 0.0, 1.0)
	if sun_color_curve:
		light_color = sun_color_curve.sample(gradient_position)
	light_energy = max_energy * smoothstep(0.0, 0.15, sun_altitude)
