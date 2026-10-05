class_name InputDialogueUI extends Control

@export var valid_entries: Dictionary[String, String]
@export var text_container: Control
@export var text_label: RichTextLabel
@export var input_field: LineEdit
@export var text_speed: float = 1
@export var pause_on_text: bool = false
var entry: ReadableEntry

func _ready() -> void:
	input_field.text_submitted.connect(_on_response_entered)

func display_dialogue(dialogue: ReadableEntry) -> void:
	entry = dialogue
	KeyManager.add_keys(["dialogue_open"])
	visible = true
	text_label.visible_ratio = 0
	text_label.text = dialogue.readable_text
	var text_tween: Tween = create_tween()
	text_tween.tween_property(text_label, "visible_ratio", 1, 1)

func _on_response_entered(value: String) -> void:
	if valid_entries.has(value):
		if entry.keys_unlocked.has(value):
			KeyManager.add_keys([valid_entries[value]])
	_close_ui()

func check_keys(readable: ReadableEntry) -> bool:
	if not KeyManager.search_keys(readable.key_whitelist):
		return false
	if KeyManager.search_keys(readable.key_blacklist) and not readable.key_blacklist.is_empty():
		return false
	return true

func _close_ui() -> void:
	KeyManager.remove_keys(["dialogue_open"])
	visible = false
	text_label.text = ""
	input_field.clear()
