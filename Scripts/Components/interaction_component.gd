## Area3D target for player raycast interactions. Emits a signal and optionally triggers linked components.
class_name InteractionComponent extends Area3D

signal interacted

@export_group("Direct Component Links")
## Optional node to call .trigger() on when interacted with (e.g., DoorComponent, ReadableComponent, KeyComponent)
@export var target_object: Node

@export_group("UI & Audio Hooks")
## Optional prompt text to display when the player hovers over this interactable
@export var interaction_prompt: String = "Interact"
@export var audio_player: AudioStreamPlayer3D
@export var interaction_sound: AudioStream

## Called by PlayerController when the player presses interact while looking at this Area3D
func trigger_interaction() -> void:
	if audio_player and interaction_sound:
		audio_player.stream = interaction_sound
		audio_player.play()
		
	if target_object and target_object.has_method(&"trigger"):
		target_object.call(&"trigger")
		
	interacted.emit()
