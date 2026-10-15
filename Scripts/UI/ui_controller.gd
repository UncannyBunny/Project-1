## Master UI Controller managing the Pause Menu, integrated Clock/Alarm, Notebook, and cursor state.
class_name UIController extends Control

signal game_paused(is_paused: bool)
signal note_saved(line_index: int, text: String)

@export_group("Scene References")
## File path to the Main Menu scene (Pause menu will not open if this is the active scene)
@export_file("*.tscn") var main_menu_scene_path: String = ""
@export var pause_menu_container: Control
@export var dialogue_ui: DialogueUI

@export_group("Pause Buttons")
@export var button_continue: Button
@export var button_save_and_exit: Button

@export_group("Clock & Alarm UI")
## Single label that displays current time by default, or alarm time when editing alarm
@export var clock_text_label: RichTextLabel
@export var button_set_alarm: Button
@export var button_hour: Button
@export var button_minute: Button

@export_group("Notebook UI")
## Parent Control holding the LineEdit nodes for a single notebook page
@export var notebook_lines_container: Control
@export var button_prev_page: Button
@export var button_next_page: Button
@export var page_number_label: Label
@export var max_characters_per_line: int = 40
@export var max_pages: int = 10

var _is_editing_alarm: bool = false
var _target_alarm_time: int = 360

var _saved_notes: Array[String] = []
var _current_page: int = 0
var _line_edits: Array[LineEdit] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if pause_menu_container:
		pause_menu_container.visible = false
		
	_target_alarm_time = TimeManager.get_day_start_current()
	_setup_pause_buttons()
	_setup_clock_ui()
	_setup_notebook_ui()
	_update_clock_display()

func _process(_delta: float) -> void:
	_update_mouse_mode()
	if pause_menu_container and pause_menu_container.visible and not _is_editing_alarm:
		_update_clock_display()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"menu_pause"):
		if _is_in_main_menu():
			return
		# If DialogueUI is open and pausing the tree, ignore or let pause toggle cleanly
		toggle_pause_menu()

#region Pause Menu & Mouse State
func toggle_pause_menu() -> void:
	if not pause_menu_container:
		return
	set_pause_menu_open(not pause_menu_container.visible)

func set_pause_menu_open(open: bool) -> void:
	if not pause_menu_container:
		return
	pause_menu_container.visible = open
	
	if open:
		_is_editing_alarm = false
		_target_alarm_time = TimeManager.get_day_start_current()
		_update_clock_display()
		_refresh_notebook_page()
		get_tree().paused = true
	else:
		# Save alarm time if changed, reset clock mode to current time, and discard uncommitted note edits
		TimeManager.set_day_start(_target_alarm_time)
		_is_editing_alarm = false
		_update_clock_display()
		_refresh_notebook_page()
		if not (dialogue_ui and dialogue_ui.visible and dialogue_ui.pause_on_dialogue):
			get_tree().paused = false
			
	game_paused.emit(open)
	_update_mouse_mode()

func _setup_pause_buttons() -> void:
	if button_continue:
		button_continue.pressed.connect(func() -> void: set_pause_menu_open(false))
	if button_save_and_exit:
		button_save_and_exit.pressed.connect(_on_save_and_exit_pressed)

func _on_save_and_exit_pressed() -> void:
	set_pause_menu_open(false)
	get_tree().paused = false
	if not main_menu_scene_path.is_empty():
		get_tree().change_scene_to_file(main_menu_scene_path)

func _is_in_main_menu() -> bool:
	if main_menu_scene_path.is_empty() or not get_tree().current_scene:
		return false
	return get_tree().current_scene.scene_file_path == main_menu_scene_path

func _update_mouse_mode() -> void:
	var any_menu_open: bool = (pause_menu_container and pause_menu_container.visible) or (dialogue_ui and dialogue_ui.visible)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if any_menu_open else Input.MOUSE_MODE_CAPTURED
#endregion

#region Clock & Alarm Logic
func _setup_clock_ui() -> void:
	if button_set_alarm:
		button_set_alarm.pressed.connect(_on_toggle_alarm_mode)
	if button_hour:
		button_hour.pressed.connect(_on_hour_pressed)
	if button_minute:
		button_minute.pressed.connect(_on_minute_pressed)

func _on_toggle_alarm_mode() -> void:
	_is_editing_alarm = not _is_editing_alarm
	if not _is_editing_alarm:
		TimeManager.set_day_start(_target_alarm_time)
	_update_clock_display()

func _on_hour_pressed() -> void:
	if not _is_editing_alarm:
		return
	var time_vec: Vector2i = TimeManager.time_as_vector(_target_alarm_time)
	var max_hour: int = TimeManager.time_as_vector(TimeManager.get_day_end()).x - 1
	var min_hour: int = TimeManager.time_as_vector(TimeManager.get_day_start()).x
	
	if time_vec.x + 1 <= max_hour:
		time_vec.x += 1
	else:
		time_vec.x = min_hour
	_target_alarm_time = TimeManager.time_from_vector(time_vec)
	_update_clock_display()

func _on_minute_pressed() -> void:
	if not _is_editing_alarm:
		return
	var time_vec: Vector2i = TimeManager.time_as_vector(_target_alarm_time)
	var min_minute: int = TimeManager.time_as_vector(TimeManager.get_day_start()).y
	
	if time_vec.y + 5 < 60:
		time_vec.y += 5
	else:
		time_vec.y = min_minute
	_target_alarm_time = TimeManager.time_from_vector(time_vec)
	_update_clock_display()

func _update_clock_display() -> void:
	if not clock_text_label:
		return
	var displayed_time: int = _target_alarm_time if _is_editing_alarm else TimeManager.get_current_time()
	clock_text_label.text = TimeManager.time_as_string(displayed_time)
#endregion

#region Notebook Logic
func _setup_notebook_ui() -> void:
	if not notebook_lines_container:
		return
	_line_edits.clear()
	for child: Node in notebook_lines_container.get_children():
		if child is LineEdit:
			var line_edit := child as LineEdit
			var local_idx: int = _line_edits.size()
			line_edit.max_length = max_characters_per_line
			line_edit.text_submitted.connect(_on_note_line_submitted.bind(local_idx))
			_line_edits.append(line_edit)
			
	var total_lines: int = _line_edits.size() * maxf(max_pages, 1)
	_saved_notes.resize(total_lines)
	_saved_notes.fill("")
	
	if button_prev_page:
		button_prev_page.pressed.connect(func() -> void: _change_notebook_page(-1))
	if button_next_page:
		button_next_page.pressed.connect(func() -> void: _change_notebook_page(1))
		
	_refresh_notebook_page()

func _change_notebook_page(delta_page: int) -> void:
	if _line_edits.is_empty():
		return
	_current_page = clampi(_current_page + delta_page, 0, max_pages - 1)
	# Uncommitted edits on the previous page are automatically discarded when refreshing
	_refresh_notebook_page()

func _refresh_notebook_page() -> void:
	if _line_edits.is_empty():
		return
	var lines_per_page: int = _line_edits.size()
	var start_index: int = _current_page * lines_per_page
	
	for i: int in range(lines_per_page):
		var global_index: int = start_index + i
		var saved_text: String = _saved_notes[global_index] if global_index < _saved_notes.size() else ""
		var line_edit: LineEdit = _line_edits[i]
		line_edit.text = saved_text
		# Once committed (non-empty in _saved_notes), the line is locked from further editing
		line_edit.editable = saved_text.is_empty()
		
	if page_number_label:
		page_number_label.text = "%d / %d" % [_current_page + 1, max_pages]
	if button_prev_page:
		button_prev_page.disabled = (_current_page <= 0)
	if button_next_page:
		button_next_page.disabled = (_current_page >= max_pages - 1)

func _on_note_line_submitted(submitted_text: String, local_line_index: int) -> void:
	var clean_text: String = submitted_text.strip_edges()
	if clean_text.is_empty():
		return
	var global_index: int = (_current_page * _line_edits.size()) + local_line_index
	if global_index >= _saved_notes.size():
		_saved_notes.resize(global_index + 1)
	_saved_notes[global_index] = submitted_text
	
	var line_edit: LineEdit = _line_edits[local_line_index]
	line_edit.editable = false
	line_edit.release_focus()
	note_saved.emit(global_index, submitted_text)

## Overwrites the entire saved notebook array with a new array of strings
func set_notebook_lines(new_lines: Array[String]) -> void:
	var total_capacity: int = _line_edits.size() * maxf(max_pages, 1)
	_saved_notes = new_lines.duplicate()
	if _saved_notes.size() < total_capacity:
		_saved_notes.resize(total_capacity)
	_refresh_notebook_page()

## Returns a copy of the saved notebook lines array
func get_notebook_lines() -> Array[String]:
	return _saved_notes.duplicate()

## Clears all saved notebook lines and unlocks all text boxes
func clear_notebook_lines() -> void:
	_saved_notes.fill("")
	_refresh_notebook_page()
#endregion
