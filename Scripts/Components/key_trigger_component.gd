## Monitors KeyManager and triggers a target node or signal whenever key conditions are met.
class_name KeyTriggerComponent extends Node3D

signal triggered

@export_group("Key Conditions")
@export var key_whitelist: Array[StringName] = []
@export var key_blacklist: Array[StringName] = []
## If true, triggers only once per loop
@export var one_shot: bool = false

@export_group("Target")
## Optional node to call .trigger() on when conditions are met
@export var target_object: Node

var _has_triggered: bool = false

func _ready() -> void:
	KeyManager.keys_changed.connect(_on_keys_changed)
	_on_keys_changed.call_deferred()

func _on_keys_changed() -> void:
	if one_shot and _has_triggered:
		return
	if KeyManager.check_keys(key_whitelist, key_blacklist):
		_has_triggered = true
		if target_object and target_object.has_method(&"trigger"):
			target_object.call(&"trigger")
		triggered.emit()
