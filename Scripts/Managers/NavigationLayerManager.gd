class_name NavigationLayerManager extends Node3D

static var _available_layers: Array[int] = [
	2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768
]

static func claim_layer() -> int:
	if _available_layers.is_empty():
		return 1 # Fallback to public layer if over 30 NPCs move at the exact same time
	return _available_layers.pop_back()

static func release_layer(layer: int) -> void:
	if layer != 1 and not _available_layers.has(layer):
		_available_layers.append(layer)
