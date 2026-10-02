class_name DialogueUI extends Control

@export var text_container: Control
@export var text_label: RichTextLabel
@export var button_container: HBoxContainer
@export var text_speed: float = 1
@export var pause_on_text: bool = false

func display_dialogue(dialogue: ReadableEntry) -> void:
	KeyManager.add_keys(["dialogue_open"])
	for child in button_container.get_children():
		child.queue_free()
	KeyManager.add_keys(dialogue.keys_unlocked)
	KeyManager.remove_keys(dialogue.keys_taken)
	visible = true
	text_label.visible_ratio = 0
	text_label.text = dialogue.readable_text
	var text_tween: Tween = create_tween()
	text_tween.tween_property(text_label, "visible_ratio", 1, 1)
	if not dialogue.readable_chain.is_empty():
		for response in dialogue.readable_chain:
			var response_button: Button = Button.new()
			response_button.text = response
			response_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var next_entry: ReadableEntry = dialogue.readable_chain[response]
			if not KeyManager.search_keys(next_entry.keys_required):
				response_button.disabled = true
			if next_entry.readable_text.is_empty():
				continue
			response_button.pressed.connect(_on_response_pressed.bind(next_entry))
			button_container.add_child(response_button)
	var response_button: Button = Button.new()
	response_button.text = "..."
	response_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	response_button.pressed.connect(_close_ui)
	button_container.add_child(response_button)

## Triggered when a dialogue choice with a chained entry is selected
func _on_response_pressed(next_entry: ReadableEntry) -> void:
	# Pass the chained entry back into the display function
	display_dialogue(next_entry)

## Triggered when the interaction has no chained entries
func _close_ui() -> void:
	KeyManager.remove_keys(["dialogue_open"])
	visible = false
	text_label.text = ""
	for child in button_container.get_children():
		child.queue_free()
