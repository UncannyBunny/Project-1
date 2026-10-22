## Manages branching dialogue display, text input, and the 4-digit keypad interface.
class_name DialogueUI extends Control

signal dialogue_opened(entry: ReadableEntry)
signal dialogue_closed

const KEYPAD_MAX_DIGITS: int = 4

@export_group("Dialogue Containers")
## Root container for standard text/button dialogue (hidden when Keypad is active)
@export var text_container: Control
@export var text_label: RichTextLabel
@export var button_container: HBoxContainer
@export var input_field: LineEdit
@export var pause_on_dialogue: bool = true

@export_group("Keypad UI")
## Root container for the keypad UI (shown only when entry.input_type == KEYPAD)
@export var keypad_container: Control
## Label displaying the 4-digit code (e.g., "12__", "XXXX")
@export var keypad_display_label: RichTextLabel
## Container holding buttons named "0"-"9", "Enter", and "Exit" (or assign explicitly below)
@export var keypad_buttons_container: Control
@export var keypad_enter_button: Button
@export var keypad_exit_button: Button
@export var keypad_error_duration: float = 0.6

var current_entry: ReadableEntry = null
var text_tween: Tween
var _keypad_input: String = ""
var _keypad_locked: bool = false

func _ready() -> void:
	add_to_group(&"dialogue_ui")
	visible = false
	if input_field:
		input_field.text_submitted.connect(_on_response_entered)
	_setup_keypad_buttons()

func display_dialogue(dialogue: ReadableEntry) -> void:
	if not dialogue:
		return
	current_entry = dialogue
	KeyManager.add_keys([&"dialogue_open"])
	
	if pause_on_dialogue:
		process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().paused = true
		
	_clear_choice_buttons()
	if not dialogue.keys_unlocked.is_empty():
		KeyManager.add_keys(dialogue.keys_unlocked)
	if not dialogue.keys_taken.is_empty():
		KeyManager.remove_keys(dialogue.keys_taken)
		
	visible = true
	if text_tween and text_tween.is_running():
		text_tween.kill()
		
	# Only animate text if we are not in Keypad mode
	if dialogue.input_type != ReadableEntry.InputType.KEYPAD and text_label:
		text_label.visible_ratio = 0.0
		text_label.text = dialogue.readable_text
		var speed: float = maxf(dialogue.text_speed, 1.0)
		var reading_duration: float = float(dialogue.readable_text.length()) / speed
		text_tween = create_tween()
		text_tween.tween_property(text_label, ^"visible_ratio", 1.0, reading_duration)
		
	_configure_input_mode(dialogue)
	dialogue_opened.emit(dialogue)

func _configure_input_mode(dialogue: ReadableEntry) -> void:
	var is_keypad: bool = (dialogue.input_type == ReadableEntry.InputType.KEYPAD)
	
	if text_container:
		text_container.visible = not is_keypad
	if keypad_container:
		keypad_container.visible = is_keypad
		if is_keypad:
			_reset_keypad()
			
	if input_field:
		input_field.visible = (dialogue.input_type == ReadableEntry.InputType.TEXT)
		if input_field.visible:
			input_field.clear()
			input_field.grab_focus()
			
	if button_container:
		button_container.visible = (dialogue.input_type == ReadableEntry.InputType.BUTTONS)
		if dialogue.input_type == ReadableEntry.InputType.BUTTONS:
			_populate_choice_buttons(dialogue)
		elif dialogue.input_type == ReadableEntry.InputType.TEXT:
			_add_close_button()

#region Choice Buttons & LineEdit Input
func _populate_choice_buttons(dialogue: ReadableEntry) -> void:
	for response_text: String in dialogue.readable_chain:
		var next_entry: ReadableEntry = dialogue.readable_chain[response_text]
		if not next_entry or (next_entry.input_type != ReadableEntry.InputType.KEYPAD and next_entry.readable_text.is_empty()):
			continue
		var response_button := Button.new()
		response_button.text = response_text
		response_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not KeyManager.check_keys(next_entry.key_whitelist, next_entry.key_blacklist):
			response_button.disabled = true
		response_button.pressed.connect(_on_response_pressed.bind(next_entry))
		button_container.add_child(response_button)
	_add_close_button()

func _add_close_button() -> void:
	var close_button := Button.new()
	close_button.text = "..."
	close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_button.pressed.connect(_close_ui)
	button_container.add_child(close_button)

func _clear_choice_buttons() -> void:
	if not button_container:
		return
	for child: Node in button_container.get_children():
		if child is Button:
			child.queue_free()

func _on_response_entered(value: String) -> void:
	if _skip_text_animation_if_running():
		return
	if current_entry and current_entry.readable_chain.has(value):
		var next_entry: ReadableEntry = current_entry.readable_chain[value]
		if next_entry and KeyManager.check_keys(next_entry.key_whitelist, next_entry.key_blacklist):
			display_dialogue(next_entry)
			return
	if current_entry:
		display_dialogue(current_entry)

func _on_response_pressed(next_entry: ReadableEntry) -> void:
	if _skip_text_animation_if_running():
		return
	display_dialogue(next_entry)
#endregion

#region Keypad Logic
func _setup_keypad_buttons() -> void:
	if keypad_enter_button:
		keypad_enter_button.pressed.connect(_on_keypad_enter_pressed)
	if keypad_exit_button:
		keypad_exit_button.pressed.connect(func() -> void: _close_ui(true))
		
	if not keypad_buttons_container:
		return
	for child: Node in keypad_buttons_container.find_children("*", "Button", true, false):
		var btn := child as Button
		var btn_text: String = btn.name.strip_edges()
		if btn_text.length() == 1 and btn_text.is_valid_int():
			btn.pressed.connect(_on_keypad_digit_pressed.bind(btn_text))
		elif btn != keypad_enter_button and btn_text.to_lower() == "enter":
			btn.pressed.connect(_on_keypad_enter_pressed)
		elif btn != keypad_exit_button and btn_text.to_lower() == "exit":
			btn.pressed.connect(func() -> void: _close_ui(true))

func _reset_keypad() -> void:
	_keypad_input = ""
	_keypad_locked = false
	_update_keypad_display()

func _update_keypad_display() -> void:
	if not keypad_display_label:
		return
	var remaining: int = KEYPAD_MAX_DIGITS - _keypad_input.length()
	keypad_display_label.text = _keypad_input + "_".repeat(maxi(remaining, 0))

func _on_keypad_digit_pressed(digit: String) -> void:
	if _keypad_locked or _keypad_input.length() >= KEYPAD_MAX_DIGITS:
		return
	_keypad_input += digit
	_update_keypad_display()
	
	# If 4 digits are reached and it doesn't match a valid entry, flash XXXX and reset
	if _keypad_input.length() == KEYPAD_MAX_DIGITS:
		if not _is_keypad_code_valid(_keypad_input):
			_flash_keypad_error()

func _on_keypad_enter_pressed() -> void:
	if _keypad_locked:
		return
	if _is_keypad_code_valid(_keypad_input):
		var next_entry: ReadableEntry = current_entry.readable_chain[_keypad_input]
		# If the unlocked target entry has no text (e.g., just unlocks a door key), apply keys and close!
		if next_entry.input_type != ReadableEntry.InputType.KEYPAD and next_entry.readable_text.is_empty():
			if not next_entry.keys_unlocked.is_empty():
				KeyManager.add_keys(next_entry.keys_unlocked)
			if not next_entry.keys_taken.is_empty():
				KeyManager.remove_keys(next_entry.keys_taken)
			_close_ui(true)
		else:
			display_dialogue(next_entry)
	else:
		_flash_keypad_error()

func _is_keypad_code_valid(code: String) -> bool:
	if not current_entry or not current_entry.readable_chain.has(code):
		return false
	var next_entry: ReadableEntry = current_entry.readable_chain[code]
	return next_entry != null and KeyManager.check_keys(next_entry.key_whitelist, next_entry.key_blacklist)

func _flash_keypad_error() -> void:
	_keypad_locked = true
	if keypad_display_label:
		keypad_display_label.text = "XXXX"
	await get_tree().create_timer(keypad_error_duration, true).timeout
	if is_instance_valid(self):
		_reset_keypad()
#endregion

#region Closing & Helpers
func _skip_text_animation_if_running() -> bool:
	if text_tween and text_tween.is_running():
		text_tween.custom_step(100.0)
		return true
	return false

func _close_ui(force_immediate: bool = false) -> void:
	if not force_immediate and _skip_text_animation_if_running():
		return
	KeyManager.remove_keys([&"dialogue_open"])
	visible = false
	if text_label:
		text_label.text = ""
	if input_field:
		input_field.clear()
	_reset_keypad()
	_clear_choice_buttons()
	
	if pause_on_dialogue:
		get_tree().paused = false
		process_mode = Node.PROCESS_MODE_INHERIT
	dialogue_closed.emit()
#endregion
