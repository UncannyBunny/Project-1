@tool
## Component that spawns MultiMesh grass across a parent StaticBody3D/VisualInstance3D's AABB using a group whitelist.
class_name ProceduralGrass extends MultiMeshInstance3D

@export_group("Generator Actions")
@export_tool_button("Bake Grass", "MultiMeshInstance3D") var btn_bake: Callable:
	get:
		return bake_grass
@export_tool_button("Randomize Seed & Bake", "RandomNumberGenerator") var btn_randomize: Callable:
	get:
		return randomize_and_bake
@export_tool_button("Clear Grass", "Clear") var btn_clear: Callable:
	get:
		return clear_grass

@export var seed_value: int = 12345
@export_range(1, 100000, 1) var grass_count: int = 8000

@export_group("Target & Whitelist")
## Optional explicit body/mesh to read AABB from. If empty, uses get_parent().
@export var target_body: Node3D
## Whitelist of Node Groups allowed to grow grass. Any object above the floor NOT in these groups blocks grass!
@export var allowed_groups: Array[StringName] = [&"grass_surface"]
## If true, the parent/target_body itself is automatically treated as whitelisted even if you forgot to add the group to it.
@export var allow_target_body_without_group: bool = true
## Extra vertical height above the AABB top to start downward raycasts (catches tall roofs/trees blocking the floor)
@export var raycast_top_margin: float = 15.0
## Extra vertical depth below the AABB bottom for the raycast end
@export var raycast_bottom_margin: float = 2.0
## Fallback area and height if no parent AABB can be found
@export var fallback_aabb: AABB = AABB(Vector3(-20.0, -2.0, -20.0), Vector3(40.0, 10.0, 40.0))

@export_group("Clump Mesh & Scale")
## Width (X) and Height (Y) of each grass plane in meters
@export var blade_base_size: Vector2 = Vector2(0.55, 0.5)
## Generates intersecting X cross-planes so grass has volume from all camera angles
@export var cross_planes: bool = true
@export var scale_randomness: Vector2 = Vector2(0.75, 1.35)
## Maximum slope angle (in degrees) where grass is allowed to grow
@export_range(0.0, 89.0, 1.0) var max_slope_degrees: float = 35.0
## Optional noise to group grass into natural lush patches and bare spots
@export var density_noise: Noise
@export_range(0.0, 1.0, 0.01) var noise_threshold: float = 0.25
@export var grass_material: Material

@export_group("Performance & Culling")
## Distance in meters where grass finishes fading out (0 = never fade)
@export var visibility_max_distance: float = 60.0
@export var visibility_fade_margin: float = 10.0

@export_group("Baked Data")
@export var baked_multimesh: MultiMesh:
	set(value):
		baked_multimesh = value
		multimesh = baked_multimesh


func _ready() -> void:
	_apply_visibility_settings()
	if baked_multimesh:
		multimesh = baked_multimesh


func randomize_and_bake() -> void:
	seed_value = randi()
	bake_grass()


func clear_grass() -> void:
	baked_multimesh = null
	multimesh = null
	notify_property_list_changed()


func bake_grass() -> void:
	if not is_inside_tree():
		return

	_apply_visibility_settings()

	var host: Node3D = _get_target_host()
	var world_aabb: AABB = _compute_target_world_aabb(host)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var max_slope_cos: float = cos(deg_to_rad(max_slope_degrees))

	var min_x: float = world_aabb.position.x
	var max_x: float = world_aabb.end.x
	var min_z: float = world_aabb.position.z
	var max_z: float = world_aabb.end.z

	var ray_start_y: float = world_aabb.end.y + raycast_top_margin
	var ray_end_y: float = world_aabb.position.y - raycast_bottom_margin

	var valid_transforms: Array[Transform3D] = []
	var valid_custom_data: Array[Color] = []

	for i: int in range(grass_count):
		var world_x: float = rng.randf_range(min_x, max_x)
		var world_z: float = rng.randf_range(min_z, max_z)

		# 1. Optional Noise Patchiness Filter
		if density_noise:
			var n_val: float = (density_noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5
			if n_val < noise_threshold:
				continue

		var ray_start := Vector3(world_x, ray_start_y, world_z)
		var ray_end := Vector3(world_x, ray_end_y, world_z)

		# Raycast against all physics layers so any house, road, or prop above the floor intercepts the ray first
		var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		query.collide_with_bodies = true
		query.collide_with_areas = false

		var hit: Dictionary = space_state.intersect_ray(query)
		if hit.is_empty():
			continue

		var collider: Object = hit.get("collider")
		if not (collider is Node):
			continue

		# 2. Whitelist Check: Only spawn if the top-most hit collider is whitelisted
		if not _is_collider_whitelisted(collider as Node, host):
			continue

		var hit_pos: Vector3 = hit["position"]
		var hit_normal: Vector3 = (hit["normal"] as Vector3).normalized()

		# 3. Slope Check: Reject steep cliffs/walls
		if hit_normal.dot(Vector3.UP) < max_slope_cos:
			continue

		# Convert hit position & normal into this MultiMeshInstance3D's local space
		var local_pos: Vector3 = to_local(hit_pos)
		var local_normal: Vector3 = (global_basis.inverse() * hit_normal).normalized()

		var yaw: float = rng.randf_range(0.0, TAU)
		var rand_scale: float = rng.randf_range(scale_randomness.x, scale_randomness.y)

		var up_vec: Vector3 = Vector3.UP.lerp(local_normal, 0.65).normalized()
		var forward_vec := Vector3(sin(yaw), 0.0, cos(yaw))
		var right_vec: Vector3 = up_vec.cross(forward_vec).normalized()
		forward_vec = right_vec.cross(up_vec).normalized()

		var blade_basis := Basis(right_vec, up_vec, forward_vec).scaled(Vector3.ONE * rand_scale)
		valid_transforms.append(Transform3D(blade_basis, local_pos))

		valid_custom_data.append(Color(
			rng.randf(), # R: Random color variation (0..1)
			rng.randf(), # G: Random wind phase offset
			rand_scale,  # B: Scale factor
			1.0
		))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _build_clump_mesh()
	mm.instance_count = valid_transforms.size()

	for idx: int in range(valid_transforms.size()):
		mm.set_instance_transform(idx, valid_transforms[idx])
		mm.set_instance_custom_data(idx, valid_custom_data[idx])

	baked_multimesh = mm
	notify_property_list_changed()


#region AABB & Whitelist Helpers
func _get_target_host() -> Node3D:
	if is_instance_valid(target_body):
		return target_body
	return get_parent() as Node3D


func _is_collider_whitelisted(collider_node: Node, host: Node3D) -> bool:
	if allow_target_body_without_group and is_instance_valid(host):
		if collider_node == host or host.is_ancestor_of(collider_node):
			return true

	# Check the collider node itself, its parent, and its scene owner for any allowed group
	var check_nodes: Array[Node] = [collider_node]
	if collider_node.get_parent():
		check_nodes.append(collider_node.get_parent())
	if collider_node.owner and not check_nodes.has(collider_node.owner):
		check_nodes.append(collider_node.owner)

	for n: Node in check_nodes:
		for grp: StringName in allowed_groups:
			if grp != &"" and n.is_in_group(grp):
				return true
	return false


func _compute_target_world_aabb(host: Node3D) -> AABB:
	if not is_instance_valid(host):
		return global_transform * fallback_aabb

	var found_any: bool = false
	var combined_aabb := AABB()

	# Gather AABBs from VisualInstance3D (MeshInstance3D, CSGShape3D) and CollisionShape3D on the host
	var candidates: Array[Node] = [host]
	for child: Node in host.get_children():
		if child != self:
			candidates.append(child)

	for node: Node in candidates:
		if node is VisualInstance3D and not (node is MultiMeshInstance3D):
			var vis := node as VisualInstance3D
			var local_box: AABB = vis.get_aabb()
			if local_box.size.length_squared() > 0.0001:
				var world_box: AABB = vis.global_transform * local_box
				combined_aabb = world_box if not found_any else combined_aabb.merge(world_box)
				found_any = true
		elif node is CollisionShape3D:
			var col := node as CollisionShape3D
			if col.shape:
				var debug_mesh: ArrayMesh = col.shape.get_debug_mesh()
				if debug_mesh:
					var world_box: AABB = col.global_transform * debug_mesh.get_aabb()
					combined_aabb = world_box if not found_any else combined_aabb.merge(world_box)
					found_any = true

	if not found_any:
		return host.global_transform * fallback_aabb

	return combined_aabb
#endregion


#region Clump Mesh Generation
func _apply_visibility_settings() -> void:
	if visibility_max_distance > 0.0:
		visibility_range_end = visibility_max_distance
		visibility_range_end_margin = visibility_fade_margin
		visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	else:
		visibility_range_end = 0.0


func _build_clump_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	if cross_planes:
		_append_vertical_quad(vertices, normals, uvs, indices, Basis(Vector3.UP, deg_to_rad(45.0)), blade_base_size)
		_append_vertical_quad(vertices, normals, uvs, indices, Basis(Vector3.UP, deg_to_rad(-45.0)), blade_base_size)
	else:
		_append_vertical_quad(vertices, normals, uvs, indices, Basis.IDENTITY, blade_base_size)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if grass_material:
		arr_mesh.surface_set_material(0, grass_material)
	return arr_mesh


func _append_vertical_quad(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	basis: Basis,
	size: Vector2
) -> void:
	var half_w: float = size.x * 0.5
	var h: float = size.y
	var base_idx: int = vertices.size()

	var v0: Vector3 = basis * Vector3(-half_w, 0.0, 0.0)
	var v1: Vector3 = basis * Vector3(half_w, 0.0, 0.0)
	var v2: Vector3 = basis * Vector3(half_w, h, 0.0)
	var v3: Vector3 = basis * Vector3(-half_w, h, 0.0)

	vertices.append_array([v0, v1, v2, v3])
	normals.append_array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	uvs.append_array([
		Vector2(0.0, 1.0),
		Vector2(1.0, 1.0),
		Vector2(1.0, 0.0),
		Vector2(0.0, 0.0)
	])

	indices.append_array([
		base_idx + 0, base_idx + 1, base_idx + 2,
		base_idx + 0, base_idx + 2, base_idx + 3
	])
#endregion
