@tool
class_name ScheduleController extends Node3D

## Object to receive the input
@export var target_object: Node3D:
	set(value):
		target_object = value
		notify_property_list_changed()
## Method that will be called with the input
@export var target_method_string: String = ""
var target_method_callable: Callable
@export var schedule_entries: Array[ScheduleEntry]

func _ready() -> void:
	# Avoid execution in editor environment.
	if Engine.is_editor_hint():
		return
	# Bind target callable for 
	if target_object and not target_method_string.is_empty():
		target_method_callable = Callable(target_object, target_method_string)

func _process(delta: float) -> void:
	# Avoid execution in editor environment.
	if Engine.is_editor_hint():
		return
	var schedule_current: ScheduleEntry = schedule_selection()
	if schedule_current:
		target_method_callable.call(schedule_current.position)

func schedule_selection() -> ScheduleEntry:
	if not schedule_entries or not target_object or schedule_entries.is_empty():
		return
	var time_current: int = TimeManager.get_current_time()
	var schedule_candidates: Array[ScheduleEntry]
	for schedule in schedule_entries:
		if schedule.time_start_minutes > time_current:
			continue
		if time_current > schedule.time_end_minutes and not schedule.time_end_minutes == 0:
			continue
		if not KeyManager.search_keys(schedule.keys_whitelist):
			continue
		if KeyManager.search_keys(schedule.keys_blacklist) and not schedule.keys_blacklist.is_empty():
			continue
		schedule_candidates.append(schedule)
	if schedule_candidates.is_empty():
		return
	else:
		schedule_candidates.sort_custom(func(a: ScheduleEntry, b: ScheduleEntry): return a.priority > b.priority)
		return schedule_candidates[0]

func _validate_property(property: Dictionary) -> void:
	if property.name == "target_method_string":
		var target_method_options: String = ""
		
		if target_object and target_object.get_script():
			var methods: Array = target_object.get_script().get_script_method_list()
			var method_names: Array[String] = []
			
			for method in methods:
				if not method["name"].begins_with("_"):
					method_names.append(method["name"])
					
			target_method_options = ",".join(method_names)
			
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = target_method_options
