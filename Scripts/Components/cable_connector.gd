@tool
## Editor tool component that bakes catenary power cables between nearby poles with the same script.
class_name CableConnectorComponent extends Node3D

@export_group("Actions")
## Click in the Inspector (in Editor) to bake cables to all nearby CableConnectorComponents
@export_tool_button("Bake Cables", "MeshInstance3D") var bake_action: Callable:
	get:
		return bake_cables
## Click in the Inspector (in Editor) to clear all baked cables across the scene
@export_tool_button("Clear All Cables", "Clear") var clear_action: Callable:
	get:
		return clear_all_cables

@export_group("References & Connection Rules")
## The MeshInstance3D where the generated cable mesh will be assigned
@export var target_mesh_instance: MeshInstance3D
## The Node3D where the cable physically attaches (defaults to self if left empty)
@export var origin_node: Node3D
## Maximum distance (in meters) to search for other CableConnectorComponent nodes
@export var connection_radius: float = 10.0
## Tracks connected peer nodes so two poles never generate duplicate overlapping cables
@export var connected_peers: Array[NodePath] = []
## Saved on the root node so instanced scenes persist the baked mesh in-game without Editable Children
@export var baked_cable_mesh: ArrayMesh:
	set(value):
		baked_cable_mesh = value
		_apply_baked_mesh()

@export_group("Cable Geometry")
## Slack factor (1.001 = taut, higher values = more sag)
@export_range(1.001, 20.0, 0.001, "or_greater") var slack_factor: float = 1.01
## Thickness radius of the cable tube
@export var radius: float = 0.02
## Number of lengthwise subdivisions along the catenary curve
@export var segments: int = 12
## Number of radial sides around the cylinder cross-section
@export var sides: int = 5

static var _black_material: StandardMaterial3D

func _ready() -> void:
	_apply_baked_mesh()

func _apply_baked_mesh() -> void:
	var mesh_inst: MeshInstance3D = _get_mesh_instance()
	if mesh_inst:
		mesh_inst.mesh = baked_cable_mesh

#region Editor Baking Actions
## Scans the edited scene for all CableConnectorComponents and bakes non-repeating cables within radius
func bake_cables() -> void:
	var all_connectors: Array[CableConnectorComponent] = _get_all_connectors_in_scene()
	if all_connectors.is_empty():
		return
		
	# Put 'self' first so the currently edited node's slack_factor / geometry settings take priority on its connections
	if all_connectors.has(self):
		all_connectors.erase(self)
		all_connectors.push_front(self)
		
	# Reset existing connections and meshes first for a clean bake
	for connector: CableConnectorComponent in all_connectors:
		connector.connected_peers.clear()
		connector.baked_cable_mesh = null
			
	var mat: StandardMaterial3D = _get_black_material()
	
	for i: int in range(all_connectors.size()):
		var current: CableConnectorComponent = all_connectors[i]
		var mesh_inst: MeshInstance3D = current._get_mesh_instance()
		if not mesh_inst:
			push_warning("CableConnectorComponent on '%s' has no target_mesh_instance assigned." % current.name)
			continue
			
		var start_global: Vector3 = current.get_origin_global_position()
		var new_mesh := ArrayMesh.new()
		var has_surfaces: bool = false
		
		for j: int in range(i + 1, all_connectors.size()):
			var other: CableConnectorComponent = all_connectors[j]
			var end_global: Vector3 = other.get_origin_global_position()
			var dist: float = start_global.distance_to(end_global)
			
			if dist <= 0.01 or dist > minf(current.connection_radius, other.connection_radius):
				continue
			if current.is_connected_to(other) or other.is_connected_to(current):
				continue
				
			# Convert global positions into the target MeshInstance3D's local space
			var local_start: Vector3 = mesh_inst.to_local(start_global)
			var local_end: Vector3 = mesh_inst.to_local(end_global)
			
			# Use the average slack_factor of the two poles (or self's if self is one of them)
			var effective_slack: float = self.slack_factor if (current == self or other == self) else (current.slack_factor + other.slack_factor) * 0.5
			
			var arrays: Array = current._build_catenary_surface_arrays(local_start, local_end, effective_slack)
			if not arrays.is_empty():
				new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				new_mesh.surface_set_material(new_mesh.get_surface_count() - 1, mat)
				has_surfaces = true
				
				# Record connection on both poles to prevent duplicates
				current.register_connection(other)
				other.register_connection(current)
				
		if has_surfaces:
			current.baked_cable_mesh = new_mesh
		current.notify_property_list_changed()

## Clears baked meshes and connection records on all CableConnectorComponents in the scene
func clear_all_cables() -> void:
	for connector: CableConnectorComponent in _get_all_connectors_in_scene():
		connector.connected_peers.clear()
		connector.baked_cable_mesh = null
		connector.notify_property_list_changed()
#endregion

#region Connection Helpers
## Returns the assigned target_mesh_instance, or looks for a child MeshInstance3D fallback
func _get_mesh_instance() -> MeshInstance3D:
	if is_instance_valid(target_mesh_instance):
		return target_mesh_instance
	var cable_node := get_node_or_null("Cable") as MeshInstance3D
	if cable_node:
		return cable_node
	return get_node_or_null("MeshInstance3D") as MeshInstance3D

## Returns the global position of the selected origin_node, or self if none is assigned
func get_origin_global_position() -> Vector3:
	if is_instance_valid(origin_node):
		return origin_node.global_position
	var conn_node := get_node_or_null("Connection") as Node3D
	if conn_node:
		return conn_node.global_position
	return global_position

## Returns true if this connector already has a registered link to other
func is_connected_to(other: CableConnectorComponent) -> bool:
	var path_to_other: NodePath = get_path_to(other)
	return connected_peers.has(path_to_other)

## Stores a NodePath reference to a connected peer
func register_connection(other: CableConnectorComponent) -> void:
	var path_to_other: NodePath = get_path_to(other)
	if not connected_peers.has(path_to_other):
		connected_peers.append(path_to_other)

func _get_all_connectors_in_scene() -> Array[CableConnectorComponent]:
	var result: Array[CableConnectorComponent] = []
	var root: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	if not root:
		root = self
	if root is CableConnectorComponent:
		result.append(root as CableConnectorComponent)
	for child: Node in root.find_children("*", "CableConnectorComponent", true, false):
		if child is CableConnectorComponent:
			result.append(child as CableConnectorComponent)
	return result

static func _get_black_material() -> StandardMaterial3D:
	if not _black_material:
		_black_material = StandardMaterial3D.new()
		_black_material.albedo_color = Color.BLACK
		_black_material.roughness = 1.0
	return _black_material
#endregion

#region Catenary Math & Mesh Generation
func _build_catenary_surface_arrays(start: Vector3, end: Vector3, custom_slack: float = -1.0) -> Array:
	var xz_start := Vector3(start.x, 0.0, start.z)
	var xz_end := Vector3(end.x, 0.0, end.z)
	var x2: float = (xz_end - xz_start).length()
	var y2: float = end.y - start.y
	
	if x2 < 0.001:
		x2 = 0.001
		
	var active_slack: float = custom_slack if custom_slack > 1.0 else slack_factor
	var straight_dist: float = sqrt((x2 * x2) + (y2 * y2))
	var rope_length: float = straight_dist * maxf(active_slack, 1.0005)
	
	var a: float = _solve_catenary_parameter(x2, y2, rope_length)
	if a <= 0.0001:
		return []
		
	var x0: float = (x2 / 2.0) - a * atanh(clampf(y2 / rope_length, -0.9999, 0.9999))
	var y0: float = -a * cosh(x0 / a)
	
	var dx: float = x2 / float(maxi(segments, 1))
	var points: Array[Vector3] = []
	for i: int in range(segments + 1):
		var cur_x: float = dx * float(i)
		var cur_y: float = _evaluate_catenary_y(cur_x, a, x0, y0)
		points.append(Vector3(cur_x, cur_y, 0.0))
		
	return _build_tube_arrays(points, start, end)

## Solves sinh(x2 / (2*a)) = sqrt(L^2 - y2^2) / (2*a) using monotonic binary search on z = x2 / (2*a)
func _solve_catenary_parameter(x2: float, y2: float, rope_length: float) -> float:
	var vertical_span_sq: float = maxf((rope_length * rope_length) - (y2 * y2), 0.0)
	var ratio: float = sqrt(vertical_span_sq) / maxf(x2, 0.0001)
	
	# If rope_length is barely longer than straight distance, return a very large 'a' (nearly straight line)
	if ratio <= 1.00001:
		return x2 * 100.0
		
	# Solve sinh(z) / z = ratio for z > 0, where z = x2 / (2 * a)
	var low_z: float = 0.00001
	var high_z: float = 1.0
	while (sinh(high_z) / high_z) < ratio and high_z < 50.0:
		high_z *= 2.0
		
	for _i: int in range(32):
		var mid_z: float = 0.5 * (low_z + high_z)
		var val: float = sinh(mid_z) / mid_z
		if val < ratio:
			low_z = mid_z
		else:
			high_z = mid_z
			
	var solved_z: float = 0.5 * (low_z + high_z)
	return maxf(x2 / (2.0 * solved_z), 0.001)

func _evaluate_catenary_y(x: float, a: float, x0: float, y0: float) -> float:
	return y0 + a * cosh((x - x0) / a)

func _build_tube_arrays(points: Array[Vector3], start: Vector3, end: Vector3) -> Array:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	
	var offset_transform: Transform3D = _get_segment_transform(points[0], start, end)
	var ring_count: int = points.size()
	var ring_size: int = maxi(sides, 3)
	
	var angles := PackedFloat32Array()
	for i: int in range(ring_size):
		angles.append(TAU * float(i) / float(ring_size))
		
	var prev_binormal: Vector3 = Vector3.ZERO
	
	for i: int in range(ring_count):
		var p: Vector3 = points[i]
		var tangent: Vector3
		if i == 0:
			tangent = (points[i + 1] - p).normalized()
		elif i == ring_count - 1:
			tangent = (p - points[i - 1]).normalized()
		else:
			tangent = (points[i + 1] - points[i - 1]).normalized()
			
		var normal: Vector3
		if prev_binormal == Vector3.ZERO:
			normal = tangent.cross(Vector3.UP)
			if normal.length_squared() < 0.0001:
				normal = tangent.cross(Vector3.RIGHT)
			normal = normal.normalized()
		else:
			normal = prev_binormal.cross(tangent).normalized()
			
		var binormal: Vector3 = tangent.cross(normal).normalized()
		prev_binormal = binormal
		
		for j: int in range(ring_size):
			var angle: float = angles[j]
			var local_dir: Vector3 = cos(angle) * normal + sin(angle) * binormal
			var v: Vector3 = offset_transform * (p + local_dir * radius)
			var world_normal: Vector3 = (offset_transform.basis * local_dir).normalized()
			vertices.append(v)
			normals.append(world_normal)
			
	for i: int in range(ring_count - 1):
		var base0: int = i * ring_size
		var base1: int = (i + 1) * ring_size
		for j: int in range(ring_size):
			var j0: int = j
			var j1: int = (j + 1) % ring_size
			
			indices.append(base0 + j0)
			indices.append(base1 + j0)
			indices.append(base1 + j1)
			
			indices.append(base0 + j0)
			indices.append(base1 + j1)
			indices.append(base0 + j1)
			
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays

func _get_segment_transform(curve_start: Vector3, target_start: Vector3, target_end: Vector3) -> Transform3D:
	var dir_xz := Vector3(target_end.x - target_start.x, 0.0, target_end.z - target_start.z)
	if dir_xz.length_squared() < 0.0001:
		dir_xz = Vector3.RIGHT
	else:
		dir_xz = dir_xz.normalized()
		
	var up := Vector3.UP
	var z_axis: Vector3 = dir_xz.cross(up).normalized()
	var rot_basis := Basis(dir_xz, up, z_axis)
	var translation: Vector3 = target_start - (rot_basis * curve_start)
	return Transform3D(rot_basis, translation)
#endregion
