## Area3D target for player raycast interactions. Emits a signal, provides hover UI text, and triggers linked components.
class_name InteractionComponent extends Area3D

signal interacted

const _DEFAULT_NODE_PREFIXES: Array[String] = [
	"InteractionComponent",
	"Area3D"
]

@export_group("Direct Component Links")
## Optional node to call .trigger() on when interacted with (e.g., DoorComponent, ReadableComponent, KeyComponent)
@export var target_object: Node

@export_group("UI & Audio Hooks")
## Action verb displayed when hovering (e.g., "interact", "open", "read", "chat") -> "<NodeName>: Click to <interaction_prompt>"
@export var interaction_prompt: String = "interact"
@export var audio_player: AudioStreamPlayer3D
@export var interaction_sound: AudioStream

## Called by PlayerController when the player presses interact while looking at this Area3D. Returns true if interaction succeeded.
func trigger_interaction() -> bool:
	var succeeded: bool = true
	if target_object and target_object.has_method(&"trigger"):
		var result: Variant = target_object.call(&"trigger")
		if result is bool:
			succeeded = result
			
	if not succeeded:
		return false
		
	if audio_player and interaction_sound:
		audio_player.stream = interaction_sound
		audio_player.play()
		
	interacted.emit()
	return true

## Returns "<NodeName>: Click to <action>" ONLY if this node's name is not a default node name; otherwise returns "".
func get_hover_display_text() -> String:
	if _is_default_node_name(name):
		return ""
	var action_verb: String = interaction_prompt.strip_edges()
	if action_verb.is_empty():
		action_verb = "interact"
	return "%s: Click to %s" % [String(name), action_verb]

static func _is_default_node_name(node_name: String) -> bool:
	var clean: String = node_name.strip_edges()
	if clean.is_empty():
		return true
	for prefix: String in _DEFAULT_NODE_PREFIXES:
		if clean.begins_with(prefix):
			var suffix: String = clean.substr(prefix.length())
			if suffix.is_empty() or suffix.is_valid_int():
				return true
	return false
