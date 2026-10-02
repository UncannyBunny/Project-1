class_name StateMachine extends Node3D

## Dictionary of keys and nodes affected by the state machine
@export var state_machine: Dictionary[String, Node]
var current_state: String

func _process(delta: float) -> void:
	current_state = verify_state()
	process_state()

func verify_state() -> String:
	for key in state_machine:
		if KeyManager.search_keys([key]):
			return key
	return ""

func process_state() -> void:
	if current_state == "":
		return
	state_machine.get(current_state).process_mode = Node.PROCESS_MODE_INHERIT
	for key in state_machine:
		if not key == current_state:
			state_machine[key].process_mode = Node.PROCESS_MODE_DISABLED
