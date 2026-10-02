class_name PauseUI extends Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	visible = false

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_pause"):
		visible = not visible
		if visible:
			get_tree().paused = true
		else:
			get_tree().paused = false
