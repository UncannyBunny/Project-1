class_name ScheduleEntry extends Resource

## Time from when the schedule entry is triggered
@export var time: Vector2i = Vector2i.ZERO:
	set(value):
		time = value
		time_minutes = time.x * 60 + time.y
var time_minutes: int = 0
## Target schedule position
@export var position: Vector3 = Vector3.ZERO
