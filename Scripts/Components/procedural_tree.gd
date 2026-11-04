@tool
## Procedural tree generator that builds multi-trunk/splitting trees (Surface 0), branch planes (Surface 1), and a child trunk collider.
class_name ProceduralTree extends MeshInstance3D

@export_group("Generator Actions")
@export_tool_button("Generate Tree (Keep Seed)", "MeshInstance3D") var btn_bake: Callable:
	get:
		return bake_tree
@export_tool_button("Randomize Seed & Generate", "RandomNumberGenerator") var btn_randomize: Callable:
	get:
		return randomize_and_bake

@export var seed_value: int = 12345:
	set(value):
		seed_value = value
		if Engine.is_editor_hint() and auto_regenerate and is_inside_tree():
			bake_tree()
@export var auto_regenerate: bool = true

@export_group("Trunk Settings")
@export_range(1.0, 30.0, 0.1) var trunk_height: float = 8.0
@export_range(0.05, 2.0, 0.01) var trunk_radius: float = 0.35
@export_range(3, 32, 1) var trunk_segments: int = 14
@export_range(4, 16, 1) var trunk_sides: int = 7
## How much the trunk wanders/bends horizontally per segment
@export_range(0.0, 2.0, 0.01) var trunk_crookedness: float = 0.25
## Controls trunk thickness from base (X=0.0) to tip (X=1.0). Defaults to linear taper if empty.
@export var trunk_taper_curve: Curve
@export var trunk_uv_scale: Vector2 = Vector2(1.0, 4.0)
@export var trunk_material: Material

@export_group("Trunk Splits & Multi-Trunk")
## Number of main trunks emerging from the ground (1 = single trunk, 2+ = multi-stem cluster)
@export_range(1, 5, 1) var base_trunk_count: int = 1
## Outward tilt angle in degrees when base_trunk_count > 1
@export_range(0.0, 45.0, 1.0) var base_trunk_spread: float = 12.0
## Number of secondary trunk forks/splits that branch off along the trunk
@export_range(0, 12, 1) var split_count: int = 2
## X = Normalized height on trunk (0..1), Y = Probability of splitting at this height
@export var split_height_curve: Curve
## Outward fork angle range (in degrees) when a trunk splits
@export var split_angle_range: Vector2 = Vector2(20.0, 42.0)
## How much the parent trunk bends away in the opposite direction at a split point (0 = none, 0.5 = symmetric Y-fork)
@export_range(0.0, 1.0, 0.05) var parent_fork_deflection: float = 0.35
## Length multiplier for split trunks relative to remaining tree height
@export_range(0.3, 1.2, 0.05) var split_length_factor: float = 0.85
## Radius multiplier for split trunks relative to the parent trunk's radius at the split point
@export_range(0.3, 1.0, 0.05) var split_radius_factor: float = 0.75

@export_group("Branch Placement & Bias")
@export_range(0, 500, 1) var branch_count: int = 65
## Minimum normalized height (0.0 to 1.0) where branches can start spawning
@export_range(0.0, 1.0, 0.01) var min_branch_height: float = 0.2
## Maximum normalized height (0.0 to 1.0) where branches can spawn
@export_range(0.0, 1.0, 0.01) var max_branch_height: float = 0.98
## X = Height on tree (0..1), Y = Spawn density probability (0..1). Leave empty for uniform placement.
@export var branch_density_curve: Curve
## Uses Golden Angle phyllotaxis so branches wrap evenly around the trunk without bald spots
@export var use_golden_angle: bool = true
## Random radial jitter (in degrees) added to the branch angle around the trunk
@export_range(0.0, 180.0, 1.0) var radial_angle_jitter: float = 25.0

@export_group("Branch Size & Rotation")
## Base width (X) and length (Y) of each branch plane in meters
@export var branch_base_size: Vector2 = Vector2(1.6, 1.8)
## Random +/- scale variation per individual branch (e.g. 0.2 = +/- 20%)
@export_range(0.0, 0.8, 0.01) var branch_size_randomness: float = 0.2
## X = Height on tree (0..1), Y = Scale multiplier. Great for making middle or bottom branches larger.
@export var branch_scale_curve: Curve
## Vertical tilt in degrees (0 = horizontal like a pine, + = angled up, - = drooping down)
@export var pitch_angle_range: Vector2 = Vector2(-15.0, 5.0)
## Optional X = Height on tree (0..1), Y = Additional pitch offset (-1..1 mapped to +/- 45 deg)
@export var pitch_height_bias_curve: Curve
## Random twist/roll around the branch's length axis in degrees
@export var roll_angle_range: Vector2 = Vector2(-12.0, 12.0)
## How far inside the trunk radius the branch quad starts so its base never floats
@export_range(0.0, 1.0, 0.05) var trunk_embed_factor: float = 0.35
## Generates an intersecting V-crossed quad per branch so planes have volume from side angles
@export var cross_planes: bool = false
@export_range(0.0, 90.0, 1.0) var cross_plane_angle: float = 35.0
@export var branch_material: Material

@export_group("Collision Settings")
## Automatically generates a StaticBody3D + CollisionShape3D child matching the trunk geometry
@export var generate_collider: bool = true
@export_flags_3d_physics var collision_layer: int = 1
@export_flags_3d_physics var collision_mask: int = 1

@export_group("Baked Data")
## Stored on the root node so instanced scenes keep their generated mesh at runtime
@export var baked_tree_mesh: ArrayMesh:
	set(value):
		baked_tree_mesh = value
		mesh = baked_tree_mesh
## Stored on the root node so instanced scenes keep their trunk collision shape at runtime
@export var baked_trunk_collision: ConcavePolygonShape3D:
	set(value):
		baked_trunk_collision = value
		if is_inside_tree():
			_sync_collider_nodes()


func _ready() -> void:
	if baked_tree_mesh:
		mesh = baked_tree_mesh
		_sync_collider_nodes()
	elif Engine.is_editor_hint():
		bake_tree()


func randomize_and_bake() -> void:
	seed_value = randi()
	bake_tree()


func bake_tree() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# 1. Generate all Trunk Branches (Base Trunks + Weighted Splits)
	var trunks: Array[Dictionary] = _generate_all_trunks(rng)

	var new_mesh := ArrayMesh.new()

	# 2. Build Surface 0: Combined Trunk Tubes
	var trunk_arrays: Array = _build_all_trunks_surface(trunks)
	var trunk_verts: PackedVector3Array = trunk_arrays[Mesh.ARRAY_VERTEX]
	if not trunk_verts.is_empty():
		new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, trunk_arrays)
		if trunk_material:
			new_mesh.surface_set_material(0, trunk_material)

	# 3. Build Surface 1: Biased Branch Planes distributed across all trunks
	if branch_count > 0 and not trunks.is_empty():
		var branch_arrays: Array = _build_branches_surface(rng, trunks)
		if not (branch_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, branch_arrays)
			var branch_surf_idx: int = new_mesh.get_surface_count() - 1
			if branch_material:
				new_mesh.surface_set_material(branch_surf_idx, branch_material)

	baked_tree_mesh = new_mesh

	# 4. Bake Trunk Collision Shape from Surface 0 triangles
	if generate_collider and not trunk_verts.is_empty():
		baked_trunk_collision = _build_concave_collision_from_arrays(trunk_arrays)
	else:
		baked_trunk_collision = null

	_sync_collider_nodes()
	notify_property_list_changed()


#region Multi-Trunk & Split Curve Generation
func _generate_all_trunks(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var trunks: Array[Dictionary] = []

	# 1. Generate Base Trunks starting at (0, 0, 0)
	var base_count: int = maxi(base_trunk_count, 1)
	for i: int in range(base_count):
		var initial_dir := Vector3.UP
		if base_count > 1:
			var angle: float = (TAU * float(i) / float(base_count)) + rng.randf_range(-0.25, 0.25)
			var spread_rad: float = deg_to_rad(base_trunk_spread * rng.randf_range(0.8, 1.2))
			initial_dir = Vector3(
				cos(angle) * sin(spread_rad),
				cos(spread_rad),
				sin(angle) * sin(spread_rad)
			).normalized()

		var base_trunk: Dictionary = _create_trunk_chain(
			rng,
			Vector3.ZERO,
			initial_dir,
			trunk_height,
			trunk_radius,
			trunk_segments,
			0.0,
			1.0
		)
		base_trunk["parent_idx"] = -1
		base_trunk["attach_ring_idx"] = -1
		trunks.append(base_trunk)

	# 2. Sample and SORT split heights bottom-to-top so lower deflections happen BEFORE upper splits spawn!
	var split_heights := PackedFloat32Array()
	split_heights.resize(split_count)
	for s: int in range(split_count):
		split_heights[s] = _sample_curve_weighted(rng, split_height_curve, 0.12, 0.85)
	split_heights.sort()

	# 3. Generate Split Trunks in bottom-to-top order
	for s: int in range(split_count):
		var split_t: float = split_heights[s]

		# Find eligible parent trunks that exist at height split_t
		var eligible_indices: Array[int] = []
		for idx: int in range(trunks.size()):
			var tr: Dictionary = trunks[idx]
			if split_t >= float(tr["t_start"]) + 0.08 and split_t <= float(tr["t_end"]) - 0.12:
				eligible_indices.append(idx)

		var parent_idx: int = eligible_indices[rng.randi() % eligible_indices.size()] if not eligible_indices.is_empty() else 0
		var parent_trunk: Dictionary = trunks[parent_idx]

		var local_t: float = remap(split_t, float(parent_trunk["t_start"]), float(parent_trunk["t_end"]), 0.0, 1.0)
		local_t = clampf(local_t, 0.1, 0.85)

		var parent_points: PackedVector3Array = parent_trunk["points"]
		var split_ring_idx: int = clampi(int(roundf(local_t * float(parent_points.size() - 1))), 1, parent_points.size() - 2)
		var actual_local_t: float = float(split_ring_idx) / float(parent_points.size() - 1)
		var actual_tree_t: float = lerpf(float(parent_trunk["t_start"]), float(parent_trunk["t_end"]), actual_local_t)

		var split_origin: Vector3 = parent_points[split_ring_idx]
		var parent_tangent: Vector3 = (parent_points[split_ring_idx + 1] - parent_points[split_ring_idx - 1]).normalized()
		var parent_r_at_split: float = _evaluate_radius_on_trunk(parent_trunk, actual_local_t)

		# Compute an outward fork axis & angle
		var radial_angle: float = float(s) * 2.3999632 + rng.randf_range(-0.6, 0.6)
		var horiz_out := Vector3(cos(radial_angle), 0.0, sin(radial_angle))
		var fork_axis: Vector3 = parent_tangent.cross(horiz_out).normalized()
		if fork_axis.length_squared() < 0.001:
			fork_axis = Vector3.RIGHT

		var min_ang: float = minf(split_angle_range.x, split_angle_range.y)
		var max_ang: float = maxf(split_angle_range.x, split_angle_range.y)
		var fork_angle_rad: float = deg_to_rad(rng.randf_range(min_ang, max_ang))

		# Deflect upper points of parent trunk (and any already-attached upper child trunks)
		if parent_fork_deflection > 0.001:
			var deflect_basis := Basis(fork_axis, -fork_angle_rad * parent_fork_deflection)
			for p_idx: int in range(split_ring_idx + 1, parent_points.size()):
				var offset: Vector3 = parent_points[p_idx] - split_origin
				parent_points[p_idx] = split_origin + deflect_basis * offset
			parent_trunk["points"] = parent_points
			parent_trunk["tangents"] = _compute_tangents(parent_points)

			# Also deflect any existing child trunks attached to this parent above split_ring_idx
			_deflect_dependent_trunks(trunks, parent_idx, split_ring_idx, split_origin, deflect_basis)

		var child_dir: Vector3 = (Basis(fork_axis, fork_angle_rad) * parent_tangent).normalized()
		var remaining_height: float = trunk_height * (1.0 - actual_tree_t) * split_length_factor * rng.randf_range(0.85, 1.15)
		var child_segs: int = maxi(int(roundf(float(trunk_segments) * (1.0 - actual_tree_t))), 4)
		var child_base_r: float = parent_r_at_split * split_radius_factor
		var child_t_end: float = clampf(actual_tree_t + (1.0 - actual_tree_t) * split_length_factor, actual_tree_t + 0.1, 1.0)

		var child_trunk: Dictionary = _create_trunk_chain(
			rng,
			split_origin,
			child_dir,
			remaining_height,
			child_base_r,
			child_segs,
			actual_tree_t,
			child_t_end
		)
		child_trunk["parent_idx"] = parent_idx
		child_trunk["attach_ring_idx"] = split_ring_idx
		trunks.append(child_trunk)

	return trunks


## Recursively rotates any child trunks attached above split_ring_idx when their parent trunk bends
func _deflect_dependent_trunks(
	trunks: Array[Dictionary],
	parent_idx: int,
	split_ring_idx: int,
	pivot: Vector3,
	deflect_basis: Basis
) -> void:
	for i: int in range(trunks.size()):
		var tr: Dictionary = trunks[i]
		if int(tr.get("parent_idx", -1)) == parent_idx and int(tr.get("attach_ring_idx", -1)) > split_ring_idx:
			var pts: PackedVector3Array = tr["points"]
			for p_idx: int in range(pts.size()):
				pts[p_idx] = pivot + deflect_basis * (pts[p_idx] - pivot)
			tr["points"] = pts
			tr["tangents"] = _compute_tangents(pts)
			# Recursively deflect sub-splits attached to this child trunk
			_deflect_dependent_trunks(trunks, i, -1, pivot, deflect_basis)


func _create_trunk_chain(
	rng: RandomNumberGenerator,
	start_pos: Vector3,
	initial_dir: Vector3,
	length: float,
	base_radius: float,
	seg_count: int,
	t_start: float,
	t_end: float
) -> Dictionary:
	var points := PackedVector3Array()
	var step_len: float = length / float(maxi(seg_count, 1))
	var current_pos: Vector3 = start_pos
	var current_dir: Vector3 = initial_dir.normalized()
	var wander := Vector3.ZERO

	points.append(current_pos)
	for i: int in range(1, seg_count + 1):
		var local_ratio: float = float(i) / float(seg_count)
		wander += Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-0.2, 0.35),
			rng.randf_range(-1.0, 1.0)
		) * (trunk_crookedness * 0.35)
		wander = wander.limit_length(trunk_crookedness * 0.6)

		var sway_weight: float = smoothstep(0.0, 0.25, local_ratio)
		# Gently bias upward so angled splits curve toward the sky like real tree limbs
		var sky_pull: Vector3 = Vector3.UP * 0.18
		current_dir = (current_dir + wander * sway_weight + sky_pull).normalized()

		current_pos += current_dir * step_len
		points.append(current_pos)

	return {
		"points": points,
		"tangents": _compute_tangents(points),
		"base_radius": base_radius,
		"t_start": t_start,
		"t_end": t_end,
		"length": length
	}


func _compute_tangents(points: PackedVector3Array) -> PackedVector3Array:
	var count: int = points.size()
	var tangents := PackedVector3Array()
	tangents.resize(count)
	for i: int in range(count):
		if i == 0:
			tangents[i] = (points[1] - points[0]).normalized()
		elif i == count - 1:
			tangents[i] = (points[i] - points[i - 1]).normalized()
		else:
			tangents[i] = (points[i + 1] - points[i - 1]).normalized()
	return tangents


func _evaluate_radius_on_trunk(trunk: Dictionary, local_t: float) -> float:
	var base_r: float = float(trunk["base_radius"])
	var tree_t: float = lerpf(float(trunk["t_start"]), float(trunk["t_end"]), clampf(local_t, 0.0, 1.0))
	if trunk_taper_curve:
		var start_sample: float = maxf(trunk_taper_curve.sample_baked(clampf(float(trunk["t_start"]), 0.0, 1.0)), 0.05)
		var cur_sample: float = maxf(trunk_taper_curve.sample_baked(clampf(tree_t, 0.0, 1.0)), 0.02)
		return base_r * (cur_sample / start_sample) * lerpf(1.0, 0.25, local_t)
	return base_r * lerpf(1.0, 0.12, clampf(local_t, 0.0, 1.0))


func _build_all_trunks_surface(trunks: Array[Dictionary]) -> Array:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var ring_stride: int = trunk_sides + 1

	for trunk: Dictionary in trunks:
		var points: PackedVector3Array = trunk["points"]
		var tangents: PackedVector3Array = trunk["tangents"]
		var ring_count: int = points.size()
		var vert_offset: int = vertices.size()
		var prev_binormal := Vector3.ZERO

		for i: int in range(ring_count):
			var local_t: float = float(i) / float(maxi(ring_count - 1, 1))
			var tree_t: float = lerpf(float(trunk["t_start"]), float(trunk["t_end"]), local_t)
			var p: Vector3 = points[i]
			var tangent: Vector3 = tangents[i]
			var r: float = _evaluate_radius_on_trunk(trunk, local_t)

			var normal: Vector3
			if prev_binormal == Vector3.ZERO:
				normal = tangent.cross(Vector3.FORWARD)
				if normal.length_squared() < 0.001:
					normal = tangent.cross(Vector3.RIGHT)
				normal = normal.normalized()
			else:
				normal = prev_binormal.cross(tangent).normalized()

			var binormal: Vector3 = tangent.cross(normal).normalized()
			prev_binormal = binormal

			for j: int in range(ring_stride):
				var u_ratio: float = float(j) / float(trunk_sides)
				var angle: float = TAU * u_ratio
				var dir: Vector3 = (cos(angle) * normal + sin(angle) * binormal).normalized()
				vertices.append(p + dir * r)
				normals.append(dir)
				uvs.append(Vector2(u_ratio * trunk_uv_scale.x, tree_t * trunk_uv_scale.y))

		for i: int in range(ring_count - 1):
			var base0: int = vert_offset + i * ring_stride
			var base1: int = vert_offset + (i + 1) * ring_stride
			for j: int in range(trunk_sides):
				indices.append(base0 + j)
				indices.append(base1 + j)
				indices.append(base1 + j + 1)

				indices.append(base0 + j)
				indices.append(base1 + j + 1)
				indices.append(base0 + j + 1)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
#endregion


#region Branch Sampling & Plane Generation
func _sample_curve_weighted(rng: RandomNumberGenerator, curve: Curve, low: float, high: float) -> float:
	var min_v: float = minf(low, high)
	var max_v: float = maxf(low, high)
	if not curve:
		return rng.randf_range(min_v, max_v)

	for _attempt: int in range(32):
		var candidate_t: float = rng.randf_range(min_v, max_v)
		var prob: float = clampf(curve.sample_baked(candidate_t), 0.0, 1.0)
		if rng.randf() <= prob:
			return candidate_t
	return rng.randf_range(min_v, max_v)


func _evaluate_trunk_dict_at(trunk: Dictionary, local_t: float) -> Dictionary:
	var points: PackedVector3Array = trunk["points"]
	var tangents: PackedVector3Array = trunk["tangents"]
	var max_idx: int = points.size() - 1
	var scaled_t: float = clampf(local_t, 0.0, 1.0) * float(max_idx)
	var idx0: int = clampi(int(floorf(scaled_t)), 0, max_idx)
	var idx1: int = mini(idx0 + 1, max_idx)
	var frac: float = scaled_t - float(idx0)

	return {
		"position": points[idx0].lerp(points[idx1], frac),
		"tangent": tangents[idx0].lerp(tangents[idx1], frac).normalized(),
		"radius": _evaluate_radius_on_trunk(trunk, local_t)
	}


func _build_branches_surface(rng: RandomNumberGenerator, trunks: Array[Dictionary]) -> Array:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var heights := PackedFloat32Array()
	heights.resize(branch_count)
	for i: int in range(branch_count):
		heights[i] = _sample_curve_weighted(rng, branch_density_curve, min_branch_height, max_branch_height)
	heights.sort()

	const GOLDEN_ANGLE: float = 2.39996322972865332

	for i: int in range(branch_count):
		var tree_t: float = heights[i]

		# Pick a trunk that spans across tree_t (weighted by trunk length)
		var valid_trunks: Array[Dictionary] = []
		var total_weight: float = 0.0
		for tr: Dictionary in trunks:
			if tree_t >= float(tr["t_start"]) and tree_t <= float(tr["t_end"]):
				valid_trunks.append(tr)
				total_weight += float(tr["length"])

		var chosen_trunk: Dictionary = trunks[0]
		if not valid_trunks.is_empty():
			var pick: float = rng.randf() * total_weight
			var accum: float = 0.0
			for tr: Dictionary in valid_trunks:
				accum += float(tr["length"])
				if pick <= accum:
					chosen_trunk = tr
					break

		var span: float = maxf(float(chosen_trunk["t_end"]) - float(chosen_trunk["t_start"]), 0.001)
		var local_t: float = clampf((tree_t - float(chosen_trunk["t_start"])) / span, 0.0, 1.0)

		var trunk_sample: Dictionary = _evaluate_trunk_dict_at(chosen_trunk, local_t)
		var trunk_pos: Vector3 = trunk_sample["position"]
		var trunk_up: Vector3 = trunk_sample["tangent"]
		var current_radius: float = trunk_sample["radius"]

		var radial_angle: float = 0.0
		if use_golden_angle:
			radial_angle = float(i) * GOLDEN_ANGLE + deg_to_rad(rng.randf_range(-radial_angle_jitter, radial_angle_jitter))
		else:
			radial_angle = rng.randf_range(0.0, TAU)

		var raw_out := Vector3(cos(radial_angle), 0.0, sin(radial_angle))
		var outward: Vector3 = (raw_out - trunk_up * raw_out.dot(trunk_up)).normalized()
		if outward.length_squared() < 0.001:
			outward = trunk_up.cross(Vector3.RIGHT).normalized()
		var side: Vector3 = trunk_up.cross(outward).normalized()

		var branch_basis := Basis(side, trunk_up, outward)

		var min_pitch: float = minf(pitch_angle_range.x, pitch_angle_range.y)
		var max_pitch: float = maxf(pitch_angle_range.x, pitch_angle_range.y)
		var pitch_deg: float = rng.randf_range(min_pitch, max_pitch)
		if pitch_height_bias_curve:
			pitch_deg += pitch_height_bias_curve.sample_baked(tree_t) * 45.0

		var roll_deg: float = rng.randf_range(
			minf(roll_angle_range.x, roll_angle_range.y),
			maxf(roll_angle_range.x, roll_angle_range.y)
		)
		branch_basis = branch_basis * Basis.from_euler(Vector3(deg_to_rad(-pitch_deg), 0.0, deg_to_rad(roll_deg)))

		var curve_scale: float = branch_scale_curve.sample_baked(tree_t) if branch_scale_curve else lerpf(1.0, 0.35, tree_t)
		var rand_scale: float = 1.0 + rng.randf_range(-branch_size_randomness, branch_size_randomness)
		var final_size: Vector2 = branch_base_size * maxf(curve_scale * rand_scale, 0.05)

		var attach_pos: Vector3 = trunk_pos + outward * (current_radius * (1.0 - trunk_embed_factor))

		if cross_planes:
			var tilt_rad: float = deg_to_rad(cross_plane_angle)
			_append_branch_quad(vertices, normals, uvs, indices, attach_pos, branch_basis * Basis(Vector3.BACK, tilt_rad), final_size)
			_append_branch_quad(vertices, normals, uvs, indices, attach_pos, branch_basis * Basis(Vector3.BACK, -tilt_rad), final_size)
		else:
			_append_branch_quad(vertices, normals, uvs, indices, attach_pos, branch_basis, final_size)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func _append_branch_quad(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	origin: Vector3,
	basis: Basis,
	size: Vector2
) -> void:
	var half_w: float = size.x * 0.5
	var length: float = size.y
	var base_idx: int = vertices.size()

	var v0: Vector3 = origin + basis * Vector3(-half_w, 0.0, 0.0)
	var v1: Vector3 = origin + basis * Vector3(half_w, 0.0, 0.0)
	var v2: Vector3 = origin + basis * Vector3(half_w, 0.0, length)
	var v3: Vector3 = origin + basis * Vector3(-half_w, 0.0, length)

	var quad_normal: Vector3 = (basis.y + basis.z * 0.35).normalized()

	vertices.append_array([v0, v1, v2, v3])
	normals.append_array([quad_normal, quad_normal, quad_normal, quad_normal])
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


#region Trunk Collider Generation & Node Sync
func _build_concave_collision_from_arrays(trunk_arrays: Array) -> ConcavePolygonShape3D:
	var verts: PackedVector3Array = trunk_arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = trunk_arrays[Mesh.ARRAY_INDEX]
	var faces := PackedVector3Array()
	faces.resize(indices.size())

	for i: int in range(indices.size()):
		faces[i] = verts[indices[i]]

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape


func _sync_collider_nodes() -> void:
	var body_node := get_node_or_null("TrunkStaticBody3D") as StaticBody3D
	if not generate_collider or not baked_trunk_collision:
		if is_instance_valid(body_node):
			body_node.queue_free()
		return

	if not is_instance_valid(body_node):
		body_node = StaticBody3D.new()
		body_node.name = "TrunkStaticBody3D"
		add_child(body_node)

	body_node.collision_layer = collision_layer
	body_node.collision_mask = collision_mask

	var col_shape := body_node.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not is_instance_valid(col_shape):
		col_shape = CollisionShape3D.new()
		col_shape.name = "CollisionShape3D"
		body_node.add_child(col_shape)

	col_shape.shape = baked_trunk_collision

	# If editing the ProceduralTree scene directly in the editor, set owner so it's visible in the Scene tree
	if Engine.is_editor_hint() and is_inside_tree():
		var edited_root: Node = get_tree().edited_scene_root
		if edited_root == self:
			body_node.owner = edited_root
			col_shape.owner = edited_root
#endregion
