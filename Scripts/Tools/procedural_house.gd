@tool
## Procedural single-footprint house generator that builds separate Foundation, Walls, and Roof child MeshInstance3Ds.
class_name ProceduralHouse extends Node3D

enum RoofType {
	GABLE,
	HIP,
	FLAT,
	DUTCH,
	SHED,
	GAMBREL
}

const WALL_BIT_FRONT_POS_Z: int = 1
const WALL_BIT_BACK_NEG_Z: int = 2
const WALL_BIT_RIGHT_POS_X: int = 4
const WALL_BIT_LEFT_NEG_X: int = 8

@export_group("Generator Actions")
@export_tool_button("Generate House (Keep Seed)", "MeshInstance3D") var btn_generate: Callable:
	get:
		return generate_house
@export_tool_button("Randomize Seed & Generate", "RandomNumberGenerator") var btn_randomize_seed: Callable:
	get:
		return randomize_seed_and_generate
@export_tool_button("Randomize All Parameters & Generate", "Reload") var btn_randomize_all: Callable:
	get:
		return randomize_all_and_generate
@export_tool_button("Clear House", "Clear") var btn_clear: Callable:
	get:
		return clear_house
@export_tool_button("Save Meshes to Disk", "Save") var btn_save: Callable:
	get:
		return save_resources_to_disk

@export var seed_value: int = 12345:
	set(value):
		seed_value = value
		if Engine.is_editor_hint() and auto_regenerate and is_inside_tree():
			generate_house()
@export var auto_regenerate: bool = true

@export_group("Walls & Stories")
@export_range(2.0, 50.0, 0.1) var wall_width_x: float = 7.0
@export_range(2.0, 50.0, 0.1) var wall_length_z: float = 6.0
@export_range(0.05, 1.0, 0.01) var wall_thickness: float = 0.2
@export_range(1.8, 8.0, 0.05) var floor_height: float = 2.8
@export_range(1, 10, 1) var floors: int = 1
## Generates interior horizontal floor/ceiling slabs between stories
@export var generate_floor_slabs: bool = true

@export_group("Doors & Windows")
## Bitmask selecting which walls can receive doors: +Z (Front), -Z (Back), +X (Right), -X (Left)
@export_flags("+Z (Front):1", "-Z (Back):2", "+X (Right):4", "-X (Left):8") var door_allowed_walls: int = 1
@export_range(0, 8, 1) var doors_per_floor: int = 1
@export var doors_only_on_ground_floor: bool = true
@export var door_size: Vector2 = Vector2(1.0, 2.1)
@export_range(0.0, 2.0, 0.01) var door_floor_offset: float = 0.0
## Bitmask selecting which walls can receive windows: +Z (Front), -Z (Back), +X (Right), -X (Left)
@export_flags("+Z (Front):1", "-Z (Back):2", "+X (Right):4", "-X (Left):8") var window_allowed_walls: int = 15
@export_range(0, 32, 1) var windows_per_floor: int = 5
@export var window_size: Vector2 = Vector2(0.85, 1.1)
@export_range(0.1, 4.0, 0.05) var window_floor_offset: float = 0.9
@export_range(0.0, 1.0, 0.05) var window_vertical_alignment_bias: float = 0.8
@export_range(0.0, 1.0, 0.05) var window_horizontal_variation: float = 0.12
@export_range(0.1, 5.0, 0.05) var min_opening_separation: float = 0.45
@export_range(0.1, 3.0, 0.05) var corner_margin: float = 0.45

@export_group("Roof Settings")
@export var roof_type: RoofType = RoofType.GABLE
@export_range(5.0, 75.0, 0.5) var roof_angle: float = 32.0
@export_range(0.05, 5.0, 0.05) var roof_height: float = 0.22
@export_range(0.1, 3.0, 0.05) var roof_peak_height_scale: float = 1.0
@export var rotate_roof_ridge_90: bool = false

@export_subgroup("Roof Overhangs")
@export_range(0.0, 4.0, 0.05) var overhang_front: float = 0.4
@export_range(0.0, 4.0, 0.05) var overhang_back: float = 0.4
@export_range(0.0, 4.0, 0.05) var overhang_left: float = 0.4
@export_range(0.0, 4.0, 0.05) var overhang_right: float = 0.4

@export_group("Foundation & Steps")
@export_range(0.05, 5.0, 0.05) var foundation_height: float = 0.6
@export_range(0.05, 1.0, 0.01) var max_step_height: float = 0.18
@export_range(0.1, 1.5, 0.01) var step_depth: float = 0.28
@export_range(0.0, 2.0, 0.05) var step_extra_width: float = 0.2

@export_group("Randomizer Ranges")
@export var random_width_x_range: Vector2 = Vector2(5.0, 11.0)
@export var random_length_z_range: Vector2 = Vector2(5.0, 10.0)
@export var random_floors_range: Vector2i = Vector2i(1, 3)
@export var random_windows_per_floor_range: Vector2i = Vector2i(3, 8)
@export var random_roof_angle_range: Vector2 = Vector2(22.0, 42.0)
@export var random_overhang_range: Vector2 = Vector2(0.25, 0.65)
@export var random_foundation_height_range: Vector2 = Vector2(0.3, 0.9)

@export_group("Materials & UVs")
@export var foundation_material: Material
@export var walls_material: Material
@export var roof_material: Material
@export var uv_scale: Vector2 = Vector2(0.5, 0.5)

@export_group("Collision & Storage")
@export var generate_colliders: bool = true
@export var house_body_groups: Array[StringName] = [&"building", &"no_grass"]
@export_flags_3d_physics var collision_layer: int = 1
@export_flags_3d_physics var collision_mask: int = 1
@export var auto_save_to_disk: bool = false
@export var save_subfolder_name: String = "GeneratedHouses"

@export_group("Baked Data")
@export var baked_foundation_mesh: ArrayMesh:
	set(value):
		baked_foundation_mesh = value
		if is_inside_tree():
			_sync_child_meshes()
@export var baked_walls_mesh: ArrayMesh:
	set(value):
		baked_walls_mesh = value
		if is_inside_tree():
			_sync_child_meshes()
@export var baked_roof_mesh: ArrayMesh:
	set(value):
		baked_roof_mesh = value
		if is_inside_tree():
			_sync_child_meshes()


func _ready() -> void:
	var w_inst := get_node_or_null("WallsMesh") as MeshInstance3D
	if w_inst and w_inst.mesh != null:
		return # Already loaded from the .tscn / .res file! Do zero work on startup.
	if baked_foundation_mesh or baked_walls_mesh or baked_roof_mesh:
		_sync_child_meshes()
	elif Engine.is_editor_hint():
		generate_house()


func randomize_seed_and_generate() -> void:
	var prev_auto: bool = auto_regenerate
	auto_regenerate = false
	seed_value = randi()
	auto_regenerate = prev_auto
	generate_house()


func randomize_all_and_generate() -> void:
	var prev_auto: bool = auto_regenerate
	auto_regenerate = false
	seed_value = randi()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	wall_width_x = snappedf(rng.randf_range(random_width_x_range.x, random_width_x_range.y), 0.1)
	wall_length_z = snappedf(rng.randf_range(random_length_z_range.x, random_length_z_range.y), 0.1)
	floors = rng.randi_range(
		mini(random_floors_range.x, random_floors_range.y),
		maxi(random_floors_range.x, random_floors_range.y)
	)
	windows_per_floor = rng.randi_range(
		mini(random_windows_per_floor_range.x, random_windows_per_floor_range.y),
		maxi(random_windows_per_floor_range.x, random_windows_per_floor_range.y)
	)
	roof_type = rng.randi_range(0, 5) as RoofType
	roof_angle = snappedf(rng.randf_range(random_roof_angle_range.x, random_roof_angle_range.y), 0.5)
	rotate_roof_ridge_90 = rng.randf() < 0.5

	var ovh: float = snappedf(rng.randf_range(random_overhang_range.x, random_overhang_range.y), 0.05)
	overhang_front = ovh
	overhang_back = ovh
	overhang_left = ovh
	overhang_right = ovh

	foundation_height = snappedf(rng.randf_range(random_foundation_height_range.x, random_foundation_height_range.y), 0.05)

	auto_regenerate = prev_auto
	generate_house()


func clear_house() -> void:
	baked_foundation_mesh = null
	baked_walls_mesh = null
	baked_roof_mesh = null
	for child_name: String in ["FoundationMesh", "WallsMesh", "RoofMesh", "HouseStaticBody3D"]:
		var node := get_node_or_null(child_name)
		if node:
			node.free()
	notify_property_list_changed()


func generate_house() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var layout: Dictionary = _plan_all_openings(rng)
	var openings_by_floor: Array = layout["openings_by_floor"]
	var ground_doors: Array[Dictionary] = layout["ground_doors"]

	baked_foundation_mesh = _build_foundation_mesh(ground_doors)
	baked_walls_mesh = _build_walls_mesh(openings_by_floor)
	baked_roof_mesh = _build_roof_mesh()

	_sync_child_meshes()

	if auto_save_to_disk and Engine.is_editor_hint():
		save_resources_to_disk()

	notify_property_list_changed()


#region Child Node & Collider Synchronization
func _sync_child_meshes() -> void:
	var scene_owner: Node = null
	if Engine.is_editor_hint() and is_inside_tree():
		var edited_root: Node = get_tree().edited_scene_root
		if edited_root == self or (edited_root and edited_root.is_ancestor_of(self)):
			scene_owner = edited_root

	var f_inst: MeshInstance3D = _get_or_create_mesh_child("FoundationMesh", scene_owner)
	f_inst.position = Vector3.ZERO
	f_inst.mesh = baked_foundation_mesh
	if foundation_material and baked_foundation_mesh and baked_foundation_mesh.get_surface_count() > 0:
		baked_foundation_mesh.surface_set_material(0, foundation_material)

	var w_inst: MeshInstance3D = _get_or_create_mesh_child("WallsMesh", scene_owner)
	w_inst.position = Vector3(0.0, foundation_height, 0.0)
	w_inst.mesh = baked_walls_mesh
	if walls_material and baked_walls_mesh and baked_walls_mesh.get_surface_count() > 0:
		baked_walls_mesh.surface_set_material(0, walls_material)

	var r_inst: MeshInstance3D = _get_or_create_mesh_child("RoofMesh", scene_owner)
	r_inst.position = Vector3(0.0, foundation_height + float(floors) * floor_height, 0.0)
	r_inst.mesh = baked_roof_mesh
	if roof_material and baked_roof_mesh and baked_roof_mesh.get_surface_count() > 0:
		baked_roof_mesh.surface_set_material(0, roof_material)

	_sync_colliders(scene_owner)


func _get_or_create_mesh_child(node_name: String, scene_owner: Node) -> MeshInstance3D:
	var inst := get_node_or_null(node_name) as MeshInstance3D
	if not is_instance_valid(inst):
		inst = MeshInstance3D.new()
		inst.name = node_name
		add_child(inst)
	if scene_owner and get_tree().edited_scene_root == self:
		inst.owner = scene_owner
	return inst


func _sync_colliders(scene_owner: Node) -> void:
	var body := get_node_or_null("HouseStaticBody3D") as StaticBody3D
	if not generate_colliders:
		if is_instance_valid(body):
			body.free()
		return

	if not is_instance_valid(body):
		body = StaticBody3D.new()
		body.name = "HouseStaticBody3D"
		add_child(body)

	body.collision_layer = collision_layer
	body.collision_mask = collision_mask
	for grp: StringName in house_body_groups:
		if grp != &"" and not body.is_in_group(grp):
			body.add_to_group(grp, true)

	if scene_owner and get_tree().edited_scene_root == self:
		body.owner = scene_owner

	var parts: Array[Dictionary] = [
		{"name": "FoundationCol", "mesh": baked_foundation_mesh, "y": 0.0},
		{"name": "WallsCol", "mesh": baked_walls_mesh, "y": foundation_height},
		{"name": "RoofCol", "mesh": baked_roof_mesh, "y": foundation_height + float(floors) * floor_height}
	]

	for part: Dictionary in parts:
		var col_name: String = part["name"]
		var m: ArrayMesh = part["mesh"]
		var col_node := body.get_node_or_null(col_name) as CollisionShape3D
		if not m or m.get_surface_count() == 0:
			if is_instance_valid(col_node):
				col_node.free()
			continue

		if not is_instance_valid(col_node):
			col_node = CollisionShape3D.new()
			col_node.name = col_name
			body.add_child(col_node)

		col_node.position = Vector3(0.0, float(part["y"]), 0.0)
		col_node.shape = m.create_trimesh_shape()
		if scene_owner and get_tree().edited_scene_root == self:
			col_node.owner = scene_owner
#endregion


#region Step 1: Door & Vertically-Biased Window Slot Planner
## Wall indices: 0 = Front (+Z, bit 1), 1 = Back (-Z, bit 2), 2 = Right (+X, bit 4), 3 = Left (-X, bit 8)
func _get_wall_definitions() -> Array[Dictionary]:
	var hx: float = wall_width_x * 0.5
	var hz: float = wall_length_z * 0.5
	return [
		{
			"id": 0,
			"bit": WALL_BIT_FRONT_POS_Z,
			"length": wall_width_x,
			"start": Vector3(-hx, 0.0, hz),
			"right": Vector3.RIGHT,
			"normal": Vector3.BACK,
			"overhang": overhang_front
		},
		{
			"id": 1,
			"bit": WALL_BIT_BACK_NEG_Z,
			"length": wall_width_x,
			"start": Vector3(hx, 0.0, -hz),
			"right": Vector3.LEFT,
			"normal": Vector3.FORWARD,
			"overhang": overhang_back
		},
		{
			"id": 2,
			"bit": WALL_BIT_RIGHT_POS_X,
			"length": wall_length_z,
			"start": Vector3(hx, 0.0, hz),
			"right": Vector3.FORWARD,
			"normal": Vector3.RIGHT,
			"overhang": overhang_right
		},
		{
			"id": 3,
			"bit": WALL_BIT_LEFT_NEG_X,
			"length": wall_length_z,
			"start": Vector3(-hx, 0.0, -hz),
			"right": Vector3.BACK,
			"normal": Vector3.LEFT,
			"overhang": overhang_left
		}
	]


func _plan_all_openings(rng: RandomNumberGenerator) -> Dictionary:
	var wall_defs: Array[Dictionary] = _get_wall_definitions()
	var openings_by_floor: Array = []
	var ground_doors: Array[Dictionary] = []

	var eff_margin: float = maxf(corner_margin, wall_thickness + 0.05)
	var d_width: float = clampf(door_size.x, 0.3, 10.0)
	var d_height: float = clampf(door_size.y, 0.5, floor_height - 0.05)
	var d_v0: float = clampf(door_floor_offset, 0.0, floor_height - d_height)
	var d_v1: float = d_v0 + d_height

	var w_width: float = clampf(window_size.x, 0.2, 10.0)
	var w_height: float = clampf(window_size.y, 0.2, floor_height - 0.1)
	var w_v0: float = clampf(window_floor_offset, 0.05, floor_height - w_height - 0.05)
	var w_v1: float = w_v0 + w_height

	var active_door_mask: int = door_allowed_walls if door_allowed_walls != 0 else 15
	var active_win_mask: int = window_allowed_walls

	var master_wall_columns: Array = [[], [], [], []]
	for w_id: int in range(4):
		var w_len: float = float(wall_defs[w_id]["length"])
		var usable_len: float = w_len - 2.0 * eff_margin
		var col_count: int = int(floorf((usable_len + min_opening_separation) / (w_width + min_opening_separation)))
		if col_count >= 1:
			var step_gap: float = (usable_len - float(col_count) * w_width) / float(col_count + 1)
			for k: int in range(col_count):
				var u_center: float = eff_margin + step_gap * float(k + 1) + w_width * (float(k) + 0.5)
				(master_wall_columns[w_id] as Array).append(u_center)

	for f_idx: int in range(floors):
		var floor_walls: Array = [[], [], [], []]

		var target_doors: int = doors_per_floor if (f_idx == 0 or not doors_only_on_ground_floor) else 0
		if target_doors > 0:
			var door_candidates: Array[Dictionary] = []
			for w_id: int in range(4):
				var w_bit: int = int(wall_defs[w_id]["bit"])
				if (active_door_mask & w_bit) == 0:
					continue

				var w_len: float = float(wall_defs[w_id]["length"])
				var usable_len: float = w_len - 2.0 * eff_margin
				var max_doors_on_wall: int = int(floorf((usable_len + min_opening_separation) / (d_width + min_opening_separation)))
				if max_doors_on_wall >= 1:
					var gap: float = (usable_len - float(max_doors_on_wall) * d_width) / float(max_doors_on_wall + 1)
					for k: int in range(max_doors_on_wall):
						var u0: float = eff_margin + gap * float(k + 1) + d_width * float(k)
						door_candidates.append({
							"wall_id": w_id,
							"u0": u0,
							"u1": u0 + d_width,
							"center": u0 + d_width * 0.5,
							"v0": d_v0,
							"v1": d_v1,
							"is_door": true
						})

			_shuffle_array_seeded(rng, door_candidates)
			var doors_to_pick: int = mini(target_doors, door_candidates.size())
			for d_i: int in range(doors_to_pick):
				var d_open: Dictionary = door_candidates[d_i]
				var w_id: int = int(d_open["wall_id"])
				(floor_walls[w_id] as Array).append(d_open)
				if f_idx == 0:
					ground_doors.append(d_open)

		for w_id: int in range(4):
			(floor_walls[w_id] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["u0"]) < float(b["u0"]))

		if windows_per_floor > 0 and active_win_mask != 0:
			var window_candidates: Array[Dictionary] = []

			for w_id: int in range(4):
				var w_bit: int = int(wall_defs[w_id]["bit"])
				if (active_win_mask & w_bit) == 0:
					continue

				var w_len: float = float(wall_defs[w_id]["length"])
				var existing_doors: Array = floor_walls[w_id]
				var free_spans: Array[Vector2] = []

				var cursor: float = eff_margin
				for d_open: Dictionary in existing_doors:
					var span_end: float = float(d_open["u0"]) - min_opening_separation
					if span_end - cursor >= w_width:
						free_spans.append(Vector2(cursor, span_end))
					cursor = float(d_open["u1"]) + min_opening_separation

				var final_end: float = w_len - eff_margin
				if final_end - cursor >= w_width:
					free_spans.append(Vector2(cursor, final_end))

				for span: Vector2 in free_spans:
					var span_len: float = span.y - span.x
					var max_win: int = int(floorf((span_len + min_opening_separation) / (w_width + min_opening_separation)))
					if max_win <= 0:
						continue
					var step_gap: float = (span_len - float(max_win) * w_width) / float(max_win + 1)
					var max_jitter: float = minf(step_gap * 0.45, w_width * 0.35) * window_horizontal_variation

					for k: int in range(max_win):
						var base_u0: float = span.x + step_gap * float(k + 1) + w_width * float(k)
						var base_center: float = base_u0 + w_width * 0.5

						for col_c: float in (master_wall_columns[w_id] as Array):
							if absf(col_c - base_center) <= step_gap * 0.5:
								base_center = lerpf(base_center, col_c, window_vertical_alignment_bias)
								break

						var jitter: float = rng.randf_range(-max_jitter, max_jitter)
						var u0: float = clampf(base_center - w_width * 0.5 + jitter, span.x, span.y - w_width)
						var center_u: float = u0 + w_width * 0.5

						var weight: float = _compute_window_vertical_weight(
							w_id,
							center_u,
							w_width,
							f_idx,
							openings_by_floor
						)

						window_candidates.append({
							"wall_id": w_id,
							"u0": u0,
							"u1": u0 + w_width,
							"center": center_u,
							"v0": w_v0,
							"v1": w_v1,
							"is_door": false,
							"weight": weight
						})

			var win_to_pick: int = mini(windows_per_floor, window_candidates.size())
			for _w_i: int in range(win_to_pick):
				if window_candidates.is_empty():
					break
				var picked_idx: int = _pick_weighted_candidate_index(rng, window_candidates)
				var w_open: Dictionary = window_candidates[picked_idx]
				window_candidates.remove_at(picked_idx)

				var w_id: int = int(w_open["wall_id"])
				(floor_walls[w_id] as Array).append(w_open)

				for c_idx: int in range(window_candidates.size() - 1, -1, -1):
					var cand: Dictionary = window_candidates[c_idx]
					if int(cand["wall_id"]) == w_id:
						if float(cand["u0"]) < float(w_open["u1"]) + min_opening_separation and float(cand["u1"]) > float(w_open["u0"]) - min_opening_separation:
							window_candidates.remove_at(c_idx)

			for w_id: int in range(4):
				(floor_walls[w_id] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["u0"]) < float(b["u0"]))

		openings_by_floor.append(floor_walls)

	return {
		"openings_by_floor": openings_by_floor,
		"ground_doors": ground_doors
	}


func _compute_window_vertical_weight(
	w_id: int,
	center_u: float,
	w_width: float,
	current_floor: int,
	openings_by_floor: Array
) -> float:
	if current_floor <= 0 or window_vertical_alignment_bias <= 0.001:
		return 1.0

	var best_alignment: float = 0.0
	var search_radius: float = maxf(w_width * 1.35, 0.5)

	for check_f: int in range(current_floor - 1, -1, -1):
		var below_wall_openings: Array = openings_by_floor[check_f][w_id]
		var floor_decay: float = 1.0 if (check_f == current_floor - 1) else 0.7
		for below_open: Dictionary in below_wall_openings:
			var below_center: float = float(below_open.get("center", (float(below_open["u0"]) + float(below_open["u1"])) * 0.5))
			var dist: float = absf(center_u - below_center)
			if dist < search_radius:
				var match_strength: float = 1.0 - (dist / search_radius)
				var type_mult: float = 1.0 if not bool(below_open["is_door"]) else 0.65
				best_alignment = maxf(best_alignment, match_strength * floor_decay * type_mult)

	return 1.0 + best_alignment * best_alignment * window_vertical_alignment_bias * 15.0


func _pick_weighted_candidate_index(rng: RandomNumberGenerator, candidates: Array[Dictionary]) -> int:
	var total_w: float = 0.0
	for cand: Dictionary in candidates:
		total_w += maxf(float(cand.get("weight", 1.0)), 0.01)

	var roll: float = rng.randf() * total_w
	var accum: float = 0.0
	for idx: int in range(candidates.size()):
		accum += maxf(float(candidates[idx].get("weight", 1.0)), 0.01)
		if roll <= accum:
			return idx
	return candidates.size() - 1


func _shuffle_array_seeded(rng: RandomNumberGenerator, arr: Array) -> void:
	for i: int in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
#endregion


#region Step 2: Foundation & Door Steps Builder
func _build_foundation_mesh(ground_doors: Array[Dictionary]) -> ArrayMesh:
	var mb: Dictionary = _create_mesh_buffers()

	var hx: float = wall_width_x * 0.5
	var hz: float = wall_length_z * 0.5

	var min_x: float = -hx - overhang_left
	var max_x: float = hx + overhang_right
	var min_z: float = -hz - overhang_back
	var max_z: float = hz + overhang_front

	_append_box(
		mb,
		Vector3(min_x, 0.0, min_z),
		Vector3(max_x, foundation_height, max_z)
	)

	if foundation_height > 0.01 and not ground_doors.is_empty():
		var wall_defs: Array[Dictionary] = _get_wall_definitions()
		var step_count: int = maxi(int(ceilf(foundation_height / maxf(max_step_height, 0.02))), 1)
		var actual_step_h: float = foundation_height / float(step_count)

		for d_open: Dictionary in ground_doors:
			var w_id: int = int(d_open["wall_id"])
			var w_def: Dictionary = wall_defs[w_id]
			var w_start: Vector3 = w_def["start"]
			var w_right: Vector3 = w_def["right"]
			var w_normal: Vector3 = w_def["normal"]
			var w_overhang: float = float(w_def["overhang"])

			var u0: float = float(d_open["u0"]) - step_extra_width
			var u1: float = float(d_open["u1"]) + step_extra_width
			var foundation_edge_origin: Vector3 = w_start + w_normal * w_overhang

			for s_idx: int in range(step_count):
				var top_y: float = foundation_height - float(s_idx) * actual_step_h
				var d0: float = float(s_idx) * step_depth
				var d1: float = float(s_idx + 1) * step_depth

				var p_fl: Vector3 = foundation_edge_origin + w_right * u0 + w_normal * d1
				var p_fr: Vector3 = foundation_edge_origin + w_right * u1 + w_normal * d1
				var p_bl: Vector3 = foundation_edge_origin + w_right * u0 + w_normal * d0
				var p_br: Vector3 = foundation_edge_origin + w_right * u1 + w_normal * d0

				_add_quad(
					mb,
					Vector3(p_bl.x, top_y, p_bl.z),
					Vector3(p_br.x, top_y, p_br.z),
					Vector3(p_fr.x, top_y, p_fr.z),
					Vector3(p_fl.x, top_y, p_fl.z),
					Vector3.UP
				)
				var bot_y: float = top_y - actual_step_h
				_add_quad(
					mb,
					Vector3(p_fl.x, bot_y, p_fl.z),
					Vector3(p_fr.x, bot_y, p_fr.z),
					Vector3(p_fr.x, top_y, p_fr.z),
					Vector3(p_fl.x, top_y, p_fl.z),
					w_normal
				)
				_add_quad(
					mb,
					Vector3(p_bl.x, 0.0, p_bl.z),
					Vector3(p_fl.x, 0.0, p_fl.z),
					Vector3(p_fl.x, top_y, p_fl.z),
					Vector3(p_bl.x, top_y, p_bl.z),
					-w_right
				)
				_add_quad(
					mb,
					Vector3(p_fr.x, 0.0, p_fr.z),
					Vector3(p_br.x, 0.0, p_br.z),
					Vector3(p_br.x, top_y, p_br.z),
					Vector3(p_fr.x, top_y, p_fr.z),
					w_right
				)

	return _commit_mesh_buffers(mb, foundation_material)
#endregion


#region Step 3: Multi-Story Walls, Slabs, Cutouts & Roof Wall Continuations
func _build_walls_mesh(openings_by_floor: Array) -> ArrayMesh:
	var mb: Dictionary = _create_mesh_buffers()
	var wall_defs: Array[Dictionary] = _get_wall_definitions()
	var t: float = clampf(wall_thickness, 0.02, minf(wall_width_x, wall_length_z) * 0.4)
	var hx: float = wall_width_x * 0.5 - t
	var hz: float = wall_length_z * 0.5 - t

	for f_idx: int in range(floors):
		var y_base: float = float(f_idx) * floor_height
		var floor_walls: Array = openings_by_floor[f_idx]

		for w_id: int in range(4):
			var w_def: Dictionary = wall_defs[w_id]
			var w_len: float = float(w_def["length"])
			var w_start: Vector3 = w_def["start"] + Vector3(0.0, y_base, 0.0)
			var w_right: Vector3 = w_def["right"]
			var w_normal: Vector3 = w_def["normal"]
			var openings: Array = floor_walls[w_id]

			_append_wall_with_openings(mb, w_start, w_right, w_normal, w_len, floor_height, t, openings)

		if generate_floor_slabs and f_idx > 0:
			_append_box(
				mb,
				Vector3(-hx, y_base - t * 0.5, -hz),
				Vector3(hx, y_base + t * 0.5, hz)
			)

	_append_roof_wall_extensions(mb, float(floors) * floor_height, t)

	return _commit_mesh_buffers(mb, walls_material)


func _append_roof_wall_extensions(mb: Dictionary, y_top: float, thickness: float) -> void:
	var half_u: float = (wall_length_z if rotate_roof_ridge_90 else wall_width_x) * 0.5
	var half_v: float = (wall_width_x if rotate_roof_ridge_90 else wall_length_z) * 0.5
	var span_u: float = half_u * 2.0
	var slope_tan: float = tan(deg_to_rad(clampf(roof_angle, 2.0, 80.0))) * roof_peak_height_scale

	var out_pos_v: Vector3 = _roof_dir(0.0, 0.0, 1.0)
	var out_neg_v: Vector3 = _roof_dir(0.0, 0.0, -1.0)
	var out_pos_u: Vector3 = _roof_dir(1.0, 0.0, 0.0)

	match roof_type:
		RoofType.GABLE:
			var y_peak: float = y_top + half_u * slope_tan
			for s_sign: float in [1.0, -1.0]:
				var v_ext: float = half_v * s_sign
				var v_int: float = (half_v - thickness) * s_sign
				var n_out: Vector3 = out_pos_v if s_sign > 0.0 else out_neg_v

				_add_tri(
					mb,
					_roof_pt(-half_u, y_top, v_ext),
					_roof_pt(half_u, y_top, v_ext),
					_roof_pt(0.0, y_peak, v_ext),
					n_out
				)
				_add_tri(
					mb,
					_roof_pt(half_u, y_top, v_int),
					_roof_pt(-half_u, y_top, v_int),
					_roof_pt(0.0, y_peak, v_int),
					-n_out
				)

		RoofType.SHED:
			var y_high: float = y_top + span_u * slope_tan
			for s_sign: float in [1.0, -1.0]:
				var v_ext: float = half_v * s_sign
				var v_int: float = (half_v - thickness) * s_sign
				var n_out: Vector3 = out_pos_v if s_sign > 0.0 else out_neg_v

				_add_tri(
					mb,
					_roof_pt(-half_u, y_top, v_ext),
					_roof_pt(half_u, y_top, v_ext),
					_roof_pt(half_u, y_high, v_ext),
					n_out
				)
				_add_tri(
					mb,
					_roof_pt(half_u, y_top, v_int),
					_roof_pt(-half_u, y_top, v_int),
					_roof_pt(half_u, y_high, v_int),
					-n_out
				)

			var u_ext: float = half_u
			var u_int: float = half_u - thickness
			_add_quad(
				mb,
				_roof_pt(u_ext, y_top, -half_v),
				_roof_pt(u_ext, y_top, half_v),
				_roof_pt(u_ext, y_high, half_v),
				_roof_pt(u_ext, y_high, -half_v),
				out_pos_u
			)
			_add_quad(
				mb,
				_roof_pt(u_int, y_top, half_v),
				_roof_pt(u_int, y_top, -half_v),
				_roof_pt(u_int, y_high, -half_v),
				_roof_pt(u_int, y_high, half_v),
				-out_pos_u
			)

		RoofType.GAMBREL:
			var knuckle_u: float = half_u * 0.55
			var steep_tan: float = tan(deg_to_rad(clampf(roof_angle * 1.45, 10.0, 78.0))) * roof_peak_height_scale
			var gentle_tan: float = tan(deg_to_rad(clampf(roof_angle * 0.55, 5.0, 60.0))) * roof_peak_height_scale

			var y_knuckle: float = y_top + (half_u - knuckle_u) * steep_tan
			var y_peak: float = y_knuckle + knuckle_u * gentle_tan

			for s_sign: float in [1.0, -1.0]:
				var v_ext: float = half_v * s_sign
				var v_int: float = (half_v - thickness) * s_sign
				var n_out: Vector3 = out_pos_v if s_sign > 0.0 else out_neg_v

				_add_quad(
					mb,
					_roof_pt(-half_u, y_top, v_ext),
					_roof_pt(half_u, y_top, v_ext),
					_roof_pt(knuckle_u, y_knuckle, v_ext),
					_roof_pt(-knuckle_u, y_knuckle, v_ext),
					n_out
				)
				_add_tri(
					mb,
					_roof_pt(-knuckle_u, y_knuckle, v_ext),
					_roof_pt(knuckle_u, y_knuckle, v_ext),
					_roof_pt(0.0, y_peak, v_ext),
					n_out
				)

				_add_quad(
					mb,
					_roof_pt(half_u, y_top, v_int),
					_roof_pt(-half_u, y_top, v_int),
					_roof_pt(-knuckle_u, y_knuckle, v_int),
					_roof_pt(knuckle_u, y_knuckle, v_int),
					-n_out
				)
				_add_tri(
					mb,
					_roof_pt(knuckle_u, y_knuckle, v_int),
					_roof_pt(-knuckle_u, y_knuckle, v_int),
					_roof_pt(0.0, y_peak, v_int),
					-n_out
				)


func _append_wall_with_openings(
	mb: Dictionary,
	w_start: Vector3,
	w_right: Vector3,
	w_normal: Vector3,
	w_len: float,
	w_height: float,
	thickness: float,
	openings: Array
) -> void:
	var inward_offset: Vector3 = -w_normal * thickness
	var cursor_u: float = 0.0

	for open_data: Dictionary in openings:
		var u0: float = clampf(float(open_data["u0"]), cursor_u, w_len)
		var u1: float = clampf(float(open_data["u1"]), u0, w_len)
		var v0: float = clampf(float(open_data["v0"]), 0.0, w_height)
		var v1: float = clampf(float(open_data["v1"]), v0, w_height)

		if u0 - cursor_u > 0.001:
			_append_wall_panel(mb, w_start, w_right, w_normal, inward_offset, cursor_u, u0, 0.0, w_height)
		if v0 > 0.001:
			_append_wall_panel(mb, w_start, w_right, w_normal, inward_offset, u0, u1, 0.0, v0)
		if w_height - v1 > 0.001:
			_append_wall_panel(mb, w_start, w_right, w_normal, inward_offset, u0, u1, v1, w_height)

		var ext_bl: Vector3 = w_start + w_right * u0 + Vector3(0.0, v0, 0.0)
		var ext_br: Vector3 = w_start + w_right * u1 + Vector3(0.0, v0, 0.0)
		var ext_tr: Vector3 = w_start + w_right * u1 + Vector3(0.0, v1, 0.0)
		var ext_tl: Vector3 = w_start + w_right * u0 + Vector3(0.0, v1, 0.0)

		var int_bl: Vector3 = ext_bl + inward_offset
		var int_br: Vector3 = ext_br + inward_offset
		var int_tr: Vector3 = ext_tr + inward_offset
		var int_tl: Vector3 = ext_tl + inward_offset

		_add_quad(mb, ext_bl, int_bl, int_tl, ext_tl, w_right)
		_add_quad(mb, int_br, ext_br, ext_tr, int_tr, -w_right)
		_add_quad(mb, ext_tl, int_tl, int_tr, ext_tr, Vector3.DOWN)
		if v0 > 0.001:
			_add_quad(mb, ext_bl, ext_br, int_br, int_bl, Vector3.UP)

		cursor_u = u1

	if w_len - cursor_u > 0.001:
		_append_wall_panel(mb, w_start, w_right, w_normal, inward_offset, cursor_u, w_len, 0.0, w_height)


func _append_wall_panel(
	mb: Dictionary,
	w_start: Vector3,
	w_right: Vector3,
	w_normal: Vector3,
	inward_offset: Vector3,
	u0: float,
	u1: float,
	v0: float,
	v1: float
) -> void:
	var ext_bl: Vector3 = w_start + w_right * u0 + Vector3(0.0, v0, 0.0)
	var ext_br: Vector3 = w_start + w_right * u1 + Vector3(0.0, v0, 0.0)
	var ext_tr: Vector3 = w_start + w_right * u1 + Vector3(0.0, v1, 0.0)
	var ext_tl: Vector3 = w_start + w_right * u0 + Vector3(0.0, v1, 0.0)

	_add_quad(mb, ext_bl, ext_br, ext_tr, ext_tl, w_normal)
	_add_quad(
		mb,
		ext_br + inward_offset,
		ext_bl + inward_offset,
		ext_tl + inward_offset,
		ext_tr + inward_offset,
		-w_normal
	)
#endregion


#region Step 4: Six-Type Roof Builder
func _build_roof_mesh() -> ArrayMesh:
	var mb: Dictionary = _create_mesh_buffers()

	var hx: float = wall_width_x * 0.5
	var hz: float = wall_length_z * 0.5

	var min_x: float = -hx - overhang_left
	var max_x: float = hx + overhang_right
	var min_z: float = -hz - overhang_back
	var max_z: float = hz + overhang_front

	var thickness: float = maxf(roof_height, 0.02)

	if roof_type == RoofType.FLAT:
		_append_box(mb, Vector3(min_x, 0.0, min_z), Vector3(max_x, thickness, max_z))
		return _commit_mesh_buffers(mb, roof_material)

	var half_u: float = hz if rotate_roof_ridge_90 else hx
	var u_min: float = min_z if rotate_roof_ridge_90 else min_x
	var u_max: float = max_z if rotate_roof_ridge_90 else max_x
	var v_min: float = min_x if rotate_roof_ridge_90 else min_z
	var v_max: float = max_x if rotate_roof_ridge_90 else max_z

	var ovh_u_min: float = overhang_back if rotate_roof_ridge_90 else overhang_left
	var ovh_u_max: float = overhang_front if rotate_roof_ridge_90 else overhang_right

	var span_u: float = u_max - u_min
	var span_v: float = v_max - v_min
	var mid_u: float = (u_min + u_max) * 0.5
	var mid_v: float = (v_min + v_max) * 0.5
	var slope_tan: float = tan(deg_to_rad(clampf(roof_angle, 2.0, 80.0))) * roof_peak_height_scale

	var out_pos_u: Vector3 = _roof_dir(1.0, 0.0, 0.0)
	var out_neg_u: Vector3 = _roof_dir(-1.0, 0.0, 0.0)
	var out_pos_v: Vector3 = _roof_dir(0.0, 0.0, 1.0)
	var out_neg_v: Vector3 = _roof_dir(0.0, 0.0, -1.0)

	match roof_type:
		RoofType.GABLE:
			var y_peak: float = half_u * slope_tan
			var y_left_eave: float = -ovh_u_min * slope_tan
			var y_right_eave: float = -ovh_u_max * slope_tan

			_append_roof_slope_segment(mb, u_min, y_left_eave, 0.0, y_peak, v_min, v_max, thickness, true, false)
			_append_roof_slope_segment(mb, 0.0, y_peak, u_max, y_right_eave, v_min, v_max, thickness, false, true)

		RoofType.SHED:
			var y_wall_high: float = (2.0 * half_u) * slope_tan
			var y_low_eave: float = -ovh_u_min * slope_tan
			var y_high_eave: float = y_wall_high + ovh_u_max * slope_tan

			_append_roof_slope_segment(mb, u_min, y_low_eave, u_max, y_high_eave, v_min, v_max, thickness, true, true)

		RoofType.GAMBREL:
			var knuckle_u: float = half_u * 0.55
			var steep_tan: float = tan(deg_to_rad(clampf(roof_angle * 1.45, 10.0, 78.0))) * roof_peak_height_scale
			var gentle_tan: float = tan(deg_to_rad(clampf(roof_angle * 0.55, 5.0, 60.0))) * roof_peak_height_scale

			var y_knuckle: float = (half_u - knuckle_u) * steep_tan
			var y_peak: float = y_knuckle + knuckle_u * gentle_tan
			var y_left_eave: float = -ovh_u_min * steep_tan
			var y_right_eave: float = -ovh_u_max * steep_tan

			_append_roof_slope_segment(mb, u_min, y_left_eave, -knuckle_u, y_knuckle, v_min, v_max, thickness, true, false)
			_append_roof_slope_segment(mb, -knuckle_u, y_knuckle, 0.0, y_peak, v_min, v_max, thickness, false, false)
			_append_roof_slope_segment(mb, 0.0, y_peak, knuckle_u, y_knuckle, v_min, v_max, thickness, false, false)
			_append_roof_slope_segment(mb, knuckle_u, y_knuckle, u_max, y_right_eave, v_min, v_max, thickness, false, true)

		RoofType.HIP:
			_append_eave_fascia_ring(mb, min_x, max_x, min_z, max_z, thickness)
			var inset: float = minf(span_u, span_v) * 0.5
			var y_peak: float = thickness + slope_tan * inset

			var bl: Vector3 = _roof_pt(u_min, thickness, v_min)
			var fl: Vector3 = _roof_pt(u_min, thickness, v_max)
			var br: Vector3 = _roof_pt(u_max, thickness, v_min)
			var fr: Vector3 = _roof_pt(u_max, thickness, v_max)

			if span_v >= span_u:
				var r_back: Vector3 = _roof_pt(mid_u, y_peak, v_min + inset)
				var r_front: Vector3 = _roof_pt(mid_u, y_peak, v_max - inset)
				_add_oriented_quad(mb, fl, bl, r_back, r_front, Vector3.UP + out_neg_u)
				_add_oriented_quad(mb, br, fr, r_front, r_back, Vector3.UP + out_pos_u)
				_add_oriented_tri(mb, fl, fr, r_front, Vector3.UP + out_pos_v)
				_add_oriented_tri(mb, br, bl, r_back, Vector3.UP + out_neg_v)
			else:
				var r_left: Vector3 = _roof_pt(u_min + inset, y_peak, mid_v)
				var r_right: Vector3 = _roof_pt(u_max - inset, y_peak, mid_v)
				_add_oriented_quad(mb, fl, fr, r_right, r_left, Vector3.UP + out_pos_v)
				_add_oriented_quad(mb, br, bl, r_left, r_right, Vector3.UP + out_neg_v)
				_add_oriented_tri(mb, bl, fl, r_left, Vector3.UP + out_neg_u)
				_add_oriented_tri(mb, fr, br, r_right, Vector3.UP + out_pos_u)

		RoofType.DUTCH:
			_append_eave_fascia_ring(mb, min_x, max_x, min_z, max_z, thickness)
			var hip_ratio: float = 0.42
			var inset_u: float = (span_u * 0.5) * hip_ratio
			var inset_v: float = minf(span_v * 0.28, inset_u)
			var y_mid: float = thickness + slope_tan * inset_u
			var y_peak: float = thickness + slope_tan * (span_u * 0.5)

			var bl: Vector3 = _roof_pt(u_min, thickness, v_min)
			var fl: Vector3 = _roof_pt(u_min, thickness, v_max)
			var br: Vector3 = _roof_pt(u_max, thickness, v_min)
			var fr: Vector3 = _roof_pt(u_max, thickness, v_max)

			var m_bl: Vector3 = _roof_pt(u_min + inset_u, y_mid, v_min + inset_v)
			var m_fl: Vector3 = _roof_pt(u_min + inset_u, y_mid, v_max - inset_v)
			var m_br: Vector3 = _roof_pt(u_max - inset_u, y_mid, v_min + inset_v)
			var m_fr: Vector3 = _roof_pt(u_max - inset_u, y_mid, v_max - inset_v)

			var r_back: Vector3 = _roof_pt(mid_u, y_peak, v_min + inset_v)
			var r_front: Vector3 = _roof_pt(mid_u, y_peak, v_max - inset_v)

			_add_oriented_quad(mb, fl, bl, m_bl, m_fl, Vector3.UP + out_neg_u)
			_add_oriented_quad(mb, br, fr, m_fr, m_br, Vector3.UP + out_pos_u)
			_add_oriented_quad(mb, fl, fr, m_fr, m_fl, Vector3.UP + out_pos_v)
			_add_oriented_quad(mb, br, bl, m_bl, m_br, Vector3.UP + out_neg_v)

			_add_oriented_tri(mb, m_fl, m_fr, r_front, out_pos_v)
			_add_oriented_tri(mb, m_br, m_bl, r_back, out_neg_v)

			var brow: float = minf(inset_v * 0.35, 0.25)
			_append_roof_slope_segment(
				mb,
				u_min + inset_u, y_mid,
				mid_u, y_peak,
				v_min + inset_v - brow, v_max - inset_v + brow,
				thickness * 0.75,
				true, false
			)
			_append_roof_slope_segment(
				mb,
				mid_u, y_peak,
				u_max - inset_u, y_mid,
				v_min + inset_v - brow, v_max - inset_v + brow,
				thickness * 0.75,
				false, true
			)

	return _commit_mesh_buffers(mb, roof_material)


func _append_roof_slope_segment(
	mb: Dictionary,
	u0: float, y0: float,
	u1: float, y1: float,
	v_min: float, v_max: float,
	thickness: float,
	cap_u0_eave: bool,
	cap_u1_eave: bool
) -> void:
	var b0_back: Vector3 = _roof_pt(u0, y0, v_min)
	var b0_front: Vector3 = _roof_pt(u0, y0, v_max)
	var b1_back: Vector3 = _roof_pt(u1, y1, v_min)
	var b1_front: Vector3 = _roof_pt(u1, y1, v_max)

	var t0_back: Vector3 = _roof_pt(u0, y0 + thickness, v_min)
	var t0_front: Vector3 = _roof_pt(u0, y0 + thickness, v_max)
	var t1_back: Vector3 = _roof_pt(u1, y1 + thickness, v_min)
	var t1_front: Vector3 = _roof_pt(u1, y1 + thickness, v_max)

	var out_pos_u: Vector3 = _roof_dir(1.0, 0.0, 0.0)
	var out_neg_u: Vector3 = _roof_dir(-1.0, 0.0, 0.0)
	var out_pos_v: Vector3 = _roof_dir(0.0, 0.0, 1.0)
	var out_neg_v: Vector3 = _roof_dir(0.0, 0.0, -1.0)

	_add_oriented_quad(mb, t0_front, t0_back, t1_back, t1_front, Vector3.UP)
	_add_oriented_quad(mb, b0_back, b0_front, b1_front, b1_back, Vector3.DOWN)
	_add_oriented_quad(mb, b0_front, b1_front, t1_front, t0_front, out_pos_v)
	_add_oriented_quad(mb, b1_back, b0_back, t0_back, t1_back, out_neg_v)

	if cap_u0_eave:
		_add_oriented_quad(mb, b0_back, b0_front, t0_front, t0_back, out_neg_u)
	if cap_u1_eave:
		_add_oriented_quad(mb, b1_front, b1_back, t1_back, t1_front, out_pos_u)


func _roof_pt(u: float, y: float, v: float) -> Vector3:
	if rotate_roof_ridge_90:
		return Vector3(v, y, u)
	return Vector3(u, y, v)


func _roof_dir(du: float, dy: float, dv: float) -> Vector3:
	if rotate_roof_ridge_90:
		return Vector3(dv, dy, du).normalized()
	return Vector3(du, dy, dv).normalized()


func _append_eave_fascia_ring(mb: Dictionary, min_x: float, max_x: float, min_z: float, max_z: float, y0: float) -> void:
	_add_quad(
		mb,
		Vector3(min_x, 0.0, min_z),
		Vector3(max_x, 0.0, min_z),
		Vector3(max_x, 0.0, max_z),
		Vector3(min_x, 0.0, max_z),
		Vector3.DOWN
	)
	_add_quad(
		mb,
		Vector3(min_x, 0.0, max_z),
		Vector3(max_x, 0.0, max_z),
		Vector3(max_x, y0, max_z),
		Vector3(min_x, y0, max_z),
		Vector3.BACK
	)
	_add_quad(
		mb,
		Vector3(max_x, 0.0, min_z),
		Vector3(min_x, 0.0, min_z),
		Vector3(min_x, y0, min_z),
		Vector3(max_x, y0, min_z),
		Vector3.FORWARD
	)
	_add_quad(
		mb,
		Vector3(max_x, 0.0, max_z),
		Vector3(max_x, 0.0, min_z),
		Vector3(max_x, y0, min_z),
		Vector3(max_x, y0, max_z),
		Vector3.RIGHT
	)
	_add_quad(
		mb,
		Vector3(min_x, 0.0, min_z),
		Vector3(min_x, 0.0, max_z),
		Vector3(min_x, y0, max_z),
		Vector3(min_x, y0, min_z),
		Vector3.LEFT
	)
#endregion


#region Low-Level Mesh & World-UV Geometry Helpers
func _create_mesh_buffers() -> Dictionary:
	return {
		"vertices": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"uvs": PackedVector2Array(),
		"indices": PackedInt32Array()
	}


func _commit_mesh_buffers(mb: Dictionary, mat: Material) -> ArrayMesh:
	var verts: PackedVector3Array = mb["vertices"]
	var arr_mesh := ArrayMesh.new()
	if verts.is_empty():
		return arr_mesh

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = mb["normals"]
	arrays[Mesh.ARRAY_TEX_UV] = mb["uvs"]
	arrays[Mesh.ARRAY_INDEX] = mb["indices"]

	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if mat:
		arr_mesh.surface_set_material(0, mat)
	return arr_mesh


func _append_box(mb: Dictionary, p_min: Vector3, p_max: Vector3) -> void:
	_add_quad(
		mb,
		Vector3(p_min.x, p_max.y, p_min.z),
		Vector3(p_max.x, p_max.y, p_min.z),
		Vector3(p_max.x, p_max.y, p_max.z),
		Vector3(p_min.x, p_max.y, p_max.z),
		Vector3.UP
	)
	_add_quad(
		mb,
		Vector3(p_min.x, p_min.y, p_max.z),
		Vector3(p_max.x, p_min.y, p_max.z),
		Vector3(p_max.x, p_min.y, p_min.z),
		Vector3(p_min.x, p_min.y, p_min.z),
		Vector3.DOWN
	)
	_add_quad(
		mb,
		Vector3(p_min.x, p_min.y, p_max.z),
		Vector3(p_max.x, p_min.y, p_max.z),
		Vector3(p_max.x, p_max.y, p_max.z),
		Vector3(p_min.x, p_max.y, p_max.z),
		Vector3.BACK
	)
	_add_quad(
		mb,
		Vector3(p_max.x, p_min.y, p_min.z),
		Vector3(p_min.x, p_min.y, p_min.z),
		Vector3(p_min.x, p_max.y, p_min.z),
		Vector3(p_max.x, p_max.y, p_min.z),
		Vector3.FORWARD
	)
	_add_quad(
		mb,
		Vector3(p_max.x, p_min.y, p_max.z),
		Vector3(p_max.x, p_min.y, p_min.z),
		Vector3(p_max.x, p_max.y, p_min.z),
		Vector3(p_max.x, p_max.y, p_max.z),
		Vector3.RIGHT
	)
	_add_quad(
		mb,
		Vector3(p_min.x, p_min.y, p_min.z),
		Vector3(p_min.x, p_min.y, p_max.z),
		Vector3(p_min.x, p_max.y, p_max.z),
		Vector3(p_min.x, p_max.y, p_min.z),
		Vector3.LEFT
	)


func _add_oriented_quad(mb: Dictionary, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, outward_hint: Vector3) -> void:
	var n: Vector3 = (v2 - v0).cross(v1 - v0).normalized()
	if n.dot(outward_hint) < 0.0:
		n = -n
	_add_quad(mb, v0, v1, v2, v3, n)


func _add_oriented_tri(mb: Dictionary, v0: Vector3, v1: Vector3, v2: Vector3, outward_hint: Vector3) -> void:
	var n: Vector3 = (v2 - v0).cross(v1 - v0).normalized()
	if n.dot(outward_hint) < 0.0:
		n = -n
	_add_tri(mb, v0, v1, v2, n)


func _add_quad(mb: Dictionary, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3) -> void:
	var verts: PackedVector3Array = mb["vertices"]
	var norms: PackedVector3Array = mb["normals"]
	var uvs: PackedVector2Array = mb["uvs"]
	var indices: PackedInt32Array = mb["indices"]

	var n: Vector3 = normal.normalized()
	var base_idx: int = verts.size()

	verts.append_array([v0, v1, v2, v3])
	norms.append_array([n, n, n, n])

	var axes: Array[Vector3] = _get_planar_uv_axes(n)
	var u_axis: Vector3 = axes[0]
	var v_axis: Vector3 = axes[1]

	uvs.append_array([
		Vector2(v0.dot(u_axis) * uv_scale.x, -v0.dot(v_axis) * uv_scale.y),
		Vector2(v1.dot(u_axis) * uv_scale.x, -v1.dot(v_axis) * uv_scale.y),
		Vector2(v2.dot(u_axis) * uv_scale.x, -v2.dot(v_axis) * uv_scale.y),
		Vector2(v3.dot(u_axis) * uv_scale.x, -v3.dot(v_axis) * uv_scale.y)
	])

	if ((v2 - v0).cross(v1 - v0)).dot(n) >= 0.0:
		indices.append_array([
			base_idx + 0, base_idx + 1, base_idx + 2,
			base_idx + 0, base_idx + 2, base_idx + 3
		])
	else:
		indices.append_array([
			base_idx + 0, base_idx + 2, base_idx + 1,
			base_idx + 0, base_idx + 3, base_idx + 2
		])


func _add_tri(mb: Dictionary, v0: Vector3, v1: Vector3, v2: Vector3, normal: Vector3) -> void:
	var verts: PackedVector3Array = mb["vertices"]
	var norms: PackedVector3Array = mb["normals"]
	var uvs: PackedVector2Array = mb["uvs"]
	var indices: PackedInt32Array = mb["indices"]

	var n: Vector3 = normal.normalized()
	var base_idx: int = verts.size()

	verts.append_array([v0, v1, v2])
	norms.append_array([n, n, n])

	var axes: Array[Vector3] = _get_planar_uv_axes(n)
	var u_axis: Vector3 = axes[0]
	var v_axis: Vector3 = axes[1]

	uvs.append_array([
		Vector2(v0.dot(u_axis) * uv_scale.x, -v0.dot(v_axis) * uv_scale.y),
		Vector2(v1.dot(u_axis) * uv_scale.x, -v1.dot(v_axis) * uv_scale.y),
		Vector2(v2.dot(u_axis) * uv_scale.x, -v2.dot(v_axis) * uv_scale.y)
	])

	if ((v2 - v0).cross(v1 - v0)).dot(n) >= 0.0:
		indices.append_array([base_idx + 0, base_idx + 1, base_idx + 2])
	else:
		indices.append_array([base_idx + 0, base_idx + 2, base_idx + 1])


func _get_planar_uv_axes(n: Vector3) -> Array[Vector3]:
	if absf(n.y) > 0.95:
		return [Vector3.RIGHT, Vector3.FORWARD]
	var u_axis: Vector3 = Vector3.UP.cross(n).normalized()
	if u_axis.length_squared() < 0.001:
		u_axis = Vector3.RIGHT
	var v_axis: Vector3 = n.cross(u_axis).normalized()
	return [u_axis, v_axis]
#endregion


#region Binary Resource Saving
func save_resources_to_disk() -> void:
	var edited_root: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	if not edited_root or edited_root.scene_file_path.is_empty():
		return

	var base_dir: String = edited_root.scene_file_path.get_base_dir()
	var scene_name: String = edited_root.scene_file_path.get_file().get_basename()
	var save_dir: String = "%s/%s_%s" % [base_dir, save_subfolder_name, scene_name]

	if not DirAccess.dir_exists_absolute(save_dir):
		DirAccess.make_dir_recursive_absolute(save_dir)

	var meshes_to_save: Array[Dictionary] = [
		{"prop": &"baked_foundation_mesh", "suffix": "Foundation", "mesh": baked_foundation_mesh},
		{"prop": &"baked_walls_mesh", "suffix": "Walls", "mesh": baked_walls_mesh},
		{"prop": &"baked_roof_mesh", "suffix": "Roof", "mesh": baked_roof_mesh}
	]

	for item: Dictionary in meshes_to_save:
		var m: ArrayMesh = item["mesh"]
		if m:
			var res_path: String = "%s/%s_%s_%d.res" % [save_dir, name, item["suffix"], seed_value]
			if ResourceSaver.save(m, res_path, ResourceSaver.FLAG_COMPRESS) == OK:
				m.take_over_path(res_path)
#endregion
