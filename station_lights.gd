extends Node3D

@export var lights: Array[SpotLight3D]

func _process(delta: float) -> void:
	if KeyManager.search_keys(["store_open"]):
		for light in lights:
			light.light_energy = 1
	else:
		for light in lights:
			light.light_energy = 0
