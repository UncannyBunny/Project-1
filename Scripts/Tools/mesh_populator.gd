@tool
## Component that populates a parent or target surface AABB with weighted PackedScene instances and MultiMesh meshes, automatically batching per chunk when targeting a TerrainGenerator.
class_name MultiMeshPopulator extends Node3D

enum SpawnCountMode {
	FIXED_AMOUNT,
	DENSITY_PER_M2
}

enum ColliderType {
	NONE,
	CUBE,
	SPHERE,
	CYLINDER,
	AUTO_AABB,
	CONVEX_FROM_MESH
}

@export_group("Generator Actions")
@export_tool_button("Populate Surface", "Node3D") var btn_populate: Callable:
	get:
		return populate_surface
@export_tool_button("Randomize Seed & Populate", "RandomNumberGenerator") var btn_randomize: Callable:
	get:
		return randomize_and_populate
@export_tool_button("Clear Objects", "Clear") var btn_clear: Callable:
	get:
		return clear_objects
@export_tool_button("Save Resources to Disk", "Save") var btn_save: Callable:
	get:
		return save_resources_to_disk

@export var seed_value: int = 1337
@export_range(2, 30, 1) var frame_budget_ms: int = 8

@export_group("Target & Chunk Batching")
@export var target_body: Node3D
## When targeting a TerrainGenerator, splits MultiMeshes per terrain chunk for frustum culling, distance culling, and lag-free baking
@export var batch_by_terrain_chunks: bool = true
## Hardware distance culling for chunked MultiMeshes (0 = disabled; e.g. 65.0 culls entire distant grass chunks on the CPU!)
@export_range(0.0, 500.0, 1.0) var chunk_visibility_max_distance: float = 65.0
@export_range(0.0, 50.0, 1.0) var chunk_visibility_fade_margin: float = 10.0
@export var allowed_groups: Array[StringName] = [&"grass_surface"]
@export var allow_target_body_without_group: bool = true
@export var raycast_top_margin: float = 20.0
@export var raycast_bottom_margin: float = 5.0
@export var fallback_aabb: AABB = AABB(Vector3(-25.0, -5.0, -25.0), Vector3(50.0, 20.0, 50.0))

@export_group("Weighted Scenes & Meshes")
@export var object_scenes: Dictionary[PackedScene, float] = {}
@export var randomize_procedural_trees: bool = true
@export_range(0, 100, 1) var max_unique_variants_per_scene: int = 12
@export var object_meshes: Dictionary[Mesh, float] = {}

@export_group("Count & Spacing")
@export var count_mode: SpawnCountMode = SpawnCountMode.DENSITY_PER_M2
@export_range(1, 500000, 1) var fixed_object_amount: int = 200
@export_range(0.001, 50.0, 0.01) var density_per_m2: float = 0.15
@export_range(0.0, 50.0, 0.1) var spacing: float = 2.5

@export_group("Noise & Density Scaling")
@export var use_density_noise: bool = true
@export_range(0.005, 0.5, 0.005) var noise_base_frequency: float = 0.02
@export_range(0.0, 1.0, 0.01) var noise_threshold: float = 0.42
@export_range(0.01, 0.5, 0.01) var noise_transition_margin: float = 0.18
@export var density_affects_scale: bool = true
@export_range(0.05, 3.0, 0.05) var min_edge_scale: float = 0.65
@export_range(0.1, 5.0, 0.05) var max_core_scale: float = 1.25
@export_range(0.25, 3.0, 0.05) var density_height_exponent: float = 1.15

@export_group("Surface & Transform Rules")
@export var height_range: Vector2 = Vector2(-500.0, 500.0)
@export_range(0.0, 89.0, 1.0) var max_slope_degrees: float = 35.0
@export_range(0.0, 1.0, 0.05) var align_to_normal_factor: float = 0.15
@export var offset_position: Vector3 = Vector3.ZERO
@export var random_offset_position: Vector3 = Vector3.ZERO
@export var random_offset_degrees: Vector3 = Vector3(0.0, 180.0, 0.0)
@export var random_offset_scale: Vector3 = Vector3(0.15, 0.15, 0.15)

@export_group("MultiMesh Collision")
@export var collider_type: ColliderType = ColliderType.NONE
@export var collider_size: Vector3 = Vector3.ONE
@export var collider_group: StringName = &"object"
@export_flags_3d_physics var collision_layer: int = 1
@export_flags_3d_physics var collision_mask: int = 1
@export var custom_collider_script: Script

@export_group("Storage")
@export var auto_save_to_disk: bool = true
@export var save_subfolder_name: String = "GeneratedPopulator"

var _is_populating: bool = false
var _cancel_requested: bool = false


func randomize_and_populate() -> void:
	seed_value = randi()
	populate_surface()


func clear_objects() -> void:
	if _is_populating:
		return
	_clear_children_internal()


func _clear_children_internal() -> void:
	for child: Node in get_children():
		child.free()


func _get_meshes_to_populate() -> Array[Mesh]:
	return []


func _build_instance_custom_data(rng: RandomNumberGenerator, density_weight: float) -> Color:
	return Color(rng.randf(), rng.randf(), density_weight, 0.0)


func _build_weighted_pool() -> Dictionary:
	var scenes: Array[PackedScene] = []
	var meshes: Array[Mesh] = []
	var entries: Array[Dictionary] = []
	var total_weight: float = 0.0

	for scene: PackedScene in object_scenes.keys():
		var w: float = float(object_scenes[scene])
		if scene != null and w > 0.0:
			var s_idx: int = scenes.size()
			scenes.append(scene)
			total_weight += w
			entries.append({
				"is_scene": true,
				"index": s_idx,
				"cumulative": total_weight
			})

	for mesh: Mesh in object_meshes.keys():
		var w: float = float(object_meshes[mesh])
		if mesh != null and w > 0.0:
			var m_idx: int = meshes.size()
			meshes.append(mesh)
			total_weight += w
			entries.append({
				"is_scene": false,
				"index": m_idx,
				"cumulative": total_weight
			})

	for extra_mesh: Mesh in _get_meshes_to_populate():
		if extra_mesh != null:
			var m_idx: int = meshes.size()
			meshes.append(extra_mesh)
			total_weight += 1.0
			entries.append({
				"is_scene": false,
				"index": m_idx,
				"cumulative": total_weight
			})

	return {
		"scenes": scenes,
		"meshes": meshes,
		"entries": entries,
		"total_weight": total_weight
	}


func _pick_weighted_entry(rng: RandomNumberGenerator, entries: Array[Dictionary], total_weight: float) -> Dictionary:
	var roll: float = rng.randf() * total_weight
	for entry: Dictionary in entries:
		if roll <= float(entry["cumulative"]):
			return entry
	return entries.back()


#region Main Population Coroutine (With Automatic Terrain Chunk Batching)
func populate_surface() -> void:
	if _is_populating or not is_inside_tree():
		return

	var pool: Dictionary = _build_weighted_pool()
	var scenes: Array[PackedScene] = pool["scenes"]
	var meshes: Array[Mesh] = pool["meshes"]
	var pool_entries: Array[Dictionary] = pool["entries"]
	var total_weight: float = pool["total_weight"]

	if pool_entries.is_empty() or total_weight <= 0.0:
		printerr("%s: No valid weighted scenes or meshes assigned." % name)
		return

	_is_populating = true
	_cancel_requested = false

	var popup_data: Dictionary = _create_progress_popup()
	_update_progress(popup_data, 2.0, "Stage 1/4: Preparing surface...", 50.0, "Clearing previous objects...")

	_clear_children_internal()
	await get_tree().physics_frame
	if _cancel_requested:
		_abort_population(popup_data)
		return

	var host: Node3D = _get_target_host()
	var chunk_boxes: Array[Dictionary] = _collect_terrain_chunk_aabbs(host)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noises: Array[FastNoiseLite] = _create_three_seeded_noises(seed_value)

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var max_slope_cos: float = cos(deg_to_rad(max_slope_degrees))
	var min_h: float = minf(height_range.x, height_range.y)
	var max_h: float = maxf(height_range.x, height_range.y)
	var edge0: float = clampf(noise_threshold - noise_transition_margin, 0.0, 1.0)
	var edge1: float = clampf(noise_threshold + noise_transition_margin, 0.001, 1.0)

	var spatial_grid: Dictionary = {}
	var cell_size: float = maxf(spacing, 0.01)

	var scene_transforms: Dictionary = {}
	for s_idx: int in range(scenes.size()):
		scene_transforms[s_idx] = []

	var total_chunks: int = chunk_boxes.size()
	var total_area_m2: float = 0.0
	for c_info: Dictionary in chunk_boxes:
		var box: AABB = c_info["aabb"]
		total_area_m2 += maxf(box.size.x * box.size.z, 0.01)

	var scene_owner: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else owner
	var chunks_mm_root: Node3D = null
	if total_chunks > 1 and not meshes.is_empty():
		chunks_mm_root = Node3D.new()
		chunks_mm_root.name = "ChunkMultiMeshes"
		add_child(chunks_mm_root)
		if scene_owner:
			chunks_mm_root.owner = scene_owner

	var frame_start: int = Time.get_ticks_msec()

	for c_idx: int in range(total_chunks):
		var c_info: Dictionary = chunk_boxes[c_idx]
		var c_name: String = c_info["name"]
		var c_aabb: AABB = c_info["aabb"]
		var c_area: float = maxf(c_aabb.size.x * c_aabb.size.z, 0.01)

		var chunk_target_count: int = 0
		if count_mode == SpawnCountMode.DENSITY_PER_M2:
			chunk_target_count = clampi(int(roundf(c_area * density_per_m2)), 0, 250000)
		else:
			chunk_target_count = int(roundf(float(fixed_object_amount) * (c_area / maxf(total_area_m2, 0.01))))

		if chunk_target_count <= 0:
			continue

		var max_attempts: int = chunk_target_count * 5 if spacing > 0.001 else chunk_target_count

		var min_x: float = c_aabb.position.x
		var max_x: float = c_aabb.end.x
		var min_z: float = c_aabb.position.z
		var max_z: float = c_aabb.end.z
		var ray_start_y: float = c_aabb.end.y + raycast_top_margin
		var ray_end_y: float = c_aabb.position.y - raycast_bottom_margin

		# Center this chunk's MultiMeshInstance3D at the chunk's geometric center for accurate frustum & distance culling!
		var chunk_world_center := Vector3((min_x + max_x) * 0.5, c_aabb.position.y, (min_z + max_z) * 0.5)
		var chunk_local_center: Vector3 = to_local(chunk_world_center) if chunks_mm_root != null else Vector3.ZERO

		var mesh_transforms: Dictionary = {}
		var mesh_custom_data: Dictionary = {}
		for m_idx: int in range(meshes.size()):
			mesh_transforms[m_idx] = []
			mesh_custom_data[m_idx] = []

		var successful_spawns: int = 0
		for attempt: int in range(max_attempts):
			if successful_spawns >= chunk_target_count:
				break

			var world_x: float = rng.randf_range(min_x, max_x)
			var world_z: float = rng.randf_range(min_z, max_z)

			var density_weight: float = 1.0
			if use_density_noise:
				var n0: float = (noises[0].get_noise_2d(world_x, world_z) + 1.0) * 0.5
				var n1: float = (noises[1].get_noise_2d(world_x, world_z) + 1.0) * 0.5
				var n2: float = (noises[2].get_noise_2d(world_x, world_z) + 1.0) * 0.5
				var n_avg: float = (n0 + n1 + n2) / 3.0
				density_weight = smoothstep(edge0, edge1, n_avg)
				if density_weight <= 0.001 or rng.randf() > density_weight:
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
			if not (collider is Node) or not _is_collider_whitelisted(collider as Node, host):
				continue

			var hit_pos: Vector3 = hit["position"]
			if hit_pos.y < min_h or hit_pos.y > max_h:
				continue

			var hit_normal: Vector3 = (hit["normal"] as Vector3).normalized()
			if hit_normal.dot(Vector3.UP) < max_slope_cos:
				continue

			if spacing > 0.001:
				if _is_too_close_in_grid(hit_pos, spacing, cell_size, spatial_grid):
					continue
				_register_in_grid(hit_pos, cell_size, spatial_grid)

			var local_pos: Vector3 = to_local(hit_pos)
			var local_normal: Vector3 = (global_basis.inverse() * hit_normal).normalized()

			var up_vec: Vector3 = Vector3.UP.lerp(local_normal, align_to_normal_factor).normalized()
			var rand_yaw: float = deg_to_rad(rng.randf_range(-random_offset_degrees.y, random_offset_degrees.y))
			var rand_pitch: float = deg_to_rad(rng.randf_range(-random_offset_degrees.x, random_offset_degrees.x))
			var rand_roll: float = deg_to_rad(rng.randf_range(-random_offset_degrees.z, random_offset_degrees.z))

			var forward_vec := Vector3(sin(rand_yaw), 0.0, cos(rand_yaw))
			var right_vec: Vector3 = up_vec.cross(forward_vec).normalized()
			if right_vec.length_squared() < 0.001:
				right_vec = Vector3.RIGHT
			forward_vec = right_vec.cross(up_vec).normalized()

			var inst_basis := Basis(right_vec, up_vec, forward_vec)
			if absf(rand_pitch) > 0.0001 or absf(rand_roll) > 0.0001:
				inst_basis = inst_basis * Basis.from_euler(Vector3(rand_pitch, 0.0, rand_roll))

			var base_scale_factor: float = 1.0
			if use_density_noise and density_affects_scale:
				base_scale_factor = lerpf(min_edge_scale, max_core_scale, pow(density_weight, density_height_exponent))

			var scale_jitter := Vector3(
				1.0 + rng.randf_range(-random_offset_scale.x, random_offset_scale.x),
				1.0 + rng.randf_range(-random_offset_scale.y, random_offset_scale.y),
				1.0 + rng.randf_range(-random_offset_scale.z, random_offset_scale.z)
			)
			var final_scale: Vector3 = (scale_jitter * base_scale_factor).max(Vector3.ONE * 0.05)
			inst_basis = inst_basis.scaled(final_scale)

			var rand_pos_jitter := Vector3(
				rng.randf_range(-random_offset_position.x, random_offset_position.x),
				rng.randf_range(-random_offset_position.y, random_offset_position.y),
				rng.randf_range(-random_offset_position.z, random_offset_position.z)
			)
			var final_origin: Vector3 = local_pos + (inst_basis * (offset_position + rand_pos_jitter))

			var chosen_entry: Dictionary = _pick_weighted_entry(rng, pool_entries, total_weight)
			var item_idx: int = int(chosen_entry["index"])
			if bool(chosen_entry["is_scene"]):
				(scene_transforms[item_idx] as Array).append(Transform3D(inst_basis, final_origin))
			else:
				# Offset origin relative to the chunk's center if chunk batching is active
				var mm_origin: Vector3 = final_origin - chunk_local_center
				(mesh_transforms[item_idx] as Array).append(Transform3D(inst_basis, mm_origin))
				(mesh_custom_data[item_idx] as Array).append(_build_instance_custom_data(rng, density_weight))

			successful_spawns += 1

			if Time.get_ticks_msec() - frame_start >= frame_budget_ms:
				var task_pct: float = maxf(
					float(successful_spawns) / float(maxi(chunk_target_count, 1)),
					float(attempt) / float(maxi(max_attempts, 1))
				) * 100.0
				var overall_pct: float = 5.0 + ((float(c_idx) + (task_pct / 100.0)) / float(maxi(total_chunks, 1))) * 60.0
				_update_progress(
					popup_data,
					overall_pct,
					"Stage 2/4: Populating chunk %d / %d (%s)..." % [c_idx + 1, total_chunks, c_name],
					task_pct,
					"Raycasting %s (%d / %d)..." % [c_name, successful_spawns, chunk_target_count]
				)
				await get_tree().process_frame
				frame_start = Time.get_ticks_msec()
				if _cancel_requested:
					_abort_population(popup_data)
					return

		# Commit this chunk's MultiMeshes immediately so RAM stays flat even on huge 500x500m terrains!
		if not meshes.is_empty():
			var parent_container: Node3D = chunks_mm_root if chunks_mm_root != null else self
			_apply_chunk_multimeshes(
				parent_container,
				c_name,
				chunk_local_center,
				meshes,
				mesh_transforms,
				mesh_custom_data,
				scene_owner
			)

	if not scenes.is_empty():
		var completed_scenes: bool = await _apply_scene_instances(scenes, scene_transforms, rng, popup_data)
		if not completed_scenes:
			_abort_population(popup_data)
			return

	if auto_save_to_disk and Engine.is_editor_hint():
		_update_progress(
			popup_data,
			95.0,
			"Stage 4/4: Saving binary resources to disk...",
			50.0,
			"Writing compressed .res files..."
		)
		await get_tree().process_frame
		save_resources_to_disk()

	_update_progress(popup_data, 100.0, "Complete!", 100.0, "Done!")
	await get_tree().process_frame
	_close_progress_popup(popup_data)
	_is_populating = false
	notify_property_list_changed()
#endregion


#region PackedScene Spawning
func _apply_scene_instances(
	scenes: Array[PackedScene],
	scene_transforms: Dictionary,
	rng: RandomNumberGenerator,
	popup_data: Dictionary
) -> bool:
	var scene_owner: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else owner
	var scenes_root := Node3D.new()
	scenes_root.name = "SpawnedScenes"
	var frame_start: int = Time.get_ticks_msec()

	var total_to_spawn: int = 0
	for s_idx: int in scene_transforms.keys():
		total_to_spawn += (scene_transforms[s_idx] as Array).size()

	var spawned_so_far: int = 0

	for s_idx: int in scene_transforms.keys():
		var transforms: Array = scene_transforms[s_idx]
		if transforms.is_empty():
			continue

		var packed: PackedScene = scenes[s_idx]
		var variant_pool: Array[Dictionary] = []

		for i: int in range(transforms.size()):
			var inst: Node = packed.instantiate()
			if not (inst is Node3D):
				inst.free()
				continue

			var inst_3d := inst as Node3D
			inst_3d.name = "Scene_%d_%d" % [s_idx, i]
			inst_3d.transform = transforms[i]

			if inst_3d is ProceduralTree and randomize_procedural_trees:
				var ptree := inst_3d as ProceduralTree
				ptree.auto_regenerate = false

				if max_unique_variants_per_scene > 0 and variant_pool.size() >= max_unique_variants_per_scene:
					var chosen_var: Dictionary = variant_pool[i % variant_pool.size()]
					ptree.seed_value = int(chosen_var["seed"])
					ptree.baked_tree_mesh = chosen_var["mesh"] as ArrayMesh
					ptree.baked_trunk_collision = chosen_var["shape"] as ConcavePolygonShape3D
					scenes_root.add_child(ptree)
				else:
					scenes_root.add_child(ptree)
					ptree.seed_value = rng.randi()
					ptree.bake_tree()
					if max_unique_variants_per_scene > 0:
						variant_pool.append({
							"seed": ptree.seed_value,
							"mesh": ptree.baked_tree_mesh,
							"shape": ptree.baked_trunk_collision
						})
				ptree.auto_regenerate = true
			else:
				scenes_root.add_child(inst_3d)

			spawned_so_far += 1
			if Time.get_ticks_msec() - frame_start >= frame_budget_ms:
				var task_pct: float = (float(spawned_so_far) / float(maxi(total_to_spawn, 1))) * 100.0
				var overall_pct: float = 65.0 + (task_pct / 100.0) * 28.0
				_update_progress(
					popup_data,
					overall_pct,
					"Stage 3/4: Instantiating scenes...",
					task_pct,
					"Spawning scene %d / %d..." % [spawned_so_far, total_to_spawn]
				)
				await get_tree().process_frame
				frame_start = Time.get_ticks_msec()
				if _cancel_requested:
					scenes_root.free()
					return false

	# Attach populated subtree to SceneTree in one shot to avoid O(N^2) Editor SceneTree dock slowdown!
	add_child(scenes_root)
	if scene_owner:
		scenes_root.owner = scene_owner
		for child: Node in scenes_root.get_children():
			child.owner = scene_owner

	return true
#endregion


#region Chunked MultiMesh Spawning
func _apply_chunk_multimeshes(
	parent_container: Node3D,
	chunk_prefix: String,
	chunk_local_center: Vector3,
	meshes: Array[Mesh],
	grouped_transforms: Dictionary,
	grouped_custom_data: Dictionary,
	scene_owner: Node
) -> void:
	for mesh_idx: int in grouped_transforms.keys():
		var transforms: Array = grouped_transforms[mesh_idx]
		var custom_data: Array = grouped_custom_data[mesh_idx]
		if transforms.is_empty():
			continue

		var mm_inst := MultiMeshInstance3D.new()
		mm_inst.name = "%s_MM_%d" % [chunk_prefix, mesh_idx]
		mm_inst.position = chunk_local_center

		if chunk_visibility_max_distance > 0.0:
			mm_inst.visibility_range_end = chunk_visibility_max_distance
			mm_inst.visibility_range_end_margin = chunk_visibility_fade_margin
			mm_inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		else:
			mm_inst.visibility_range_end = 0.0

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = meshes[mesh_idx]
		mm.instance_count = transforms.size()

		for i: int in range(transforms.size()):
			mm.set_instance_transform(i, transforms[i])
			mm.set_instance_custom_data(i, custom_data[i])

		mm_inst.multimesh = mm
		parent_container.add_child(mm_inst)
		if scene_owner:
			mm_inst.owner = scene_owner

		_create_colliders(transforms, mm_inst, mm.mesh, scene_owner)


func _create_colliders(transforms: Array, mm_inst: MultiMeshInstance3D, ref_mesh: Mesh, scene_owner: Node) -> void:
	if collider_type == ColliderType.NONE:
		return

	var shared_convex: ConvexPolygonShape3D = null
	if collider_type == ColliderType.CONVEX_FROM_MESH and ref_mesh:
		shared_convex = ref_mesh.create_convex_shape()

	for i: int in range(transforms.size()):
		var t: Transform3D = transforms[i]
		var inst_scale: Vector3 = t.basis.get_scale()

		var body := StaticBody3D.new()
		body.name = "Collider_%d" % i
		if custom_collider_script:
			body.set_script(custom_collider_script)

		body.collision_layer = collision_layer
		body.collision_mask = collision_mask
		if collider_group != &"":
			body.add_to_group(collider_group, true)

		var col_shape := CollisionShape3D.new()
		match collider_type:
			ColliderType.CUBE:
				var box := BoxShape3D.new()
				box.size = collider_size * inst_scale
				col_shape.shape = box
			ColliderType.SPHERE:
				var sph := SphereShape3D.new()
				var max_s: float = maxf(inst_scale.x, maxf(inst_scale.y, inst_scale.z))
				sph.radius = maxf(collider_size.x, maxf(collider_size.y, collider_size.z)) * max_s
				col_shape.shape = sph
			ColliderType.CYLINDER:
				var cyl := CylinderShape3D.new()
				cyl.radius = maxf(collider_size.x, collider_size.z) * maxf(inst_scale.x, inst_scale.z)
				cyl.height = collider_size.y * inst_scale.y
				col_shape.shape = cyl
			ColliderType.AUTO_AABB:
				var box := BoxShape3D.new()
				var aabb_size: Vector3 = ref_mesh.get_aabb().size if ref_mesh else Vector3.ONE
				box.size = aabb_size * inst_scale
				col_shape.shape = box
				if ref_mesh:
					col_shape.position = ref_mesh.get_aabb().get_center() * inst_scale
			ColliderType.CONVEX_FROM_MESH:
				col_shape.shape = shared_convex
				col_shape.scale = inst_scale

		body.transform = Transform3D(t.basis.orthonormalized(), t.origin)
		body.add_child(col_shape)
		mm_inst.add_child(body)

		if scene_owner:
			body.owner = scene_owner
			col_shape.owner = scene_owner
#endregion


#region Terrain Chunk Discovery, Spatial Grid, Noise & AABB Helpers
## Returns an Array of {"name": String, "aabb": AABB} for each terrain chunk if host is a TerrainGenerator
func _collect_terrain_chunk_aabbs(host: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if batch_by_terrain_chunks and is_instance_valid(host):
		var chunks_root := host.get_node_or_null("TerrainChunks")
		if chunks_root and chunks_root.get_child_count() > 0:
			for child: Node in chunks_root.get_children():
				if child is MeshInstance3D and child.mesh:
					var mi := child as MeshInstance3D
					var world_box: AABB = mi.global_transform * mi.get_aabb()
					result.append({
						"name": mi.name,
						"aabb": world_box
					})
			if not result.is_empty():
				return result

		if host is TerrainGenerator:
			var tgen := host as TerrainGenerator
			var cx_count: int = maxi(tgen.chunk_grid.x, 1)
			var cz_count: int = maxi(tgen.chunk_grid.y, 1)
			var step_x: float = tgen.terrain_size.x / float(cx_count)
			var step_z: float = tgen.terrain_size.z / float(cz_count)
			var start_x: float = -tgen.terrain_size.x * 0.5
			var start_z: float = -tgen.terrain_size.z * 0.5

			for cz: int in range(cz_count):
				for cx: int in range(cx_count):
					var local_box := AABB(
						Vector3(start_x + float(cx) * step_x, -2.0, start_z + float(cz) * step_z),
						Vector3(step_x, tgen.terrain_size.y + 4.0, step_z)
					)
					result.append({
						"name": "Chunk_%d_%d" % [cx, cz],
						"aabb": tgen.global_transform * local_box
					})
			return result

	result.append({
		"name": "Surface",
		"aabb": _compute_target_world_aabb(host)
	})
	return result


func _is_too_close_in_grid(pos: Vector3, min_dist: float, cell_size: float, grid: Dictionary) -> bool:
	var cx: int = int(floorf(pos.x / cell_size))
	var cz: int = int(floorf(pos.z / cell_size))
	var min_dist_sq: float = min_dist * min_dist

	for dz: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var key := Vector2i(cx + dx, cz + dz)
			if grid.has(key):
				var bucket: Array = grid[key]
				for other_pos: Vector3 in bucket:
					if pos.distance_squared_to(other_pos) < min_dist_sq:
						return true
	return false


func _register_in_grid(pos: Vector3, cell_size: float, grid: Dictionary) -> void:
	var key := Vector2i(int(floorf(pos.x / cell_size)), int(floorf(pos.z / cell_size)))
	if not grid.has(key):
		grid[key] = []
	(grid[key] as Array).append(pos)


func _create_three_seeded_noises(base_seed: int) -> Array[FastNoiseLite]:
	var n1 := FastNoiseLite.new()
	n1.seed = base_seed
	n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n1.frequency = noise_base_frequency
	n1.fractal_octaves = 2

	var n2 := FastNoiseLite.new()
	n2.seed = base_seed + 1013
	n2.noise_type = FastNoiseLite.TYPE_PERLIN
	n2.frequency = noise_base_frequency * 2.15
	n2.fractal_octaves = 2

	var n3 := FastNoiseLite.new()
	n3.seed = base_seed + 2027
	n3.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n3.frequency = noise_base_frequency * 4.3
	n3.fractal_octaves = 1

	return [n1, n2, n3]


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

	if host is TerrainGenerator:
		var tgen := host as TerrainGenerator
		var half_x: float = tgen.terrain_size.x * 0.5
		var half_z: float = tgen.terrain_size.z * 0.5
		var local_box := AABB(
			Vector3(-half_x, -2.0, -half_z),
			Vector3(tgen.terrain_size.x, tgen.terrain_size.y + 4.0, tgen.terrain_size.z)
		)
		return tgen.global_transform * local_box

	var found_any: bool = false
	var combined_aabb := AABB()

	var candidates: Array[Node] = [host]
	for child: Node in host.find_children("*", "", true, false):
		if child != self and not is_ancestor_of(child):
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


func save_resources_to_disk() -> void:
	var edited_root: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	if not edited_root or edited_root.scene_file_path.is_empty():
		return

	var base_dir: String = edited_root.scene_file_path.get_base_dir()
	var scene_name: String = edited_root.scene_file_path.get_file().get_basename()
	var save_dir: String = "%s/%s_%s" % [base_dir, save_subfolder_name, scene_name]

	if not DirAccess.dir_exists_absolute(save_dir):
		DirAccess.make_dir_recursive_absolute(save_dir)

	var saved_count: int = 0

	var mm_nodes: Array[Node] = find_children("*", "MultiMeshInstance3D", true, false)
	for child: Node in mm_nodes:
		if child is MultiMeshInstance3D and child.multimesh:
			var mm_inst := child as MultiMeshInstance3D
			var res_path: String = "%s/%s_%s.res" % [save_dir, name, mm_inst.name]
			var err: Error = ResourceSaver.save(mm_inst.multimesh, res_path, ResourceSaver.FLAG_COMPRESS)
			if err == OK:
				mm_inst.multimesh.take_over_path(res_path)
				saved_count += 1

	var scenes_root := get_node_or_null("SpawnedScenes")
	if scenes_root:
		var saved_meshes: Dictionary = {}
		var saved_shapes: Dictionary = {}

		for child: Node in scenes_root.get_children():
			if child is ProceduralTree:
				var ptree := child as ProceduralTree
				if ptree.baked_tree_mesh:
					var m_id: int = ptree.baked_tree_mesh.get_instance_id()
					if not saved_meshes.has(m_id):
						var m_path: String = "%s/%s_TreeMesh_%d.res" % [save_dir, name, ptree.seed_value]
						if ResourceSaver.save(ptree.baked_tree_mesh, m_path, ResourceSaver.FLAG_COMPRESS) == OK:
							ptree.baked_tree_mesh.take_over_path(m_path)
							saved_meshes[m_id] = ptree.baked_tree_mesh
							saved_count += 1
					if saved_meshes.has(m_id):
						ptree.baked_tree_mesh = saved_meshes[m_id]

				if ptree.baked_trunk_collision:
					var s_id: int = ptree.baked_trunk_collision.get_instance_id()
					if not saved_shapes.has(s_id):
						var s_path: String = "%s/%s_TreeShape_%d.res" % [save_dir, name, ptree.seed_value]
						if ResourceSaver.save(ptree.baked_trunk_collision, s_path, ResourceSaver.FLAG_COMPRESS) == OK:
							ptree.baked_trunk_collision.take_over_path(s_path)
							saved_shapes[s_id] = ptree.baked_trunk_collision
							saved_count += 1
					if saved_shapes.has(s_id):
						ptree.baked_trunk_collision = saved_shapes[s_id]

	print("%s: Saved %d binary resources to '%s'." % [name, saved_count, save_dir])
#endregion


#region Dual-Bar Editor Progress Popup (With "time elapsed: mm:ss")
func _create_progress_popup() -> Dictionary:
	var dialog := AcceptDialog.new()
	dialog.title = "Populating Surface (%s)..." % name
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

	var elapsed_label := Label.new()
	elapsed_label.text = "Time elapsed: 00:00"
	vbox.add_child(elapsed_label)

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
		"task_bar": task_bar,
		"elapsed_label": elapsed_label,
		"start_msec": Time.get_ticks_msec()
	}


func _update_progress(
	popup_data: Dictionary,
	overall_pct: float,
	overall_text: String,
	task_pct: float,
	task_text: String
) -> void:
	var overall_bar := popup_data.get("overall_bar") as ProgressBar
	var overall_label := popup_data.get("overall_label") as Label
	var task_bar := popup_data.get("task_bar") as ProgressBar
	var task_label := popup_data.get("task_label") as Label
	var elapsed_label := popup_data.get("elapsed_label") as Label
	var start_msec: int = int(popup_data.get("start_msec", Time.get_ticks_msec()))

	if is_instance_valid(overall_bar):
		overall_bar.value = overall_pct
	if is_instance_valid(overall_label):
		overall_label.text = overall_text
	if is_instance_valid(task_bar):
		task_bar.value = task_pct
	if is_instance_valid(task_label):
		task_label.text = task_text
	if is_instance_valid(elapsed_label):
		var total_secs: int = maxi(int((Time.get_ticks_msec() - start_msec) / 1000), 0)
		@warning_ignore("integer_division")
		var mins: int = total_secs / 60
		var secs: int = total_secs % 60
		elapsed_label.text = "Time elapsed: %02d:%02d" % [mins, secs]


func _close_progress_popup(popup_data: Dictionary) -> void:
	var dialog := popup_data.get("dialog") as AcceptDialog
	if is_instance_valid(dialog):
		dialog.hide()
		dialog.queue_free()


func _abort_population(popup_data: Dictionary) -> void:
	_close_progress_popup(popup_data)
	_is_populating = false
	push_warning("%s: Surface population canceled by user." % name)
#endregion
