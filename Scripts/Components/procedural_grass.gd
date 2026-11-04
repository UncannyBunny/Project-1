@tool
## Component that spawns density-based MultiMesh grass across a parent's AABB using 3 seeded noises and smooth transitions.
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

@export_group("Density & Noise Patches")
## Number of grass clump candidates per square meter (m^2) of the AABB area
@export_range(0.1, 50.0, 0.1) var grass_density: float = 5.5
## Base world scale of the 3 averaged noise layers (Macro, Medium, Micro)
@export_range(0.005, 0.5, 0.005) var noise_base_frequency: float = 0.04
## Center threshold (0..1) of the averaged noise where grass starts growing
@export_range(0.0, 1.0, 0.01) var noise_threshold: float = 0.42
## Width of the smooth transition margin around noise_threshold (feathers density and height at patch edges)
@export_range(0.01, 0.5, 0.01) var noise_transition_margin: float = 0.18

@export_group("Clump Mesh, Scale & Cross-Planes")
## Base Width (X) and Height (Y) of each grass plane in meters
@export var blade_base_size: Vector2 = Vector2(0.45, 0.45)
## Generates intersecting cross-planes. Plane B's angle is randomized per instance via cross_plane_angle_range!
@export var cross_planes: bool = true
## Range of relative angles (in degrees) between the two cross-planes (90 = perpendicular X, 45..135 = organic varied angles)
@export var cross_plane_angle_range: Vector2 = Vector2(55.0, 125.0)
## Slight random horizontal separation between the two planes so they don't form a harsh center X intersection
@export_range(0.0, 0.25, 0.01) var cross_plane_offset: float = 0.06
## Minimum scale at the outer edge of a noise patch (low density)
@export_range(0.05, 2.0, 0.05) var min_edge_scale: float = 0.35
## Maximum scale at the dense center of a noise patch (high density = taller grass)
@export_range(0.1, 4.0, 0.05) var max_core_scale: float = 1.45
## Controls how strongly density affects height (1.0 = linear, >1.0 = only very dense centers get super tall)
@export_range(0.25, 3.0, 0.05) var density_height_exponent: float = 1.2
## Additional random +/- scale jitter on top of the noise-driven scale
@export_range(0.0, 0.5, 0.01) var random_scale_jitter: float = 0.15
## Maximum ground slope angle (in degrees) where grass is allowed to grow
@export_range(0.0, 89.0, 1.0) var max_slope_degrees: float = 35.0
@export var grass_material: Material

@export_group("Target & Whitelist")
## Optional explicit body/mesh to read AABB from. If empty, uses get_parent().
@export var target_body: Node3D
## Whitelist of Node Groups allowed to grow grass. Any object above the floor NOT in these groups blocks grass!
@export var allowed_groups: Array[StringName] = [&"grass_surface"]
## If true, the parent/target_body itself is automatically treated as whitelisted
@export var allow_target_body_without_group: bool = true
@export var raycast_top_margin: float = 15.0
@export var raycast_bottom_margin: float = 2.0
@export var fallback_aabb: AABB = AABB(Vector3(-20.0, -2.0, -20.0), Vector3(40.0, 10.0, 40.0))

@export_group("Baked Data")
@export var baked_multimesh: MultiMesh:
	set(value):
		baked_multimesh = value
		multimesh = baked_multimesh


func _ready() -> void:
	# Disable MultiMesh-origin distance fade; distance culling is now handled per-blade in the shader!
	visibility_range_end = 0.0
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

	visibility_range_end = 0.0

	var host: Node3D = _get_target_host()
	var world_aabb: AABB = _compute_target_world_aabb(host)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# 1. Build 3 distinct FastNoiseLite generators from seed_value
	var noises: Array[FastNoiseLite] = _create_three_seeded_noises(seed_value)

	# 2. Calculate candidate count from AABB surface area (m^2) * grass_density
	var area_m2: float = maxf(world_aabb.size.x * world_aabb.size.z, 0.1)
	var candidate_count: int = clampi(int(roundf(area_m2 * grass_density)), 1, 250000)

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var max_slope_cos: float = cos(deg_to_rad(max_slope_degrees))

	var min_x: float = world_aabb.position.x
	var max_x: float = world_aabb.end.x
	var min_z: float = world_aabb.position.z
	var max_z: float = world_aabb.end.z

	var ray_start_y: float = world_aabb.end.y + raycast_top_margin
	var ray_end_y: float = world_aabb.position.y - raycast_bottom_margin

	var edge0: float = clampf(noise_threshold - noise_transition_margin, 0.0, 1.0)
	var edge1: float = clampf(noise_threshold + noise_transition_margin, 0.001, 1.0)

	var min_cp_rad: float = deg_to_rad(minf(cross_plane_angle_range.x, cross_plane_angle_range.y))
	var max_cp_rad: float = deg_to_rad(maxf(cross_plane_angle_range.x, cross_plane_angle_range.y))

	var valid_transforms: Array[Transform3D] = []
	var valid_custom_data: Array[Color] = []

	for i: int in range(candidate_count):
		var world_x: float = rng.randf_range(min_x, max_x)
		var world_z: float = rng.randf_range(min_z, max_z)

		# 3. Sample the 3 averaged noise textures (mapped from -1..1 to 0..1)
		var n0: float = (noises[0].get_noise_2d(world_x, world_z) + 1.0) * 0.5
		var n1: float = (noises[1].get_noise_2d(world_x, world_z) + 1.0) * 0.5
		var n2: float = (noises[2].get_noise_2d(world_x, world_z) + 1.0) * 0.5
		var n_avg: float = (n0 + n1 + n2) / 3.0

		# Smooth transition weight (0.0 below margin, 0.0->1.0 across margin, 1.0 in dense core)
		var density_weight: float = smoothstep(edge0, edge1, n_avg)
		if density_weight <= 0.001:
			continue

		# Probabilistic feathering in the smooth transition zone so edges thin out naturally
		if rng.randf() > density_weight:
			continue

		var ray_start := Vector3(world_x, ray_start_y, world_z)
		var ray_end := Vector3(world_x, ray_end_y, world_z)

		var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		query.collide_with_bodies = true
		query.collide_with_areas = false

		var hit: Dictionary = space_state.intersect_ray(query)
		if hit.is_empty():
			continue

		var collider: Object = hit.get("collider")
		if not (collider is Node):
			continue

		if not _is_collider_whitelisted(collider as Node, host):
			continue

		var hit_pos: Vector3 = hit["position"]
		var hit_normal: Vector3 = (hit["normal"] as Vector3).normalized()

		if hit_normal.dot(Vector3.UP) < max_slope_cos:
			continue

		var local_pos: Vector3 = to_local(hit_pos)
		var local_normal: Vector3 = (global_basis.inverse() * hit_normal).normalized()

		# 4. Size variation driven by density_weight (Denser areas = Taller/Larger grass)
		var height_curve_factor: float = pow(density_weight, density_height_exponent)
		var density_scale: float = lerpf(min_edge_scale, max_core_scale, height_curve_factor)
		var jitter: float = 1.0 + rng.randf_range(-random_scale_jitter, random_scale_jitter)
		var final_scale_xz: float = maxf(density_scale * jitter, 0.05)
		var final_scale_y: float = maxf(density_scale * (1.0 + (jitter - 1.0) * 1.25), 0.05)

		var yaw: float = rng.randf_range(0.0, TAU)
		var up_vec: Vector3 = Vector3.UP.lerp(local_normal, 0.65).normalized()
		var forward_vec := Vector3(sin(yaw), 0.0, cos(yaw))
		var right_vec: Vector3 = up_vec.cross(forward_vec).normalized()
		forward_vec = right_vec.cross(up_vec).normalized()

		var blade_basis := Basis(right_vec, up_vec, forward_vec).scaled(Vector3(final_scale_xz, final_scale_y, final_scale_xz))
		valid_transforms.append(Transform3D(blade_basis, local_pos))

		# Random relative rotation angle (in radians) for the second cross-plane
		var cross_angle_rad: float = rng.randf_range(min_cp_rad, max_cp_rad)

		valid_custom_data.append(Color(
			rng.randf(),      # R: Random color variation (0..1)
			rng.randf(),      # G: Random wind phase offset (0..1)
			density_weight,   # B: Smooth density factor (0..1)
			cross_angle_rad   # A: Relative angle (radians) for Plane B of the cross-plane
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


#region Three Seeded Noises
func _create_three_seeded_noises(base_seed: int) -> Array[FastNoiseLite]:
	# Noise 1: Large macro meadows & clearings (Simplex Smooth)
	var n1 := FastNoiseLite.new()
	n1.seed = base_seed
	n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n1.frequency = noise_base_frequency
	n1.fractal_octaves = 2

	# Noise 2: Medium organic clusters (Perlin)
	var n2 := FastNoiseLite.new()
	n2.seed = base_seed + 1013
	n2.noise_type = FastNoiseLite.TYPE_PERLIN
	n2.frequency = noise_base_frequency * 2.15
	n2.fractal_octaves = 2

	# Noise 3: Fine local tufts & variation (Cellular / Simplex)
	var n3 := FastNoiseLite.new()
	n3.seed = base_seed + 2027
	n3.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n3.frequency = noise_base_frequency * 4.3
	n3.fractal_octaves = 1

	return [n1, n2, n3]
#endregion


#region AABB & Whitelist Helpers
func _get_target_host() -> Node3D:
	if is_instance_valid(target_body):
		return target_body
	return get_parent() as Node3D


func _is_collider_whitelisted(collider_node: Node, host: Node3D) -> bool:
	if allow_target_body_without_group and is_instance_valid(host):
		if collider_node == host or host.is_ancestor_of(collider_node):
			return true

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
func _build_clump_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	# Plane 0: Base plane (COLOR.r = 0.0 means fixed at 0 deg)
	_append_vertical_quad(
		vertices, normals, uvs, colors, indices,
		Vector3(0.0, 0.0, -cross_plane_offset * 0.5),
		blade_base_size,
		0.0
	)

	if cross_planes:
		# Plane 1: Second plane (COLOR.r = 1.0 tells the vertex shader to rotate it by INSTANCE_CUSTOM.a!)
		_append_vertical_quad(
			vertices, normals, uvs, colors, indices,
			Vector3(0.0, 0.0, cross_plane_offset * 0.5),
			blade_base_size,
			1.0
		)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
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
	colors: PackedColorArray,
	indices: PackedInt32Array,
	offset: Vector3,
	size: Vector2,
	plane_id: float
) -> void:
	var half_w: float = size.x * 0.5
	var h: float = size.y
	var base_idx: int = vertices.size()

	# Slight upward curve/tilt (0.08 * h on Z) so planes don't look dead-vertical from directly above!
	var top_tilt_z: float = h * 0.12 * (1.0 if plane_id < 0.5 else -1.0)

	var v0: Vector3 = offset + Vector3(-half_w, 0.0, 0.0)
	var v1: Vector3 = offset + Vector3(half_w, 0.0, 0.0)
	var v2: Vector3 = offset + Vector3(half_w, h, top_tilt_z)
	var v3: Vector3 = offset + Vector3(-half_w, h, top_tilt_z)

	vertices.append_array([v0, v1, v2, v3])
	normals.append_array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	uvs.append_array([
		Vector2(0.0, 1.0),
		Vector2(1.0, 1.0),
		Vector2(1.0, 0.0),
		Vector2(0.0, 0.0)
	])
	var col := Color(plane_id, 0.0, 0.0, 1.0)
	colors.append_array([col, col, col, col])

	indices.append_array([
		base_idx + 0, base_idx + 1, base_idx + 2,
		base_idx + 0, base_idx + 2, base_idx + 3
	])
#endregion
