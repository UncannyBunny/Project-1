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
@export var schedule: Array[ScheduleEntry]
var schedule_current: int = -1

func _ready() -> void:
	# Avoid execution in editor environment.
	if Engine.is_editor_hint():
		return
	# Bind target callable for 
	if target_object and not target_method_string.is_empty():
		target_method_callable = Callable(target_object, target_method_string)
	schedule.sort_custom(_schedule_sorter)

func _schedule_sorter(a: ScheduleEntry, b: ScheduleEntry) -> bool:
	return a.time_minutes < b.time_minutes

func _process(delta: float) -> void:
	# Avoid execution in editor environment.
	if Engine.is_editor_hint():
		return
	if not schedule or not target_object:
		return
	var time_current: int = TimeManager.get_current_time()
	if schedule.size() - 1 < schedule_current + 1:
		return
	if schedule[schedule_current + 1].time_minutes <= time_current:
		schedule_current += 1
		target_method_callable.call(schedule[schedule_current].position)

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
