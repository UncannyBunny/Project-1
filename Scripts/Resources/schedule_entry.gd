## Resource defining a single scheduled waypoint and state change for an NPC.
class_name ScheduleEntry extends Resource

@export_group("Schedule Timing")
## Higher priority entries override lower priority ones when time windows overlap
@export var priority: int = 0
## Time (Hours, Minutes) when this schedule entry becomes active
@export var time_start: Vector2i = Vector2i.ZERO:
	set(value):
		time_start = value
		time_start_minutes = value.x * 60 + value.y
var time_start_minutes: int = 0

## Time (Hours, Minutes) when this schedule entry expires (0, 0 means no expiration)
@export var time_end: Vector2i = Vector2i.ZERO:
	set(value):
		time_end = value
		time_end_minutes = value.x * 60 + value.y
var time_end_minutes: int = 0

@export_group("Destination")
## Target global position in 3D space
@export var position: Vector3 = Vector3.ZERO
## Optional NodePath to a Marker3D/Node3D in the scene; if valid, overrides position
@export var waypoint_node_path: NodePath
## Optional Y-axis rotation (in degrees) the NPC should face upon arriving
@export var arrival_rotation_degrees: float = 0.0
@export var use_arrival_rotation: bool = false
## If true, the NPC should run on its way to the target position
@export var run: bool = false

@export_group("Key Conditions & Effects")
## If false, keys_unlocked and keys_taken are applied when the schedule starts instead of when the NPC reaches the destination
@export var add_keys_on_arrival: bool = true
## Keys required for this schedule entry to be valid
@export var keys_whitelist: Array[StringName] = []
## Keys that prevent this schedule entry from being valid
@export var keys_blacklist: Array[StringName] = []
## Keys unlocked globally when this schedule entry begins
@export var keys_unlocked: Array[StringName] = []
## Keys removed globally when this schedule entry begins
@export var keys_taken: Array[StringName] = []

@export_group("Presentation Hooks")
## Optional animation to play once the NPC reaches this waypoint
@export var arrival_animation: StringName = &""
## Optional audio stream to play when this schedule triggers
@export var trigger_sound: AudioStream
