## Evaluates ScheduleEntry resources on time or key changes and directs the NPC's PathfindingComponent.
class_name ScheduleController extends Node3D

signal schedule_changed(new_schedule: ScheduleEntry)

@export var pathfinding_component: PathfindingComponent
@export var schedule_entries: Array[ScheduleEntry] = []

var current_schedule: ScheduleEntry = null

func _ready() -> void:
	if not pathfinding_component:
		pathfinding_component = get_node_or_null("../PathfindingComponent") as PathfindingComponent
		
	TimeManager.time_changed.connect(_on_time_or_keys_changed)
	KeyManager.keys_changed.connect(_on_time_or_keys_changed)
	schedule_process.call_deferred()

func _on_time_or_keys_changed(_arg: Variant = null) -> void:
	schedule_process()

func schedule_process() -> void:
	var selected: ScheduleEntry = select_best_schedule()
	if selected == current_schedule or selected == null:
		return
		
	current_schedule = selected
	var target_pos: Vector3 = _resolve_target_position(current_schedule)
	if pathfinding_component:
		pathfinding_component.set_target_position(
			target_pos,
			current_schedule.use_arrival_rotation,
			current_schedule.arrival_rotation_degrees
		)
		
	if not current_schedule.keys_unlocked.is_empty():
		KeyManager.add_keys(current_schedule.keys_unlocked)
	if not current_schedule.keys_taken.is_empty():
		KeyManager.remove_keys(current_schedule.keys_taken)
		
	schedule_changed.emit(current_schedule)

func select_best_schedule() -> ScheduleEntry:
	if schedule_entries.is_empty():
		return null
		
	var time_current: int = TimeManager.get_current_time()
	var best_entry: ScheduleEntry = null
	
	for schedule: ScheduleEntry in schedule_entries:
		if not schedule:
			continue
		if schedule.time_start_minutes > time_current:
			continue
		if schedule.time_end_minutes != 0 and time_current > schedule.time_end_minutes:
			continue
		if not KeyManager.check_keys(schedule.keys_whitelist, schedule.keys_blacklist):
			continue
		if best_entry == null or schedule.priority > best_entry.priority:
			best_entry = schedule
			
	return best_entry

func _resolve_target_position(entry: ScheduleEntry) -> Vector3:
	if not entry.waypoint_node_path.is_empty():
		var waypoint := get_node_or_null(entry.waypoint_node_path) as Node3D
		if waypoint:
			return waypoint.global_position
	return entry.position
