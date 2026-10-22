## Triggers a signal or target node when matching bodies enter or exit the Area3D.
class_name AreaTriggerComponent extends Area3D

signal triggered(body: Node3D)
signal body_entered_valid(body: Node3D)
signal body_exited_valid(body: Node3D)

@export_group("Trigger Conditions")
@export var trigger_on_enter: bool = true
@export var trigger_on_exit: bool = false
## If true, triggers only when the first valid body enters or the last valid body exits
@export var check_occupied: bool = false
## If true, only triggers for nodes in the "player" group (ignores trigger_objects dictionary if enabled)
@export var player_only: bool = false
## Filter dictionary of "name_pattern": &"ClassName" (e.g., "*": &"CharacterController3D")
@export var trigger_objects: Dictionary[String, StringName] = {}

@export_group("Target")
## Optional node to call .trigger() on when activated
@export var target_object: Node

var valid_bodies: Array[Node3D] = []

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if not validate_body(body):
		return
	body_entered_valid.emit(body)
	if not trigger_on_enter:
		if check_occupied and not valid_bodies.has(body):
			valid_bodies.append(body)
		return
		
	if check_occupied:
		var was_empty: bool = valid_bodies.is_empty()
		if not valid_bodies.has(body):
			valid_bodies.append(body)
		if was_empty:
			_execute_trigger(body)
	else:
		_execute_trigger(body)

func _on_body_exited(body: Node3D) -> void:
	if not validate_body(body):
		return
	body_exited_valid.emit(body)
	if check_occupied:
		valid_bodies.erase(body)
		if trigger_on_exit and valid_bodies.is_empty():
			_execute_trigger(body)
	elif trigger_on_exit:
		_execute_trigger(body)

func _execute_trigger(body: Node3D) -> void:
	if target_object and target_object.has_method(&"trigger"):
		target_object.call(&"trigger")
	triggered.emit(body)

func validate_body(body: Node3D) -> bool:
	if player_only:
		return body.is_in_group(&"player")
	if trigger_objects.is_empty():
		return true
	for pattern: String in trigger_objects:
		var type: StringName = trigger_objects[pattern]
		var script: Script = body.get_script()
		if script and script.get_global_name() == type and body.name.matchn(pattern):
			return true
		elif body.is_class(type) and body.name.matchn(pattern):
			return true
	return false
