## Top-level controller for NPCs that exposes schedule, dialogue, and AI settings on the root node.
class_name NPCController extends CharacterController3D

@export_group("NPC Data")
## Schedule entries passed down to ScheduleController on ready
@export var schedule_entries: Array[ScheduleEntry] = []
## Dialogue/readable entries passed down to ReadableComponent on ready
@export var readable_entries: Array[ReadableEntry] = []

@export_group("AI & Interaction Overrides")
## Keys that cause this NPC to enter hostile chase mode
@export var chase_trigger_keys: Array[StringName] = [&"aggresive"]

@export_group("Component References")
@export var schedule_controller: ScheduleController
@export var pathfinding_component: PathfindingComponent
@export var readable_component: ReadableComponent
@export var interaction_component: InteractionComponent

func _ready() -> void:
	rotate_with_movement = true
	super._ready()
	
	if not schedule_controller:
		schedule_controller = get_node_or_null("ScheduleController") as ScheduleController
	if not pathfinding_component:
		pathfinding_component = get_node_or_null("PathfindingComponent") as PathfindingComponent
	if not readable_component:
		readable_component = get_node_or_null("ReadableComponent") as ReadableComponent
	if not interaction_component:
		interaction_component = get_node_or_null("InteractionComponent") as InteractionComponent
		
	if pathfinding_component:
		pathfinding_component.chase_trigger_keys = chase_trigger_keys
		
	if schedule_controller and not schedule_entries.is_empty():
		schedule_controller.schedule_entries = schedule_entries
		
	if readable_component and not readable_entries.is_empty():
		readable_component.entries = readable_entries
