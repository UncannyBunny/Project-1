class_name UIController extends Control

@export var menu_items: Array[Node]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	for item in menu_items:
		if item.visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
