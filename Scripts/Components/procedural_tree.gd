@tool
## Procedural tree generator that builds a 2-surface ArrayMesh (Surface 0: Trunk, Surface 1: Branch Planes).
class_name ProceduralTree extends MeshInstance3D

@export_group("Generator Actions")
@export_tool_button("Generate Tree (Keep Seed)", "MeshInstance3D") var btn_bake: Callable = bake_tree
@export_tool_button("Randomize Seed & Generate", "RandomNumberGenerator") var btn_randomize: Callable = randomize_and_bake

@export var seed_value: int = 12345:
	set(value):
		seed_value = value
		if Engine.is_editor_hint() and auto_regenerate:
			bake_tree()
@export var auto_regenerate: bool = true

@export_group("Trunk Settings")
@export_range(1.0, 30.0, 0.1) var trunk_height: float = 8.0
@export_range(0.05, 2.0, 0.01) var trunk_radius: float = 0.35
@export_range(3, 32, 1) var trunk_segments: int = 12
@export_range(4, 16, 1) var trunk_sides: int = 7
## How much the trunk wanders/bends horizontally per segment
@export_range(0.0, 2.0, 0.01) var trunk_crookedness: float = 0.25
## Controls trunk thickness from base (X=0.0) to tip (X=1.0). Defaults to linear taper if empty.
@export var trunk_taper_curve: Curve
@export var trunk_uv_scale: Vector2 = Vector2(1.0, 4.0)
@export var trunk_material: Material

@export_group("Branch Placement & Bias")
@export_range(0, 500, 1) var branch_count: int = 65
## Minimum normalized height (0.0 to 1.0) where branches can start spawning
@export_range(0.0, 1.0, 0.01) var min_branch_height: float = 0.2
## Maximum normalized height (0.0 to 1.0) where branches can spawn
@export_range(0.0, 1.0, 0.01) var max_branch_height: float = 0.98
## X = Height on trunk (0..1), Y = Spawn density probability (0..1). Leave empty for uniform placement.
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
## X = Height on trunk (0..1), Y = Scale multiplier. Great for making middle or bottom branches larger.
@export var branch_scale_curve: Curve
## Vertical tilt in degrees (0 = horizontal like a pine, + = angled up, - = drooping down)
@export var pitch_angle_range: Vector2 = Vector2(-15.0, 5.0)
## Optional X = Height on trunk (0..1), Y = Additional pitch offset (-1..1 mapped to +/- 45 deg)
@export var pitch_height_bias_curve: Curve
## Random twist/roll around the branch's length axis in degrees
@export var roll_angle_range: Vector2 = Vector2(-12.0, 12.0)
## How far inside the trunk radius the branch quad starts so its base never floats
@export_range(0.0, 1.0, 0.05) var trunk_embed_factor: float = 0.35
## Generates an intersecting V-crossed quad per branch so planes have volume from side angles
@export var cross_planes: bool = false
@export_range(0.0, 90.0, 1.0) var cross_plane_angle: float = 35.0
@export var branch_material: Material

@export_group("Baked Data")
## Stored on the root node so instanced scenes keep their generated mesh at runtime
@export var baked_tree_mesh: ArrayMesh:
	set(value):
		baked_tree_mesh = value
		mesh = baked_tree_mesh


func _ready() -> void:
	if baked_tree_mesh:
		mesh = baked_tree_mesh
	elif Engine.is_editor_hint():
		bake_tree()


func randomize_and_bake() -> void:
	seed_value = randi()
	bake_tree()


func bake_tree() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# 1. Generate the 3D Trunk Curve Points & Tangents
	var trunk_points: PackedVector3Array = _generate_trunk_curve(rng)
	var trunk_tangents: PackedVector3Array = _compute_tangents(trunk_points)

	var new_mesh := ArrayMesh.new()

	# 2. Build Surface 0: Trunk Tube Mesh
	var trunk_arrays: Array = _build_trunk_surface(trunk_points, trunk_tangents)
	new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, trunk_arrays)
	if trunk_material:
		new_mesh.surface_set_material(0, trunk_material)

	# 3. Build Surface 1: Biased Branch Planes
	if branch_count > 0:
		var branch_arrays: Array = _build_branches_surface(rng, trunk_points, trunk_tangents)
		if not (branch_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, branch_arrays)
			if branch_material:
				new_mesh.surface_set_material(1, branch_material)

	baked_tree_mesh = new_mesh
	notify_property_list_changed()


#region Trunk Curve & Tube Generation
func _generate_trunk_curve(rng: RandomNumberGenerator) -> PackedVector3Array:
	var points := PackedVector3Array()
	var step_y: float = trunk_height / float(maxi(trunk_segments, 1))
	var current_pos := Vector3.ZERO
	var wander_dir := Vector2.ZERO

	points.append(current_pos)
	for i: int in range(1, trunk_segments + 1):
		var height_ratio: float = float(i) / float(trunk_segments)
		# Smoothly drift the wander direction so the trunk forms an S-curve or natural lean
		wander_dir += Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * trunk_crookedness
		wander_dir = wander_dir.limit_length(trunk_crookedness * 1.5)
		
		# Reduce crookedness right at the base so the roots stay planted near (0,0,0)
		var sway_weight: float = smoothstep(0.0, 0.3, height_ratio)
		current_pos.x += wander_dir.x * sway_weight
		current_pos.z += wander_dir.y * sway_weight
		current_pos.y = step_y * float(i)
		points.append(current_pos)

	return points


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


func _get_trunk_radius_at(t: float) -> float:
	if trunk_taper_curve:
		return trunk_radius * maxf(trunk_taper_curve.sample_baked(clampf(t, 0.0, 1.0)), 0.02)
	# Default natural tree taper from 100% at base to 8% at tip
	return trunk_radius * lerpf(1.0, 0.08, clampf(t, 0.0, 1.0))


func _build_trunk_surface(points: PackedVector3Array, tangents: PackedVector3Array) -> Array:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var ring_count: int = points.size()
	var ring_stride: int = trunk_sides + 1 # +1 duplicate seam vertex for clean UV wrapping

	var prev_binormal := Vector3.ZERO

	for i: int in range(ring_count):
		var t: float = float(i) / float(maxi(ring_count - 1, 1))
		var p: Vector3 = points[i]
		var tangent: Vector3 = tangents[i]
		var r: float = _get_trunk_radius_at(t)

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
			uvs.append(Vector2(u_ratio * trunk_uv_scale.x, t * trunk_uv_scale.y))

	for i: int in range(ring_count - 1):
		var base0: int = i * ring_stride
		var base1: int = (i + 1) * ring_stride
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
func _sample_biased_height(rng: RandomNumberGenerator) -> float:
	var low: float = minf(min_branch_height, max_branch_height)
	var high: float = maxf(min_branch_height, max_branch_height)
	if not branch_density_curve:
		return rng.randf_range(low, high)

	# Rejection sampling against branch_density_curve (up to 32 attempts per branch)
	for _attempt: int in range(32):
		var candidate_t: float = rng.randf_range(low, high)
		var prob: float = clampf(branch_density_curve.sample_baked(candidate_t), 0.0, 1.0)
		if rng.randf() <= prob:
			return candidate_t
	return rng.randf_range(low, high)


func _evaluate_trunk_at(t: float, points: PackedVector3Array, tangents: PackedVector3Array) -> Dictionary:
	var max_idx: int = points.size() - 1
	var scaled_t: float = clampf(t, 0.0, 1.0) * float(max_idx)
	var idx0: int = clampi(int(floorf(scaled_t)), 0, max_idx)
	var idx1: int = mini(idx0 + 1, max_idx)
	var frac: float = scaled_t - float(idx0)

	return {
		"position": points[idx0].lerp(points[idx1], frac),
		"tangent": tangents[idx0].lerp(tangents[idx1], frac).normalized(),
		"radius": _get_trunk_radius_at(t)
	}


func _build_branches_surface(
	rng: RandomNumberGenerator,
	trunk_points: PackedVector3Array,
	trunk_tangents: PackedVector3Array
) -> Array:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	# Collect and sort heights so Golden Angle spirals cleanly up the trunk
	var heights := PackedFloat32Array()
	heights.resize(branch_count)
	for i: int in range(branch_count):
		heights[i] = _sample_biased_height(rng)
	heights.sort()

	const GOLDEN_ANGLE: float = 2.39996322972865332 # ~137.5 degrees in radians

	for i: int in range(branch_count):
		var t: float = heights[i]
		var trunk_sample: Dictionary = _evaluate_trunk_at(t, trunk_points, trunk_tangents)
		var trunk_pos: Vector3 = trunk_sample["position"]
		var trunk_up: Vector3 = trunk_sample["tangent"]
		var current_radius: float = trunk_sample["radius"]

		# 1. Radial angle around the trunk
		var radial_angle: float = 0.0
		if use_golden_angle:
			radial_angle = float(i) * GOLDEN_ANGLE + deg_to_rad(rng.randf_range(-radial_angle_jitter, radial_angle_jitter))
		else:
			radial_angle = rng.randf_range(0.0, TAU)

		# Construct horizontal outward direction orthogonal to the trunk tangent
		var raw_out := Vector3(cos(radial_angle), 0.0, sin(radial_angle))
		var outward: Vector3 = (raw_out - trunk_up * raw_out.dot(trunk_up)).normalized()
		if outward.length_squared() < 0.001:
			outward = Vector3.RIGHT
		var side: Vector3 = trunk_up.cross(outward).normalized()

		# Base frame where Z+ points outward horizontally from the trunk, Y+ points along trunk_up
		var branch_basis := Basis(side, trunk_up, outward)

		# 2. Pitch (0 deg = horizontal, + = angled up toward sky, - = drooping down)
		var min_pitch: float = minf(pitch_angle_range.x, pitch_angle_range.y)
		var max_pitch: float = maxf(pitch_angle_range.x, pitch_angle_range.y)
		var pitch_deg: float = rng.randf_range(min_pitch, max_pitch)
		if pitch_height_bias_curve:
			pitch_deg += pitch_height_bias_curve.sample_baked(t) * 45.0

		# Rotate around local X (side) for vertical pitch, then local Z (outward) for roll/twist
		var roll_deg: float = rng.randf_range(
			minf(roll_angle_range.x, roll_angle_range.y),
			maxf(roll_angle_range.x, roll_angle_range.y)
		)
		branch_basis = branch_basis * Basis.from_euler(Vector3(deg_to_rad(-pitch_deg), 0.0, deg_to_rad(roll_deg)))

		# 3. Scale Bias & Random Variation
		var curve_scale: float = branch_scale_curve.sample_baked(t) if branch_scale_curve else lerpf(1.0, 0.35, t)
		var rand_scale: float = 1.0 + rng.randf_range(-branch_size_randomness, branch_size_randomness)
		var final_size: Vector2 = branch_base_size * maxf(curve_scale * rand_scale, 0.05)

		# Anchor slightly inside the trunk surface so angled branches never float
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

	# Quad grows outward along local +Z from origin (0 to length) and spans -half_w to +half_w on local X
	var v0: Vector3 = origin + basis * Vector3(-half_w, 0.0, 0.0)
	var v1: Vector3 = origin + basis * Vector3(half_w, 0.0, 0.0)
	var v2: Vector3 = origin + basis * Vector3(half_w, 0.0, length)
	var v3: Vector3 = origin + basis * Vector3(-half_w, 0.0, length)

	# Normal points upward/outward for soft hemisphere foliage shading
	var quad_normal: Vector3 = (basis.y + basis.z * 0.35).normalized()

	vertices.append_array([v0, v1, v2, v3])
	normals.append_array([quad_normal, quad_normal, quad_normal, quad_normal])
	# UV: Bottom of texture (Y=1.0) is attached to trunk; Top of texture (Y=0.0) is branch tip
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
