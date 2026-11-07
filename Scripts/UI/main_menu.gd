## Controls the Main Menu UI
class_name MainMenuController extends Control

enum SlotMode {
	NEW_GAME,
	LOAD_GAME
}

@export_group("Scene Navigation")
## Path to the main gameplay scene loaded when starting or continuing a game
@export_file("*.tscn", "*scn") var game_scene_path: String = ""

@export_group("Menu Containers")
@export var main_screen_container: Control
@export var save_slots_container: Control
@export var credits_container: Control
@export var loading_container: Control

@export_group("Main Screen Buttons")
@export var button_new_game: Button
@export var button_load_game: Button
@export var button_credits: Button
@export var button_exit: Button

@export_group("Save Slots Screen")
## Parent container holding the 6 save slot Button nodes (in order 1 to 6)
@export var slot_buttons_container: Control
var slot_buttons: Array[Button] = []
@export var button_back_from_slots: Button

@export_group("Credits Screen")
@export var button_back_from_credits: Button

var _current_slot_mode: SlotMode = SlotMode.NEW_GAME
var scene_loaded: bool = false
var scene_loading: bool = false

func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	_setup_main_buttons()
	_setup_slot_buttons()
	_setup_credits_buttons()
	show_main_screen()
	
	if not game_scene_path.is_empty():
		ResourceLoader.load_threaded_request(game_scene_path)

func _process(delta: float) -> void:
	if ResourceLoader.load_threaded_get_status(game_scene_path) == 3:
		scene_loaded = true
	if scene_loading == true and scene_loaded:
		_change_to_game_scene()

#region Screen Switching
func show_main_screen() -> void:
	if main_screen_container:
		main_screen_container.visible = true
	if save_slots_container:
		save_slots_container.visible = false
	if credits_container:
		credits_container.visible = false
	if loading_container:
		loading_container.visible = false

func show_save_slots_screen(mode: SlotMode) -> void:
	_current_slot_mode = mode
	_refresh_slot_buttons()
	
	if main_screen_container:
		main_screen_container.visible = false
	if save_slots_container:
		save_slots_container.visible = true
	if credits_container:
		credits_container.visible = false
	if loading_container:
		loading_container.visible = false

func show_credits_screen() -> void:
	if main_screen_container:
		main_screen_container.visible = false
	if save_slots_container:
		save_slots_container.visible = false
	if credits_container:
		credits_container.visible = true
	if loading_container:
		loading_container.visible = false

func show_loading_screen() -> void:
	if main_screen_container:
		main_screen_container.visible = false
	if save_slots_container:
		save_slots_container.visible = false
	if credits_container:
		credits_container.visible = false
	if loading_container:
		loading_container.visible = true
#endregion

#region Setup & Signals
func _setup_main_buttons() -> void:
	if button_new_game:
		button_new_game.pressed.connect(func() -> void: show_save_slots_screen(SlotMode.NEW_GAME))
	if button_load_game:
		button_load_game.pressed.connect(func() -> void: show_save_slots_screen(SlotMode.LOAD_GAME))
	if button_credits:
		button_credits.pressed.connect(show_credits_screen)
	if button_exit:
		button_exit.pressed.connect(func() -> void: get_tree().quit())

func _setup_slot_buttons() -> void:
	if button_back_from_slots:
		button_back_from_slots.pressed.connect(show_main_screen)
		
	if slot_buttons.is_empty() and slot_buttons_container:
		for child: Node in slot_buttons_container.find_children("*", "Button", true, false):
			var btn := child as Button
			if btn and btn != button_back_from_slots:
				slot_buttons.append(btn)
				
	for i: int in range(slot_buttons.size()):
		var slot_index: int = i + 1
		var btn: Button = slot_buttons[i]
		if btn:
			btn.pressed.connect(_on_slot_button_pressed.bind(slot_index))

func _setup_credits_buttons() -> void:
	if button_back_from_credits:
		button_back_from_credits.pressed.connect(show_main_screen)
#endregion

#region Save Slot Logic
func _refresh_slot_buttons() -> void:
	for i: int in range(slot_buttons.size()):
		var btn: Button = slot_buttons[i]
		if not btn:
			continue
		var slot_name: String = "slot_%d" % (i + 1)
		var exists: bool = SaveManager.has_save(slot_name)
		
		if _current_slot_mode == SlotMode.NEW_GAME:
			btn.disabled = false
		else:
			btn.disabled = not exists

func _on_slot_button_pressed(slot_number: int) -> void:
	if game_scene_path.is_empty():
		return
	var slot_name: String = "slot_%d" % slot_number
	SaveManager.save_path_name = slot_name
	if _current_slot_mode == SlotMode.NEW_GAME:
		SaveManager.delete_save(slot_name)
		SaveManager.save_data(slot_name)
		_change_to_game_scene.call_deferred()
	elif _current_slot_mode == SlotMode.LOAD_GAME:
		if not SaveManager.load_data(slot_name):
			return
		_change_to_game_scene.call_deferred()

func _change_to_game_scene() -> void:
	if game_scene_path.is_empty():
		return
	if not scene_loaded:
		show_loading_screen()
		scene_loading = true
		return
	var packed_scene := ResourceLoader.load_threaded_get(game_scene_path) as PackedScene
	if packed_scene:
		get_tree().change_scene_to_packed(packed_scene)
	else:
		get_tree().change_scene_to_file(game_scene_path)
#endregion
