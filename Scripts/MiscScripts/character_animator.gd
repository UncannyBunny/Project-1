extends Node3D

@export var character: CharacterController3D
@export var animator: AnimationPlayer

func _ready() -> void:
	character.movement_state_changed.connect(movement_state)
	animator.play("Idle", 0)

func movement_state(is_moving: bool, is_running: bool) -> void:
	if not is_moving:
		animator.play("Idle")
	if is_moving and not is_running:
		animator.play("Walk")
	if is_running:
		animator.play("Run")
