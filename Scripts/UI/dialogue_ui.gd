class_name DialogueUI extends Control

@export var text_container: Control
@export var text_label: RichTextLabel
@export var button_container: HBoxContainer
@export var input_field: LineEdit
@export var pause_on_dialogue: bool = true
var entry: ReadableEntry
var text_tween: Tween

func _ready() -> void:
	input_field.text_submitted.connect(_on_response_entered)

func display_dialogue(dialogue: ReadableEntry) -> void:
	KeyManager.add_keys(["dialogue_open"])
	if pause_on_dialogue:
		process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().paused = true
	for child in button_container.get_children():
		if child is Button:
			child.queue_free()
	KeyManager.add_keys(dialogue.keys_unlocked)
	KeyManager.remove_keys(dialogue.keys_taken)
	visible = true
	text_label.visible_ratio = 0
	text_label.text = dialogue.readable_text
	var reading_speed: float =  dialogue.readable_text.length() / dialogue.text_speed
	text_tween = create_tween()
	text_tween.tween_property(text_label, "visible_ratio", 1, reading_speed)
	if dialogue.has_input:
		entry = dialogue
		input_field.visible = true
	else:
		input_field.visible = false
	var response_button: Button
	if not dialogue.readable_chain.is_empty() and not dialogue.has_input:
		for response in dialogue.readable_chain:
			response_button = Button.new()
			response_button.text = response
			response_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var next_entry: ReadableEntry = dialogue.readable_chain[response]
			if not check_keys(next_entry):
				response_button.disabled = true
			if next_entry.readable_text.is_empty():
				continue
			response_button.pressed.connect(_on_response_pressed.bind(next_entry))
			button_container.add_child(response_button)
	response_button = Button.new()
	response_button.text = "..."
	response_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	response_button.pressed.connect(_close_ui)
	button_container.add_child(response_button)

func _on_response_entered(value: String) -> void:
	if text_tween.is_running():
		return
	if entry.readable_chain.has(value):
		display_dialogue(entry.readable_chain[value])
	else:
		display_dialogue(entry)

## Triggered when a dialogue choice with a chained entry is selected
func _on_response_pressed(next_entry: ReadableEntry) -> void:
	if text_tween.is_running():
		return
	# Pass the chained entry back into the display function
	display_dialogue(next_entry)

func check_keys(readable: ReadableEntry) -> bool:
	if not KeyManager.search_keys(readable.key_whitelist):
		return false
	if KeyManager.search_keys(readable.key_blacklist) and not readable.key_blacklist.is_empty():
		return false
	return true

## Triggered when the interaction has no chained entries
func _close_ui() -> void:
	KeyManager.remove_keys(["dialogue_open"])
	visible = false
	text_label.text = ""
	input_field.clear()
	for child in button_container.get_children():
		if child is Button:
			child.queue_free()
	if pause_on_dialogue:
		get_tree().paused = false
		process_mode = Node.PROCESS_MODE_INHERIT
