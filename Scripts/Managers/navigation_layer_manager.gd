## Static utility class that manages bitmask layers for NPC private door pathfinding.
class_name NavigationLayerManager extends RefCounted

const PUBLIC_LAYER: int = 1

const _ALL_PRIVATE_LAYERS: Array[int] = [
	2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768
]

static var _available_layers: Array[int] = _ALL_PRIVATE_LAYERS.duplicate()

## Claims an available navigation bitmask layer for an NPC
static func claim_layer() -> int:
	if _available_layers.is_empty():
		return PUBLIC_LAYER
	return _available_layers.pop_back()

## Releases a claimed navigation layer back into the pool
static func release_layer(layer: int) -> void:
	if layer != PUBLIC_LAYER and not _available_layers.has(layer):
		_available_layers.append(layer)

## Resets all layers back to available (called on loop/scene reset to prevent layer leaks)
static func reset_layers() -> void:
	_available_layers = _ALL_PRIVATE_LAYERS.duplicate()
