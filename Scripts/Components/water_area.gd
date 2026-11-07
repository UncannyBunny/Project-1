extends Area3D

@export var buoyancy: float = 2.0
@export var drag_water: float = 2.0

var floating_bodies: Array[RigidBody3D] = []
@onready var world_gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _physics_process(_delta: float) -> void:
	for body in floating_bodies:
		if not is_instance_valid(body):
			continue
		var depth: float = global_position.y - body.global_position.y
		if depth <= 0.0:
			continue
		var weight: float = body.mass * world_gravity
		var force_buoyancy: float = weight * (depth * buoyancy)
		var force_drag: Vector3 = -body.linear_velocity * drag_water * body.mass
		var force_total: Vector3 = Vector3(0, force_buoyancy, 0) + force_drag
		body.apply_central_force(force_total)
func _on_body_entered(body: Node3D) -> void:
	if body is RigidBody3D:
		floating_bodies.append(body)
func _on_body_exited(body: Node3D) -> void:
	if body is RigidBody3D:
		floating_bodies.erase(body)
