class_name UIController extends Control

@export var menu_pause: PauseUI
@export var menu_clock: ClockUI
@export var menu_dialogue: DialogueUI

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	if menu_pause.visible or menu_clock.clock_input_display.visible or menu_dialogue.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
