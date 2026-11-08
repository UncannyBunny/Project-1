@tool
## Unified multi-threaded terrain generator with per-chunk StaticBody3D trimesh colliders,
## per-chunk NavigationRegion3D group + AABB baking, standalone texture baking, and user:// caching.
class_name TerrainGenerator extends Node3D

enum SourceChannel {
	LUMINANCE,
	GRAYSCALE_AVG,
	RED,
	GREEN,
	BLUE,
	ALPHA
}

@export_group("Generator Actions")
@export_tool_button("Generate & Chunk Terrain", "MeshInstance3D") var btn_generate: Callable:
	get:
		return generate_terrain
@export_tool_button("Bake Materials / Textures Only", "MaterialPreviewCube") var btn_bake_textures: Callable:
	get:
		return bake_materials_only
@export_tool_button("Bake Chunk NavMeshes Only", "NavigationRegion3D") var btn_bake_navmeshes: Callable:
	get:
		return bake_chunk_navmeshes_editor
@export_tool_button("Clear Generated Terrain", "Clear") var btn_clear: Callable:
	get:
		return clear_terrain
@export_tool_button("Save Chunks & Colliders to user://", "Save") var btn_save: Callable:
	get:
		return save_resources_to_disk

@export_group("Texture & Normalization")
@export var source_texture: Texture2D
@export var source_channel: SourceChannel = SourceChannel.LUMINANCE
@export var normalize_colors: bool = true
@export var invert_height: bool = false
@export var height_curve: Curve
@export var fix_dead_pixels: bool = true
@export_range(0.0, 0.25, 0.001) var dead_pixel_threshold: float = 0.02
@export_range(0, 8, 1) var dead_pixel_rim_erosion: int = 2
@export var remove_local_pits_and_spikes: bool = true
@export_range(0.005, 0.25, 0.005) var pit_spike_threshold: float = 0.025
@export var use_bicubic_sampling: bool = true
@export_range(0, 20, 1) var smoothing_passes: int = 3
@export_range(1, 16, 1) var smoothing_radius: int = 3

@export_group("Dimensions & Detail")
@export var terrain_size: Vector3 = Vector3(128.0, 15.0, 128.0)
@export var detail: Vector2i = Vector2i(128, 128)
@export var chunk_grid: Vector2i = Vector2i(4, 4)
@export var uv_scale: Vector2 = Vector2(16.0, 16.0)
@export var generate_tangents: bool = true

@export_group("Height Materials & Border Noise")
@export var height_materials: Dictionary[float, Material] = {}
@export var fallback_material: Material
@export_range(0.05, 20.0, 0.05) var material_blend_range: float = 2.0
@export var border_noise: FastNoiseLite
@export_range(0.0, 15.0, 0.1) var border_noise_amplitude: float = 1.5
@export_range(0.01, 10.0, 0.01) var border_noise_scale: float = 1.0

@export_group("Performance & Culling")
@export_range(2, 30, 1) var frame_budget_ms: int = 8
@export var chunk_visibility_max_distance: float = 0.0
@export var chunk_visibility_fade_margin: float = 15.0
@export var cast_shadow: GeometryInstance3D.ShadowCastingSetting = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

@export_group("Per-Chunk Collision & Groups")
@export var generate_chunk_colliders: bool = true
@export var body_groups: Array[StringName] = [&"grass_surface"]
@export_flags_3d_physics var collision_layer: int = 1
@export_flags_3d_physics var collision_mask: int = 1

@export_group("Per-Chunk Navigation Baking")
@export var navigation_mesh_template: NavigationMesh
@export_range(2.0, 200.0, 1.0) var navmesh_vertical_margin: float = 25.0
@export_range(0.05, 1.0, 0.05) var default_nav_cell_size: float = 0.25
@export_range(0.05, 1.0, 0.05) var default_nav_cell_height: float = 0.15
@export_range(0.1, 2.0, 0.05) var default_nav_agent_radius: float = 0.45
@export_range(0.5, 4.0, 0.1) var default_nav_agent_height: float = 1.8
@export_range(0.05, 1.5, 0.05) var default_nav_agent_max_climb: float = 0.4
@export_range(5.0, 60.0, 1.0) var default_nav_agent_max_slope: float = 45.0
@export_flags_3d_navigation var chunk_navigation_layers: int = 1
@export_flags_3d_physics var navmesh_collision_mask: int = 1

@export_group("Storage")
@export var auto_save_to_disk: bool = false
@export var save_subfolder_name: String = "GeneratedTerrain"

var width_detail: int:
	get:
		return detail.x
var depth_detail: int:
	get:
		return detail.y

var _is_generating: bool = false
var _cancel_requested: bool = false

var _img_ref: Image
var _img_w: int = 0
var _img_h: int = 0
var _raw_pixels: PackedFloat32Array
var _row_mins: PackedFloat32Array
var _row_maxs: PackedFloat32Array
var _curve_lut: PackedFloat32Array

var _grid_w: int = 0
var _grid_d: int = 0
var _spacing_x: float = 1.0
var _spacing_z: float = 1.0
var _offset_x: float = 0.0
var _offset_z: float = 0.0
var _physics_heights: PackedFloat32Array
var _smooth_temp: PackedFloat32Array
var _valid_mask: PackedByteArray
var _eroded_mask: PackedByteArray
var _global_normals: PackedVector3Array

var _chunk_specs: Array[Dictionary] = []
var _chunk_results: Array[Dictionary] = []


func _ready() -> void:
	# Always rebuild the dynamic shader material at runtime to bypass Godot's ShaderMaterial .res texture stripping bug
	if not Engine.is_editor_hint():
		_refresh_chunk_materials_quietly.call_deferred()


func _refresh_chunk_materials_quietly() -> void:
	var chunks_root := get_node_or_null("TerrainChunks")
	if not chunks_root or chunks_root.get_child_count() == 0:
		return

	var active_material: Material = _build_blended_terrain_material()
	for child: Node in chunks_root.get_children():
		if child is MeshInstance3D:
			var chunk_inst := child as MeshInstance3D
			chunk_inst.material_override = active_material
			if chunk_inst.mesh is ArrayMesh and chunk_inst.mesh.get_surface_count() > 0:
				(chunk_inst.mesh as ArrayMesh).surface_set_material(0, active_material)


#region Chunk Lookup Helpers
func get_chunks_root() -> Node3D:
	return get_node_or_null("TerrainChunks") as Node3D


func get_all_chunk_nodes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var chunks_root := get_chunks_root()
	if not chunks_root:
		return out
	for child: Node in chunks_root.get_children():
		if child is MeshInstance3D:
			out.append(child as MeshInstance3D)
	return out
#endregion


#region Orchestrated Runtime Generation & user:// Cache
func generate_or_load_cached(
	cache_dir: String,
	use_existing_cache: bool,
	is_editor_preview: bool,
	progress_callback: Callable = Callable()
) -> void:
	if _is_generating or not is_inside_tree():
		return

	var manifest_file: String = "%s/%s_TerrainManifest.res" % [cache_dir, name.validate_filename()]

	if use_existing_cache and not is_editor_preview and FileAccess.file_exists(manifest_file):
		if await _load_terrain_from_cache(manifest_file, progress_callback):
			return

	await _generate_terrain_internal(
		not is_editor_preview and not progress_callback.is_valid(),
		is_editor_preview,
		cache_dir if not is_editor_preview else "",
		progress_callback
	)


func _load_terrain_from_cache(
	manifest_file: String,
	progress_callback: Callable
) -> bool:
	var manifest: Resource = ResourceLoader.load(manifest_file, "", ResourceLoader.CACHE_MODE_REPLACE)
	if not manifest or not manifest.has_meta("chunk_entries"):
		return false

	var chunk_entries: Array = manifest.get_meta("chunk_entries")
	if chunk_entries.is_empty():
		return false

	if progress_callback.is_valid():
		progress_callback.call(5.0, "Generating terrain...")
	await get_tree().process_frame

	# Build the blended ShaderMaterial fresh in memory from height_materials (never load TerrainMaterial.res from disk!)
	var active_material: Material = _build_blended_terrain_material()

	_clear_chunks_internal()
	var chunks_root := Node3D.new()
	chunks_root.name = "TerrainChunks"

	var total_chunks: int = chunk_entries.size()
	var frame_start: int = Time.get_ticks_msec()

	for i: int in range(total_chunks):
		var entry: Dictionary = chunk_entries[i]
		var c_name: String = str(entry.get("name", "Chunk_%d" % i))
		var cx: int = int(entry.get("cx", 0))
		var cz: int = int(entry.get("cz", 0))
		var c_center: Vector3 = entry.get("center", Vector3.ZERO)
		var mesh_path: String = str(entry.get("mesh_path", ""))
		var col_path: String = str(entry.get("col_path", ""))

		if mesh_path.is_empty() or not FileAccess.file_exists(mesh_path):
			chunks_root.free()
			return false

		var c_mesh: Mesh = ResourceLoader.load(mesh_path, "", ResourceLoader.CACHE_MODE_REPLACE) as Mesh
		if not c_mesh:
			chunks_root.free()
			return false

		if active_material and c_mesh is ArrayMesh and c_mesh.get_surface_count() > 0:
			(c_mesh as ArrayMesh).surface_set_material(0, active_material)

		var chunk_inst := MeshInstance3D.new()
		chunk_inst.name = c_name
		chunk_inst.mesh = c_mesh
		chunk_inst.material_override = active_material
		chunk_inst.position = c_center
		chunk_inst.scale = Vector3.ONE
		chunk_inst.cast_shadow = cast_shadow

		if chunk_visibility_max_distance > 0.0:
			chunk_inst.visibility_range_end = chunk_visibility_max_distance
			chunk_inst.visibility_range_end_margin = chunk_visibility_fade_margin
			chunk_inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

		if generate_chunk_colliders:
			var c_shape: Shape3D = null
			if not col_path.is_empty() and FileAccess.file_exists(col_path):
				c_shape = ResourceLoader.load(col_path, "", ResourceLoader.CACHE_MODE_REPLACE) as Shape3D
			if not c_shape:
				c_shape = c_mesh.create_trimesh_shape()

			var chunk_body := _create_chunk_static_body(cx, cz, c_shape)
			chunk_inst.add_child(chunk_body)

		chunks_root.add_child(chunk_inst)

		if Time.get_ticks_msec() - frame_start >= frame_budget_ms:
			if progress_callback.is_valid():
				var pct: float = 10.0 + (float(i + 1) / float(maxi(total_chunks, 1))) * 90.0
				progress_callback.call(pct, "Generating terrain...")
			await get_tree().process_frame
			frame_start = Time.get_ticks_msec()

	add_child(chunks_root)
	# Ensure materials are freshly bound after entering the SceneTree
	_refresh_chunk_materials_quietly.call_deferred()

	if progress_callback.is_valid():
		progress_callback.call(100.0, "Generating terrain...")
	return true


func _create_chunk_static_body(cx: int, cz: int, shape: Shape3D) -> StaticBody3D:
	var chunk_body := StaticBody3D.new()
	chunk_body.name = "ChunkBody_%d_%d" % [cx, cz]
	chunk_body.collision_layer = collision_layer
	chunk_body.collision_mask = collision_mask
	chunk_body.add_to_group(&"terrain_chunk_body", true)
	for grp: StringName in body_groups:
		if grp != &"" and not chunk_body.is_in_group(grp):
			chunk_body.add_to_group(grp, true)

	var chunk_col := CollisionShape3D.new()
	chunk_col.name = "ChunkCol_%d_%d" % [cx, cz]
	chunk_col.scale = Vector3.ONE
	chunk_col.shape = shape

	chunk_body.add_child(chunk_col)
	return chunk_body
#endregion


#region Standalone Material / Texture Baking Action
func bake_materials_only() -> void:
	var chunks_root := get_node_or_null("TerrainChunks")
	if not chunks_root or chunks_root.get_child_count() == 0:
		push_warning("TerrainGenerator: No existing TerrainChunks found. Run 'Generate & Chunk Terrain' first.")
		return

	var active_material: Material = _build_blended_terrain_material()
	var updated_count: int = 0

	for child: Node in chunks_root.get_children():
		if child is MeshInstance3D and child.mesh:
			var chunk_inst := child as MeshInstance3D
			chunk_inst.material_override = active_material
			if chunk_inst.mesh is ArrayMesh and chunk_inst.mesh.get_surface_count() > 0:
				(chunk_inst.mesh as ArrayMesh).surface_set_material(0, active_material)
			updated_count += 1

	print("TerrainGenerator: Baked and applied materials/textures to %d existing chunks." % updated_count)
#endregion


#region Main Generation Coroutine
func generate_terrain() -> void:
	var is_ed: bool = Engine.is_editor_hint()
	var target_cache_dir: String = _get_target_save_dir() if auto_save_to_disk else ""
	await _generate_terrain_internal(is_ed, is_ed, target_cache_dir, Callable())


func _generate_terrain_internal(
	show_editor_popup: bool,
	set_editor_owner: bool,
	cache_dir_to_save: String,
	progress_callback: Callable
) -> void:
	if _is_generating:
		push_warning("TerrainGenerator: Generation is already in progress.")
		return
	if not source_texture:
		printerr("TerrainGenerator: No source_texture assigned.")
		return
	if not is_inside_tree():
		return

	_is_generating = true
	_cancel_requested = false

	var popup_data: Dictionary = _create_progress_popup() if show_editor_popup else {}
	popup_data["external_cb"] = progress_callback

	_update_progress(popup_data, 0.0, "Stage 1/8: Extracting image from Texture2D...", 0.0, "Decompressing texture...")
	await get_tree().process_frame

	var img: Image = source_texture.get_image()
	if not img and source_texture is NoiseTexture2D:
		await source_texture.changed
		img = source_texture.get_image()

	if not img or img.is_empty():
		printerr("TerrainGenerator: Could not retrieve a valid Image from source_texture.")
		_close_progress_popup(popup_data)
		_is_generating = false
		return

	_img_ref = img.duplicate() as Image
	if _img_ref.is_compressed():
		_img_ref.decompress()

	var max_needed_w: int = clampi(maxi(detail.x, 2) * 2, 256, 4096)
	var max_needed_h: int = clampi(maxi(detail.y, 2) * 2, 256, 4096)
	if _img_ref.get_width() > max_needed_w * 2 or _img_ref.get_height() > max_needed_h * 2:
		_update_progress(popup_data, 1.0, "Stage 1/8: Downsampling ultra-high-res texture...", 25.0, "Resizing image...")
		await get_tree().process_frame
		_img_ref.resize(max_needed_w, max_needed_h, Image.INTERPOLATE_BILINEAR)

	_img_w = _img_ref.get_width()
	_img_h = _img_ref.get_height()
	_raw_pixels = PackedFloat32Array()
	_raw_pixels.resize(_img_w * _img_h)
	_row_mins = PackedFloat32Array()
	_row_mins.resize(_img_h)
	_row_maxs = PackedFloat32Array()
	_row_maxs.resize(_img_h)

	_raw_pixels[0] = 0.0
	_row_mins[0] = 0.0
	_row_maxs[0] = 0.0

	if not await _run_threaded_group(
		_thread_extract_pixel_row,
		_img_h,
		popup_data,
		2.0,
		12.0,
		"Stage 1/8: Scanning texture colors...",
		"Scanning pixel rows"
	):
		_abort_generation(popup_data)
		return

	var min_val: float = INF
	var max_val: float = -INF
	for py: int in range(_img_h):
		if _row_mins[py] < min_val:
			min_val = _row_mins[py]
		if _row_maxs[py] > max_val:
			max_val = _row_maxs[py]

	if min_val == INF or max_val == -INF:
		min_val = 0.0
		max_val = 1.0

	if normalize_colors:
		var val_range: float = max_val - min_val
		if val_range > 0.00001:
			for i: int in range(_raw_pixels.size()):
				if _raw_pixels[i] >= 0.0:
					_raw_pixels[i] = clampf((_raw_pixels[i] - min_val) / val_range, 0.0, 1.0)
		else:
			_raw_pixels.fill(0.0)

	_grid_w = maxi(detail.x, 2)
	_grid_d = maxi(detail.y, 2)
	_spacing_x = maxf(terrain_size.x, 0.1) / float(_grid_w - 1)
	_spacing_z = maxf(terrain_size.z, 0.1) / float(_grid_d - 1)
	_offset_x = terrain_size.x * 0.5
	_offset_z = terrain_size.z * 0.5

	_physics_heights = PackedFloat32Array()
	_physics_heights.resize(_grid_w * _grid_d)
	_physics_heights[0] = 0.0

	_valid_mask = PackedByteArray()
	_valid_mask.resize(_grid_w * _grid_d)
	_valid_mask.fill(1)
	_valid_mask[0] = 1

	if not await _run_threaded_group(
		_thread_sample_height_row,
		_grid_d,
		popup_data,
		12.0,
		22.0,
		"Stage 2/8: Sampling normalized height grid...",
		"Sampling height rows"
	):
		_abort_generation(popup_data)
		return

	if fix_dead_pixels or remove_local_pits_and_spikes:
		_eroded_mask = PackedByteArray()
		_eroded_mask.resize(_grid_w * _grid_d)
		_eroded_mask.fill(1)
		_eroded_mask[0] = 1

		if not await _run_threaded_group(
			_thread_detect_defects_row,
			_grid_d,
			popup_data,
			22.0,
			26.0,
			"Stage 2.5/8: Detecting dead rims, pits & spikes...",
			"Scanning grid rows for defects"
		):
			_abort_generation(popup_data)
			return

		_smooth_temp = PackedFloat32Array()
		_smooth_temp.resize(_grid_w * _grid_d)
		_smooth_temp[0] = 0.0

		if not await _run_threaded_group(
			_thread_heal_grid_defects_row,
			_grid_d,
			popup_data,
			26.0,
			31.0,
			"Stage 2.5/8: Inpainting craters & spikes from clean terrain...",
			"Healing defect rows"
		):
			_abort_generation(popup_data)
			return

		_physics_heights = _smooth_temp
		_smooth_temp = PackedFloat32Array()

	_curve_lut = PackedFloat32Array()
	if height_curve:
		height_curve.bake()
		_curve_lut.resize(1024)
		for i: int in range(1024):
			_curve_lut[i] = height_curve.sample_baked(float(i) / 1023.0)

	var has_lut: bool = not _curve_lut.is_empty()
	var max_h: float = terrain_size.y
	for i: int in range(_physics_heights.size()):
		var nh: float = clampf(_physics_heights[i], 0.0, 1.0)
		if invert_height:
			nh = 1.0 - nh
		if has_lut:
			var lut_idx: int = clampi(int(roundf(nh * 1023.0)), 0, 1023)
			nh = _curve_lut[lut_idx]
		_physics_heights[i] = nh * max_h

	if smoothing_passes > 0:
		_smooth_temp = PackedFloat32Array()
		_smooth_temp.resize(_grid_w * _grid_d)
		_physics_heights[0] = _physics_heights[0]
		_smooth_temp[0] = 0.0

		for pass_idx: int in range(smoothing_passes):
			var p_start: float = 31.0 + (float(pass_idx) / float(smoothing_passes)) * 10.0
			var p_mid: float = (p_start + 31.0 + (float(pass_idx + 1) / float(smoothing_passes)) * 10.0) * 0.5
			var p_end: float = 31.0 + (float(pass_idx + 1) / float(smoothing_passes)) * 10.0

			if not await _run_threaded_group(
				_thread_smooth_row_horizontal,
				_grid_d,
				popup_data,
				p_start,
				p_mid,
				"Stage 3/8: Smoothing heightfield (Pass %d/%d H)..." % [pass_idx + 1, smoothing_passes],
				"Smoothing rows horizontally"
			):
				_abort_generation(popup_data)
				return

			if not await _run_threaded_group(
				_thread_smooth_row_vertical,
				_grid_d,
				popup_data,
				p_mid,
				p_end,
				"Stage 3/8: Smoothing heightfield (Pass %d/%d V)..." % [pass_idx + 1, smoothing_passes],
				"Smoothing rows vertically"
			):
				_abort_generation(popup_data)
				return

	_global_normals = PackedVector3Array()
	_global_normals.resize(_grid_w * _grid_d)
	_global_normals[0] = Vector3.UP

	if not await _run_threaded_group(
		_thread_normal_row,
		_grid_d,
		popup_data,
		41.0,
		52.0,
		"Stage 4/8: Computing seamless global normals...",
		"Calculating normal rows"
	):
		_abort_generation(popup_data)
		return

	_update_progress(popup_data, 53.0, "Stage 5/8: Building height-blended material...", 50.0, "Compiling shader layers...")
	await get_tree().process_frame
	var active_material: Material = _build_blended_terrain_material()

	var chunks_x: int = maxi(chunk_grid.x, 1)
	var chunks_z: int = maxi(chunk_grid.y, 1)
	var quads_x: int = _grid_w - 1
	var quads_z: int = _grid_d - 1

	_chunk_specs.clear()
	for cz: int in range(chunks_z):
		var q_start_z: int = int(floorf(float(cz * quads_z) / float(chunks_z)))
		var q_end_z: int = int(floorf(float((cz + 1) * quads_z) / float(chunks_z)))
		if q_end_z <= q_start_z:
			continue
		for cx: int in range(chunks_x):
			var q_start_x: int = int(floorf(float(cx * quads_x) / float(chunks_x)))
			var q_end_x: int = int(floorf(float((cx + 1) * quads_x) / float(chunks_x)))
			if q_end_x <= q_start_x:
				continue
			_chunk_specs.append({
				"cx": cx,
				"cz": cz,
				"q_start_x": q_start_x,
				"q_end_x": q_end_x,
				"q_start_z": q_start_z,
				"q_end_z": q_end_z
			})

	var total_chunks: int = _chunk_specs.size()
	_chunk_results.clear()
	_chunk_results.resize(total_chunks)

	if not await _run_threaded_group(
		_thread_build_chunk_data,
		total_chunks,
		popup_data,
		55.0,
		80.0,
		"Stage 6/8: Computing chunk geometry on worker threads...",
		"Building chunk arrays"
	):
		_abort_generation(popup_data)
		return

	_clear_chunks_internal()
	var chunks_root := Node3D.new()
	chunks_root.name = "TerrainChunks"
	var scene_owner: Node = get_tree().edited_scene_root if (Engine.is_editor_hint() and set_editor_owner) else null

	var frame_start: int = Time.get_ticks_msec()
	for i: int in range(total_chunks):
		var res: Dictionary = _chunk_results[i]
		var cx: int = res["cx"]
		var cz: int = res["cz"]

		var arr_mesh := ArrayMesh.new()
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res["arrays"])
		if active_material:
			arr_mesh.surface_set_material(0, active_material)

		var chunk_inst := MeshInstance3D.new()
		chunk_inst.name = res["name"]
		chunk_inst.mesh = arr_mesh
		chunk_inst.material_override = active_material
		chunk_inst.position = res["center"]
		chunk_inst.scale = Vector3.ONE
		chunk_inst.cast_shadow = cast_shadow

		if chunk_visibility_max_distance > 0.0:
			chunk_inst.visibility_range_end = chunk_visibility_max_distance
			chunk_inst.visibility_range_end_margin = chunk_visibility_fade_margin
			chunk_inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

		if generate_chunk_colliders:
			var chunk_body := _create_chunk_static_body(cx, cz, arr_mesh.create_trimesh_shape())
			chunk_inst.add_child(chunk_body)

		chunks_root.add_child(chunk_inst)

		if Time.get_ticks_msec() - frame_start >= frame_budget_ms:
			var task_pct: float = (float(i + 1) / float(maxi(total_chunks, 1))) * 100.0
			var overall_pct: float = lerpf(80.0, 93.0, task_pct / 100.0)
			_update_progress(
				popup_data,
				overall_pct,
				"Stage 7/8: Building chunk nodes & trimesh colliders...",
				task_pct,
				"Creating chunk & collider %d / %d" % [i + 1, total_chunks]
			)
			await get_tree().process_frame
			frame_start = Time.get_ticks_msec()
			if _cancel_requested:
				chunks_root.free()
				_abort_generation(popup_data)
				return

	add_child(chunks_root)
	if scene_owner:
		_set_owner_recursive(chunks_root, scene_owner)

	if not cache_dir_to_save.is_empty():
		await _save_resources_to_dir_async(cache_dir_to_save, popup_data, 93.0, 100.0)

	_cleanup_temp_buffers()
	_update_progress(popup_data, 100.0, "Complete!", 100.0, "Done!")
	await get_tree().process_frame
	_close_progress_popup(popup_data)
	_is_generating = false

	print("TerrainGenerator: Generated %d chunks with per-chunk StaticBody3D trimesh colliders (%dx%d detail, %.1fx%.1fx%.1fm)." % [
		total_chunks, _grid_w, _grid_d, terrain_size.x, terrain_size.y, terrain_size.z
	])


func _set_owner_recursive(node: Node, scene_owner: Node) -> void:
	node.owner = scene_owner
	for child: Node in node.get_children():
		_set_owner_recursive(child, scene_owner)
#endregion


#region Per-Chunk NavigationRegion3D Baking (Group + AABB + user:// Cache)
func bake_chunk_navmeshes_editor() -> void:
	var save_dir: String = _get_target_save_dir() if auto_save_to_disk else ""
	var popup_data: Dictionary = _create_progress_popup()
	if popup_data.has("dialog"):
		(popup_data["dialog"] as AcceptDialog).title = "Baking Chunk NavMeshes (%s)..." % name

	var editor_cb := func(t_pct: float, t_text: String) -> void:
		_update_progress(popup_data, t_pct, "Baking Per-Chunk NavigationMeshes...", t_pct, t_text)

	await bake_or_load_chunk_navmeshes(save_dir, false, Engine.is_editor_hint(), editor_cb)
	_close_progress_popup(popup_data)


func bake_or_load_chunk_navmeshes(
	cache_dir: String,
	use_existing_cache: bool,
	is_editor_preview: bool,
	progress_callback: Callable = Callable()
) -> void:
	var chunks: Array[MeshInstance3D] = get_all_chunk_nodes()
	if chunks.is_empty():
		push_warning("TerrainGenerator (%s): No TerrainChunks found to bake NavMeshes for." % name)
		return

	PhysicsServer3D.set_active(true)
	await get_tree().physics_frame

	var total_chunks: int = chunks.size()
	var scene_owner: Node = get_tree().edited_scene_root if (Engine.is_editor_hint() and is_editor_preview) else null

	var nav_map: RID = get_world_3d().navigation_map
	var template_cell_size: float = navigation_mesh_template.cell_size if navigation_mesh_template else default_nav_cell_size
	if nav_map.is_valid():
		var current_margin: float = NavigationServer3D.map_get_edge_connection_margin(nav_map)
		var min_recommended_margin: float = maxf(template_cell_size * 3.0, 0.6)
		if current_margin < min_recommended_margin:
			NavigationServer3D.map_set_edge_connection_margin(nav_map, min_recommended_margin)

	var chunk_grid_lookup: Dictionary = {}
	for chunk_inst: MeshInstance3D in chunks:
		var parts: PackedStringArray = chunk_inst.name.split("_")
		if parts.size() >= 3:
			chunk_grid_lookup[Vector2i(int(parts[1]), int(parts[2]))] = chunk_inst

	var external_static_bodies: Array[Dictionary] = _collect_external_static_bodies_with_aabbs()

	for i: int in range(total_chunks):
		if _cancel_requested:
			break

		var chunk_inst: MeshInstance3D = chunks[i]
		if not is_instance_valid(chunk_inst) or not chunk_inst.mesh:
			continue

		var c_name: String = chunk_inst.name
		var pct: float = (float(i) / float(maxi(total_chunks, 1))) * 100.0
		var nav_cache_path: String = (
			"%s/%s_%s_nav.res" % [cache_dir, name.validate_filename(), c_name]
			if not cache_dir.is_empty()
			else ""
		)

		var chunk_nav := chunk_inst.get_node_or_null("ChunkNav_%s" % c_name) as NavigationRegion3D
		if not is_instance_valid(chunk_nav):
			chunk_nav = NavigationRegion3D.new()
			chunk_nav.name = "ChunkNav_%s" % c_name
			chunk_nav.position = Vector3.ZERO
			chunk_nav.navigation_layers = chunk_navigation_layers
			chunk_inst.add_child(chunk_nav)
			if scene_owner:
				chunk_nav.owner = scene_owner

		if use_existing_cache and not is_editor_preview and not nav_cache_path.is_empty() and FileAccess.file_exists(nav_cache_path):
			var cached_nav: NavigationMesh = ResourceLoader.load(nav_cache_path, "", ResourceLoader.CACHE_MODE_REPLACE) as NavigationMesh
			if cached_nav:
				chunk_nav.navigation_mesh = cached_nav
				if progress_callback.is_valid() and (i % 4 == 0 or i == total_chunks - 1):
					progress_callback.call(pct, "Building navigation regions...")
					await get_tree().process_frame
				continue

		if progress_callback.is_valid():
			progress_callback.call(pct, "Building navigation regions...")
		await get_tree().process_frame

		var nav_mesh: NavigationMesh = _create_chunk_navigation_mesh()
		var c_size: float = maxf(nav_mesh.cell_size, 0.05)

		var erode_pad: float = ceilf(nav_mesh.agent_radius / c_size) * c_size
		nav_mesh.border_size = 0.0

		var raw_local_aabb: AABB = chunk_inst.get_aabb()
		var min_lx: float = raw_local_aabb.position.x - erode_pad
		var max_lx: float = raw_local_aabb.end.x + erode_pad
		var min_lz: float = raw_local_aabb.position.z - erode_pad
		var max_lz: float = raw_local_aabb.end.z + erode_pad
		var min_ly: float = raw_local_aabb.position.y - navmesh_vertical_margin
		var max_ly: float = raw_local_aabb.end.y + navmesh_vertical_margin

		var local_bake_aabb := AABB(
			Vector3(min_lx, min_ly, min_lz),
			Vector3(max_lx - min_lx, max_ly - min_ly, max_lz - min_lz)
		)
		nav_mesh.filter_baking_aabb = local_bake_aabb
		nav_mesh.filter_baking_aabb_offset = Vector3.ZERO

		var nav_group := StringName("nav_bake_%s_%s" % [name.validate_filename(), c_name])
		nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
		nav_mesh.geometry_source_group_name = nav_group

		var temp_grouped_nodes: Array[Node] = []

		var parts: PackedStringArray = c_name.split("_")
		if parts.size() >= 3:
			var cx: int = int(parts[1])
			var cz: int = int(parts[2])
			for dz: int in range(-1, 2):
				for dx: int in range(-1, 2):
					var n_chunk: MeshInstance3D = chunk_grid_lookup.get(Vector2i(cx + dx, cz + dz)) as MeshInstance3D
					if is_instance_valid(n_chunk) and not n_chunk.is_in_group(nav_group):
						n_chunk.add_to_group(nav_group)
						temp_grouped_nodes.append(n_chunk)
		else:
			chunk_inst.add_to_group(nav_group)
			temp_grouped_nodes.append(chunk_inst)

		var world_bake_aabb: AABB = chunk_inst.global_transform * local_bake_aabb
		var world_query_aabb: AABB = world_bake_aabb.grow(nav_mesh.agent_radius + 0.5)
		for ext_entry: Dictionary in external_static_bodies:
			var sb: StaticBody3D = ext_entry["body"] as StaticBody3D
			if not is_instance_valid(sb):
				continue
			var sb_aabb: AABB = ext_entry["aabb"]
			if world_query_aabb.intersects(sb_aabb) and not sb.is_in_group(nav_group):
				sb.add_to_group(nav_group)
				temp_grouped_nodes.append(sb)

		var source_data := NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(nav_mesh, source_data, chunk_nav)

		for g_node: Node in temp_grouped_nodes:
			if is_instance_valid(g_node) and g_node.is_in_group(nav_group):
				g_node.remove_from_group(nav_group)

		var bake_state := {"done": false}
		NavigationServer3D.bake_from_source_geometry_data_async(
			nav_mesh,
			source_data,
			func() -> void: bake_state["done"] = true
		)

		while not bool(bake_state["done"]):
			await get_tree().process_frame

		chunk_nav.navigation_mesh = nav_mesh

		if not is_editor_preview and not nav_cache_path.is_empty():
			ResourceSaver.save(nav_mesh, nav_cache_path, ResourceSaver.FLAG_COMPRESS)

	if progress_callback.is_valid():
		progress_callback.call(100.0, "Building navigation regions...")


func _collect_external_static_bodies_with_aabbs() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var root_node: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	if not is_instance_valid(root_node):
		root_node = get_parent()
	if not is_instance_valid(root_node):
		return results

	var chunks_root: Node3D = get_chunks_root()
	for node: Node in root_node.find_children("*", "StaticBody3D", true, false):
		if not (node is StaticBody3D):
			continue
		var sb := node as StaticBody3D
		if is_instance_valid(chunks_root) and chunks_root.is_ancestor_of(sb):
			continue
		if (sb.collision_layer & navmesh_collision_mask) == 0:
			continue
		var sb_aabb: AABB = _compute_static_body_world_aabb(sb)
		results.append({
			"body": sb,
			"aabb": sb_aabb
		})
	return results


func _compute_static_body_world_aabb(sb: StaticBody3D) -> AABB:
	var found_any: bool = false
	var combined := AABB()

	for child: Node in sb.get_children():
		if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
			var cs := child as CollisionShape3D
			if cs.shape:
				var dbg: ArrayMesh = cs.shape.get_debug_mesh()
				if dbg:
					var w_box: AABB = cs.global_transform * dbg.get_aabb()
					combined = w_box if not found_any else combined.merge(w_box)
					found_any = true

	if not found_any and sb.get_parent() is VisualInstance3D:
		var p_vis := sb.get_parent() as VisualInstance3D
		combined = p_vis.global_transform * p_vis.get_aabb()
		found_any = true

	if not found_any:
		combined = AABB(sb.global_position - Vector3(4.0, 4.0, 4.0), Vector3(8.0, 8.0, 8.0))
	return combined


func _create_chunk_navigation_mesh() -> NavigationMesh:
	var nav_mesh: NavigationMesh
	if navigation_mesh_template:
		nav_mesh = navigation_mesh_template.duplicate() as NavigationMesh
	else:
		nav_mesh = NavigationMesh.new()
		nav_mesh.cell_size = default_nav_cell_size
		nav_mesh.cell_height = default_nav_cell_height
		nav_mesh.agent_radius = default_nav_agent_radius
		nav_mesh.agent_height = default_nav_agent_height
		nav_mesh.agent_max_climb = default_nav_agent_max_climb
		nav_mesh.agent_max_slope = default_nav_agent_max_slope

	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_collision_mask = navmesh_collision_mask
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	return nav_mesh
#endregion


#region WorkerThreadPool Tasks
func _run_threaded_group(
	task_callable: Callable,
	element_count: int,
	popup_data: Dictionary,
	overall_start: float,
	overall_end: float,
	overall_text: String,
	task_prefix: String
) -> bool:
	if element_count <= 0:
		return true

	var group_id: int = WorkerThreadPool.add_group_task(task_callable, element_count, -1, true)
	while not WorkerThreadPool.is_group_task_completed(group_id):
		var done: int = WorkerThreadPool.get_group_processed_element_count(group_id)
		var task_pct: float = (float(done) / float(element_count)) * 100.0
		var overall_pct: float = lerpf(overall_start, overall_end, task_pct / 100.0)
		_update_progress(
			popup_data,
			overall_pct,
			overall_text,
			task_pct,
			"%s (%d / %d)..." % [task_prefix, done, element_count]
		)
		await get_tree().process_frame
		if _cancel_requested:
			WorkerThreadPool.wait_for_group_task_completion(group_id)
			return false

	WorkerThreadPool.wait_for_group_task_completion(group_id)
	_update_progress(
		popup_data,
		overall_end,
		overall_text,
		100.0,
		"%s (%d / %d)..." % [task_prefix, element_count, element_count]
	)
	return true


func _thread_extract_pixel_row(py: int) -> void:
	var row_min: float = INF
	var row_max: float = -INF
	var base_idx: int = py * _img_w

	for px: int in range(_img_w):
		var c: Color = _img_ref.get_pixel(px, py)
		var val: float = _extract_channel(c)

		if fix_dead_pixels and (val <= dead_pixel_threshold or c.a <= 0.01):
			_raw_pixels[base_idx + px] = -1.0
			continue

		_raw_pixels[base_idx + px] = val
		if val < row_min:
			row_min = val
		if val > row_max:
			row_max = val

	_row_mins[py] = row_min
	_row_maxs[py] = row_max


func _thread_sample_height_row(z: int) -> void:
	var v: float = float(z) / float(_grid_d - 1)
	var row_offset: int = z * _grid_w

	for x: int in range(_grid_w):
		var u: float = float(x) / float(_grid_w - 1)
		var sample_res: Vector2 = (
			_sample_bicubic_safe(_raw_pixels, _img_w, _img_h, u, v)
			if use_bicubic_sampling
			else _sample_bilinear_safe(_raw_pixels, _img_w, _img_h, u, v)
		)
		_physics_heights[row_offset + x] = sample_res.x
		_valid_mask[row_offset + x] = 1 if sample_res.y >= 0.5 else 0


func _thread_detect_defects_row(z: int) -> void:
	var row_offset: int = z * _grid_w
	var erode_r: int = maxi(dead_pixel_rim_erosion, 0)
	var max_x: int = _grid_w - 1
	var max_z: int = _grid_d - 1

	for x: int in range(_grid_w):
		var idx: int = row_offset + x
		var is_clean: bool = (_valid_mask[idx] == 1)

		if is_clean and fix_dead_pixels and erode_r > 0:
			for dz: int in range(-erode_r, erode_r + 1):
				var sz: int = clampi(z + dz, 0, max_z) * _grid_w
				for dx: int in range(-erode_r, erode_r + 1):
					var sx: int = clampi(x + dx, 0, max_x)
					if _valid_mask[sz + sx] == 0:
						is_clean = false
						break
				if not is_clean:
					break

		if is_clean and remove_local_pits_and_spikes:
			var center_h: float = _physics_heights[idx]
			var ring_sum: float = 0.0
			var ring_count: int = 0
			var check_r: int = 4

			for dz: int in [-check_r, -2, 2, check_r]:
				var sz: int = clampi(z + dz, 0, max_z) * _grid_w
				for dx: int in [-check_r, -2, 2, check_r]:
					var sx: int = clampi(x + dx, 0, max_x)
					if _valid_mask[sz + sx] == 1:
						ring_sum += _physics_heights[sz + sx]
						ring_count += 1

			if ring_count >= 4:
				var ring_avg: float = ring_sum / float(ring_count)
				if absf(center_h - ring_avg) > pit_spike_threshold:
					is_clean = false

		_eroded_mask[idx] = 1 if is_clean else 0


func _thread_heal_grid_defects_row(z: int) -> void:
	var row_offset: int = z * _grid_w
	var max_x: int = _grid_w - 1
	var max_z: int = _grid_d - 1
	var max_search_r: int = mini(maxi(_grid_w, _grid_d) / 2, 64)

	for x: int in range(_grid_w):
		var idx: int = row_offset + x
		if _eroded_mask[idx] == 1:
			_smooth_temp[idx] = _physics_heights[idx]
			continue

		var weighted_sum: float = 0.0
		var weight_total: float = 0.0
		var found_clean_ring: int = 0

		for r: int in range(1, max_search_r + 1):
			var z_min: int = maxi(z - r, 0)
			var z_max: int = mini(z + r, max_z)
			var x_min: int = maxi(x - r, 0)
			var x_max: int = mini(x + r, max_x)

			for sz: int in [z_min, z_max]:
				var r_off: int = sz * _grid_w
				for sx: int in range(x_min, x_max + 1):
					if _eroded_mask[r_off + sx] == 1:
						var d2: float = float((sx - x) * (sx - x) + (sz - z) * (sz - z))
						var w: float = 1.0 / maxf(d2, 1.0)
						weighted_sum += _physics_heights[r_off + sx] * w
						weight_total += w

			for sz: int in range(z_min + 1, z_max):
				var r_off: int = sz * _grid_w
				for sx: int in [x_min, x_max]:
					if _eroded_mask[r_off + sx] == 1:
						var d2: float = float((sx - x) * (sx - x) + (sz - z) * (sz - z))
						var w: float = 1.0 / maxf(d2, 1.0)
						weighted_sum += _physics_heights[r_off + sx] * w
						weight_total += w

			if weight_total > 0.0:
				found_clean_ring += 1
				if found_clean_ring >= 2:
					break

		_smooth_temp[idx] = (weighted_sum / weight_total) if weight_total > 0.0 else 0.0


func _thread_smooth_row_horizontal(z: int) -> void:
	var row_offset: int = z * _grid_w
	var rad: int = maxi(smoothing_radius, 1)
	var max_x: int = _grid_w - 1

	for x: int in range(_grid_w):
		var sum: float = 0.0
		var weight_sum: float = 0.0
		for dx: int in range(-rad, rad + 1):
			var sx: int = clampi(x + dx, 0, max_x)
			var w: float = float(rad + 1 - absi(dx))
			sum += _physics_heights[row_offset + sx] * w
			weight_sum += w
		_smooth_temp[row_offset + x] = sum / weight_sum


func _thread_smooth_row_vertical(z: int) -> void:
	var row_offset: int = z * _grid_w
	var rad: int = maxi(smoothing_radius, 1)
	var max_z: int = _grid_d - 1

	for x: int in range(_grid_w):
		var sum: float = 0.0
		var weight_sum: float = 0.0
		for dz: int in range(-rad, rad + 1):
			var sz: int = clampi(z + dz, 0, max_z)
			var w: float = float(rad + 1 - absi(dz))
			sum += _smooth_temp[sz * _grid_w + x] * w
			weight_sum += w
		_physics_heights[row_offset + x] = sum / weight_sum


func _thread_normal_row(z: int) -> void:
	var z_up: int = maxi(z - 1, 0)
	var z_down: int = mini(z + 1, _grid_d - 1)
	var dz: float = float(z_down - z_up) * _spacing_z
	var row_c: int = z * _grid_w
	var row_up: int = z_up * _grid_w
	var row_down: int = z_down * _grid_w

	for x: int in range(_grid_w):
		var x_left: int = maxi(x - 1, 0)
		var x_right: int = mini(x + 1, _grid_w - 1)
		var dx: float = float(x_right - x_left) * _spacing_x

		var h_left: float = _physics_heights[row_c + x_left]
		var h_right: float = _physics_heights[row_c + x_right]
		var h_up: float = _physics_heights[row_up + x]
		var h_down: float = _physics_heights[row_down + x]

		var tangent_x := Vector3(dx, h_right - h_left, 0.0)
		var bitangent_z := Vector3(0.0, h_down - h_up, dz)
		_global_normals[row_c + x] = bitangent_z.cross(tangent_x).normalized()


func _thread_build_chunk_data(chunk_idx: int) -> void:
	if _cancel_requested:
		return

	var spec: Dictionary = _chunk_specs[chunk_idx]
	var cx: int = spec["cx"]
	var cz: int = spec["cz"]
	var q_start_x: int = spec["q_start_x"]
	var q_end_x: int = spec["q_end_x"]
	var q_start_z: int = spec["q_start_z"]
	var q_end_z: int = spec["q_end_z"]

	var c_verts_x: int = (q_end_x - q_start_x) + 1
	var c_verts_z: int = (q_end_z - q_start_z) + 1
	var c_quads_x: int = q_end_x - q_start_x
	var c_quads_z: int = q_end_z - q_start_z

	var min_world_x: float = (float(q_start_x) * _spacing_x) - _offset_x
	var max_world_x: float = (float(q_end_x) * _spacing_x) - _offset_x
	var min_world_z: float = (float(q_start_z) * _spacing_z) - _offset_z
	var max_world_z: float = (float(q_end_z) * _spacing_z) - _offset_z
	var chunk_center := Vector3((min_world_x + max_world_x) * 0.5, 0.0, (min_world_z + max_world_z) * 0.5)

	var total_verts: int = c_verts_x * c_verts_z
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()

	vertices.resize(total_verts)
	normals.resize(total_verts)
	if generate_tangents:
		tangents.resize(total_verts * 4)
	uvs.resize(total_verts)

	var inv_w: float = 1.0 / float(_grid_w - 1)
	var inv_d: float = 1.0 / float(_grid_d - 1)

	var v_idx: int = 0
	for lz: int in range(c_verts_z):
		var gz: int = q_start_z + lz
		var v_coord: float = float(gz) * inv_d * uv_scale.y
		var world_z: float = (float(gz) * _spacing_z) - _offset_z - chunk_center.z
		var row_base: int = gz * _grid_w

		for lx: int in range(c_verts_x):
			var gx: int = q_start_x + lx
			var u_coord: float = float(gx) * inv_w * uv_scale.x
			var world_x: float = (float(gx) * _spacing_x) - _offset_x - chunk_center.x

			var g_idx: int = row_base + gx
			var h: float = _physics_heights[g_idx]
			var n: Vector3 = _global_normals[g_idx]

			vertices[v_idx] = Vector3(world_x, h, world_z)
			normals[v_idx] = n
			uvs[v_idx] = Vector2(u_coord, v_coord)

			if generate_tangents:
				var t: Vector3 = n.cross(Vector3.BACK).normalized()
				var t_base: int = v_idx * 4
				tangents[t_base + 0] = t.x
				tangents[t_base + 1] = t.y
				tangents[t_base + 2] = t.z
				tangents[t_base + 3] = 1.0

			v_idx += 1

	var indices := PackedInt32Array()
	indices.resize(c_quads_x * c_quads_z * 6)
	var i_idx: int = 0

	for lz: int in range(c_quads_z):
		var row0: int = lz * c_verts_x
		var row1: int = (lz + 1) * c_verts_x
		for lx: int in range(c_quads_x):
			var i0: int = row0 + lx
			var i1: int = i0 + 1
			var i2: int = row1 + lx
			var i3: int = i2 + 1

			indices[i_idx + 0] = i0
			indices[i_idx + 1] = i1
			indices[i_idx + 2] = i2
			indices[i_idx + 3] = i1
			indices[i_idx + 4] = i3
			indices[i_idx + 5] = i2
			i_idx += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	if generate_tangents:
		arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	_chunk_results[chunk_idx] = {
		"cx": cx,
		"cz": cz,
		"name": "Chunk_%d_%d" % [cx, cz],
		"center": chunk_center,
		"arrays": arrays
	}


func _cleanup_temp_buffers() -> void:
	_img_ref = null
	_raw_pixels = PackedFloat32Array()
	_row_mins = PackedFloat32Array()
	_row_maxs = PackedFloat32Array()
	_curve_lut = PackedFloat32Array()
	_physics_heights = PackedFloat32Array()
	_smooth_temp = PackedFloat32Array()
	_valid_mask = PackedByteArray()
	_eroded_mask = PackedByteArray()
	_global_normals = PackedVector3Array()
	_chunk_specs.clear()
	_chunk_results.clear()
#endregion


#region Reload-Safe Height-Blended Material & Shader Builder
func _build_blended_terrain_material() -> Material:
	if height_materials.is_empty():
		return fallback_material

	var sorted_heights: Array[float] = []
	for h_key: float in height_materials.keys():
		if height_materials[h_key] != null:
			sorted_heights.append(h_key)
	sorted_heights.sort()

	if sorted_heights.is_empty():
		return fallback_material

	if sorted_heights.size() == 1 and height_materials[sorted_heights[0]] is ShaderMaterial:
		return height_materials[sorted_heights[0]]

	var layer_count: int = mini(sorted_heights.size(), 8)
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = _get_or_create_height_blend_shader()

	var heights_arr := PackedFloat32Array()
	var colors_arr := PackedColorArray()
	var roughness_arr := PackedFloat32Array()
	var uv_scales_arr := PackedVector2Array()
	heights_arr.resize(8)
	colors_arr.resize(8)
	roughness_arr.resize(8)
	uv_scales_arr.resize(8)

	for i: int in range(8):
		var src_idx: int = mini(i, layer_count - 1)
		var h_val: float = sorted_heights[src_idx]
		var mat: Material = height_materials[h_val]

		heights_arr[i] = h_val
		colors_arr[i] = Color.WHITE
		roughness_arr[i] = 0.85
		uv_scales_arr[i] = Vector2.ONE

		if mat is BaseMaterial3D:
			var bmat := mat as BaseMaterial3D
			colors_arr[i] = bmat.albedo_color
			roughness_arr[i] = bmat.roughness
			uv_scales_arr[i] = Vector2(bmat.uv1_scale.x, bmat.uv1_scale.y)
			if bmat.albedo_texture:
				shader_mat.set_shader_parameter("layer_tex_%d" % i, bmat.albedo_texture)

	shader_mat.set_shader_parameter("layer_count", layer_count)
	shader_mat.set_shader_parameter("layer_heights", heights_arr)
	shader_mat.set_shader_parameter("layer_colors", colors_arr)
	shader_mat.set_shader_parameter("layer_roughness", roughness_arr)
	shader_mat.set_shader_parameter("layer_uv_scales", uv_scales_arr)
	shader_mat.set_shader_parameter("blend_range", maxf(material_blend_range, 0.05))

	if border_noise:
		var noise_tex := NoiseTexture2D.new()
		noise_tex.width = 256
		noise_tex.height = 256
		noise_tex.seamless = true
		noise_tex.noise = border_noise
		shader_mat.set_shader_parameter("border_noise_tex", noise_tex)
		shader_mat.set_shader_parameter("border_noise_amplitude", border_noise_amplitude)
		shader_mat.set_shader_parameter("border_noise_scale", border_noise_scale * 0.05)
	else:
		shader_mat.set_shader_parameter("border_noise_amplitude", 0.0)

	return shader_mat


func _get_or_create_height_blend_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform int layer_count = 1;
uniform float layer_heights[8];
uniform vec4 layer_colors[8];
uniform float layer_roughness[8];
uniform vec2 layer_uv_scales[8];

uniform sampler2D layer_tex_0 : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer_tex_1 : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer_tex_2 : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer_tex_3 : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer_tex_4 : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer_tex_5 : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer_tex_6 : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer_tex_7 : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;

uniform float blend_range = 2.0;
uniform sampler2D border_noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float border_noise_amplitude = 1.5;
uniform float border_noise_scale = 0.05;

varying float v_local_height;
varying vec2 v_world_xz;

vec3 sample_layer_albedo(int idx, vec2 uv) {
	vec2 scaled_uv = uv * layer_uv_scales[idx];
	vec4 tex = vec4(1.0);
	if (idx == 0) tex = texture(layer_tex_0, scaled_uv);
	else if (idx == 1) tex = texture(layer_tex_1, scaled_uv);
	else if (idx == 2) tex = texture(layer_tex_2, scaled_uv);
	else if (idx == 3) tex = texture(layer_tex_3, scaled_uv);
	else if (idx == 4) tex = texture(layer_tex_4, scaled_uv);
	else if (idx == 5) tex = texture(layer_tex_5, scaled_uv);
	else if (idx == 6) tex = texture(layer_tex_6, scaled_uv);
	else if (idx == 7) tex = texture(layer_tex_7, scaled_uv);
	return tex.rgb * layer_colors[idx].rgb;
}

void vertex() {
	v_local_height = VERTEX.y;
	v_world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float n1 = texture(border_noise_tex, v_world_xz * border_noise_scale).r * 2.0 - 1.0;
	float n2 = texture(border_noise_tex, v_world_xz * border_noise_scale * 2.37 + vec2(0.31, 0.73)).r * 2.0 - 1.0;
	float scrambled_h = v_local_height + (n1 * 0.65 + n2 * 0.35) * border_noise_amplitude;

	vec3 accum_albedo = sample_layer_albedo(0, UV);
	float accum_rough = layer_roughness[0];
	float half_blend = max(blend_range * 0.5, 0.02);

	for (int i = 1; i < 8; i++) {
		if (i >= layer_count) {
			break;
		}
		float h_thresh = layer_heights[i];
		float w = smoothstep(h_thresh - half_blend, h_thresh + half_blend, scrambled_h);
		if (w > 0.001) {
			vec3 next_albedo = sample_layer_albedo(i, UV);
			accum_albedo = mix(accum_albedo, next_albedo, w);
			accum_rough = mix(accum_rough, layer_roughness[i], w);
		}
	}

	ALBEDO = accum_albedo;
	ROUGHNESS = accum_rough;
}
"""
	return shader
#endregion


#region Filtering & Sampling Helpers
func _extract_channel(c: Color) -> float:
	match source_channel:
		SourceChannel.LUMINANCE:
			return c.get_luminance()
		SourceChannel.GRAYSCALE_AVG:
			return (c.r + c.g + c.b) / 3.0
		SourceChannel.RED:
			return c.r
		SourceChannel.GREEN:
			return c.g
		SourceChannel.BLUE:
			return c.b
		SourceChannel.ALPHA:
			return c.a
	return c.get_luminance()


func _sample_bilinear_safe(pixels: PackedFloat32Array, img_w: int, img_h: int, u: float, v: float) -> Vector2:
	var fx: float = clampf(u, 0.0, 1.0) * float(img_w - 1)
	var fy: float = clampf(v, 0.0, 1.0) * float(img_h - 1)

	var x0: int = int(floorf(fx))
	var y0: int = int(floorf(fy))
	var x1: int = mini(x0 + 1, img_w - 1)
	var y1: int = mini(y0 + 1, img_h - 1)

	var tx: float = fx - float(x0)
	var ty: float = fy - float(y0)

	var c00: float = pixels[x0 + y0 * img_w]
	var c10: float = pixels[x1 + y0 * img_w]
	var c01: float = pixels[x0 + y1 * img_w]
	var c11: float = pixels[x1 + y1 * img_w]

	if c00 < 0.0 or c10 < 0.0 or c01 < 0.0 or c11 < 0.0:
		return Vector2(0.0, 0.0)

	return Vector2(lerpf(lerpf(c00, c10, tx), lerpf(c01, c11, tx), ty), 1.0)


func _sample_bicubic_safe(pixels: PackedFloat32Array, img_w: int, img_h: int, u: float, v: float) -> Vector2:
	var fx: float = clampf(u, 0.0, 1.0) * float(img_w - 1)
	var fy: float = clampf(v, 0.0, 1.0) * float(img_h - 1)

	var x1: int = int(floorf(fx))
	var y1: int = int(floorf(fy))
	var tx: float = fx - float(x1)
	var ty: float = fy - float(y1)

	var max_x: int = img_w - 1
	var max_y: int = img_h - 1

	var xm1: int = maxi(x1 - 1, 0)
	var xp1: int = mini(x1 + 1, max_x)
	var xp2: int = mini(x1 + 2, max_x)

	var ym1: int = maxi(y1 - 1, 0) * img_w
	var y0: int = y1 * img_w
	var yp1: int = mini(y1 + 1, max_y) * img_w
	var yp2: int = mini(y1 + 2, max_y) * img_w

	var p00: float = pixels[xm1 + ym1]
	var p10: float = pixels[x1 + ym1]
	var p20: float = pixels[xp1 + ym1]
	var p30: float = pixels[xp2 + ym1]

	var p01: float = pixels[xm1 + y0]
	var p11: float = pixels[x1 + y0]
	var p21: float = pixels[xp1 + y0]
	var p31: float = pixels[xp2 + y0]

	var p02: float = pixels[xm1 + yp1]
	var p12: float = pixels[x1 + yp1]
	var p22: float = pixels[xp1 + yp1]
	var p32: float = pixels[xp2 + yp1]

	var p03: float = pixels[xm1 + yp2]
	var p13: float = pixels[x1 + yp2]
	var p23: float = pixels[xp1 + yp2]
	var p33: float = pixels[xp2 + yp2]

	if (
		p00 < 0.0 or p10 < 0.0 or p20 < 0.0 or p30 < 0.0 or
		p01 < 0.0 or p11 < 0.0 or p21 < 0.0 or p31 < 0.0 or
		p02 < 0.0 or p12 < 0.0 or p22 < 0.0 or p32 < 0.0 or
		p03 < 0.0 or p13 < 0.0 or p23 < 0.0 or p33 < 0.0
	):
		return Vector2(0.0, 0.0)

	var row0: float = _cubic_hermite_clamped(p00, p10, p20, p30, tx)
	var row1: float = _cubic_hermite_clamped(p01, p11, p21, p31, tx)
	var row2: float = _cubic_hermite_clamped(p02, p12, p22, p32, tx)
	var row3: float = _cubic_hermite_clamped(p03, p13, p23, p33, tx)

	return Vector2(_cubic_hermite_clamped(row0, row1, row2, row3, ty), 1.0)


func _cubic_hermite_clamped(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var a: float = -0.5 * p0 + 1.5 * p1 - 1.5 * p2 + 0.5 * p3
	var b: float = p0 - 2.5 * p1 + 2.0 * p2 - 0.5 * p3
	var c: float = -0.5 * p0 + 0.5 * p2
	var d: float = p1
	var val: float = ((a * t + b) * t + c) * t + d
	return clampf(val, minf(p1, p2), maxf(p1, p2))
#endregion


#region Cleanup & user:// Binary Disk Saving
func clear_terrain() -> void:
	if _is_generating:
		return
	_clear_chunks_internal()


func _clear_chunks_internal() -> void:
	var existing := get_node_or_null("TerrainChunks")
	if existing:
		if is_inside_tree():
			remove_child(existing)
		existing.free()
	var old_body := get_node_or_null("TerrainStaticBody3D")
	if old_body:
		if is_inside_tree():
			remove_child(old_body)
		old_body.free()


func _get_target_save_dir() -> String:
	var edited_root: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	var scene_name: String = (
		edited_root.scene_file_path.get_file().get_basename()
		if (edited_root and not edited_root.scene_file_path.is_empty())
		else "default_level"
	)
	var save_dir: String = "user://world_cache/%s" % scene_name

	if not DirAccess.dir_exists_absolute(save_dir):
		DirAccess.make_dir_recursive_absolute(save_dir)
	return save_dir


func save_resources_to_disk() -> void:
	var save_dir: String = _get_target_save_dir()
	if save_dir.is_empty():
		return
	_save_resources_to_dir_async(save_dir, {}, 0.0, 100.0)


func _save_resources_to_dir_async(
	save_dir: String,
	popup_data: Dictionary,
	overall_start: float,
	overall_end: float
) -> void:
	if save_dir.is_empty():
		return
	if not DirAccess.dir_exists_absolute(save_dir):
		DirAccess.make_dir_recursive_absolute(save_dir)

	var safe_name: String = name.validate_filename()
	var saved_chunks: int = 0
	var saved_colliders: int = 0
	var chunk_entries: Array[Dictionary] = []

	var chunks_root := get_node_or_null("TerrainChunks")
	if chunks_root:
		var children: Array[Node] = chunks_root.get_children()
		var total_c: int = children.size()
		var frame_start: int = Time.get_ticks_msec()

		for idx: int in range(total_c):
			var child: Node = children[idx]
			if child is MeshInstance3D and child.mesh:
				var chunk_inst := child as MeshInstance3D
				var parts: PackedStringArray = chunk_inst.name.split("_")
				var cx: int = int(parts[1]) if parts.size() > 1 else 0
				var cz: int = int(parts[2]) if parts.size() > 2 else 0

				var res_path: String = "%s/%s_%s.res" % [save_dir, safe_name, chunk_inst.name]
				if ResourceSaver.save(chunk_inst.mesh, res_path, ResourceSaver.FLAG_COMPRESS) == OK:
					saved_chunks += 1

				var col_path: String = ""
				for sub: Node in chunk_inst.find_children("*", "CollisionShape3D", false, false):
					if sub is CollisionShape3D and sub.shape and sub.name.begins_with("ChunkCol_"):
						var col := sub as CollisionShape3D
						col_path = "%s/%s_%s.res" % [save_dir, safe_name, col.name]
						if ResourceSaver.save(col.shape, col_path, ResourceSaver.FLAG_COMPRESS) == OK:
							saved_colliders += 1
						break

				chunk_entries.append({
					"name": chunk_inst.name,
					"cx": cx,
					"cz": cz,
					"center": chunk_inst.position,
					"mesh_path": res_path,
					"col_path": col_path
				})

			if Time.get_ticks_msec() - frame_start >= frame_budget_ms:
				var task_pct: float = (float(idx + 1) / float(maxi(total_c, 1))) * 100.0
				var overall_pct: float = lerpf(overall_start, overall_end, task_pct / 100.0)
				_update_progress(
					popup_data,
					overall_pct,
					"Stage 8/8: Saving compressed binary .res files to user://...",
					task_pct,
					"Saving chunk & collider %d / %d..." % [idx + 1, total_c]
				)
				await get_tree().process_frame
				frame_start = Time.get_ticks_msec()

	var manifest := Resource.new()
	manifest.set_meta("chunk_entries", chunk_entries)
	var manifest_path: String = "%s/%s_TerrainManifest.res" % [save_dir, safe_name]
	ResourceSaver.save(manifest, manifest_path, ResourceSaver.FLAG_COMPRESS)

	print("TerrainGenerator: Saved %d chunk meshes and %d chunk trimesh colliders to '%s'." % [saved_chunks, saved_colliders, save_dir])
#endregion


#region Dual-Bar Editor Progress Popup & Callback Bridge
func _create_progress_popup() -> Dictionary:
	var dialog := AcceptDialog.new()
	dialog.title = "Generating Terrain (%s)..." % name
	dialog.dialog_hide_on_ok = false
	dialog.get_ok_button().text = "Cancel"
	dialog.unresizable = true
	dialog.size = Vector2i(450, 210)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(420.0, 150.0)
	vbox.add_theme_constant_override("separation", 6)

	var overall_label := Label.new()
	overall_label.text = "Overall Progress:"
	vbox.add_child(overall_label)

	var overall_bar := ProgressBar.new()
	overall_bar.min_value = 0.0
	overall_bar.max_value = 100.0
	overall_bar.value = 0.0
	overall_bar.custom_minimum_size = Vector2(410.0, 22.0)
	vbox.add_child(overall_bar)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 4.0)
	vbox.add_child(spacer)

	var task_label := Label.new()
	task_label.text = "Current Task: Initializing..."
	vbox.add_child(task_label)

	var task_bar := ProgressBar.new()
	task_bar.min_value = 0.0
	task_bar.max_value = 100.0
	task_bar.value = 0.0
	task_bar.custom_minimum_size = Vector2(410.0, 22.0)
	vbox.add_child(task_bar)

	dialog.add_child(vbox)
	dialog.confirmed.connect(func() -> void: _cancel_requested = true)
	dialog.canceled.connect(func() -> void: _cancel_requested = true)

	get_tree().root.add_child(dialog)
	dialog.popup_centered()

	return {
		"dialog": dialog,
		"overall_label": overall_label,
		"overall_bar": overall_bar,
		"task_label": task_label,
		"task_bar": task_bar
	}


func _update_progress(
	popup_data: Dictionary,
	overall_pct: float,
	overall_text: String,
	task_pct: float,
	task_text: String
) -> void:
	if popup_data.has("external_cb"):
		var ext_cb: Callable = popup_data["external_cb"]
		if ext_cb.is_valid():
			ext_cb.call(overall_pct, task_text)

	var overall_bar := popup_data.get("overall_bar") as ProgressBar
	var overall_label := popup_data.get("overall_label") as Label
	var task_bar := popup_data.get("task_bar") as ProgressBar
	var task_label := popup_data.get("task_label") as Label

	if is_instance_valid(overall_bar):
		overall_bar.value = overall_pct
	if is_instance_valid(overall_label):
		overall_label.text = overall_text
	if is_instance_valid(task_bar):
		task_bar.value = task_pct
	if is_instance_valid(task_label):
		task_label.text = task_text


func _close_progress_popup(popup_data: Dictionary) -> void:
	var dialog := popup_data.get("dialog") as AcceptDialog
	if is_instance_valid(dialog):
		dialog.hide()
		dialog.queue_free()


func _abort_generation(popup_data: Dictionary) -> void:
	_cleanup_temp_buffers()
	_close_progress_popup(popup_data)
	_is_generating = false
	push_warning("TerrainGenerator: Terrain generation canceled by user.")
#endregion
