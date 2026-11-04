@tool
## Unified non-blocking terrain generator that normalizes any Texture2D into a HeightMapShape3D collider and culled visual chunks.
class_name TerrainGenerator extends Node3D

enum SourceChannel {
	LUMINANCE, ## Perceptual brightness (0.2126 R + 0.7152 G + 0.0722 B)
	GRAYSCALE_AVG, ## Simple average ((R + G + B) / 3.0)
	RED,
	GREEN,
	BLUE,
	ALPHA
}

@export_group("Generator Actions")
@export_tool_button("Generate & Chunk Terrain", "MeshInstance3D") var btn_generate: Callable:
	get:
		return generate_terrain
@export_tool_button("Clear Generated Terrain", "Clear") var btn_clear: Callable:
	get:
		return clear_terrain
@export_tool_button("Save Chunks & Collider to Disk", "Save") var btn_save: Callable:
	get:
		return save_resources_to_disk

@export_group("Texture & Normalization")
## Any Texture2D (Imported Image, NoiseTexture2D, GradientTexture2D, etc.)
@export var source_texture: Texture2D
## How color values are extracted from source_texture before normalizing
@export var source_channel: SourceChannel = SourceChannel.LUMINANCE
## Automatically remaps the darkest pixel in the texture to 0.0 and the brightest to 1.0
@export var normalize_colors: bool = true
## Inverts the normalized height values (1.0 - value)
@export var invert_height: bool = false
## Optional curve applied after normalization (0..1) to shape valleys and peaks
@export var height_curve: Curve
## Number of 3x3 smoothing passes applied to the height grid to remove pixel stair-stepping
@export_range(0, 10, 1) var smoothing_passes: int = 1

@export_group("Dimensions & Chunking")
## Total vertex count along the X axis
@export_range(4, 2049, 1) var width: int = 128
## Total vertex count along the Z axis
@export_range(4, 2049, 1) var depth: int = 128
## Distance in meters between adjacent vertices on X and Z
@export_range(0.1, 20.0, 0.05) var spacing: float = 1.0
## Maximum vertical height in meters (at normalized height 1.0)
@export var height_scale: float = 10.0
## Number of visual chunks along X and Z (e.g. 4x4 = 16 culled MeshInstance3D chunks)
@export var chunk_grid: Vector2i = Vector2i(4, 4)
## Material applied to all generated terrain chunks
@export var terrain_material: Material
## UV tiling multiplier across the entire terrain
@export var uv_scale: Vector2 = Vector2(1.0, 1.0)

@export_group("Performance & Culling")
## Maximum milliseconds spent generating per frame before yielding to keep the Editor responsive
@export_range(2, 30, 1) var frame_budget_ms: int = 8
## Distance in meters where individual chunks fade out (0 = never fade)
@export var chunk_visibility_max_distance: float = 0.0
@export var chunk_visibility_fade_margin: float = 15.0
## Shadow casting mode for terrain chunks
@export var cast_shadow: GeometryInstance3D.ShadowCastingSetting = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

@export_group("Collision & Groups")
## Optional external CollisionShape3D. If left empty, a StaticBody3D + CollisionShape3D is created automatically.
@export var height_map_body_collider: CollisionShape3D
## Groups automatically assigned to the generated StaticBody3D (compatible with ProceduralGrass whitelist!)
@export var body_groups: Array[StringName] = [&"grass_surface"]
@export_flags_3d_physics var collision_layer: int = 1
@export_flags_3d_physics var collision_mask: int = 1

@export_group("Storage")
## Automatically saves generated chunk meshes and HeightMapShape3D as compressed binary .res files to prevent large .tscn warnings
@export var auto_save_to_disk: bool = true
## Subfolder name created next to the current .tscn file
@export var save_subfolder_name: String = "GeneratedTerrain"

var _is_generating: bool = false
var _cancel_requested: bool = false


#region Main Generation Coroutine
func generate_terrain() -> void:
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

	var popup_data: Dictionary = _create_progress_popup()
	var frame_start: int = Time.get_ticks_msec()

	# 1. Extract & Decompress Image from Texture2D
	_update_progress(popup_data, 2.0, "Extracting image from Texture2D...")
	await get_tree().process_frame
	frame_start = Time.get_ticks_msec()

	var img: Image = source_texture.get_image()
	if not img and source_texture is NoiseTexture2D:
		await source_texture.changed
		img = source_texture.get_image()

	if not img or img.is_empty():
		printerr("TerrainGenerator: Could not retrieve a valid Image from source_texture.")
		_close_progress_popup(popup_data)
		_is_generating = false
		return

	# Work on a duplicate so we never mutate the original imported resource in memory
	img = img.duplicate() as Image
	if img.is_compressed():
		img.decompress()

	var img_w: int = img.get_width()
	var img_h: int = img.get_height()

	# 2. Extract Channel & Find Min/Max for Color Normalization
	var raw_pixels := PackedFloat32Array()
	raw_pixels.resize(img_w * img_h)

	var min_val: float = INF
	var max_val: float = -INF

	for py: int in range(img_h):
		for px: int in range(img_w):
			var c: Color = img.get_pixel(px, py)
			var val: float = _extract_channel(c)
			raw_pixels[px + py * img_w] = val
			if val < min_val:
				min_val = val
			if val > max_val:
				max_val = val

		if Time.get_ticks_msec() - frame_start >= frame_budget_ms:
			var pct: float = 2.0 + (float(py) / float(maxi(img_h, 1))) * 15.0
			_update_progress(popup_data, pct, "Scanning & normalizing texture colors (%d/%d)..." % [py, img_h])
			await get_tree().process_frame
			frame_start = Time.get_ticks_msec()
			if _cancel_requested:
				_abort_generation(popup_data)
				return

	var val_range: float = max_val - min_val
	if normalize_colors and val_range > 0.00001:
		for i: int in range(raw_pixels.size()):
			raw_pixels[i] = (raw_pixels[i] - min_val) / val_range
	elif normalize_colors:
		raw_pixels.fill(0.0)

	# 3. Sample Bilinear Height Grid (width x depth)
	var grid_w: int = maxi(width, 2)
	var grid_d: int = maxi(depth, 2)
	var physics_heights := PackedFloat32Array()
	physics_heights.resize(grid_w * grid_d)

	if height_curve:
		height_curve.bake()

	for z: int in range(grid_d):
		var v: float = float(z) / float(grid_d - 1)
		for x: int in range(grid_w):
			var u: float = float(x) / float(grid_w - 1)
			var norm_h: float = _sample_bilinear(raw_pixels, img_w, img_h, u, v)
			if invert_height:
				norm_h = 1.0 - norm_h
			if height_curve:
				norm_h = height_curve.sample_baked(clampf(norm_h, 0.0, 1.0))

			physics_heights[x + z * grid_w] = norm_h * height_scale

		if Time.get_ticks_msec() - frame_start >= frame_budget_ms:
			var pct: float = 17.0 + (float(z) / float(grid_d)) * 18.0
			_update_progress(popup_data, pct, "Sampling bilinear height grid (%d/%d)..." % [z, grid_d])
			await get_tree().process_frame
			frame_start = Time.get_ticks_msec()
			if _cancel_requested:
				_abort_generation(popup_data)
				return

	# 4. Optional Smoothing Passes (Prevents blocky stair-steps on low-res textures)
	for pass_idx: int in range(smoothing_passes):
		physics_heights = _smooth_height_grid(physics_heights, grid_w, grid_d)
		if Time.get_ticks_msec() - frame_start >= frame_budget_ms:
			_update_progress(popup_data, 36.0, "Smoothing heightfield (pass %d/%d)..." % [pass_idx + 1, smoothing_passes])
			await get_tree().process_frame
			frame_start = Time.get_ticks_msec()
			if _cancel_requested:
				_abort_generation(popup_data)
				return

	# 5. Precalculate Global Smooth Normals & Tangents (Prevents seams between chunks!)
	var global_normals := PackedVector3Array()
	global_normals.resize(grid_w * grid_d)

	for z: int in range(grid_d):
		var z_up: int = maxi(z - 1, 0)
		var z_down: int = mini(z + 1, grid_d - 1)
		var dz: float = float(z_down - z_up) * spacing

		for x: int in range(grid_w):
			var x_left: int = maxi(x - 1, 0)
			var x_right: int = mini(x + 1, grid_w - 1)
			var dx: float = float(x_right - x_left) * spacing

			var h_left: float = physics_heights[x_left + z * grid_w]
			var h_right: float = physics_heights[x_right + z * grid_w]
			var h_up: float = physics_heights[x + z_up * grid_w]
			var h_down: float = physics_heights[x + z_down * grid_w]

			var tangent_x := Vector3(dx, h_right - h_left, 0.0)
			var bitangent_z := Vector3(0.0, h_down - h_up, dz)
			global_normals[x + z * grid_w] = bitangent_z.cross(tangent_x).normalized()

		if Time.get_ticks_msec() - frame_start >= frame_budget_ms:
			var pct: float = 38.0 + (float(z) / float(grid_d)) * 17.0
			_update_progress(popup_data, pct, "Computing seamless normals (%d/%d)..." % [z, grid_d])
			await get_tree().process_frame
			frame_start = Time.get_ticks_msec()
			if _cancel_requested:
				_abort_generation(popup_data)
				return

	# 6. Clear Old Chunks & Prepare Containers
	_clear_chunks_internal()
	var chunks_root := Node3D.new()
	chunks_root.name = "TerrainChunks"
	add_child(chunks_root)
	var scene_owner: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else owner
	if scene_owner:
		chunks_root.owner = scene_owner

	# 7. Slice & Build Chunks Directly from the Grid
	var chunks_x: int = maxi(chunk_grid.x, 1)
	var chunks_z: int = maxi(chunk_grid.y, 1)
	var total_chunks: int = chunks_x * chunks_z
	var quads_x: int = grid_w - 1
	var quads_z: int = grid_d - 1
	var offset_x: float = (float(quads_x) * spacing) * 0.5
	var offset_z: float = (float(quads_z) * spacing) * 0.5

	var built_chunks: int = 0
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

			var chunk_inst: MeshInstance3D = _build_single_chunk(
				cx, cz,
				q_start_x, q_end_x,
				q_start_z, q_end_z,
				grid_w, grid_d,
				offset_x, offset_z,
				physics_heights,
				global_normals
			)
			chunks_root.add_child(chunk_inst)
			if scene_owner:
				chunk_inst.owner = scene_owner

			built_chunks += 1
			if Time.get_ticks_msec() - frame_start >= frame_budget_ms:
				var pct: float = 55.0 + (float(built_chunks) / float(total_chunks)) * 35.0
				_update_progress(popup_data, pct, "Building chunk %d / %d..." % [built_chunks, total_chunks])
				await get_tree().process_frame
				frame_start = Time.get_ticks_msec()
				if _cancel_requested:
					_abort_generation(popup_data)
					return

	# 8. Build & Assign HeightMapShape3D Collider
	_update_progress(popup_data, 92.0, "Building HeightMapShape3D collider...")
	await get_tree().process_frame
	_apply_collision_shape(grid_w, grid_d, physics_heights, scene_owner)

	# 9. Auto-Save Compressed Binary .res Files to Keep .tscn Small
	if auto_save_to_disk and Engine.is_editor_hint():
		_update_progress(popup_data, 96.0, "Saving compressed binary .res files...")
		await get_tree().process_frame
		save_resources_to_disk()

	_update_progress(popup_data, 100.0, "Done!")
	await get_tree().process_frame
	_close_progress_popup(popup_data)
	_is_generating = false

	print("TerrainGenerator: Generated %d chunks (%dx%d vertices, %.1fx%.1fm)." % [
		built_chunks, grid_w, grid_d, float(quads_x) * spacing, float(quads_z) * spacing
	])
#endregion


#region Chunk & Collider Builders
func _build_single_chunk(
	cx: int, cz: int,
	q_start_x: int, q_end_x: int,
	q_start_z: int, q_end_z: int,
	grid_w: int, grid_d: int,
	offset_x: float, offset_z: float,
	physics_heights: PackedFloat32Array,
	global_normals: PackedVector3Array
) -> MeshInstance3D:
	var c_verts_x: int = (q_end_x - q_start_x) + 1
	var c_verts_z: int = (q_end_z - q_start_z) + 1
	var c_quads_x: int = q_end_x - q_start_x
	var c_quads_z: int = q_end_z - q_start_z

	# Center this chunk's local origin at its geometric XZ midpoint for accurate culling
	var min_world_x: float = (float(q_start_x) * spacing) - offset_x
	var max_world_x: float = (float(q_end_x) * spacing) - offset_x
	var min_world_z: float = (float(q_start_z) * spacing) - offset_z
	var max_world_z: float = (float(q_end_z) * spacing) - offset_z
	var chunk_center := Vector3((min_world_x + max_world_x) * 0.5, 0.0, (min_world_z + max_world_z) * 0.5)

	var total_verts: int = c_verts_x * c_verts_z
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	vertices.resize(total_verts)
	normals.resize(total_verts)
	tangents.resize(total_verts * 4)
	uvs.resize(total_verts)

	var v_idx: int = 0
	for lz: int in range(c_verts_z):
		var gz: int = q_start_z + lz
		var v_coord: float = (float(gz) / float(grid_d - 1)) * uv_scale.y
		var world_z: float = (float(gz) * spacing) - offset_z - chunk_center.z

		for lx: int in range(c_verts_x):
			var gx: int = q_start_x + lx
			var u_coord: float = (float(gx) / float(grid_w - 1)) * uv_scale.x
			var world_x: float = (float(gx) * spacing) - offset_x - chunk_center.x

			var g_idx: int = gx + gz * grid_w
			var h: float = physics_heights[g_idx]
			var n: Vector3 = global_normals[g_idx]

			vertices[v_idx] = Vector3(world_x, h, world_z)
			normals[v_idx] = n
			uvs[v_idx] = Vector2(u_coord, v_coord)

			# Orthonormal tangent along +X
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
			var i1: int = row0 + lx + 1
			var i2: int = row1 + lx
			var i3: int = row1 + lx + 1

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
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if terrain_material:
		arr_mesh.surface_set_material(0, terrain_material)

	var chunk_inst := MeshInstance3D.new()
	chunk_inst.name = "Chunk_%d_%d" % [cx, cz]
	chunk_inst.mesh = arr_mesh
	chunk_inst.position = chunk_center
	chunk_inst.cast_shadow = cast_shadow

	if chunk_visibility_max_distance > 0.0:
		chunk_inst.visibility_range_end = chunk_visibility_max_distance
		chunk_inst.visibility_range_end_margin = chunk_visibility_fade_margin
		chunk_inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

	return chunk_inst


func _apply_collision_shape(grid_w: int, grid_d: int, physics_heights: PackedFloat32Array, scene_owner: Node) -> void:
	var target_collider: CollisionShape3D = height_map_body_collider
	if not is_instance_valid(target_collider):
		var static_body := get_node_or_null("TerrainStaticBody3D") as StaticBody3D
		if not is_instance_valid(static_body):
			static_body = StaticBody3D.new()
			static_body.name = "TerrainStaticBody3D"
			add_child(static_body)
			if scene_owner:
				static_body.owner = scene_owner

		static_body.collision_layer = collision_layer
		static_body.collision_mask = collision_mask
		for grp: StringName in body_groups:
			if grp != &"" and not static_body.is_in_group(grp):
				static_body.add_to_group(grp, true)

		target_collider = static_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if not is_instance_valid(target_collider):
			target_collider = CollisionShape3D.new()
			target_collider.name = "CollisionShape3D"
			static_body.add_child(target_collider)
			if scene_owner:
				target_collider.owner = scene_owner

	var shape := HeightMapShape3D.new()
	shape.map_width = grid_w
	shape.map_depth = grid_d
	shape.map_data = physics_heights

	target_collider.shape = shape
	target_collider.position = Vector3.ZERO
	target_collider.scale = Vector3(spacing, 1.0, spacing)
#endregion


#region Image & Filtering Helpers
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


func _sample_bilinear(pixels: PackedFloat32Array, img_w: int, img_h: int, u: float, v: float) -> float:
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

	return lerpf(lerpf(c00, c10, tx), lerpf(c01, c11, tx), ty)


func _smooth_height_grid(heights: PackedFloat32Array, grid_w: int, grid_d: int) -> PackedFloat32Array:
	var smoothed := PackedFloat32Array()
	smoothed.resize(heights.size())

	for z: int in range(grid_d):
		var z0: int = maxi(z - 1, 0)
		var z1: int = mini(z + 1, grid_d - 1)
		for x: int in range(grid_w):
			var x0: int = maxi(x - 1, 0)
			var x1: int = mini(x + 1, grid_w - 1)

			var sum: float = (
				heights[x0 + z0 * grid_w] + heights[x + z0 * grid_w] * 2.0 + heights[x1 + z0 * grid_w] +
				heights[x0 + z * grid_w] * 2.0 + heights[x + z * grid_w] * 4.0 + heights[x1 + z * grid_w] * 2.0 +
				heights[x0 + z1 * grid_w] + heights[x + z1 * grid_w] * 2.0 + heights[x1 + z1 * grid_w]
			)
			smoothed[x + z * grid_w] = sum / 16.0

	return smoothed
#endregion


#region Cleanup & Binary Disk Saving
func clear_terrain() -> void:
	if _is_generating:
		return
	_clear_chunks_internal()
	var auto_body := get_node_or_null("TerrainStaticBody3D")
	if auto_body:
		auto_body.free()
	if is_instance_valid(height_map_body_collider):
		height_map_body_collider.shape = null


func _clear_chunks_internal() -> void:
	var existing := get_node_or_null("TerrainChunks")
	if existing:
		existing.free()


func save_resources_to_disk() -> void:
	var edited_root: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	if not edited_root or edited_root.scene_file_path.is_empty():
		push_warning("TerrainGenerator: Save the current scene (.tscn) to disk first so binary resources have a target folder.")
		return

	var base_dir: String = edited_root.scene_file_path.get_base_dir()
	var scene_name: String = edited_root.scene_file_path.get_file().get_basename()
	var save_dir: String = "%s/%s_%s" % [base_dir, save_subfolder_name, scene_name]

	if not DirAccess.dir_exists_absolute(save_dir):
		DirAccess.make_dir_recursive_absolute(save_dir)

	var saved_chunks: int = 0
	var chunks_root := get_node_or_null("TerrainChunks")
	if chunks_root:
		for child: Node in chunks_root.get_children():
			if child is MeshInstance3D and child.mesh:
				var chunk_inst := child as MeshInstance3D
				var res_path: String = "%s/%s_%s.res" % [save_dir, name, chunk_inst.name]
				var err: Error = ResourceSaver.save(chunk_inst.mesh, res_path, ResourceSaver.FLAG_COMPRESS)
				if err == OK:
					chunk_inst.mesh.take_over_path(res_path)
					chunk_inst.mesh = ResourceLoader.load(res_path, "", ResourceLoader.CACHE_MODE_REPLACE)
					saved_chunks += 1

	var target_collider: CollisionShape3D = height_map_body_collider
	if not is_instance_valid(target_collider):
		target_collider = get_node_or_null("TerrainStaticBody3D/CollisionShape3D") as CollisionShape3D

	if is_instance_valid(target_collider) and target_collider.shape:
		var shape_path: String = "%s/%s_HeightMapShape.res" % [save_dir, name]
		var shape_err: Error = ResourceSaver.save(target_collider.shape, shape_path, ResourceSaver.FLAG_COMPRESS)
		if shape_err == OK:
			target_collider.shape.take_over_path(shape_path)
			target_collider.shape = ResourceLoader.load(shape_path, "", ResourceLoader.CACHE_MODE_REPLACE)

	print("TerrainGenerator: Saved %d compressed chunk meshes and collider shape to '%s'." % [saved_chunks, save_dir])
#endregion


#region Editor Progress Popup
func _create_progress_popup() -> Dictionary:
	var dialog := AcceptDialog.new()
	dialog.title = "Generating Terrain..."
	dialog.dialog_hide_on_ok = false
	dialog.get_ok_button().text = "Cancel"
	dialog.unresizable = true
	dialog.size = Vector2i(420, 120)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(390.0, 65.0)
	vbox.add_theme_constant_override("separation", 10)

	var label := Label.new()
	label.text = "Initializing terrain generation..."
	vbox.add_child(label)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 0.0
	bar.custom_minimum_size = Vector2(380.0, 24.0)
	vbox.add_child(bar)

	dialog.add_child(vbox)
	dialog.confirmed.connect(func() -> void: _cancel_requested = true)
	dialog.canceled.connect(func() -> void: _cancel_requested = true)

	get_tree().root.add_child(dialog)
	dialog.popup_centered()

	return {
		"dialog": dialog,
		"label": label,
		"bar": bar
	}


func _update_progress(popup_data: Dictionary, percent: float, status_text: String) -> void:
	var bar := popup_data.get("bar") as ProgressBar
	var label := popup_data.get("label") as Label
	if is_instance_valid(bar):
		bar.value = percent
	if is_instance_valid(label):
		label.text = status_text


func _close_progress_popup(popup_data: Dictionary) -> void:
	var dialog := popup_data.get("dialog") as AcceptDialog
	if is_instance_valid(dialog):
		dialog.hide()
		dialog.queue_free()


func _abort_generation(popup_data: Dictionary) -> void:
	_close_progress_popup(popup_data)
	_is_generating = false
	push_warning("TerrainGenerator: Terrain generation canceled by user.")
#endregion
