@tool
## Projects a Path3D onto terrain (ignoring non-terrain obstacles), stretches/tiles a custom 3D model into distance-culled road chunks,
## spawns non-overlapping decorations, and supports runtime generation & user:// caching.
class_name ToolPathProjector extends Path3D

enum MeshForwardAxis {
	AXIS_Z,
	AXIS_X
}

@export_group("Projector Actions")
@export_tool_button("Project Path, Deform Model & Spawn Decorations", "Curve3D") var btn_build_all: Callable:
	get:
		return build_complete_path
@export_tool_button("Project & Smooth Curve Only", "Path3D") var btn_project_only: Callable:
	get:
		return project_and_smooth_path
@export_tool_button("Clear Generated Nodes", "Clear") var btn_clear: Callable:
	get:
		return clear_generated_nodes
@export_tool_button("Save Generated Resources to Disk", "Save") var btn_save: Callable:
	get:
		return save_resources_to_disk

@export var seed_value: int = 1337
@export_range(2, 30, 1) var frame_budget_ms: int = 10

@export_group("Target Surface & Projection")
@export var target_terrain: Node3D
@export var allowed_groups: Array[StringName] = [&"grass_surface", &"terrain_chunk_body"]
@export var height_offset: float = 0.05
@export_range(0.0, 1.0, 0.01) var smoothing_factor: float = 0.28
@export var raycast_top_height: float = 150.0
@export var raycast_length: float = 300.0
## Maximum number of non-terrain colliders (other paths, objects, props) a downward ray can pierce through before giving up
@export_range(1, 64, 1) var max_raycast_pierce_hits: int = 32

@export_group("Road / Path Model Stretching")
@export var deform_model_along_path: bool = true
@export var source_road_mesh: Mesh
@export var source_mesh_instance: MeshInstance3D
@export var model_forward_axis: MeshForwardAxis = MeshForwardAxis.AXIS_Z
@export var model_scale: Vector3 = Vector3.ONE
@export var stretch_to_fit_exact_length: bool = true
@export var snap_deformed_vertices_to_terrain: bool = true
@export var conform_cross_slope_to_terrain: bool = false
@export var fallback_material_override: Material

@export_group("Road Chunking & Distance Culling (FPS Optimization)")
## Target length in meters of each individual RoadChunk MeshInstance3D along the path
@export_range(5.0, 200.0, 1.0) var road_chunk_length: float = 25.0
## Distance from camera where road chunks fade out and stop rendering (0 = never cull)
@export_range(0.0, 1000.0, 5.0) var road_chunk_max_distance: float = 160.0
@export_range(0.0, 100.0, 1.0) var road_chunk_fade_margin: float = 20.0
@export var road_cast_shadow: GeometryInstance3D.ShadowCastingSetting = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

@export_group("Road Collision")
@export var generate_road_collider: bool = true
@export var road_body_groups: Array[StringName] = [&"road", &"no_grass"]
@export_flags_3d_physics var road_collision_layer: int = 1
@export_flags_3d_physics var road_collision_mask: int = 1

@export_group("Roadside Decorations")
@export var spawn_decorations: bool = true
@export var decorations: Array[PathDecorationEntry] = []
@export_range(0.0, 10.0, 0.1) var global_extra_clearance: float = 0.25
## Distance from camera where spawned roadside decoration meshes stop rendering (0 = never cull)
@export_range(0.0, 1000.0, 5.0) var decoration_max_distance: float = 140.0

@export_group("Storage")
@export var auto_save_to_disk: bool = false
@export var save_subfolder_name: String = "GeneratedRoads"

# Stores the last generated decoration placements so they can be saved/loaded from user:// cache
var _cached_deco_records: Array[Dictionary] = []


func build_complete_path() -> void:
	if not is_inside_tree() or not curve or curve.get_point_count() < 2:
		printerr("ToolPathProjector (%s): Path3D requires a Curve3D with at least 2 points." % name)
		return

	project_and_smooth_path()

	if deform_model_along_path:
		await _deform_and_tile_mesh_along_curve_async(Callable(), true)

	if spawn_decorations and not decorations.is_empty():
		_spawn_all_decorations(true)

	if auto_save_to_disk and Engine.is_editor_hint():
		save_resources_to_disk()


func clear_generated_nodes() -> void:
	for child_name: String in ["RoadMeshInstance3D", "RoadChunks", "RoadStaticBody3D", "RoadDecorations"]:
		var node := get_node_or_null(child_name)
		if node:
			if is_inside_tree():
				remove_child(node)
			node.free()


#region Orchestrated Runtime Generation & user:// Cache
func generate_or_load_cached(
	cache_dir: String,
	use_existing_cache: bool,
	is_editor_preview: bool,
	progress_callback: Callable = Callable()
) -> void:
	if not is_inside_tree() or not curve or curve.get_point_count() < 2:
		return

	var cache_file: String = "%s/Road_%s_cache.res" % [cache_dir, name.validate_filename()]

	if use_existing_cache and not is_editor_preview and FileAccess.file_exists(cache_file):
		if progress_callback.is_valid():
			progress_callback.call(20.0, "Loading cached road '%s'..." % name)
		await get_tree().process_frame
		if _load_from_cache_file(cache_file):
			if progress_callback.is_valid():
				progress_callback.call(100.0, "Loaded road '%s' from cache." % name)
			return

	if progress_callback.is_valid():
		progress_callback.call(5.0, "Projecting curve points for '%s'..." % name)
	project_and_smooth_path()
	await get_tree().process_frame

	if deform_model_along_path:
		await _deform_and_tile_mesh_along_curve_async(progress_callback, is_editor_preview)

	if spawn_decorations and not decorations.is_empty():
		if progress_callback.is_valid():
			progress_callback.call(88.0, "Spawning roadside decorations for '%s'..." % name)
		await get_tree().process_frame
		_spawn_all_decorations(is_editor_preview)

	if not is_editor_preview:
		if progress_callback.is_valid():
			progress_callback.call(95.0, "Saving road '%s' to user:// cache..." % name)
		await get_tree().process_frame
		_save_to_cache_file(cache_file)

	if progress_callback.is_valid():
		progress_callback.call(100.0, "Finished road '%s'." % name)


func _save_to_cache_file(cache_file: String) -> void:
	var bundle := Resource.new()
	var chunk_data: Array[Dictionary] = []
	var chunks_root := get_node_or_null("RoadChunks")
	if chunks_root:
		for child: Node in chunks_root.get_children():
			if child is MeshInstance3D and child.mesh:
				var mi := child as MeshInstance3D
				chunk_data.append({
					"name": mi.name,
					"pos": mi.position,
					"mesh": mi.mesh
				})

	var col_data: Array[Dictionary] = []
	var road_body := get_node_or_null("RoadStaticBody3D")
	if road_body:
		for child: Node in road_body.get_children():
			if child is CollisionShape3D and child.shape:
				var cs := child as CollisionShape3D
				col_data.append({
					"name": cs.name,
					"pos": cs.position,
					"shape": cs.shape
				})

	bundle.set_meta("curve_points", _serialize_curve_points())
	bundle.set_meta("chunks", chunk_data)
	bundle.set_meta("colliders", col_data)
	bundle.set_meta("decorations", _cached_deco_records)

	ResourceSaver.save(bundle, cache_file, ResourceSaver.FLAG_COMPRESS)


func _load_from_cache_file(cache_file: String) -> bool:
	var bundle: Resource = ResourceLoader.load(cache_file, "", ResourceLoader.CACHE_MODE_REPLACE)
	if not bundle or not bundle.has_meta("chunks"):
		return false

	clear_generated_nodes()

	if bundle.has_meta("curve_points"):
		_deserialize_curve_points(bundle.get_meta("curve_points"))

	var chunk_data: Array = bundle.get_meta("chunks")
	var col_data: Array = bundle.get_meta("colliders") if bundle.has_meta("colliders") else []
	var deco_data: Array = bundle.get_meta("decorations") if bundle.has_meta("decorations") else []

	if not chunk_data.is_empty():
		var chunks_root := Node3D.new()
		chunks_root.name = "RoadChunks"
		for c_dict: Dictionary in chunk_data:
			var chunk_inst := MeshInstance3D.new()
			chunk_inst.name = str(c_dict.get("name", "RoadChunk"))
			chunk_inst.position = c_dict.get("pos", Vector3.ZERO)
			chunk_inst.mesh = c_dict.get("mesh") as Mesh
			chunk_inst.cast_shadow = road_cast_shadow
			if road_chunk_max_distance > 0.0:
				chunk_inst.visibility_range_end = road_chunk_max_distance
				chunk_inst.visibility_range_end_margin = road_chunk_fade_margin
				chunk_inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			chunks_root.add_child(chunk_inst)
		add_child(chunks_root)

	if generate_road_collider and not col_data.is_empty():
		var road_body := StaticBody3D.new()
		road_body.name = "RoadStaticBody3D"
		road_body.collision_layer = road_collision_layer
		road_body.collision_mask = road_collision_mask
		for grp: StringName in road_body_groups:
			if grp != &"" and not road_body.is_in_group(grp):
				road_body.add_to_group(grp, true)

		for col_dict: Dictionary in col_data:
			var col_shape := CollisionShape3D.new()
			col_shape.name = str(col_dict.get("name", "RoadCol"))
			col_shape.position = col_dict.get("pos", Vector3.ZERO)
			col_shape.shape = col_dict.get("shape") as Shape3D
			road_body.add_child(col_shape)
		add_child(road_body)

	if spawn_decorations and not deco_data.is_empty():
		_rebuild_decorations_from_cache(deco_data)

	return true


func _serialize_curve_points() -> Array[Dictionary]:
	var pts: Array[Dictionary] = []
	if not curve:
		return pts
	for i: int in range(curve.get_point_count()):
		pts.append({
			"pos": curve.get_point_position(i),
			"in": curve.get_point_in(i),
			"out": curve.get_point_out(i),
			"tilt": curve.get_point_tilt(i)
		})
	return pts


func _deserialize_curve_points(pts: Array) -> void:
	if not curve or pts.size() != curve.get_point_count():
		return
	for i: int in range(pts.size()):
		var d: Dictionary = pts[i]
		curve.set_point_position(i, d.get("pos", curve.get_point_position(i)))
		curve.set_point_in(i, d.get("in", Vector3.ZERO))
		curve.set_point_out(i, d.get("out", Vector3.ZERO))
		curve.set_point_tilt(i, float(d.get("tilt", 0.0)))
#endregion


#region Step 1: Curve Projection & Handle Smoothing
func project_and_smooth_path() -> void:
	if not curve or curve.get_point_count() == 0:
		return

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var point_count: int = curve.get_point_count()

	for i: int in range(point_count):
		var global_pos: Vector3 = to_global(curve.get_point_position(i))
		var hit: Dictionary = _raycast_terrain_at(space_state, global_pos.x, global_pos.z)
		if not hit.is_empty():
			var hit_pos: Vector3 = hit["position"]
			hit_pos.y += height_offset
			curve.set_point_position(i, to_local(hit_pos))

	if point_count < 3:
		return

	for i: int in range(point_count):
		var p_prev: Vector3 = curve.get_point_position(maxi(0, i - 1))
		var p_current: Vector3 = curve.get_point_position(i)
		var p_next: Vector3 = curve.get_point_position(mini(point_count - 1, i + 1))

		var dir: Vector3 = (p_next - p_prev).normalized()
		var dist: float = p_prev.distance_to(p_next)

		if i == 0:
			dir = (p_next - p_current).normalized()
			dist = p_current.distance_to(p_next)
			curve.set_point_in(i, Vector3.ZERO)
			curve.set_point_out(i, dir * (dist * smoothing_factor))
		elif i == point_count - 1:
			dir = (p_current - p_prev).normalized()
			dist = p_prev.distance_to(p_current)
			curve.set_point_in(i, -dir * (dist * smoothing_factor))
			curve.set_point_out(i, Vector3.ZERO)
		else:
			curve.set_point_in(i, -dir * (dist * smoothing_factor))
			curve.set_point_out(i, dir * (dist * smoothing_factor))
#endregion


#region Step 2: Chunked 3D Model Tiling & Spline Deformation
func _get_active_source_mesh() -> Mesh:
	if source_road_mesh:
		return source_road_mesh
	if is_instance_valid(source_mesh_instance) and source_mesh_instance.mesh:
		return source_mesh_instance.mesh
	return null


func _deform_and_tile_mesh_along_curve_async(progress_callback: Callable, set_editor_owner: bool) -> void:
	var src_mesh: Mesh = _get_active_source_mesh()
	if not src_mesh or src_mesh.get_surface_count() == 0:
		push_warning("ToolPathProjector (%s): No source_road_mesh or source_mesh_instance assigned to deform." % name)
		return

	var total_curve_len: float = curve.get_baked_length()
	if total_curve_len <= 0.05:
		return

	var aabb: AABB = src_mesh.get_aabb()
	var use_z_forward: bool = (model_forward_axis == MeshForwardAxis.AXIS_Z)

	var min_fwd: float = aabb.position.z if use_z_forward else aabb.position.x
	var max_fwd: float = aabb.end.z if use_z_forward else aabb.end.x
	var raw_mesh_len: float = (max_fwd - min_fwd) * (absf(model_scale.z) if use_z_forward else absf(model_scale.x))

	if raw_mesh_len <= 0.001:
		printerr("ToolPathProjector (%s): Source mesh has zero length along the chosen forward axis." % name)
		return

	var tile_count: int = maxi(int(roundf(total_curve_len / raw_mesh_len)), 1)
	if not stretch_to_fit_exact_length:
		tile_count = maxi(int(ceilf(total_curve_len / raw_mesh_len)), 1)

	var tile_curve_len: float = (total_curve_len / float(tile_count)) if stretch_to_fit_exact_length else raw_mesh_len
	var tiles_per_chunk: int = maxi(int(roundf(maxf(road_chunk_length, tile_curve_len) / tile_curve_len)), 1)
	var chunk_count: int = int(ceilf(float(tile_count) / float(tiles_per_chunk)))

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var scene_owner: Node = get_tree().edited_scene_root if (Engine.is_editor_hint() and set_editor_owner) else null

	# Clear old single mesh or old chunks
	for old_name: String in ["RoadMeshInstance3D", "RoadChunks", "RoadStaticBody3D"]:
		var old_node := get_node_or_null(old_name)
		if old_node:
			if is_inside_tree():
				remove_child(old_node)
			old_node.free()

	var chunks_root := Node3D.new()
	chunks_root.name = "RoadChunks"

	var road_body: StaticBody3D = null
	if generate_road_collider:
		road_body = StaticBody3D.new()
		road_body.name = "RoadStaticBody3D"
		road_body.collision_layer = road_collision_layer
		road_body.collision_mask = road_collision_mask
		for grp: StringName in road_body_groups:
			if grp != &"" and not road_body.is_in_group(grp):
				road_body.add_to_group(grp, true)

	var surface_count: int = src_mesh.get_surface_count()
	var pre_surfaces: Array[Dictionary] = []

	for surf_idx: int in range(surface_count):
		var src_arrays: Array = src_mesh.surface_get_arrays(surf_idx)
		if src_arrays.is_empty():
			continue
		var src_verts: PackedVector3Array = src_arrays[Mesh.ARRAY_VERTEX] if src_arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
		if src_verts.is_empty():
			continue

		var src_normals: PackedVector3Array = src_arrays[Mesh.ARRAY_NORMAL] if src_arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var src_tangents: PackedFloat32Array = src_arrays[Mesh.ARRAY_TANGENT] if src_arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
		var src_uvs: PackedVector2Array = src_arrays[Mesh.ARRAY_TEX_UV] if src_arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var src_colors: PackedColorArray = src_arrays[Mesh.ARRAY_COLOR] if src_arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var src_indices: PackedInt32Array = src_arrays[Mesh.ARRAY_INDEX] if src_arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()

		if src_indices.is_empty():
			src_indices.resize(src_verts.size())
			for k: int in range(src_verts.size()):
				src_indices[k] = k

		pre_surfaces.append({
			"surf_idx": surf_idx,
			"verts": src_verts,
			"normals": src_normals,
			"tangents": src_tangents,
			"uvs": src_uvs,
			"colors": src_colors,
			"indices": src_indices,
			"has_normals": src_normals.size() == src_verts.size(),
			"has_tangents": src_tangents.size() == src_verts.size() * 4,
			"has_uvs": src_uvs.size() == src_verts.size(),
			"has_colors": src_colors.size() == src_verts.size(),
			"material": _resolve_surface_material(src_mesh, surf_idx)
		})

	var frame_start: int = Time.get_ticks_msec()

	for c_idx: int in range(chunk_count):
		var start_tile: int = c_idx * tiles_per_chunk
		var end_tile: int = mini(start_tile + tiles_per_chunk, tile_count)
		var c_tile_count: int = end_tile - start_tile
		if c_tile_count <= 0:
			continue

		var chunk_start_dist: float = float(start_tile) * tile_curve_len
		var chunk_end_dist: float = minf(float(end_tile) * tile_curve_len, total_curve_len)
		var chunk_mid_dist: float = (chunk_start_dist + chunk_end_dist) * 0.5
		var chunk_local_center: Vector3 = curve.sample_baked(chunk_mid_dist, true)

		var chunk_mesh := ArrayMesh.new()

		for s_data: Dictionary in pre_surfaces:
			var src_verts: PackedVector3Array = s_data["verts"]
			var src_normals: PackedVector3Array = s_data["normals"]
			var src_tangents: PackedFloat32Array = s_data["tangents"]
			var src_uvs: PackedVector2Array = s_data["uvs"]
			var src_colors: PackedColorArray = s_data["colors"]
			var src_indices: PackedInt32Array = s_data["indices"]

			var has_normals: bool = s_data["has_normals"]
			var has_tangents: bool = s_data["has_tangents"]
			var has_uvs: bool = s_data["has_uvs"]
			var has_colors: bool = s_data["has_colors"]

			var v_count: int = src_verts.size()
			var i_count: int = src_indices.size()

			var out_verts := PackedVector3Array()
			var out_normals := PackedVector3Array()
			var out_tangents := PackedFloat32Array()
			var out_uvs := PackedVector2Array()
			var out_colors := PackedColorArray()
			var out_indices := PackedInt32Array()

			out_verts.resize(v_count * c_tile_count)
			if has_normals:
				out_normals.resize(v_count * c_tile_count)
			if has_tangents:
				out_tangents.resize(v_count * 4 * c_tile_count)
			if has_uvs:
				out_uvs.resize(v_count * c_tile_count)
			if has_colors:
				out_colors.resize(v_count * c_tile_count)
			out_indices.resize(i_count * c_tile_count)

			for local_t: int in range(c_tile_count):
				var global_t: int = start_tile + local_t
				var v_offset: int = local_t * v_count
				var i_offset: int = local_t * i_count
				var tile_start_dist: float = float(global_t) * tile_curve_len

				for v_i: int in range(v_count):
					var sv: Vector3 = src_verts[v_i]

					var fwd_coord: float = sv.z if use_z_forward else sv.x
					var lat_coord: float = (sv.x * model_scale.x) if use_z_forward else (-sv.z * model_scale.z)
					var vert_y: float = sv.y * model_scale.y

					var t_progress: float = clampf((max_fwd - fwd_coord) / maxf(max_fwd - min_fwd, 0.0001), 0.0, 1.0)
					var dist_on_curve: float = clampf(tile_start_dist + t_progress * tile_curve_len, 0.0, total_curve_len)

					var frame: Dictionary = _sample_curve_frame_world(space_state, dist_on_curve, total_curve_len, lat_coord)
					var frame_origin: Vector3 = frame["position"]
					var frame_basis: Basis = frame["basis"]

					var world_deformed: Vector3 = frame_origin + frame_basis.x * lat_coord + frame_basis.y * vert_y
					var out_v_idx: int = v_offset + v_i
					out_verts[out_v_idx] = to_local(world_deformed) - chunk_local_center

					if has_normals:
						var sn: Vector3 = src_normals[v_i]
						var mapped_n: Vector3 = sn if use_z_forward else Vector3(-sn.z, sn.y, sn.x)
						var world_n: Vector3 = (frame_basis * mapped_n).normalized()
						out_normals[out_v_idx] = (global_basis.inverse() * world_n).normalized()

					if has_tangents:
						var st_base: int = v_i * 4
						var ot_base: int = out_v_idx * 4
						var st_vec := Vector3(src_tangents[st_base], src_tangents[st_base + 1], src_tangents[st_base + 2])
						var mapped_t: Vector3 = st_vec if use_z_forward else Vector3(-st_vec.z, st_vec.y, st_vec.x)
						var local_tang: Vector3 = (global_basis.inverse() * (frame_basis * mapped_t)).normalized()
						out_tangents[ot_base + 0] = local_tang.x
						out_tangents[ot_base + 1] = local_tang.y
						out_tangents[ot_base + 2] = local_tang.z
						out_tangents[ot_base + 3] = src_tangents[st_base + 3]

					if has_uvs:
						out_uvs[out_v_idx] = src_uvs[v_i]
					if has_colors:
						out_colors[out_v_idx] = src_colors[v_i]

				for idx_i: int in range(i_count):
					out_indices[i_offset + idx_i] = src_indices[idx_i] + v_offset

			var out_arrays := []
			out_arrays.resize(Mesh.ARRAY_MAX)
			out_arrays[Mesh.ARRAY_VERTEX] = out_verts
			if has_normals:
				out_arrays[Mesh.ARRAY_NORMAL] = out_normals
			if has_tangents:
				out_arrays[Mesh.ARRAY_TANGENT] = out_tangents
			if has_uvs:
				out_arrays[Mesh.ARRAY_TEX_UV] = out_uvs
			if has_colors:
				out_arrays[Mesh.ARRAY_COLOR] = out_colors
			out_arrays[Mesh.ARRAY_INDEX] = out_indices

			chunk_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
			var new_surf_idx: int = chunk_mesh.get_surface_count() - 1
			var surf_mat: Material = s_data["material"]
			if surf_mat:
				chunk_mesh.surface_set_material(new_surf_idx, surf_mat)

		var chunk_inst := MeshInstance3D.new()
		chunk_inst.name = "RoadChunk_%d" % c_idx
		chunk_inst.position = chunk_local_center
		chunk_inst.mesh = chunk_mesh
		chunk_inst.cast_shadow = road_cast_shadow

		if road_chunk_max_distance > 0.0:
			chunk_inst.visibility_range_end = road_chunk_max_distance
			chunk_inst.visibility_range_end_margin = road_chunk_fade_margin
			chunk_inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

		chunks_root.add_child(chunk_inst)

		if road_body and chunk_mesh.get_surface_count() > 0:
			var col_shape := CollisionShape3D.new()
			col_shape.name = "RoadCol_%d" % c_idx
			col_shape.position = chunk_local_center
			col_shape.shape = chunk_mesh.create_trimesh_shape()
			road_body.add_child(col_shape)

		if Time.get_ticks_msec() - frame_start >= frame_budget_ms:
			if progress_callback.is_valid():
				var pct: float = 10.0 + (float(c_idx + 1) / float(maxi(chunk_count, 1))) * 75.0
				progress_callback.call(pct, "Deforming road chunk %d / %d..." % [c_idx + 1, chunk_count])
			await get_tree().process_frame
			frame_start = Time.get_ticks_msec()
			space_state = get_world_3d().direct_space_state

	add_child(chunks_root)
	if scene_owner:
		chunks_root.owner = scene_owner
		for child: Node in chunks_root.get_children():
			child.owner = scene_owner

	if road_body:
		add_child(road_body)
		if scene_owner:
			road_body.owner = scene_owner
			for child: Node in road_body.get_children():
				child.owner = scene_owner


func _resolve_surface_material(src_mesh: Mesh, surf_idx: int) -> Material:
	if is_instance_valid(source_mesh_instance):
		var override_mat: Material = source_mesh_instance.get_surface_override_material(surf_idx)
		if override_mat:
			return override_mat
		if source_mesh_instance.material_override:
			return source_mesh_instance.material_override
	var mesh_mat: Material = src_mesh.surface_get_material(surf_idx)
	if mesh_mat:
		return mesh_mat
	return fallback_material_override


func _sample_curve_frame_world(
	space_state: PhysicsDirectSpaceState3D,
	dist_along: float,
	total_len: float,
	lateral_x: float
) -> Dictionary:
	var local_center: Vector3 = curve.sample_baked(dist_along, true)
	var world_center: Vector3 = to_global(local_center)

	var d_prev: float = maxf(dist_along - 0.2, 0.0)
	var d_next: float = minf(dist_along + 0.2, total_len)
	var world_prev: Vector3 = to_global(curve.sample_baked(d_prev, true))
	var world_next: Vector3 = to_global(curve.sample_baked(d_next, true))

	var forward: Vector3 = (world_next - world_prev).normalized()
	if forward.length_squared() < 0.0001:
		forward = -global_basis.z.normalized()

	var up_vec := Vector3.UP
	var right: Vector3 = forward.cross(up_vec).normalized()
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	up_vec = right.cross(forward).normalized()

	if snap_deformed_vertices_to_terrain:
		var sample_xz: Vector3 = world_center + (right * lateral_x if conform_cross_slope_to_terrain else Vector3.ZERO)
		var hit: Dictionary = _raycast_terrain_at(space_state, sample_xz.x, sample_xz.z)
		if not hit.is_empty():
			world_center.y = (hit["position"] as Vector3).y + height_offset
			if conform_cross_slope_to_terrain:
				var ground_n: Vector3 = (hit["normal"] as Vector3).normalized()
				right = forward.cross(ground_n).normalized()
				up_vec = right.cross(forward).normalized()

	var rh_basis := Basis(right, up_vec, -forward)
	return {
		"position": world_center,
		"basis": rh_basis,
		"forward": forward,
		"right": right,
		"up": up_vec
	}
#endregion


#region Step 3: Multi-Decoration Spawner with Overlap Prevention & Distance Culling
func _spawn_all_decorations(set_editor_owner: bool = false) -> void:
	var existing := get_node_or_null("RoadDecorations")
	if existing:
		if is_inside_tree():
			remove_child(existing)
		existing.free()

	_cached_deco_records.clear()

	var total_len: float = curve.get_baked_length()
	if total_len <= 0.5:
		return

	var scene_owner: Node = get_tree().edited_scene_root if (Engine.is_editor_hint() and set_editor_owner) else null
	var decos_root := Node3D.new()
	decos_root.name = "RoadDecorations"
	add_child(decos_root)
	if scene_owner:
		decos_root.owner = scene_owner

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var placed_records: Array[Dictionary] = []

	for entry_idx: int in range(decorations.size()):
		var entry: PathDecorationEntry = decorations[entry_idx]
		if not entry or (not entry.decoration_scene and not entry.decoration_mesh):
			continue

		var min_step: float = maxf(entry.frequency_distance.x, 0.25)
		var avg_step: float = maxf(entry.frequency_distance.y, min_step)
		var max_step: float = min_step + 2.0 * (avg_step - min_step)

		var dist: float = entry.start_offset
		var max_dist: float = total_len - entry.end_margin
		var step_counter: int = 0

		while dist <= max_dist:
			var sides: Array[float] = _resolve_entry_sides(entry, rng, step_counter)

			for side_sign: float in sides:
				var lat_dist: float = entry.lateral_offset + rng.randf_range(-entry.lateral_jitter, entry.lateral_jitter)
				var placed_dist: float = _find_non_overlapping_distance(
					space_state,
					dist,
					total_len,
					lat_dist * side_sign,
					entry.clearance_radius,
					entry.max_overlap_nudge,
					placed_records
				)

				if placed_dist >= 0.0:
					_instantiate_decoration_at(
						entry,
						entry_idx,
						decos_root,
						scene_owner,
						space_state,
						rng,
						placed_dist,
						total_len,
						side_sign,
						lat_dist,
						placed_records
					)

			dist += rng.randf_range(min_step, max_step)
			step_counter += 1


func _rebuild_decorations_from_cache(deco_data: Array) -> void:
	var decos_root := Node3D.new()
	decos_root.name = "RoadDecorations"
	add_child(decos_root)

	for i: int in range(deco_data.size()):
		var rec: Dictionary = deco_data[i]
		var entry_idx: int = int(rec.get("entry_idx", -1))
		if entry_idx < 0 or entry_idx >= decorations.size():
			continue
		var entry: PathDecorationEntry = decorations[entry_idx]
		if not entry:
			continue

		var inst_3d: Node3D = null
		if entry.decoration_scene:
			var inst: Node = entry.decoration_scene.instantiate()
			if inst is Node3D:
				inst_3d = inst as Node3D
			else:
				inst.free()
				continue
		elif entry.decoration_mesh:
			var mi := MeshInstance3D.new()
			mi.mesh = entry.decoration_mesh
			if entry.mesh_material_override:
				mi.material_override = entry.mesh_material_override
			inst_3d = mi

		if not inst_3d:
			continue

		if decoration_max_distance > 0.0:
			if inst_3d is GeometryInstance3D:
				(inst_3d as GeometryInstance3D).visibility_range_end = decoration_max_distance
			for sub_vis: Node in inst_3d.find_children("*", "GeometryInstance3D", true, false):
				if sub_vis is GeometryInstance3D:
					(sub_vis as GeometryInstance3D).visibility_range_end = decoration_max_distance

		inst_3d.name = "Deco_%d_%d" % [entry_idx, i]
		inst_3d.transform = rec.get("local_transform", Transform3D.IDENTITY)
		decos_root.add_child(inst_3d)


func _resolve_entry_sides(entry: PathDecorationEntry, rng: RandomNumberGenerator, step_counter: int) -> Array[float]:
	match entry.side:
		PathDecorationEntry.PlacementSide.RIGHT:
			return [1.0]
		PathDecorationEntry.PlacementSide.LEFT:
			return [-1.0]
		PathDecorationEntry.PlacementSide.BOTH_SYMMETRIC:
			return [1.0, -1.0]
		PathDecorationEntry.PlacementSide.BOTH_ALTERNATING:
			return [1.0 if (step_counter % 2 == 0) else -1.0]
		PathDecorationEntry.PlacementSide.RANDOM_SIDE:
			return [1.0 if (rng.randf() < 0.5) else -1.0]
	return [1.0]


func _find_non_overlapping_distance(
	space_state: PhysicsDirectSpaceState3D,
	target_dist: float,
	total_len: float,
	signed_lateral_offset: float,
	my_radius: float,
	max_nudge: float,
	placed_records: Array[Dictionary]
) -> float:
	var candidate_pos: Vector3 = _compute_decoration_world_pos(space_state, target_dist, total_len, signed_lateral_offset, false)
	if not _overlaps_any_placed(candidate_pos, my_radius, placed_records):
		return target_dist

	if max_nudge <= 0.05:
		return -1.0

	var nudge_step: float = 0.5
	var offset: float = nudge_step
	while offset <= max_nudge + 0.01:
		for dir_sign: float in [1.0, -1.0]:
			var test_dist: float = target_dist + offset * dir_sign
			if test_dist < 0.0 or test_dist > total_len:
				continue
			var test_pos: Vector3 = _compute_decoration_world_pos(space_state, test_dist, total_len, signed_lateral_offset, false)
			if not _overlaps_any_placed(test_pos, my_radius, placed_records):
				return test_dist
		offset += nudge_step

	return -1.0


func _overlaps_any_placed(pos: Vector3, my_radius: float, placed_records: Array[Dictionary]) -> bool:
	for rec: Dictionary in placed_records:
		var other_pos: Vector3 = rec["pos"]
		var min_allowed: float = my_radius + float(rec["radius"]) + global_extra_clearance
		var dist_xz: float = Vector2(pos.x - other_pos.x, pos.z - other_pos.z).length()
		if dist_xz < min_allowed:
			return true
	return false


func _compute_decoration_world_pos(
	space_state: PhysicsDirectSpaceState3D,
	dist_along: float,
	total_len: float,
	signed_lateral_offset: float,
	snap_ground: bool
) -> Vector3:
	var local_center: Vector3 = curve.sample_baked(dist_along, true)
	var world_center: Vector3 = to_global(local_center)
	var d_prev: float = maxf(dist_along - 0.25, 0.0)
	var d_next: float = minf(dist_along + 0.25, total_len)
	var forward: Vector3 = (to_global(curve.sample_baked(d_next, true)) - to_global(curve.sample_baked(d_prev, true))).normalized()
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	var right: Vector3 = forward.cross(Vector3.UP).normalized()

	var world_pos: Vector3 = world_center + right * signed_lateral_offset
	if snap_ground:
		var hit: Dictionary = _raycast_terrain_at(space_state, world_pos.x, world_pos.z)
		if not hit.is_empty():
			world_pos.y = (hit["position"] as Vector3).y
	return world_pos


func _instantiate_decoration_at(
	entry: PathDecorationEntry,
	entry_idx: int,
	decos_root: Node3D,
	scene_owner: Node,
	space_state: PhysicsDirectSpaceState3D,
	rng: RandomNumberGenerator,
	dist_along: float,
	total_len: float,
	side_sign: float,
	lat_dist: float,
	placed_records: Array[Dictionary]
) -> void:
	var local_center: Vector3 = curve.sample_baked(dist_along, true)
	var world_center: Vector3 = to_global(local_center)
	var d_prev: float = maxf(dist_along - 0.25, 0.0)
	var d_next: float = minf(dist_along + 0.25, total_len)
	var forward: Vector3 = (to_global(curve.sample_baked(d_next, true)) - to_global(curve.sample_baked(d_prev, true))).normalized()
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	var right: Vector3 = forward.cross(Vector3.UP).normalized()

	var world_pos: Vector3 = world_center + right * (lat_dist * side_sign)
	var ground_normal := Vector3.UP

	if entry.snap_to_terrain:
		var hit: Dictionary = _raycast_terrain_at(space_state, world_pos.x, world_pos.z)
		if not hit.is_empty():
			world_pos.y = (hit["position"] as Vector3).y
			ground_normal = (hit["normal"] as Vector3).normalized()

	world_pos.y += entry.vertical_offset

	var inst_3d: Node3D = null
	if entry.decoration_scene:
		var inst: Node = entry.decoration_scene.instantiate()
		if inst is Node3D:
			inst_3d = inst as Node3D
		else:
			inst.free()
			return
	elif entry.decoration_mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = entry.decoration_mesh
		if entry.mesh_material_override:
			mi.material_override = entry.mesh_material_override
		inst_3d = mi

	if not inst_3d:
		return

	if decoration_max_distance > 0.0:
		if inst_3d is GeometryInstance3D:
			(inst_3d as GeometryInstance3D).visibility_range_end = decoration_max_distance
		for sub_vis: Node in inst_3d.find_children("*", "GeometryInstance3D", true, false):
			if sub_vis is GeometryInstance3D:
				(sub_vis as GeometryInstance3D).visibility_range_end = decoration_max_distance

	inst_3d.name = "Deco_%d_%d" % [entry_idx, placed_records.size()]
	decos_root.add_child(inst_3d)
	if scene_owner:
		inst_3d.owner = scene_owner

	var base_yaw: float = atan2(forward.x, forward.z)
	var side_flip: float = PI if (side_sign < 0.0 and entry.mirror_yaw_on_left_side) else 0.0
	var yaw_jitter: float = deg_to_rad(rng.randf_range(-entry.random_yaw_jitter_degrees, entry.random_yaw_jitter_degrees))
	var final_yaw: float = base_yaw + side_flip + deg_to_rad(entry.yaw_offset_degrees) + yaw_jitter

	var up_vec: Vector3 = Vector3.UP.lerp(ground_normal, entry.align_to_slope_factor).normalized()
	var fwd_vec := Vector3(sin(final_yaw), 0.0, cos(final_yaw))
	var right_vec: Vector3 = up_vec.cross(fwd_vec).normalized()
	if right_vec.length_squared() < 0.0001:
		right_vec = Vector3.RIGHT
	fwd_vec = right_vec.cross(up_vec).normalized()

	var min_s: float = minf(entry.scale_range.x, entry.scale_range.y)
	var max_s: float = maxf(entry.scale_range.x, entry.scale_range.y)
	var rand_scale: float = maxf(rng.randf_range(min_s, max_s), 0.05)

	inst_3d.global_position = world_pos
	inst_3d.global_basis = Basis(right_vec, up_vec, fwd_vec).scaled(Vector3.ONE * rand_scale)

	placed_records.append({
		"pos": world_pos,
		"radius": entry.clearance_radius * rand_scale
	})

	_cached_deco_records.append({
		"entry_idx": entry_idx,
		"local_transform": inst_3d.transform
	})
#endregion


#region Multi-Hit Terrain Raycast (Pierces Non-Target Paths/Objects) & Disk Saving
func _raycast_terrain_at(space_state: PhysicsDirectSpaceState3D, world_x: float, world_z: float) -> Dictionary:
	var base_y: float = target_terrain.global_position.y if is_instance_valid(target_terrain) else global_position.y
	var ray_start := Vector3(world_x, base_y + raycast_top_height, world_z)
	var ray_end := ray_start + Vector3.DOWN * raycast_length

	var exclude_rids: Array[RID] = []
	var own_body := get_node_or_null("RoadStaticBody3D") as CollisionObject3D
	if is_instance_valid(own_body):
		exclude_rids.append(own_body.get_rid())

	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	# Loop until we either hit our actual terrain target or reach the bottom of the ray
	for attempt: int in range(max_raycast_pierce_hits):
		query.exclude = exclude_rids
		var hit: Dictionary = space_state.intersect_ray(query)
		if hit.is_empty():
			return {}

		var collider: Object = hit.get("collider")
		if collider is Node and _is_valid_terrain_collider(collider as Node):
			return hit

		# Hit a non-target object (another road, house, tree, decoration, etc.):
		# exclude its RID and keep raycasting down to the terrain!
		if hit.has("rid"):
			var hit_rid: RID = hit["rid"]
			if hit_rid.is_valid() and not exclude_rids.has(hit_rid):
				exclude_rids.append(hit_rid)
			else:
				break
		else:
			break

	return {}


func _is_valid_terrain_collider(col_node: Node) -> bool:
	# Reject any road or spawned obstacle collider even if parented under a terrain chunk
	if col_node.is_in_group(&"road") or col_node.is_in_group(&"object") or col_node.is_in_group(&"house") or col_node.is_in_group(&"building"):
		return false

	# If a specific target_terrain is set, verify the collider belongs to that terrain's own chunk bodies
	if is_instance_valid(target_terrain):
		if col_node == target_terrain:
			return true
		if target_terrain.is_ancestor_of(col_node):
			if col_node.is_in_group(&"terrain_chunk_body") or col_node.name.begins_with("ChunkBody_") or col_node.name == "TerrainStaticBody3D":
				return true
			for grp: StringName in allowed_groups:
				if grp != &"" and col_node.is_in_group(grp):
					return true
		return false

	# Otherwise, check allowed_groups when no explicit target_terrain is assigned
	for grp: StringName in allowed_groups:
		if grp != &"" and (col_node.is_in_group(grp) or (col_node.get_parent() and col_node.get_parent().is_in_group(grp))):
			return true

	return false


func save_resources_to_disk() -> void:
	var edited_root: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	var scene_name: String = edited_root.scene_file_path.get_file().get_basename() if (edited_root and not edited_root.scene_file_path.is_empty()) else "default_level"
	var save_dir: String = "user://world_cache/%s" % scene_name

	if not DirAccess.dir_exists_absolute(save_dir):
		DirAccess.make_dir_recursive_absolute(save_dir)

	var cache_file: String = "%s/Road_%s_cache.res" % [save_dir, name.validate_filename()]
	_save_to_cache_file(cache_file)
	print("ToolPathProjector (%s): Saved road cache to '%s'." % [name, cache_file])
#endregion
