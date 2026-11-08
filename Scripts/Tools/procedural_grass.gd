@tool
## Procedural grass populator that extends MultiMeshPopulator using 3-layer smoothstep noise,
## density-driven blade scaling, and randomized cross-plane shader custom data.
class_name ProceduralGrass extends MultiMeshPopulator

@export_group("Grass Clump Mesh & Cross-Planes")
## Base Width (X) and Height (Y) of each grass plane in meters
@export var blade_base_size: Vector2 = Vector2(0.45, 0.45)
## Generates intersecting cross-planes. Plane B's angle is randomized per instance via cross_plane_angle_range
@export var cross_planes: bool = true
## Range of relative angles (in degrees) between the two cross-planes (55..125 breaks up harsh 90-degree X shapes)
@export var cross_plane_angle_range: Vector2 = Vector2(55.0, 125.0)
## Slight horizontal separation between the two planes so they don't intersect at a rigid center line
@export_range(0.0, 0.25, 0.01) var cross_plane_offset: float = 0.06
## Slight outward tilt at the top of each plane so clumps have volume when viewed from above
@export_range(0.0, 0.5, 0.01) var tip_tilt_factor: float = 0.12
## ShaderMaterial using grass_wind.gdshader
@export var grass_material: Material


func _init() -> void:
	density_per_m2 = 6.0
	spacing = 0.0
	check_obstacle_clearance = false
	use_density_noise = true
	noise_base_frequency = 0.02
	noise_threshold = 0.42
	noise_transition_margin = 0.18
	density_affects_scale = true
	min_edge_scale = 0.65
	max_core_scale = 1.25
	density_height_exponent = 1.15
	chunk_visibility_max_distance = 65.0
	chunk_visibility_fade_margin = 10.0
	collider_type = ColliderType.NONE


func _get_meshes_to_populate() -> Array[Mesh]:
	return [_build_clump_mesh()]


func _build_instance_custom_data(rng: RandomNumberGenerator, density_weight: float) -> Color:
	var min_cp_rad: float = deg_to_rad(minf(cross_plane_angle_range.x, cross_plane_angle_range.y))
	var max_cp_rad: float = deg_to_rad(maxf(cross_plane_angle_range.x, cross_plane_angle_range.y))
	var cross_angle_rad: float = rng.randf_range(min_cp_rad, max_cp_rad)

	return Color(
		rng.randf(),      # R: Random color variation (0..1)
		rng.randf(),      # G: Random wind phase offset (0..1)
		density_weight,   # B: Smooth 3-noise density factor (0..1)
		cross_angle_rad   # A: Relative angle (radians) for Plane B in grass_wind.gdshader
	)


func _build_clump_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	# Plane 0: Base plane (COLOR.r = 0.0 keeps fixed base rotation)
	_append_vertical_quad(
		vertices,
		normals,
		uvs,
		colors,
		indices,
		Vector3(0.0, 0.0, -cross_plane_offset * 0.5),
		blade_base_size,
		0.0
	)

	if cross_planes:
		# Plane 1: Cross plane (COLOR.r = 1.0 tells grass_wind.gdshader to rotate by INSTANCE_CUSTOM.a)
		_append_vertical_quad(
			vertices,
			normals,
			uvs,
			colors,
			indices,
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
	var half_w: float = maxf(size.x * 0.5, 0.01)
	var h: float = maxf(size.y, 0.01)
	var base_idx: int = vertices.size()

	var top_tilt_z: float = h * tip_tilt_factor * (1.0 if plane_id < 0.5 else -1.0)

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
