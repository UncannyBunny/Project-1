@tool
## Unified non-blocking terrain generator with Vector3 meter dimensions, Vector2i detail, and noise-scrambled height material blending.
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

@export_group("Dimensions & Detail")
## Total size of the terrain in meters: X = Width, Y = Max Height, Z = Depth
@export var terrain_size: Vector3 = Vector3(128.0, 15.0, 128.0)
## Vertex resolution along the X and Z axes
@export var detail: Vector2i = Vector2i(128, 128)
## Number of visual chunks along X and Z (e.g. 4x4 = 16 culled MeshInstance3D chunks)
@export var chunk_grid: Vector2i = Vector2i(4, 4)
## UV tiling multiplier across the entire terrain
@export var uv_scale: Vector2 = Vector2(16.0, 16.0)

@export_group("Height Materials & Border Noise")
## Dictionary mapping start height in meters (float) -> Material (StandardMaterial3D/BaseMaterial3D). Up to 8 layers.
@export var height_materials: Dictionary[float, Material] = {}
## Fallback single material used if height_materials is empty
@export var fallback_material: Material
## Vertical distance (in meters) over which adjacent height materials smoothly blend into each other
@export_range(0.05, 20.0, 0.05) var material_blend_range: float = 2.0
## FastNoiseLite used to scramble the height borders between materials
@export var border_noise: FastNoiseLite
## How many meters up/down the border_noise warps the material transition height
@export_range(0.0, 15.0, 0.1) var border_noise_amplitude: float = 1.5
## World-space scale multiplier for sampling border_noise
@export_range(0.01, 10.0, 0.01) var border_noise_scale: float = 1.0

@export_group("Performance & Culling")
## Maximum milliseconds spent generating per frame before yielding to keep the Editor responsive
@export_range(2, 30, 1) var frame_budget_ms: int = 8
## Distance in meters where individual chunks fade out (0 = never fade)
@export var chunk_visibility_max_distance: float = 0.0
@export var chunk_visibility_fade_margin: float = 15.0
@export var cast_shadow: GeometryInstance3D.ShadowCastingSetting = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

@export_group("Collision & Groups")
## Optional external CollisionShape3D. If left empty, a StaticBody3D + CollisionShape3D is created automatically.
@export var height_map_body_collider: CollisionShape3D
## Groups automatically assigned to the generated StaticBody3D (compatible with ProceduralGrass/MultiMeshPopulator!)
@export var body_groups: Array[StringName] = [&"grass_surface"]
@export_flags_3d_physics var collision_layer: int = 1
@export_flags_3d_physics var collision_mask: int = 1

@export_group("Storage")
## Automatically saves generated chunk meshes and HeightMapShape3D as compressed binary .res files
@export var auto_save_to_disk: bool = true
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

	img = img.duplicate() as Image
	if img.is_compressed():
		img.decompress()

	var img_w: int = img.get_width()
	var img_h: int = img.get_height()

	# 2. Extract Channel & Normalize Colors (0.0 .. 1.0)
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

	# 3. Compute Grid Resolution & Spacing from terrain_size and detail
	var grid_w: int = maxi(detail.x, 2)
	var grid_d: int = maxi(detail.y, 2)
	var spacing_x: float = maxf(terrain_size.x, 0.1) / float(grid_w - 1)
	var spacing_z: float = maxf(terrain_size.z, 0.1) / float(grid_d - 1)
	var max_height: float = terrain_size.y

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

			physics_heights[x + z * grid_w] = norm_h * max_height

		if Time.get_ticks_msec() - frame_start >= frame_budget_ms:
			var pct: float = 17.0 + (float(z) / float(grid_d)) * 18.0
			_update_progress(popup_data, pct, "Sampling bilinear height grid (%d/%d)..." % [z, grid_d])
			await get_tree().process_frame
			frame_start = Time.get_ticks_msec()
			if _cancel_requested:
				_abort_generation(popup_data)
				return

	# 4. Optional Smoothing Passes
	for pass_idx: int in range(smoothing_passes):
		physics_heights = _smooth_height_grid(physics_heights, grid_w, grid_d)
		if Time.get_ticks_msec() - frame_start >= frame_budget_ms:
			_update_progress(popup_data, 36.0, "Smoothing heightfield (pass %d/%d)..." % [pass_idx + 1, smoothing_passes])
			await get_tree().process_frame
			frame_start = Time.get_ticks_msec()
			if _cancel_requested:
				_abort_generation(popup_data)
				return

	# 5. Precalculate Global Smooth Normals
	var global_normals := PackedVector3Array()
	global_normals.resize(grid_w * grid_d)

	for z: int in range(grid_d):
		var z_up: int = maxi(z - 1, 0)
		var z_down: int = mini(z + 1, grid_d - 1)
		var dz: float = float(z_down - z_up) * spacing_z

		for x: int in range(grid_w):
			var x_left: int = maxi(x - 1, 0)
			var x_right: int = mini(x + 1, grid_w - 1)
			var dx: float = float(x_right - x_left) * spacing_x

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

	# 6. Build Shared Height-Blending ShaderMaterial (if height_materials is populated)
	_update_progress(popup_data, 55.0, "Building height-blended material...")
	await get_tree().process_frame
	var active_material: Material = await _build_blended_terrain_material()
	frame_start = Time.get_ticks_msec()

	# 7. Clear Old Chunks & Prepare Containers
	_clear_chunks_internal()
	var chunks_root := Node3D.new()
	chunks_root.name = "TerrainChunks"
	add_child(chunks_root)
	var scene_owner: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else owner
	if scene_owner:
		chunks_root.owner = scene_owner

	# 8. Slice & Build Chunks Directly from the Grid
	var chunks_x: int = maxi(chunk_grid.x, 1)
	var chunks_z: int = maxi(chunk_grid.y, 1)
	var total_chunks: int = chunks_x * chunks_z
	var quads_x: int = grid_w - 1
	var quads_z: int = grid_d - 1
	var offset_x: float = terrain_size.x * 0.5
	var offset_z: float = terrain_size.z * 0.5

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
				spacing_x, spacing_z,
				offset_x, offset_z,
				physics_heights,
				global_normals,
				active_material
			)
			chunks_root.add_child(chunk_inst)
			if scene_owner:
				chunk_inst.owner = scene_owner

			built_chunks += 1
			if Time.get_ticks_msec() - frame_start >= frame_budget_ms:
				var pct: float = 57.0 + (float(built_chunks) / float(total_chunks)) * 33.0
				_update_progress(popup_data, pct, "Building chunk %d / %d..." % [built_chunks, total_chunks])
				await get_tree().process_frame
				frame_start = Time.get_ticks_msec()
				if _cancel_requested:
					_abort_generation(popup_data)
					return

	# 9. Build & Assign HeightMapShape3D Collider
	_update_progress(popup_data, 92.0, "Building HeightMapShape3D collider...")
	await get_tree().process_frame
	_apply_collision_shape(grid_w, grid_d, spacing_x, spacing_z, physics_heights, scene_owner)

	# 10. Auto-Save Compressed Binary .res Files
	if auto_save_to_disk and Engine.is_editor_hint():
		_update_progress(popup_data, 96.0, "Saving compressed binary .res files...")
		await get_tree().process_frame
		save_resources_to_disk()

	_update_progress(popup_data, 100.0, "Done!")
	await get_tree().process_frame
	_close_progress_popup(popup_data)
	_is_generating = false

	print("TerrainGenerator: Generated %d chunks (%dx%d detail, %.1fx%.1fx%.1fm)." % [
		built_chunks, grid_w, grid_d, terrain_size.x, terrain_size.y, terrain_size.z
	])
#endregion


#region Height-Blended Material & Shader Builder
func _build_blended_terrain_material() -> Material:
	if height_materials.is_empty():
		return fallback_material

	# Collect valid float height keys and sort ascending
	var sorted_heights: Array[float] = []
	for h_key: float in height_materials.keys():
		if height_materials[h_key] != null:
			sorted_heights.append(h_key)
	sorted_heights.sort()

	if sorted_heights.is_empty():
		return fallback_material

	# If only 1 material is provided and it's already a ShaderMaterial, return it directly
	if sorted_heights.size() == 1 and height_materials[sorted_heights[0]] is ShaderMaterial:
		return height_materials[sorted_heights[0]]

	var layer_count: int = mini(sorted_heights.size(), 8)
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = _get_or_create_height_blend_shader()

	# 1x1 white fallback texture for materials that only use albedo_color
	var white_img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	white_img.fill(Color.WHITE)
	var white_tex := ImageTexture.create_from_image(white_img)

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

		var albedo_tex: Texture2D = white_tex
		if mat is BaseMaterial3D:
			var bmat := mat as BaseMaterial3D
			colors_arr[i] = bmat.albedo_color
			roughness_arr[i] = bmat.roughness
			uv_scales_arr[i] = Vector2(bmat.uv1_scale.x, bmat.uv1_scale.y)
			if bmat.albedo_texture:
				albedo_tex = bmat.albedo_texture

		shader_mat.set_shader_parameter("layer_tex_%d" % i, albedo_tex)

	shader_mat.set_shader_parameter("layer_count", layer_count)
	shader_mat.set_shader_parameter("layer_heights", heights_arr)
	shader_mat.set_shader_parameter("layer_colors", colors_arr)
	shader_mat.set_shader_parameter("layer_roughness", roughness_arr)
	shader_mat.set_shader_parameter("layer_uv_scales", uv_scales_arr)
	shader_mat.set_shader_parameter("blend_range", maxf(material_blend_range, 0.05))

	# Configure FastNoiseLite border scrambling texture
	if border_noise:
		var noise_tex := NoiseTexture2D.new()
		noise_tex.width = 256
		noise_tex.height = 256
		noise_tex.seamless = true
		noise_tex.noise = border_noise
		await noise_tex.changed
		shader_mat.set_shader_parameter("border_noise_tex", noise_tex)
		shader_mat.set_shader_parameter("border_noise_amplitude", border_noise_amplitude)
		shader_mat.set_shader_parameter("border_noise_scale", border_noise_scale * 0.05)
	else:
		shader_mat.set_shader_parameter("border_noise_tex", white_tex)
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

uniform sampler2D layer_tex_0 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer_tex_1 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer_tex_2 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer_tex_3 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer_tex_4 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer_tex_5 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer_tex_6 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer_tex_7 : source_color, filter_linear_mipmap, repeat_enable;

uniform float blend_range = 2.0;
uniform sampler2D border_noise_tex : filter_linear_mipmap, repeat_enable;
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


#region Chunk & Collider Builders
func _build_single_chunk(
	cx: int, cz: int,
	q_start_x: int, q_end_x: int,
	q_start_z: int, q_end_z: int,
	grid_w: int, grid_d: int,
	spacing_x: float, spacing_z: float,
	offset_x: float, offset_z: float,
	physics_heights: PackedFloat32Array,
	global_normals: PackedVector3Array,
	active_material: Material
) -> MeshInstance3D:
	var c_verts_x: int = (q_end_x - q_start_x) + 1
	var c_verts_z: int = (q_end_z - q_start_z) + 1
	var c_quads_x: int = q_end_x - q_start_x
	var c_quads_z: int = q_end_z - q_start_z

	var min_world_x: float = (float(q_start_x) * spacing_x) - offset_x
	var max_world_x: float = (float(q_end_x) * spacing_x) - offset_x
	var min_world_z: float = (float(q_start_z) * spacing_z) - offset_z
	var max_world_z: float = (float(q_end_z) * spacing_z) - offset_z
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
		var world_z: float = (float(gz) * spacing_z) - offset_z - chunk_center.z

		for lx: int in range(c_verts_x):
			var gx: int = q_start_x + lx
			var u_coord: float = (float(gx) / float(grid_w - 1)) * uv_scale.x
			var world_x: float = (float(gx) * spacing_x) - offset_x - chunk_center.x

			var g_idx: int = gx + gz * grid_w
			var h: float = physics_heights[g_idx]
			var n: Vector3 = global_normals[g_idx]

			vertices[v_idx] = Vector3(world_x, h, world_z)
			normals[v_idx] = n
			uvs[v_idx] = Vector2(u_coord, v_coord)

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
	if active_material:
		arr_mesh.surface_set_material(0, active_material)

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


func _apply_collision_shape(
	grid_w: int,
	grid_d: int,
	spacing_x: float,
	spacing_z: float,
	physics_heights: PackedFloat32Array,
	scene_owner: Node
) -> void:
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
	target_collider.scale = Vector3(spacing_x, 1.0, spacing_z)
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
