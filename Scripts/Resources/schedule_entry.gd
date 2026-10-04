class_name ScheduleEntry extends Resource

## The priority of the entry, if multiple entries overlap the one with the highest priority should be picked.
@export var priority: int
## Time from when the schedule entry is triggered
@export var time_start: Vector2i = Vector2i.ZERO:
	set(value):
		time_start = value
		time_start_minutes = TimeManager.time_from_vector(time_start)
var time_start_minutes: int = 0
## Time from when the schedule entry can no longer be triggered
@export var time_end: Vector2i = Vector2i.ZERO:
	set(value):
		time_end = value
		time_end_minutes = TimeManager.time_from_vector(time_end)
var time_end_minutes: int = 0
## Target schedule position
@export var position: Vector3 = Vector3.ZERO
@export var keys_whitelist: Array[String]
@export var keys_blacklist: Array[String]
## The keys unlocked by triggering the entry
@export var keys_unlocked: Array[String]
## The keys lost by triggering the entry
@export var keys_taken: Array[String]
