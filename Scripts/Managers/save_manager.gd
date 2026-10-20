extends Node

const save_path_prefix: String = "user://"
const save_path_suffix: String = ".save"
var save_path_name: String = "slot_default"

var save_contents: Dictionary = {
	"persistent_keys": [],
	"loop_count": 0,
	"current_start_time": 0,
	"notebook_lines": []
}

func has_save(file_name: String = save_path_name) -> bool:
	var save_path: String = save_path_prefix + file_name + save_path_suffix
	return FileAccess.file_exists(save_path)

func save_data(file_name: String = save_path_name) -> void:
	save_path_name = file_name
	_collect_state_from_managers()
	
	var save_path: String = save_path_prefix + file_name + save_path_suffix
	var file: FileAccess = FileAccess.open_encrypted_with_pass(save_path, FileAccess.WRITE, "256fd81450cc4cae932d2be39a367d5a")
	if not file:
		return
	file.store_var(save_contents.duplicate(true))
	file.close()

func load_data(file_name: String = save_path_name) -> bool:
	save_path_name = file_name
	var save_path = save_path_prefix + file_name + save_path_suffix
	if not FileAccess.file_exists(save_path):
		return false
	var file: FileAccess = FileAccess.open_encrypted_with_pass(save_path, FileAccess.READ, "256fd81450cc4cae932d2be39a367d5a")
	var data: Variant = file.get_var()
	file.close()
	
	if data is Dictionary:
		var save_data: Dictionary = (data as Dictionary).duplicate(true)
		for key: String in save_contents:
			if save_data.has(key):
				save_contents[key] = save_data[key]
		_apply_state_to_managers()
		return true
	return false

func _collect_state_from_managers() -> void:
	save_contents["persistent_keys"] = KeyManager.get_persistent_keys()
	save_contents["current_keys"] = KeyManager.get_active_keys()
	save_contents["loop_count"] = LoopManager.get_loop_count()
	save_contents["current_time"] = TimeManager.get_current_time()
	save_contents["current_start_time"] = TimeManager.get_day_start_current()
	
	var ui := get_tree().get_first_node_in_group(&"ui_controller") as UIController
	if ui:
		save_contents["notebook_lines"] = ui.get_notebook_lines()

func _apply_state_to_managers() -> void:
	var loaded_persistent: Array[StringName] = []
	for k: Variant in save_contents["persistent_keys"]:
		loaded_persistent.append(StringName(k))
		
	KeyManager.set_persistent_keys(loaded_persistent)
	LoopManager.set_loop_count(int(save_contents["loop_count"]))
	TimeManager.set_day_start(int(save_contents["current_start_time"]))

func delete_save(file_name: String = save_path_name) -> bool:
	var save_path: String = save_path_prefix + file_name + save_path_suffix
	var deleted_from_disk: bool = false
	
	if FileAccess.file_exists(save_path):
		var err: Error = DirAccess.remove_absolute(save_path)
		if err != OK:
			push_error("SaveManager: Failed to delete save file at %s (Error %d)" % [save_path, err])
			return false
		deleted_from_disk = true
		
	reset_state()
	return deleted_from_disk

func reset_state() -> void:
	save_contents = {
		"persistent_keys": [],
		"current_keys": [],
		"loop_count": 0,
		"current_time": TimeManager.get_day_start(),
		"current_start_time": TimeManager.get_day_start(),
		"notebook_lines": []
	}
	_apply_state_to_managers()
	TimeManager.force_time(TimeManager.get_day_start())
	
	var ui := get_tree().get_first_node_in_group(&"ui_controller") as UIController
	if ui:
		ui.clear_notebook_lines()
