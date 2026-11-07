@tool
## Watabou-style procedural multi-room floorplan house generator with 3D procedural windows, interactive DoorComponent doors, and ramp stair colliders.
class_name ProceduralFloorplanHouse extends Node3D

enum FloorplanAlgorithm {
	SQUARE_DIVISION,
	SQUARE_RANDOM
}

enum RoofType {
	GABLE,
	HIP,
	FLAT,
	DUTCH,
	SHED,
	GAMBREL
}

enum WindowType {
	FIXED,
	PICTURE,
	COTTAGE,
	FRENCH_DOOR_WINDOW,
	GLASS_BLOCK,
	PALLADIAN,
	BAY,
	GARDEN,
	ROUND
}

enum DoorType {
	FLUSH,
	PANEL,
	FRENCH,
	DUTCH,
	BARN,
	LOUVERED,
	GLASS,
	GARAGE
}

const WALL_BIT_FRONT_POS_Z: int = 1
const WALL_BIT_BACK_NEG_Z: int = 2
const WALL_BIT_RIGHT_POS_X: int = 4
const WALL_BIT_LEFT_NEG_X: int = 8

@export_group("Generator Actions")
@export_tool_button("Generate Floorplan House (Keep Seed)", "MeshInstance3D") var btn_generate: Callable:
	get:
		return generate_house
@export_tool_button("Randomize Seed & Generate", "RandomNumberGenerator") var btn_randomize_seed: Callable:
	get:
		return randomize_seed_and_generate
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

@export_subgroup("Randomize All & Ranges")
@export_tool_button("Randomize Enabled Parameters & Generate", "Reload") var btn_randomize_all: Callable:
	get:
		return randomize_all_and_generate

@export var randomize_algorithm: bool = true
@export var randomize_building_width: bool = true
@export var random_building_width_range: Vector2 = Vector2(10.0, 18.0)

@export var randomize_building_depth: bool = true
@export var random_building_depth_range: Vector2 = Vector2(9.0, 16.0)

@export var randomize_room_count: bool = true
@export var random_room_count_bounds: Vector2i = Vector2i(3, 8)

@export var randomize_room_squareness: bool = true
@export var random_room_squareness_range: Vector2 = Vector2(0.35, 0.85)

@export var randomize_division_steps: bool = true
@export var random_division_steps_range: Vector2i = Vector2i(2, 4)

@export var randomize_division_chance: bool = true
@export var random_division_chance_range: Vector2 = Vector2(0.65, 0.95)

@export var randomize_floors: bool = true
@export var random_floors_range: Vector2i = Vector2i(1, 3)

@export var randomize_floor_height: bool = false
@export var random_floor_height_range: Vector2 = Vector2(2.6, 3.4)

@export var randomize_exterior_door_count: bool = true
@export var random_exterior_door_count_range: Vector2i = Vector2i(1, 2)

@export var randomize_exterior_door_type: bool = true
@export var randomize_double_doors: bool = true

@export var randomize_window_type: bool = true
@export var randomize_windows_per_floor: bool = true
@export var random_windows_per_floor_range: Vector2i = Vector2i(5, 12)

@export var randomize_frame_width_multiplier: bool = false
@export var random_frame_width_multiplier_range: Vector2 = Vector2(0.75, 1.35)

@export var randomize_roof_type: bool = true
@export var randomize_roof_angle: bool = true
@export var random_roof_angle_range: Vector2 = Vector2(22.0, 42.0)
@export var randomize_roof_rotation: bool = true

@export var randomize_overhangs: bool = true
@export var random_overhang_range: Vector2 = Vector2(0.25, 0.6)

@export var randomize_foundation_height: bool = true
@export var random_foundation_height_range: Vector2 = Vector2(0.3, 0.9)

@export_group("Floorplan Algorithm & Bounds")
@export var algorithm: FloorplanAlgorithm = FloorplanAlgorithm.SQUARE_DIVISION
@export var max_building_size: Vector2 = Vector2(14.0, 12.0)
@export var min_room_size: Vector2 = Vector2(3.5, 3.5)
@export var max_room_size: Vector2 = Vector2(6.5, 6.5)
@export var room_count_range: Vector2i = Vector2i(4, 7)
@export_range(0.0, 1.0, 0.05) var room_squareness: float = 0.65
@export_range(0.25, 1.0, 0.25) var grid_snap: float = 0.5

@export_subgroup("Square Division & Corridor Settings")
@export_range(1, 6, 1) var division_steps: int = 3
@export_range(0.1, 1.0, 0.05) var division_chance: float = 0.8
@export_range(1.2, 4.0, 0.1) var min_corridor_width: float = 1.5
@export_range(1.2, 5.0, 0.1) var corridor_width: float = 1.8

@export_group("Stories & Upper Floor Reduction")
@export_range(1, 6, 1) var floors: int = 2
@export_range(2.0, 6.0, 0.05) var floor_height: float = 2.8
@export_range(0.05, 0.6, 0.01) var wall_thickness: float = 0.2
@export var floor_room_retention_curve: Curve
@export_range(0.2, 1.0, 0.05) var default_upper_floor_retention: float = 0.7
@export var generate_floor_slabs: bool = true

@export_group("Doors & Windows")
@export var generate_door_nodes: bool = true
@export var exterior_door_type: DoorType = DoorType.PANEL
## Makes compatible exterior doors spawn as a pair of double doors instead of a single leaf
@export var double_doors: bool = false
@export_range(1, 8, 1) var exterior_door_rooms_count: int = 1
@export_flags("+Z (Front):1", "-Z (Back):2", "+X (Right):4", "-X (Left):8") var door_allowed_walls: int = 15
@export var door_size: Vector2 = Vector2(1.0, 2.1)
@export_range(0.0, 1.5, 0.01) var door_floor_offset: float = 0.0
@export_range(0.1, 2.0, 0.05) var door_animation_time: float = 0.5
## Extra width & depth added to each DoorComponent's Area3D collision shape so it is easy to click and detects NPCs
@export_range(0.05, 1.5, 0.05) var door_area_extra_margin: float = 0.3

@export_subgroup("Window Settings")
@export var generate_window_meshes: bool = true
@export var window_type: WindowType = WindowType.FIXED
@export_range(0.25, 3.0, 0.05) var frame_width_multiplier: float = 1.0
@export_flags("+Z (Front):1", "-Z (Back):2", "+X (Right):4", "-X (Left):8") var window_allowed_walls: int = 15
@export_range(0, 40, 1) var windows_per_floor: int = 8
@export var window_size: Vector2 = Vector2(0.85, 1.1)
@export_range(0.1, 4.0, 0.05) var window_floor_offset: float = 0.9
@export_range(0.0, 1.0, 0.05) var window_vertical_alignment_bias: float = 0.8
@export_range(0.0, 1.0, 0.05) var window_horizontal_variation: float = 0.12
@export_range(0.1, 4.0, 0.05) var min_opening_separation: float = 0.4
@export_range(0.1, 2.0, 0.05) var corner_margin: float = 0.35

@export_group("Roof Settings")
@export var roof_type: RoofType = RoofType.GABLE
@export_range(5.0, 70.0, 0.5) var roof_angle: float = 32.0
@export_range(0.05, 3.0, 0.02) var roof_height: float = 0.22
@export_range(0.1, 3.0, 0.05) var roof_peak_height_scale: float = 1.0
@export var rotate_roof_ridge_90: bool = false
## Places roof_type on the largest continuous block and builds Shed roofs on secondary wings that reach into the main roof's center at a lower height
@export var secondary_wings_use_shed_roof: bool = true

@export_subgroup("Roof Overhangs")
@export_range(0.0, 3.0, 0.05) var overhang_front: float = 0.4
@export_range(0.0, 3.0, 0.05) var overhang_back: float = 0.4
@export_range(0.0, 3.0, 0.05) var overhang_left: float = 0.4
@export_range(0.0, 3.0, 0.05) var overhang_right: float = 0.4

@export_group("Foundation & Steps")
@export_range(0.05, 4.0, 0.05) var foundation_height: float = 0.6
@export_range(0.05, 1.0, 0.01) var max_step_height: float = 0.18
@export_range(0.1, 1.5, 0.01) var step_depth: float = 0.28
@export_range(0.0, 2.0, 0.05) var step_extra_width: float = 0.2

@export_group("Materials & UVs")
@export var foundation_material: Material
@export var walls_material: Material
@export var roof_material: Material
## Material applied to window frames, door frames, and solid door bodies
@export var accent_material: Material
## Material applied to window glass panes and door windows
@export var window_material: Material
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
@export var baked_windows_mesh: ArrayMesh:
	set(value):
		baked_windows_mesh = value
		if is_inside_tree():
			_sync_child_meshes()
@export var baked_foundation_col: ConcavePolygonShape3D
@export var baked_walls_col: ConcavePolygonShape3D
@export var baked_roof_col: ConcavePolygonShape3D
@export var baked_windows_col: ConcavePolygonShape3D

var _roof_occlusion_boxes: Array[AABB] = []
var _is_rebuilding: bool = false


func _ready() -> void:
	var w_inst := get_node_or_null("WallsMesh") as MeshInstance3D
	if w_inst and w_inst.mesh != null:
		return
	if baked_foundation_mesh or baked_walls_mesh or baked_roof_mesh or baked_windows_mesh:
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

	if randomize_algorithm:
		algorithm = FloorplanAlgorithm.SQUARE_DIVISION if rng.randf() < 0.5 else FloorplanAlgorithm.SQUARE_RANDOM

	if randomize_building_width:
		max_building_size.x = snappedf(rng.randf_range(random_building_width_range.x, random_building_width_range.y), 0.5)
	if randomize_building_depth:
		max_building_size.y = snappedf(rng.randf_range(random_building_depth_range.x, random_building_depth_range.y), 0.5)

	if randomize_room_count:
		var low_b: int = mini(random_room_count_bounds.x, random_room_count_bounds.y)
		var high_b: int = maxi(random_room_count_bounds.x, random_room_count_bounds.y)
		var min_r: int = rng.randi_range(low_b, maxi(low_b, high_b - 2))
		var max_r: int = rng.randi_range(min_r + 1, maxi(min_r + 1, high_b))
		room_count_range = Vector2i(min_r, max_r)

	if randomize_room_squareness:
		room_squareness = snappedf(rng.randf_range(random_room_squareness_range.x, random_room_squareness_range.y), 0.05)

	if randomize_division_steps:
		division_steps = rng.randi_range(
			mini(random_division_steps_range.x, random_division_steps_range.y),
			maxi(random_division_steps_range.x, random_division_steps_range.y)
		)

	if randomize_division_chance:
		division_chance = snappedf(rng.randf_range(random_division_chance_range.x, random_division_chance_range.y), 0.05)

	if randomize_floors:
		floors = rng.randi_range(
			mini(random_floors_range.x, random_floors_range.y),
			maxi(random_floors_range.x, random_floors_range.y)
		)

	if randomize_floor_height:
		floor_height = snappedf(rng.randf_range(random_floor_height_range.x, random_floor_height_range.y), 0.05)

	if randomize_exterior_door_count:
		exterior_door_rooms_count = rng.randi_range(
			mini(random_exterior_door_count_range.x, random_exterior_door_count_range.y),
			maxi(random_exterior_door_count_range.x, random_exterior_door_count_range.y)
		)

	if randomize_exterior_door_type:
		exterior_door_type = rng.randi_range(0, DoorType.size() - 1) as DoorType

	if randomize_double_doors:
		double_doors = (rng.randf() < 0.35) and (exterior_door_type != DoorType.GARAGE)

	if randomize_window_type:
		window_type = rng.randi_range(0, WindowType.size() - 1) as WindowType

	if randomize_windows_per_floor:
		windows_per_floor = rng.randi_range(
			mini(random_windows_per_floor_range.x, random_windows_per_floor_range.y),
			maxi(random_windows_per_floor_range.x, random_windows_per_floor_range.y)
		)

	if randomize_frame_width_multiplier:
		frame_width_multiplier = snappedf(
			rng.randf_range(random_frame_width_multiplier_range.x, random_frame_width_multiplier_range.y),
			0.05
		)

	if randomize_roof_type:
		roof_type = rng.randi_range(0, RoofType.size() - 1) as RoofType

	if randomize_roof_angle:
		roof_angle = snappedf(rng.randf_range(random_roof_angle_range.x, random_roof_angle_range.y), 0.5)

	if randomize_roof_rotation:
		rotate_roof_ridge_90 = rng.randf() < 0.5

	if randomize_overhangs:
		var ovh: float = snappedf(rng.randf_range(random_overhang_range.x, random_overhang_range.y), 0.05)
		overhang_front = ovh
		overhang_back = ovh
		overhang_left = ovh
		overhang_right = ovh

	if randomize_foundation_height:
		foundation_height = snappedf(rng.randf_range(random_foundation_height_range.x, random_foundation_height_range.y), 0.05)

	auto_regenerate = prev_auto
	generate_house()


func clear_house() -> void:
	_is_rebuilding = true
	baked_foundation_mesh = null
	baked_walls_mesh = null
	baked_roof_mesh = null
	baked_windows_mesh = null
	baked_foundation_col = null
	baked_walls_col = null
	baked_roof_col = null
	baked_windows_col = null
	_is_rebuilding = false
	for child_name: String in ["FoundationMesh", "WallsMesh", "RoofMesh", "WindowsMesh", "DoorsContainer", "HouseStaticBody3D"]:
		var node := get_node_or_null(child_name)
		if node:
			node.free()
	notify_property_list_changed()


func _to_typed_dict_array(raw_arr: Variant) -> Array[Dictionary]:
	var typed: Array[Dictionary] = []
	if raw_arr is Array:
		for item: Variant in raw_arr:
			if item is Dictionary:
				typed.append(item)
	return typed


func generate_house() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# 1. Generate Ground Floorplan & Prune Connected Upper Stories
	var ground_rooms: Array[Dictionary] = (
		_generate_floorplan_square_division(rng)
		if algorithm == FloorplanAlgorithm.SQUARE_DIVISION
		else _generate_floorplan_square_random(rng)
	)
	if ground_rooms.is_empty():
		return

	_recenter_rooms(ground_rooms)

	var floors_rooms: Array[Array] = []
	floors_rooms.append(ground_rooms)

	if floor_room_retention_curve:
		floor_room_retention_curve.bake()

	for f_idx: int in range(1, floors):
		var prev_rooms: Array[Dictionary] = _to_typed_dict_array(floors_rooms[f_idx - 1])
		var norm_f: float = float(f_idx) / float(maxi(floors - 1, 1))
		var retention_ratio: float = (
			clampf(floor_room_retention_curve.sample_baked(norm_f), 0.15, 1.0)
			if floor_room_retention_curve
			else pow(default_upper_floor_retention, float(f_idx))
		)
		var target_count: int = clampi(int(roundf(float(ground_rooms.size()) * retention_ratio)), 1, prev_rooms.size())
		var upper_rooms: Array[Dictionary] = _prune_rooms_for_upper_floor(rng, prev_rooms, target_count)
		floors_rooms.append(upper_rooms)

	var foundation_mb: Dictionary = _create_mesh_buffers()
	var foundation_col_mb: Dictionary = _create_mesh_buffers()
	var walls_mb: Dictionary = _create_mesh_buffers()
	var roof_mb: Dictionary = _create_mesh_buffers()
	var win_accent_mb: Dictionary = _create_mesh_buffers()
	var win_glass_mb: Dictionary = _create_mesh_buffers()
	var win_col_mb: Dictionary = _create_mesh_buffers()

	# 2. Build All Story Roofs FIRST so we record _roof_occlusion_boxes before placing any windows!
	_roof_occlusion_boxes.clear()
	_build_all_story_roofs(roof_mb, walls_mb, floors_rooms)

	# 3. Decompose Wall Segments, Place Doors, and Place Windows Last
	var placed_exterior_windows_by_floor: Array[Array] = []
	var ground_exterior_doors: Array[Dictionary] = []
	var all_doors_to_spawn: Array[Dictionary] = []

	for f_idx: int in range(floors):
		var current_rooms: Array[Dictionary] = _to_typed_dict_array(floors_rooms[f_idx])
		var next_rooms: Array[Dictionary] = (
			_to_typed_dict_array(floors_rooms[f_idx + 1])
			if (f_idx + 1 < floors)
			else _to_typed_dict_array([])
		)

		var floor_plan_data: Dictionary = _analyze_floor_topology_and_openings(
			rng,
			f_idx,
			current_rooms,
			ground_rooms,
			placed_exterior_windows_by_floor
		)
		var placed_wins: Array[Dictionary] = _to_typed_dict_array(floor_plan_data["placed_windows"])
		placed_exterior_windows_by_floor.append(placed_wins)

		if f_idx == 0:
			ground_exterior_doors = _to_typed_dict_array(floor_plan_data["exterior_doors"])

		var segs: Array[Dictionary] = _to_typed_dict_array(floor_plan_data["segments"])
		_append_floor_walls_and_slabs(
			walls_mb,
			foundation_mb,
			foundation_col_mb,
			win_accent_mb,
			win_glass_mb,
			win_col_mb,
			all_doors_to_spawn,
			f_idx,
			current_rooms,
			next_rooms,
			segs
		)

	# 4. Build Foundation (Stepped Visual Mesh + Smooth Ramp Collision Mesh)
	_build_multi_room_foundation(foundation_mb, foundation_col_mb, ground_rooms, ground_exterior_doors)

	_is_rebuilding = true
	baked_foundation_mesh = _commit_mesh_buffers(foundation_mb, foundation_material)
	baked_walls_mesh = _commit_mesh_buffers(walls_mb, walls_material)
	baked_roof_mesh = _commit_mesh_buffers(roof_mb, roof_material)
	baked_windows_mesh = _commit_two_surface_mesh(win_accent_mb, accent_material, win_glass_mb, window_material)

	# 5. Bake & Store Concave Trimesh Colliders
	if generate_colliders:
		var f_col_mesh: ArrayMesh = _commit_mesh_buffers(foundation_col_mb, null)
		var w_col_mesh: ArrayMesh = _commit_mesh_buffers(win_col_mb, null)
		baked_foundation_col = f_col_mesh.create_trimesh_shape() if (f_col_mesh and f_col_mesh.get_surface_count() > 0) else null
		baked_walls_col = baked_walls_mesh.create_trimesh_shape() if (baked_walls_mesh and baked_walls_mesh.get_surface_count() > 0) else null
		baked_roof_col = baked_roof_mesh.create_trimesh_shape() if (baked_roof_mesh and baked_roof_mesh.get_surface_count() > 0) else null
		baked_windows_col = w_col_mesh.create_trimesh_shape() if (w_col_mesh and w_col_mesh.get_surface_count() > 0) else null
	else:
		baked_foundation_col = null
		baked_walls_col = null
		baked_roof_col = null
		baked_windows_col = null
	_is_rebuilding = false

	_sync_child_meshes()
	_rebuild_door_components(all_doors_to_spawn)

	if auto_save_to_disk and Engine.is_editor_hint():
		save_resources_to_disk()

	notify_property_list_changed()


#region Child Node, DoorComponent & Collider Synchronization
func _sync_child_meshes() -> void:
	if _is_rebuilding:
		return

	var scene_owner: Node = _get_scene_owner()

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
	r_inst.position = Vector3(0.0, foundation_height, 0.0)
	r_inst.mesh = baked_roof_mesh
	if roof_material and baked_roof_mesh and baked_roof_mesh.get_surface_count() > 0:
		baked_roof_mesh.surface_set_material(0, roof_material)

	var win_inst: MeshInstance3D = _get_or_create_mesh_child("WindowsMesh", scene_owner)
	win_inst.position = Vector3(0.0, foundation_height, 0.0)
	win_inst.mesh = baked_windows_mesh

	_sync_colliders(scene_owner)


func _get_scene_owner() -> Node:
	if Engine.is_editor_hint() and is_inside_tree():
		var edited_root: Node = get_tree().edited_scene_root
		if edited_root == self or (edited_root and edited_root.is_ancestor_of(self)):
			return edited_root
	return owner


func _get_or_create_mesh_child(node_name: String, scene_owner: Node) -> MeshInstance3D:
	var inst := get_node_or_null(node_name) as MeshInstance3D
	if not is_instance_valid(inst):
		inst = MeshInstance3D.new()
		inst.name = node_name
		add_child(inst)
	if scene_owner:
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

	if scene_owner:
		body.owner = scene_owner

	var parts: Array[Dictionary] = [
		{"name": "FoundationCol", "shape": baked_foundation_col, "y": 0.0},
		{"name": "WallsCol", "shape": baked_walls_col, "y": foundation_height},
		{"name": "RoofCol", "shape": baked_roof_col, "y": foundation_height},
		{"name": "WindowsCol", "shape": baked_windows_col, "y": foundation_height}
	]

	for part: Dictionary in parts:
		var col_name: String = part["name"]
		var shp: Shape3D = part["shape"]
		var col_node := body.get_node_or_null(col_name) as CollisionShape3D
		if not shp:
			if is_instance_valid(col_node):
				col_node.free()
			continue

		if not is_instance_valid(col_node):
			col_node = CollisionShape3D.new()
			col_node.name = col_name
			body.add_child(col_node)

		col_node.position = Vector3(0.0, float(part["y"]), 0.0)
		col_node.shape = shp
		if scene_owner:
			col_node.owner = scene_owner
#endregion


#region Step 1A: Floorplan Algorithm 1 — Square Division (BSP + Minimum-Width Corridor)
func _generate_floorplan_square_division(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var snap: float = maxf(grid_snap, 0.25)
	var min_w: float = maxf(snappedf(min_room_size.x, snap), 2.5)
	var min_d: float = maxf(snappedf(min_room_size.y, snap), 2.5)

	var eff_corr_w: float = maxf(corridor_width, min_corridor_width)
	eff_corr_w = maxf(snappedf(eff_corr_w, snap), maxf(door_size.x + 0.4, 1.2))

	var total_w: float = maxf(snappedf(max_building_size.x, snap), min_w * 2.0 + eff_corr_w)
	var total_d: float = maxf(snappedf(max_building_size.y, snap), min_d * 2.0 + eff_corr_w)

	if room_squareness > 0.5:
		var avg_dim: float = snappedf((total_w + total_d) * 0.5, snap)
		total_w = snappedf(lerpf(total_w, avg_dim, (room_squareness - 0.5) * 0.6), snap)
		total_d = snappedf(lerpf(total_d, avg_dim, (room_squareness - 0.5) * 0.6), snap)

	var target_max_rooms: int = maxi(room_count_range.x, room_count_range.y)
	var rects: Array[Rect2] = [Rect2(-total_w * 0.5, -total_d * 0.5, total_w, total_d)]

	var first_split_horizontal: bool = (total_d >= total_w)
	var first_split_coord: float = 0.0
	var recorded_first_split: bool = false

	for step: int in range(division_steps):
		var next_rects: Array[Rect2] = []
		for r: Rect2 in rects:
			if rects.size() + next_rects.size() >= target_max_rooms:
				next_rects.append(r)
				continue
			if step > 0 and rng.randf() > division_chance:
				next_rects.append(r)
				continue

			var can_split_x: bool = (r.size.x >= min_w * 2.0)
			var can_split_z: bool = (r.size.y >= min_d * 2.0)
			if not can_split_x and not can_split_z:
				next_rects.append(r)
				continue

			var split_along_x: bool = true
			if can_split_x and can_split_z:
				var ratio_xz: float = r.size.x / maxf(r.size.y, 0.1)
				if ratio_xz > 1.15:
					split_along_x = true
				elif ratio_xz < 0.85:
					split_along_x = false
				else:
					split_along_x = (rng.randf() < 0.5)
			elif can_split_x:
				split_along_x = true
			else:
				split_along_x = false

			if split_along_x:
				var low_x: float = min_w
				var high_x: float = r.size.x - min_w
				var mid_x: float = r.size.x * 0.5
				var raw_split: float = lerpf(rng.randf_range(low_x, high_x), mid_x, room_squareness * 0.5)
				var split_w: float = clampf(snappedf(raw_split, snap), low_x, high_x)

				var r_left := Rect2(r.position.x, r.position.y, split_w, r.size.y)
				var r_right := Rect2(r.position.x + split_w, r.position.y, r.size.x - split_w, r.size.y)
				next_rects.append(r_left)
				next_rects.append(r_right)

				if not recorded_first_split:
					recorded_first_split = true
					first_split_horizontal = false
					first_split_coord = r.position.x + split_w
			else:
				var low_z: float = min_d
				var high_z: float = r.size.y - min_d
				var mid_z: float = r.size.y * 0.5
				var raw_split: float = lerpf(rng.randf_range(low_z, high_z), mid_z, room_squareness * 0.5)
				var split_d: float = clampf(snappedf(raw_split, snap), low_z, high_z)

				var r_top := Rect2(r.position.x, r.position.y, r.size.x, split_d)
				var r_bot := Rect2(r.position.x, r.position.y + split_d, r.size.x, r.size.y - split_d)
				next_rects.append(r_top)
				next_rects.append(r_bot)

				if not recorded_first_split:
					recorded_first_split = true
					first_split_horizontal = true
					first_split_coord = r.position.y + split_d

		rects = next_rects

	var corr_rect := Rect2()
	var has_corridor: bool = false

	if recorded_first_split and rects.size() >= 3:
		var half_c: float = eff_corr_w * 0.5
		if first_split_horizontal:
			var c_y: float = clampf(snappedf(first_split_coord - half_c, snap), -total_d * 0.5 + min_d, total_d * 0.5 - min_d - eff_corr_w)
			corr_rect = Rect2(-total_w * 0.5, c_y, total_w, eff_corr_w)
		else:
			var c_x: float = clampf(snappedf(first_split_coord - half_c, snap), -total_w * 0.5 + min_w, total_w * 0.5 - min_w - eff_corr_w)
			corr_rect = Rect2(c_x, -total_d * 0.5, eff_corr_w, total_d)

		var trimmed_rects: Array[Rect2] = []
		var valid_trim: bool = true
		for r: Rect2 in rects:
			var clipped: Array[Rect2] = _subtract_rect_2d(r, corr_rect)
			for cr: Rect2 in clipped:
				if cr.size.x < min_corridor_width or cr.size.y < min_corridor_width:
					valid_trim = false
				trimmed_rects.append(cr)

		if valid_trim and not trimmed_rects.is_empty():
			rects = trimmed_rects
			has_corridor = true

	var rooms: Array[Dictionary] = []
	var largest_idx: int = 0
	var largest_area: float = -1.0

	for i: int in range(rects.size()):
		var area: float = rects[i].get_area()
		if area > largest_area:
			largest_area = area
			largest_idx = i
		rooms.append({
			"id": i,
			"rect": rects[i],
			"is_corridor": false,
			"is_main": false
		})

	if not rooms.is_empty():
		rooms[largest_idx]["is_main"] = true

	if has_corridor:
		rooms.append({
			"id": rooms.size(),
			"rect": corr_rect,
			"is_corridor": true,
			"is_main": false
		})

	return rooms
#endregion


#region Step 1B: Floorplan Algorithm 2 — Square Random
func _generate_floorplan_square_random(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var snap: float = maxf(grid_snap, 0.25)
	var min_w: float = maxf(snappedf(min_room_size.x, snap), maxf(min_corridor_width, 2.5))
	var min_d: float = maxf(snappedf(min_room_size.y, snap), maxf(min_corridor_width, 2.5))
	var max_w: float = maxf(snappedf(max_room_size.x, snap), min_w + snap)
	var max_d: float = maxf(snappedf(max_room_size.y, snap), min_d + snap)

	var bound_w: float = maxf(snappedf(max_building_size.x, snap), max_w)
	var bound_d: float = maxf(snappedf(max_building_size.y, snap), max_d)
	var bounds := Rect2(-bound_w * 0.5, -bound_d * 0.5, bound_w, bound_d)

	var min_target: int = maxi(2, mini(room_count_range.x, room_count_range.y))
	var max_target: int = maxi(min_target, maxi(room_count_range.x, room_count_range.y))
	var target_rooms: int = rng.randi_range(min_target, max_target)

	var placed_rects: Array[Rect2] = []
	var has_corridor_spine: bool = (target_rooms >= 3)

	if has_corridor_spine:
		var eff_corr_w: float = maxf(snappedf(maxf(corridor_width, min_corridor_width), snap), 1.5)
		var horiz_spine: bool = (rng.randf() < 0.5)
		var spine_len: float = snappedf(rng.randf_range(min_w * 1.5, maxf(bound_w * 0.65, min_w * 1.6)), snap)
		var c_rect: Rect2
		if horiz_spine:
			c_rect = Rect2(snappedf(-spine_len * 0.5, snap), snappedf(-eff_corr_w * 0.5, snap), spine_len, eff_corr_w)
		else:
			c_rect = Rect2(snappedf(-eff_corr_w * 0.5, snap), snappedf(-spine_len * 0.5, snap), eff_corr_w, spine_len)
		placed_rects.append(c_rect)
	else:
		var w0: float = _sample_room_dim(rng, min_w, minf(max_w, bound_w), snap)
		var d0: float = _sample_room_dim_squared(rng, w0, min_d, minf(max_d, bound_d), snap)
		placed_rects.append(Rect2(snappedf(-w0 * 0.5, snap), snappedf(-d0 * 0.5, snap), w0, d0))

	var max_attempts: int = target_rooms * 50
	var attempts: int = 0
	var total_goal: int = target_rooms + (1 if has_corridor_spine else 0)

	while placed_rects.size() < total_goal and attempts < max_attempts:
		attempts += 1
		var anchor_idx: int = 0 if (has_corridor_spine and rng.randf() < 0.65) else (rng.randi() % placed_rects.size())
		var anchor: Rect2 = placed_rects[anchor_idx]

		var rw: float = _sample_room_dim(rng, min_w, max_w, snap)
		var rd: float = _sample_room_dim_squared(rng, rw, min_d, max_d, snap)

		var side: int = rng.randi_range(0, 3)
		var align_end_corner: bool = (rng.randf() < 0.5)

		var cand_pos := Vector2.ZERO
		match side:
			0:
				cand_pos.y = anchor.end.y
				cand_pos.x = (anchor.end.x - rw) if align_end_corner else anchor.position.x
			1:
				cand_pos.y = anchor.position.y - rd
				cand_pos.x = (anchor.end.x - rw) if align_end_corner else anchor.position.x
			2:
				cand_pos.x = anchor.end.x
				cand_pos.y = (anchor.end.y - rd) if align_end_corner else anchor.position.y
			3:
				cand_pos.x = anchor.position.x - rw
				cand_pos.y = (anchor.end.y - rd) if align_end_corner else anchor.position.y

		var cand_rect := Rect2(snappedf(cand_pos.x, snap), snappedf(cand_pos.y, snap), rw, rd)

		if not bounds.encloses(cand_rect):
			continue

		var overlaps: bool = false
		for existing: Rect2 in placed_rects:
			var inter: Rect2 = cand_rect.intersection(existing)
			if inter.size.x > 0.01 and inter.size.y > 0.01:
				overlaps = true
				break

		if not overlaps:
			placed_rects.append(cand_rect)

	var rooms: Array[Dictionary] = []
	var largest_idx: int = -1
	var largest_area: float = -1.0

	for i: int in range(placed_rects.size()):
		var is_corr: bool = (has_corridor_spine and i == 0 and placed_rects.size() > 1)
		var area: float = placed_rects[i].get_area()
		if not is_corr and area > largest_area:
			largest_area = area
			largest_idx = i
		rooms.append({
			"id": i,
			"rect": placed_rects[i],
			"is_corridor": is_corr,
			"is_main": false
		})

	if largest_idx != -1:
		rooms[largest_idx]["is_main"] = true
	elif not rooms.is_empty():
		rooms[0]["is_main"] = true

	return rooms


func _sample_room_dim(rng: RandomNumberGenerator, min_v: float, max_v: float, snap: float) -> float:
	if max_v <= min_v:
		return min_v
	return clampf(snappedf(rng.randf_range(min_v, max_v), snap), min_v, max_v)


func _sample_room_dim_squared(rng: RandomNumberGenerator, ref_dim: float, min_v: float, max_v: float, snap: float) -> float:
	var rand_dim: float = _sample_room_dim(rng, min_v, max_v, snap)
	var blended: float = lerpf(rand_dim, clampf(ref_dim, min_v, max_v), room_squareness)
	return clampf(snappedf(blended, snap), min_v, max_v)


func _subtract_rect_2d(subject: Rect2, clipper: Rect2) -> Array[Rect2]:
	var inter: Rect2 = subject.intersection(clipper)
	if inter.size.x <= 0.01 or inter.size.y <= 0.01:
		return [subject]

	var result: Array[Rect2] = []
	if inter.position.y - subject.position.y > 0.01:
		result.append(Rect2(subject.position.x, subject.position.y, subject.size.x, inter.position.y - subject.position.y))
	if subject.end.y - inter.end.y > 0.01:
		result.append(Rect2(subject.position.x, inter.end.y, subject.size.x, subject.end.y - inter.end.y))
	if inter.position.x - subject.position.x > 0.01:
		result.append(Rect2(subject.position.x, inter.position.y, inter.position.x - subject.position.x, inter.size.y))
	if subject.end.x - inter.end.x > 0.01:
		result.append(Rect2(inter.end.x, inter.position.y, subject.end.x - inter.end.x, inter.size.y))

	return result


func _recenter_rooms(rooms: Array[Dictionary]) -> void:
	if rooms.is_empty():
		return
	var combined: Rect2 = rooms[0]["rect"]
	for i: int in range(1, rooms.size()):
		combined = combined.merge(rooms[i]["rect"] as Rect2)
	var center_offset: Vector2 = combined.get_center()
	var snap: float = maxf(grid_snap, 0.25)
	center_offset = Vector2(snappedf(center_offset.x, snap), snappedf(center_offset.y, snap))

	for i: int in range(rooms.size()):
		var r: Rect2 = rooms[i]["rect"]
		r.position -= center_offset
		rooms[i]["rect"] = r
#endregion


#region Step 2: Upper-Floor Connected Room Pruning
func _prune_rooms_for_upper_floor(
	rng: RandomNumberGenerator,
	prev_rooms: Array[Dictionary],
	target_count: int
) -> Array[Dictionary]:
	var current: Array[Dictionary] = []
	for rm: Dictionary in prev_rooms:
		var cloned_rm: Dictionary = rm.duplicate(true)
		var r: Rect2 = rm["rect"]
		cloned_rm["rect"] = Rect2(r.position.x, r.position.y, r.size.x, r.size.y)
		current.append(cloned_rm)

	var main_center := Vector2.ZERO
	for rm: Dictionary in current:
		if bool(rm["is_main"]):
			main_center = (rm["rect"] as Rect2).get_center()
			break

	while current.size() > target_count and current.size() > 1:
		var adj: Dictionary = _build_room_adjacency_graph(current)
		var best_remove_idx: int = -1
		var best_dist: float = -1.0

		for idx: int in range(current.size()):
			var rm: Dictionary = current[idx]
			if bool(rm["is_main"]) or bool(rm["is_corridor"]):
				continue
			var r_id: int = int(rm["id"])
			var neighbors: Array = adj.get(r_id, [])
			var dist: float = (rm["rect"] as Rect2).get_center().distance_to(main_center) + rng.randf_range(0.0, 0.5)
			if neighbors.size() <= 1:
				dist += 100.0
			if dist > best_dist:
				best_dist = dist
				best_remove_idx = idx

		if best_remove_idx == -1:
			break
		current.remove_at(best_remove_idx)

	for i: int in range(current.size()):
		current[i]["id"] = i

	return current


func _build_room_adjacency_graph(rooms: Array[Dictionary]) -> Dictionary:
	var adj: Dictionary = {}
	var min_door_span: float = maxf(door_size.x + 0.15, 0.8)

	for i: int in range(rooms.size()):
		adj[int(rooms[i]["id"])] = []

	for i: int in range(rooms.size()):
		var r1: Rect2 = rooms[i]["rect"]
		var id1: int = int(rooms[i]["id"])
		for j: int in range(i + 1, rooms.size()):
			var r2: Rect2 = rooms[j]["rect"]
			var id2: int = int(rooms[j]["id"])
			if _shared_boundary_length(r1, r2) >= min_door_span:
				(adj[id1] as Array).append(id2)
				(adj[id2] as Array).append(id1)

	return adj


func _shared_boundary_length(r1: Rect2, r2: Rect2) -> float:
	if absf(r1.end.x - r2.position.x) < 0.02 or absf(r2.end.x - r1.position.x) < 0.02:
		var overlap_z: float = minf(r1.end.y, r2.end.y) - maxf(r1.position.y, r2.position.y)
		if overlap_z > 0.0:
			return overlap_z
	if absf(r1.end.y - r2.position.y) < 0.02 or absf(r2.end.y - r1.position.y) < 0.02:
		var overlap_x: float = minf(r1.end.x, r2.end.x) - maxf(r1.position.x, r2.position.x)
		if overlap_x > 0.0:
			return overlap_x
	return 0.0
#endregion


#region Step 3: Atomic Edge Decomposition, Corridor Spanning Tree & Opening Placement
func _analyze_floor_topology_and_openings(
	rng: RandomNumberGenerator,
	f_idx: int,
	rooms: Array[Dictionary],
	ground_rooms: Array[Dictionary],
	placed_exterior_windows_by_floor: Array[Array]
) -> Dictionary:
	var x_coords: Array[float] = []
	var z_coords: Array[float] = []
	for rm: Dictionary in rooms:
		var r: Rect2 = rm["rect"]
		_add_unique_coord(x_coords, r.position.x)
		_add_unique_coord(x_coords, r.end.x)
		_add_unique_coord(z_coords, r.position.y)
		_add_unique_coord(z_coords, r.end.y)
	x_coords.sort()
	z_coords.sort()

	var segments: Array[Dictionary] = []

	for z_val: float in z_coords:
		for ix: int in range(x_coords.size() - 1):
			var x0: float = x_coords[ix]
			var x1: float = x_coords[ix + 1]
			var mid_x: float = (x0 + x1) * 0.5
			if x1 - x0 < 0.05:
				continue

			var room_neg_z: int = _find_room_containing_point(rooms, Vector2(mid_x, z_val - 0.05))
			var room_pos_z: int = _find_room_containing_point(rooms, Vector2(mid_x, z_val + 0.05))

			if room_neg_z == -1 and room_pos_z == -1:
				continue
			if room_neg_z != -1 and room_pos_z != -1 and room_neg_z == room_pos_z:
				continue

			var is_interior: bool = (room_neg_z != -1 and room_pos_z != -1)
			var normal_vec := Vector3.BACK
			var start_pt := Vector3(x0, 0.0, z_val)
			var right_vec := Vector3.RIGHT
			var wall_bit: int = WALL_BIT_FRONT_POS_Z

			if not is_interior:
				if room_neg_z != -1:
					normal_vec = Vector3.BACK
					start_pt = Vector3(x0, 0.0, z_val)
					right_vec = Vector3.RIGHT
					wall_bit = WALL_BIT_FRONT_POS_Z
				else:
					normal_vec = Vector3.FORWARD
					start_pt = Vector3(x1, 0.0, z_val)
					right_vec = Vector3.LEFT
					wall_bit = WALL_BIT_BACK_NEG_Z

			segments.append({
				"is_interior": is_interior,
				"room_a": room_neg_z if room_neg_z != -1 else room_pos_z,
				"room_b": room_pos_z if is_interior else -1,
				"start": start_pt,
				"right": right_vec,
				"length": x1 - x0,
				"normal": normal_vec,
				"wall_bit": wall_bit,
				"openings": []
			})

	for x_val: float in x_coords:
		for iz: int in range(z_coords.size() - 1):
			var z0: float = z_coords[iz]
			var z1: float = z_coords[iz + 1]
			var mid_z: float = (z0 + z1) * 0.5
			if z1 - z0 < 0.05:
				continue

			var room_neg_x: int = _find_room_containing_point(rooms, Vector2(x_val - 0.05, mid_z))
			var room_pos_x: int = _find_room_containing_point(rooms, Vector2(x_val + 0.05, mid_z))

			if room_neg_x == -1 and room_pos_x == -1:
				continue
			if room_neg_x != -1 and room_pos_x != -1 and room_neg_x == room_pos_x:
				continue

			var is_interior: bool = (room_neg_x != -1 and room_pos_x != -1)
			var normal_vec := Vector3.RIGHT
			var start_pt := Vector3(x_val, 0.0, z1)
			var right_vec := Vector3.FORWARD
			var wall_bit: int = WALL_BIT_RIGHT_POS_X

			if not is_interior:
				if room_neg_x != -1:
					normal_vec = Vector3.RIGHT
					start_pt = Vector3(x_val, 0.0, z1)
					right_vec = Vector3.FORWARD
					wall_bit = WALL_BIT_RIGHT_POS_X
				else:
					normal_vec = Vector3.LEFT
					start_pt = Vector3(x_val, 0.0, z0)
					right_vec = Vector3.BACK
					wall_bit = WALL_BIT_LEFT_NEG_X

			segments.append({
				"is_interior": is_interior,
				"room_a": room_neg_x if room_neg_x != -1 else room_pos_x,
				"room_b": room_pos_x if is_interior else -1,
				"start": start_pt,
				"right": right_vec,
				"length": z1 - z0,
				"normal": normal_vec,
				"wall_bit": wall_bit,
				"openings": []
			})

	segments = _merge_collinear_segments(segments)

	if f_idx == 0 or generate_floor_slabs:
		_place_interior_doors_on_segments(rooms, segments)

	var exterior_doors: Array[Dictionary] = []
	if f_idx == 0 and exterior_door_rooms_count > 0:
		exterior_doors = _place_exterior_doors_on_segments(rng, rooms, segments)

	var placed_windows: Array[Dictionary] = _place_exterior_windows_on_segments(
		rng,
		f_idx,
		segments,
		rooms,
		ground_rooms,
		placed_exterior_windows_by_floor
	)

	return {
		"segments": segments,
		"exterior_doors": exterior_doors,
		"placed_windows": placed_windows
	}


func _merge_collinear_segments(raw_segments: Array[Dictionary]) -> Array[Dictionary]:
	var merged: Array[Dictionary] = []
	var used := PackedByteArray()
	used.resize(raw_segments.size())
	used.fill(0)

	for i: int in range(raw_segments.size()):
		if used[i] == 1:
			continue
		var cur: Dictionary = raw_segments[i].duplicate(true)
		used[i] = 1

		var changed: bool = true
		while changed:
			changed = false
			var cur_end: Vector3 = (cur["start"] as Vector3) + (cur["right"] as Vector3) * float(cur["length"])
			for j: int in range(raw_segments.size()):
				if used[j] == 1:
					continue
				var other: Dictionary = raw_segments[j]
				if bool(cur["is_interior"]) != bool(other["is_interior"]):
					continue
				if int(cur["room_a"]) != int(other["room_a"]) or int(cur["room_b"]) != int(other["room_b"]):
					continue
				if (cur["normal"] as Vector3).distance_to(other["normal"] as Vector3) > 0.01:
					continue
				if (cur["right"] as Vector3).distance_to(other["right"] as Vector3) > 0.01:
					continue

				var other_start: Vector3 = other["start"]
				var other_end: Vector3 = other_start + (other["right"] as Vector3) * float(other["length"])

				if cur_end.distance_to(other_start) < 0.02:
					cur["length"] = float(cur["length"]) + float(other["length"])
					used[j] = 1
					changed = true
				elif other_end.distance_to(cur["start"] as Vector3) < 0.02:
					cur["start"] = other_start
					cur["length"] = float(cur["length"]) + float(other["length"])
					used[j] = 1
					changed = true

		merged.append(cur)

	return merged


func _place_interior_doors_on_segments(rooms: Array[Dictionary], segments: Array[Dictionary]) -> void:
	if rooms.size() <= 1:
		return

	var d_width: float = clampf(door_size.x, 0.4, 4.0)
	var d_height: float = clampf(door_size.y, 0.5, floor_height - 0.1)
	var d_v0: float = clampf(door_floor_offset, 0.0, floor_height - d_height)
	var d_v1: float = d_v0 + d_height

	var pair_to_seg_idx: Dictionary = {}
	for s_idx: int in range(segments.size()):
		var seg: Dictionary = segments[s_idx]
		if not bool(seg["is_interior"]):
			continue
		if float(seg["length"]) < d_width + 0.25:
			continue

		var ra: int = int(seg["room_a"])
		var rb: int = int(seg["room_b"])
		var pair_key: String = "%d_%d" % [mini(ra, rb), maxi(ra, rb)]

		if not pair_to_seg_idx.has(pair_key):
			pair_to_seg_idx[pair_key] = s_idx
		else:
			var prev_idx: int = int(pair_to_seg_idx[pair_key])
			if float(seg["length"]) > float(segments[prev_idx]["length"]):
				pair_to_seg_idx[pair_key] = s_idx

	var main_id: int = 0
	var corridor_id: int = -1
	for rm: Dictionary in rooms:
		if bool(rm["is_main"]):
			main_id = int(rm["id"])
		if bool(rm["is_corridor"]):
			corridor_id = int(rm["id"])

	var connected_ids: Array[int] = [main_id]
	var selected_seg_indices: Array[int] = []

	if corridor_id != -1 and corridor_id != main_id:
		var mc_key: String = "%d_%d" % [mini(main_id, corridor_id), maxi(main_id, corridor_id)]
		if pair_to_seg_idx.has(mc_key):
			selected_seg_indices.append(int(pair_to_seg_idx[mc_key]))
			connected_ids.append(corridor_id)

	if corridor_id != -1 and connected_ids.has(corridor_id):
		for rm: Dictionary in rooms:
			var rid: int = int(rm["id"])
			if connected_ids.has(rid):
				continue
			var c_key: String = "%d_%d" % [mini(rid, corridor_id), maxi(rid, corridor_id)]
			if pair_to_seg_idx.has(c_key):
				selected_seg_indices.append(int(pair_to_seg_idx[c_key]))
				connected_ids.append(rid)

	var made_progress: bool = true
	while connected_ids.size() < rooms.size() and made_progress:
		made_progress = false
		for rm: Dictionary in rooms:
			var rid: int = int(rm["id"])
			if connected_ids.has(rid):
				continue
			for conn_id: int in connected_ids:
				var p_key: String = "%d_%d" % [mini(rid, conn_id), maxi(rid, conn_id)]
				if pair_to_seg_idx.has(p_key):
					selected_seg_indices.append(int(pair_to_seg_idx[p_key]))
					connected_ids.append(rid)
					made_progress = true
					break
			if made_progress:
				break

	for s_idx: int in selected_seg_indices:
		var seg: Dictionary = segments[s_idx]
		var s_len: float = float(seg["length"])
		var eff_d_w: float = minf(d_width, s_len - 0.2)
		var u0: float = (s_len - eff_d_w) * 0.5
		(seg["openings"] as Array).append({
			"u0": u0,
			"u1": u0 + eff_d_w,
			"center": s_len * 0.5,
			"v0": d_v0,
			"v1": d_v1,
			"is_door": true,
			"is_interior": true,
			"door_type": DoorType.FLUSH,
			"is_double": false
		})


func _is_door_type_double_compatible(d_type: DoorType) -> bool:
	return d_type != DoorType.GARAGE


func _place_exterior_doors_on_segments(
	rng: RandomNumberGenerator,
	rooms: Array[Dictionary],
	segments: Array[Dictionary]
) -> Array[Dictionary]:
	var placed_doors: Array[Dictionary] = []
	var base_d_width: float = clampf(door_size.x, 0.4, 6.0)
	var d_height: float = clampf(door_size.y, 0.5, floor_height - 0.1)
	var d_v0: float = clampf(door_floor_offset, 0.0, floor_height - d_height)
	var d_v1: float = d_v0 + d_height
	var eff_margin: float = minf(maxf(corner_margin, wall_thickness), 0.35)
	var active_door_mask: int = door_allowed_walls if door_allowed_walls != 0 else 15

	var wants_wide_opening: bool = (exterior_door_type == DoorType.GARAGE) or (double_doors and _is_door_type_double_compatible(exterior_door_type))
	var preferred_width: float = (base_d_width * 2.0) if wants_wide_opening else base_d_width

	var room_order: Array[int] = []
	var other_rooms: Array[int] = []
	for rm: Dictionary in rooms:
		var rid: int = int(rm["id"])
		if bool(rm["is_main"]):
			room_order.push_front(rid)
		elif not bool(rm["is_corridor"]):
			other_rooms.append(rid)
	_shuffle_array_seeded(rng, other_rooms)
	room_order.append_array(other_rooms)

	var rooms_with_doors: int = 0
	for rid: int in room_order:
		if rooms_with_doors >= exterior_door_rooms_count:
			break

		var candidate_segs: Array[int] = []
		for s_idx: int in range(segments.size()):
			var seg: Dictionary = segments[s_idx]
			if bool(seg["is_interior"]) or int(seg["room_a"]) != rid:
				continue
			if (active_door_mask & int(seg["wall_bit"])) == 0:
				continue
			if float(seg["length"]) >= preferred_width + 2.0 * eff_margin:
				candidate_segs.append(s_idx)

		# Fallback to single-door width if no wall is wide enough for double/garage width
		if candidate_segs.is_empty():
			for s_idx: int in range(segments.size()):
				var seg: Dictionary = segments[s_idx]
				if bool(seg["is_interior"]) or int(seg["room_a"]) != rid:
					continue
				if (active_door_mask & int(seg["wall_bit"])) == 0:
					continue
				if float(seg["length"]) >= base_d_width + 2.0 * eff_margin:
					candidate_segs.append(s_idx)

		if candidate_segs.is_empty() and rooms_with_doors == 0:
			for s_idx: int in range(segments.size()):
				var seg: Dictionary = segments[s_idx]
				if not bool(seg["is_interior"]) and int(seg["room_a"]) == rid and float(seg["length"]) >= base_d_width + 0.25:
					candidate_segs.append(s_idx)

		if candidate_segs.is_empty():
			continue

		var chosen_s_idx: int = candidate_segs[rng.randi() % candidate_segs.size()]
		var chosen_seg: Dictionary = segments[chosen_s_idx]
		var s_len: float = float(chosen_seg["length"])

		var actual_d_width: float = base_d_width
		var use_double_here: bool = false
		if wants_wide_opening and s_len >= preferred_width + 0.3:
			actual_d_width = preferred_width
			use_double_here = double_doors and _is_door_type_double_compatible(exterior_door_type)
		elif double_doors and _is_door_type_double_compatible(exterior_door_type) and s_len >= base_d_width * 1.5 + 0.3:
			actual_d_width = minf(preferred_width, s_len - 2.0 * eff_margin)
			use_double_here = true

		var safe_margin: float = minf(eff_margin, maxf((s_len - actual_d_width) * 0.45, 0.05))
		var min_u0: float = safe_margin
		var max_u0: float = maxf(s_len - safe_margin - actual_d_width, min_u0)
		var u0: float = lerpf(rng.randf_range(min_u0, max_u0), (s_len - actual_d_width) * 0.5, 0.5)

		var door_record: Dictionary = {
			"u0": u0,
			"u1": u0 + actual_d_width,
			"center": u0 + actual_d_width * 0.5,
			"v0": d_v0,
			"v1": d_v1,
			"is_door": true,
			"is_interior": false,
			"door_type": exterior_door_type,
			"is_double": use_double_here,
			"seg_start": chosen_seg["start"],
			"seg_right": chosen_seg["right"],
			"seg_normal": chosen_seg["normal"],
			"wall_bit": chosen_seg["wall_bit"]
		}
		(chosen_seg["openings"] as Array).append(door_record)
		placed_doors.append(door_record)
		rooms_with_doors += 1

	return placed_doors


func _place_exterior_windows_on_segments(
	rng: RandomNumberGenerator,
	f_idx: int,
	segments: Array[Dictionary],
	current_rooms: Array[Dictionary],
	ground_rooms: Array[Dictionary],
	placed_exterior_windows_by_floor: Array[Array]
) -> Array[Dictionary]:
	var placed_windows: Array[Dictionary] = []
	if windows_per_floor <= 0:
		return placed_windows

	var active_win_mask: int = window_allowed_walls if window_allowed_walls != 0 else 15
	var w_width: float = clampf(window_size.x, 0.2, 8.0)
	var w_height: float = clampf(window_size.y, 0.2, floor_height - 0.1)
	var w_v0: float = clampf(window_floor_offset, 0.05, floor_height - w_height - 0.05)
	var w_v1: float = w_v0 + w_height

	var y_floor_base: float = float(f_idx) * floor_height
	var win_world_y0: float = y_floor_base + w_v0
	var win_world_y1: float = y_floor_base + w_v1

	var window_candidates: Array[Dictionary] = []

	for s_idx: int in range(segments.size()):
		var seg: Dictionary = segments[s_idx]
		# Strictly never place windows on interior wall segments
		if bool(seg["is_interior"]):
			continue
		if (active_win_mask & int(seg["wall_bit"])) == 0:
			continue

		var s_len: float = float(seg["length"])
		var eff_margin: float = minf(maxf(corner_margin, wall_thickness), maxf((s_len - w_width) * 0.25, 0.12))
		var eff_sep: float = minf(min_opening_separation, maxf((s_len - w_width) * 0.2, 0.15))

		if s_len < w_width + 2.0 * eff_margin:
			continue

		var existing_openings: Array = seg["openings"]
		existing_openings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["u0"]) < float(b["u0"]))

		var free_spans: Array[Vector2] = []
		var cursor: float = eff_margin
		for d_open: Dictionary in existing_openings:
			var span_end: float = float(d_open["u0"]) - eff_sep
			if span_end - cursor >= w_width:
				free_spans.append(Vector2(cursor, span_end))
			cursor = float(d_open["u1"]) + eff_sep

		var final_end: float = s_len - eff_margin
		if final_end - cursor >= w_width:
			free_spans.append(Vector2(cursor, final_end))

		var seg_start: Vector3 = seg["start"]
		var seg_right: Vector3 = seg["right"]
		var seg_normal: Vector3 = seg["normal"]

		for span: Vector2 in free_spans:
			var span_len: float = span.y - span.x
			var max_win: int = maxi(int(floorf((span_len + eff_sep) / (w_width + eff_sep))), 1)
			var step_gap: float = maxf((span_len - float(max_win) * w_width) / float(max_win + 1), 0.0)
			var max_jitter: float = minf(step_gap * 0.45, w_width * 0.35) * window_horizontal_variation

			for k: int in range(max_win):
				var base_u0: float = span.x + step_gap * float(k + 1) + w_width * float(k)
				var jitter: float = rng.randf_range(-max_jitter, max_jitter)
				var u0: float = clampf(base_u0 + jitter, span.x, maxf(span.y - w_width, span.x))
				var u1: float = u0 + w_width
				var center_u: float = u0 + w_width * 0.5
				var world_xz: Vector3 = seg_start + seg_right * center_u

				# Prevent any window whose outward side is inside a room on the current floor,
				# or inside the ground floor footprint when floor slabs are disabled!
				var outside_check_pt := Vector2(
					world_xz.x + seg_normal.x * (wall_thickness + 0.15),
					world_xz.z + seg_normal.z * (wall_thickness + 0.15)
				)
				if _find_room_containing_point(current_rooms, outside_check_pt) != -1:
					continue
				if not generate_floor_slabs and _find_room_containing_point(ground_rooms, outside_check_pt) != -1:
					continue

				# Skip any window slot that is covered by a lower-story roof!
				if _is_window_blocked_by_roof(seg_start, seg_right, seg_normal, u0, u1, win_world_y0, win_world_y1):
					continue

				var weight: float = _compute_world_window_vertical_weight(
					world_xz,
					seg_normal,
					w_width,
					f_idx,
					placed_exterior_windows_by_floor
				)

				window_candidates.append({
					"seg_idx": s_idx,
					"u0": u0,
					"u1": u1,
					"center": center_u,
					"v0": w_v0,
					"v1": w_v1,
					"is_door": false,
					"is_interior": false,
					"window_type": window_type,
					"world_xz": world_xz,
					"normal": seg_normal,
					"weight": weight,
					"eff_sep": eff_sep
				})

	var win_to_pick: int = mini(windows_per_floor, window_candidates.size())
	for _w_i: int in range(win_to_pick):
		if window_candidates.is_empty():
			break
		var picked_idx: int = _pick_weighted_candidate_index(rng, window_candidates)
		var w_open: Dictionary = window_candidates[picked_idx]
		window_candidates.remove_at(picked_idx)

		var s_idx: int = int(w_open["seg_idx"])
		var sep: float = float(w_open.get("eff_sep", min_opening_separation))
		(segments[s_idx]["openings"] as Array).append(w_open)
		placed_windows.append(w_open)

		for c_idx: int in range(window_candidates.size() - 1, -1, -1):
			var cand: Dictionary = window_candidates[c_idx]
			if int(cand["seg_idx"]) == s_idx:
				if float(cand["u0"]) < float(w_open["u1"]) + sep and float(cand["u1"]) > float(w_open["u0"]) - sep:
					window_candidates.remove_at(c_idx)

	for seg: Dictionary in segments:
		(seg["openings"] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["u0"]) < float(b["u0"]))

	return placed_windows


func _is_window_blocked_by_roof(
	seg_start: Vector3,
	seg_right: Vector3,
	seg_normal: Vector3,
	u0: float,
	u1: float,
	win_y0: float,
	win_y1: float
) -> bool:
	var p0: Vector3 = seg_start + seg_right * u0 + seg_normal * 0.2
	var p1: Vector3 = seg_start + seg_right * u1 + seg_normal * 0.2
	var min_pt := Vector3(minf(p0.x, p1.x) - 0.15, win_y0 - 0.12, minf(p0.z, p1.z) - 0.15)
	var max_pt := Vector3(maxf(p0.x, p1.x) + 0.15, win_y1 + 0.12, maxf(p0.z, p1.z) + 0.15)
	var win_box := AABB(min_pt, max_pt - min_pt)

	for roof_box: AABB in _roof_occlusion_boxes:
		if win_box.intersects(roof_box):
			return true
	return false


func _compute_world_window_vertical_weight(
	world_xz: Vector3,
	normal: Vector3,
	w_width: float,
	current_floor: int,
	placed_exterior_windows_by_floor: Array[Array]
) -> float:
	if current_floor <= 0 or window_vertical_alignment_bias <= 0.001:
		return 1.0

	var best_alignment: float = 0.0
	var search_radius: float = maxf(w_width * 1.5, 0.6)

	for check_f: int in range(current_floor - 1, -1, -1):
		var below_windows: Array = placed_exterior_windows_by_floor[check_f]
		var floor_decay: float = 1.0 if (check_f == current_floor - 1) else 0.75
		for bw_var: Variant in below_windows:
			if not (bw_var is Dictionary):
				continue
			var bw: Dictionary = bw_var
			if normal.dot(bw["normal"] as Vector3) < 0.9:
				continue
			var dist_xz: float = Vector2(world_xz.x - (bw["world_xz"] as Vector3).x, world_xz.z - (bw["world_xz"] as Vector3).z).length()
			if dist_xz < search_radius:
				var match_strength: float = 1.0 - (dist_xz / search_radius)
				best_alignment = maxf(best_alignment, match_strength * floor_decay)

	return 1.0 + best_alignment * best_alignment * window_vertical_alignment_bias * 15.0


func _find_room_containing_point(rooms: Array[Dictionary], pt: Vector2) -> int:
	for rm: Dictionary in rooms:
		var r: Rect2 = rm["rect"]
		if pt.x >= r.position.x and pt.x <= r.end.x and pt.y >= r.position.y and pt.y <= r.end.y:
			return int(rm["id"])
	return -1


func _add_unique_coord(arr: Array[float], val: float) -> void:
	for existing: float in arr:
		if absf(existing - val) < 0.01:
			return
	arr.append(val)


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


#region Step 4: Foundation, 2x Interior Walls, Foundation-Textured Floor Slabs & Roof Solver
func _build_multi_room_foundation(
	visual_mb: Dictionary,
	col_mb: Dictionary,
	ground_rooms: Array[Dictionary],
	ground_exterior_doors: Array[Dictionary]
) -> void:
	var foundation_rects: Array[Rect2] = []
	for rm: Dictionary in ground_rooms:
		var r: Rect2 = rm["rect"]
		var expanded := Rect2(
			r.position.x - overhang_left,
			r.position.y - overhang_back,
			r.size.x + overhang_left + overhang_right,
			r.size.y + overhang_back + overhang_front
		)
		foundation_rects.append(expanded)

	foundation_rects = _coalesce_rectangles_2d(foundation_rects)

	for fr: Rect2 in foundation_rects:
		var p_min := Vector3(fr.position.x, 0.0, fr.position.y)
		var p_max := Vector3(fr.end.x, foundation_height, fr.end.y)
		_append_box(visual_mb, p_min, p_max)
		_append_box(col_mb, p_min, p_max)

	if foundation_height > 0.01 and not ground_exterior_doors.is_empty():
		var step_count: int = maxi(int(ceilf(foundation_height / maxf(max_step_height, 0.02))), 1)
		var actual_step_h: float = foundation_height / float(step_count)
		var total_run: float = float(step_count) * step_depth

		for d_open: Dictionary in ground_exterior_doors:
			var w_start: Vector3 = d_open["seg_start"]
			var w_right: Vector3 = d_open["seg_right"]
			var w_normal: Vector3 = d_open["seg_normal"]
			var w_bit: int = int(d_open["wall_bit"])

			var w_overhang: float = overhang_front
			if w_bit == WALL_BIT_BACK_NEG_Z:
				w_overhang = overhang_back
			elif w_bit == WALL_BIT_RIGHT_POS_X:
				w_overhang = overhang_right
			elif w_bit == WALL_BIT_LEFT_NEG_X:
				w_overhang = overhang_left

			var u0: float = float(d_open["u0"]) - step_extra_width
			var u1: float = float(d_open["u1"]) + step_extra_width
			var foundation_edge_origin: Vector3 = w_start + w_normal * w_overhang

			# 1. Visual Mesh: Individual Stepped Stairs
			for s_idx: int in range(step_count):
				var top_y: float = foundation_height - float(s_idx) * actual_step_h
				var d0: float = float(s_idx) * step_depth
				var d1: float = float(s_idx + 1) * step_depth

				var p_fl: Vector3 = foundation_edge_origin + w_right * u0 + w_normal * d1
				var p_fr: Vector3 = foundation_edge_origin + w_right * u1 + w_normal * d1
				var p_bl: Vector3 = foundation_edge_origin + w_right * u0 + w_normal * d0
				var p_br: Vector3 = foundation_edge_origin + w_right * u1 + w_normal * d0

				_add_quad(
					visual_mb,
					Vector3(p_bl.x, top_y, p_bl.z),
					Vector3(p_br.x, top_y, p_br.z),
					Vector3(p_fr.x, top_y, p_fr.z),
					Vector3(p_fl.x, top_y, p_fl.z),
					Vector3.UP
				)
				var bot_y: float = top_y - actual_step_h
				_add_quad(
					visual_mb,
					Vector3(p_fl.x, bot_y, p_fl.z),
					Vector3(p_fr.x, bot_y, p_fr.z),
					Vector3(p_fr.x, top_y, p_fr.z),
					Vector3(p_fl.x, top_y, p_fl.z),
					w_normal
				)
				_add_quad(
					visual_mb,
					Vector3(p_bl.x, 0.0, p_bl.z),
					Vector3(p_fl.x, 0.0, p_fl.z),
					Vector3(p_fl.x, top_y, p_fl.z),
					Vector3(p_bl.x, top_y, p_bl.z),
					-w_right
				)
				_add_quad(
					visual_mb,
					Vector3(p_fr.x, 0.0, p_fr.z),
					Vector3(p_br.x, 0.0, p_br.z),
					Vector3(p_br.x, top_y, p_br.z),
					Vector3(p_fr.x, top_y, p_fr.z),
					w_right
				)

			# 2. Collision Mesh: Smooth NavMesh-Friendly Wedge Ramp Following the Stair Envelope
			var r_back_l: Vector3 = foundation_edge_origin + w_right * u0
			var r_back_r: Vector3 = foundation_edge_origin + w_right * u1
			var r_front_l: Vector3 = r_back_l + w_normal * total_run
			var r_front_r: Vector3 = r_back_r + w_normal * total_run

			var top_back_l := Vector3(r_back_l.x, foundation_height, r_back_l.z)
			var top_back_r := Vector3(r_back_r.x, foundation_height, r_back_r.z)
			var bot_back_l := Vector3(r_back_l.x, 0.0, r_back_l.z)
			var bot_back_r := Vector3(r_back_r.x, 0.0, r_back_r.z)
			var bot_front_l := Vector3(r_front_l.x, 0.0, r_front_l.z)
			var bot_front_r := Vector3(r_front_r.x, 0.0, r_front_r.z)

			var ramp_normal: Vector3 = (Vector3.UP * total_run + w_normal * foundation_height).normalized()
			_add_oriented_quad(col_mb, top_back_l, top_back_r, bot_front_r, bot_front_l, ramp_normal)
			_add_oriented_quad(col_mb, bot_front_l, bot_front_r, bot_back_r, bot_back_l, Vector3.DOWN)
			_add_oriented_tri(col_mb, bot_back_l, bot_front_l, top_back_l, -w_right)
			_add_oriented_tri(col_mb, bot_front_r, bot_back_r, top_back_r, w_right)


func _append_floor_walls_and_slabs(
	walls_mb: Dictionary,
	foundation_mb: Dictionary,
	foundation_col_mb: Dictionary,
	win_accent_mb: Dictionary,
	win_glass_mb: Dictionary,
	win_col_mb: Dictionary,
	all_doors_to_spawn: Array[Dictionary],
	f_idx: int,
	rooms: Array[Dictionary],
	_next_floor_rooms: Array[Dictionary],
	segments: Array[Dictionary]
) -> void:
	var y_base: float = float(f_idx) * floor_height
	var ext_t: float = clampf(wall_thickness, 0.04, 0.6)
	# Interior walls are twice as wide (2 * ext_t) as exterior walls so there are never corner/T-junction gaps!
	var int_t: float = ext_t * 2.0

	for seg: Dictionary in segments:
		var is_interior: bool = bool(seg["is_interior"])
		var s_start: Vector3 = (seg["start"] as Vector3) + Vector3(0.0, y_base, 0.0)
		var s_right: Vector3 = seg["right"]
		var s_normal: Vector3 = seg["normal"]
		var s_len: float = float(seg["length"])
		var openings: Array = seg["openings"]

		var active_t: float = int_t if is_interior else ext_t
		var wall_front_start: Vector3 = (s_start + s_normal * ext_t) if is_interior else s_start

		_append_wall_with_openings(
			walls_mb,
			wall_front_start,
			s_right,
			s_normal,
			s_len,
			floor_height,
			active_t,
			openings
		)

		for open_data: Dictionary in openings:
			var u0: float = float(open_data["u0"])
			var u1: float = float(open_data["u1"])
			var v0: float = float(open_data["v0"])
			var v1: float = float(open_data["v1"])
			var open_origin: Vector3 = wall_front_start + s_right * u0 + Vector3(0.0, v0, 0.0)
			var open_w: float = u1 - u0
			var open_h: float = v1 - v0

			if bool(open_data.get("is_door", false)):
				if generate_door_nodes:
					var d_type: DoorType = int(open_data.get("door_type", DoorType.FLUSH)) as DoorType
					var is_dbl: bool = bool(open_data.get("is_double", false))
					# Build stationary outer door frame into win_accent_mb
					var frame_t: float = clampf(0.055 * frame_width_multiplier, 0.02, minf(open_w, open_h) * 0.15)
					_append_door_outer_frame(
						win_accent_mb,
						open_origin,
						s_right,
						s_normal,
						open_w,
						open_h,
						active_t,
						frame_t,
						d_type
					)
					all_doors_to_spawn.append({
						"origin_walls_space": open_origin,
						"right": s_right,
						"normal": s_normal,
						"width": open_w,
						"height": open_h,
						"wall_t": active_t,
						"frame_t": frame_t,
						"door_type": d_type,
						"is_double": is_dbl,
						"is_interior": is_interior
					})
			else:
				if generate_window_meshes and not is_interior:
					var w_type: WindowType = int(open_data.get("window_type", window_type)) as WindowType
					_append_window_mesh(
						win_accent_mb,
						win_glass_mb,
						win_col_mb,
						open_origin,
						s_right,
						s_normal,
						open_w,
						open_h,
						ext_t,
						w_type
					)

	# Floor slabs are added to foundation_mb & foundation_col_mb (offset by foundation_height) so they share foundation_material!
	if generate_floor_slabs:
		var y_top_foundation_space: float = foundation_height + float(f_idx + 1) * floor_height
		var slab_rects: Array[Rect2] = []
		for rm: Dictionary in rooms:
			slab_rects.append(rm["rect"] as Rect2)
		slab_rects = _coalesce_rectangles_2d(slab_rects)
		var inset: float = ext_t
		for sr: Rect2 in slab_rects:
			if sr.size.x > inset * 2.0 and sr.size.y > inset * 2.0:
				var p_min := Vector3(sr.position.x + inset, y_top_foundation_space - ext_t * 0.4, sr.position.y + inset)
				var p_max := Vector3(sr.end.x - inset, y_top_foundation_space - 0.01, sr.end.y - inset)
				_append_box(foundation_mb, p_min, p_max)
				_append_box(foundation_col_mb, p_min, p_max)


func _build_all_story_roofs(roof_mb: Dictionary, walls_mb: Dictionary, floors_rooms: Array[Array]) -> void:
	var t: float = clampf(wall_thickness, 0.04, 0.6)

	for f_idx: int in range(floors_rooms.size() - 1, -1, -1):
		var cur_rooms: Array[Dictionary] = _to_typed_dict_array(floors_rooms[f_idx])
		if cur_rooms.is_empty():
			continue

		var is_top_floor: bool = (f_idx == floors_rooms.size() - 1)
		var above_rooms: Array[Dictionary] = (
			_to_typed_dict_array([])
			if is_top_floor
			else _to_typed_dict_array(floors_rooms[f_idx + 1])
		)

		var y_eave: float = float(f_idx + 1) * floor_height

		if is_top_floor:
			var story_wings: Array[Rect2] = _extract_macro_footprint_wings(cur_rooms)
			_build_story_roof_wings(roof_mb, walls_mb, story_wings, [], y_eave, t, true)
		else:
			var above_wings: Array[Rect2] = _extract_macro_footprint_wings(above_rooms)
			var exposed_pieces: Array[Rect2] = []
			for rm: Dictionary in cur_rooms:
				exposed_pieces.append(rm["rect"] as Rect2)

			for aw: Rect2 in above_wings:
				var next_pieces: Array[Rect2] = []
				for piece: Rect2 in exposed_pieces:
					next_pieces.append_array(_subtract_rect_2d(piece, aw))
				exposed_pieces = next_pieces

			var valid_exposed: Array[Rect2] = []
			for piece: Rect2 in exposed_pieces:
				if piece.size.x >= 0.75 and piece.size.y >= 0.75:
					valid_exposed.append(piece)

			valid_exposed = _coalesce_rectangles_2d(valid_exposed)
			_build_story_roof_wings(roof_mb, walls_mb, valid_exposed, above_wings, y_eave, t, false)


func _extract_macro_footprint_wings(rooms: Array[Dictionary]) -> Array[Rect2]:
	if rooms.is_empty():
		return []

	var raw_rects: Array[Rect2] = []
	for rm: Dictionary in rooms:
		raw_rects.append(rm["rect"] as Rect2)

	var merged: Array[Rect2] = _coalesce_rectangles_2d(raw_rects)
	if merged.size() <= 1:
		return merged

	var total_bounds: Rect2 = merged[0]
	for i: int in range(1, merged.size()):
		total_bounds = total_bounds.merge(merged[i])

	var total_room_area: float = 0.0
	for r: Rect2 in raw_rects:
		total_room_area += r.get_area()

	if total_room_area >= total_bounds.get_area() * 0.92:
		return [total_bounds]

	var x_set: Array[float] = []
	var z_set: Array[float] = []
	for r: Rect2 in merged:
		_add_unique_coord(x_set, r.position.x)
		_add_unique_coord(x_set, r.end.x)
		_add_unique_coord(z_set, r.position.y)
		_add_unique_coord(z_set, r.end.y)
	x_set.sort()
	z_set.sort()

	var cols: int = x_set.size() - 1
	var rows: int = z_set.size() - 1
	var grid: Array[bool] = []
	grid.resize(cols * rows)
	grid.fill(false)

	for r_idx: int in range(rows):
		var mid_z: float = (z_set[r_idx] + z_set[r_idx + 1]) * 0.5
		for c_idx: int in range(cols):
			var mid_x: float = (x_set[c_idx] + x_set[c_idx + 1]) * 0.5
			if _find_room_containing_point(rooms, Vector2(mid_x, mid_z)) != -1:
				grid[c_idx + r_idx * cols] = true

	var macro_wings: Array[Rect2] = []
	while true:
		var best_area: float = -1.0
		var best_rect := Rect2()
		var best_coords := Vector4i(-1, -1, -1, -1)

		for r0: int in range(rows):
			for c0: int in range(cols):
				if not grid[c0 + r0 * cols]:
					continue
				for r1: int in range(r0, rows):
					for c1: int in range(c0, cols):
						if _is_grid_rect_filled(grid, cols, c0, r0, c1, r1):
							var cand := Rect2(
								x_set[c0],
								z_set[r0],
								x_set[c1 + 1] - x_set[c0],
								z_set[r1 + 1] - z_set[r0]
							)
							var area: float = cand.get_area()
							if area > best_area:
								best_area = area
								best_rect = cand
								best_coords = Vector4i(c0, r0, c1, r1)

		if best_area <= 0.0:
			break

		macro_wings.append(best_rect)
		for rr: int in range(best_coords.y, best_coords.w + 1):
			for cc: int in range(best_coords.x, best_coords.z + 1):
				grid[cc + rr * cols] = false

	return _coalesce_rectangles_2d(macro_wings)


func _is_grid_rect_filled(grid: Array[bool], cols: int, c0: int, r0: int, c1: int, r1: int) -> bool:
	for rr: int in range(r0, r1 + 1):
		var row_off: int = rr * cols
		for cc: int in range(c0, c1 + 1):
			if not grid[row_off + cc]:
				return false
	return true


func _build_story_roof_wings(
	roof_mb: Dictionary,
	walls_mb: Dictionary,
	wings: Array[Rect2],
	above_wings: Array[Rect2],
	y_eave: float,
	wall_t: float,
	is_top_floor: bool
) -> void:
	if wings.is_empty():
		return

	wings.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.get_area() > b.get_area())

	var slope_tan: float = tan(deg_to_rad(clampf(roof_angle, 2.0, 80.0))) * roof_peak_height_scale

	var primary: Rect2 = wings[0]
	var primary_ridge_x: bool = (primary.size.x >= primary.size.y)
	if rotate_roof_ridge_90:
		primary_ridge_x = not primary_ridge_x

	var primary_span: float = primary.size.y if primary_ridge_x else primary.size.x
	var primary_rise: float = (primary_span * 0.5) * slope_tan
	if roof_type == RoofType.SHED:
		primary_rise = primary_span * slope_tan

	var ref_box: Rect2 = primary if is_top_floor else (above_wings[0] if not above_wings.is_empty() else primary)

	for w_idx: int in range(wings.size()):
		var raw_wing: Rect2 = wings[w_idx]
		var wing := Rect2(raw_wing.position.x, raw_wing.position.y, raw_wing.size.x, raw_wing.size.y)

		var ext_min_x: float = overhang_left
		var ext_max_x: float = overhang_right
		var ext_min_z: float = overhang_back
		var ext_max_z: float = overhang_front

		var is_primary_top: bool = (is_top_floor and w_idx == 0)

		if is_primary_top:
			_append_wing_roof_and_gable_walls(
				roof_mb, walls_mb, wing, y_eave, wall_t, primary_ridge_x,
				ext_min_x, ext_max_x, ext_min_z, ext_max_z,
				roof_type, 0, primary_rise, false
			)
			continue

		var target_box: Rect2 = ref_box
		if is_top_floor:
			for p_i: int in range(w_idx):
				if _rects_touch(wing, wings[p_i]):
					target_box = wings[p_i]
					break
		else:
			for aw: Rect2 in above_wings:
				if _rects_touch(wing, aw):
					target_box = aw
					break

		var target_center: Vector2 = target_box.get_center()
		var high_dir: int = 0

		if absf(wing.position.x - target_box.end.x) < 0.12:
			high_dir = 2
			ext_min_x = 0.0
		elif absf(wing.end.x - target_box.position.x) < 0.12:
			high_dir = 1
			ext_max_x = 0.0
		elif absf(wing.position.y - target_box.end.y) < 0.12:
			high_dir = 4
			ext_min_z = 0.0
		elif absf(wing.end.y - target_box.position.y) < 0.12:
			high_dir = 3
			ext_max_z = 0.0
		else:
			high_dir = _pick_shed_high_edge_toward_point(wing, target_center)

		var max_sec_rise: float = (
			maxf(primary_rise - roof_height * 1.1, 0.25)
			if is_top_floor
			else (floor_height * 0.55)
		)

		var chosen_type: RoofType = roof_type
		var wing_ridge_x: bool = (wing.size.x >= wing.size.y)

		if (secondary_wings_use_shed_roof or not is_top_floor) and roof_type != RoofType.FLAT:
			chosen_type = RoofType.SHED
			wing_ridge_x = (high_dir == 3 or high_dir == 4)
		else:
			wing_ridge_x = (high_dir == 1 or high_dir == 2)

		_append_wing_roof_and_gable_walls(
			roof_mb, walls_mb, wing, y_eave, wall_t, wing_ridge_x,
			ext_min_x, ext_max_x, ext_min_z, ext_max_z,
			chosen_type, high_dir, max_sec_rise, not is_top_floor
		)


func _rects_touch(a: Rect2, b: Rect2) -> bool:
	if (absf(a.position.x - b.end.x) < 0.12 or absf(a.end.x - b.position.x) < 0.12) and _intervals_overlap(a.position.y, a.end.y, b.position.y, b.end.y):
		return true
	if (absf(a.position.y - b.end.y) < 0.12 or absf(a.end.y - b.position.y) < 0.12) and _intervals_overlap(a.position.x, a.end.x, b.position.x, b.end.x):
		return true
	return false


func _pick_shed_high_edge_toward_point(wing: Rect2, ref_center: Vector2) -> int:
	var w_center: Vector2 = wing.get_center()
	var delta: Vector2 = ref_center - w_center
	if absf(delta.x) >= absf(delta.y):
		return 1 if delta.x >= 0.0 else 2
	else:
		return 3 if delta.y >= 0.0 else 4


func _append_wing_roof_and_gable_walls(
	roof_mb: Dictionary,
	walls_mb: Dictionary,
	wing: Rect2,
	y_eave: float,
	wall_t: float,
	ridge_along_x: bool,
	ext_min_x: float,
	ext_max_x: float,
	ext_min_z: float,
	ext_max_z: float,
	active_roof_type: RoofType = roof_type,
	shed_high_dir: int = 0,
	max_allowed_rise: float = 999.0,
	record_occlusion: bool = false
) -> void:
	var min_x: float = wing.position.x - ext_min_x
	var max_x: float = wing.end.x + ext_max_x
	var min_z: float = wing.position.y - ext_min_z
	var max_z: float = wing.end.y + ext_max_z

	var thickness: float = maxf(roof_height, 0.02)

	if active_roof_type == RoofType.FLAT:
		_append_box(roof_mb, Vector3(min_x, y_eave, min_z), Vector3(max_x, y_eave + thickness, max_z))
		if record_occlusion:
			_roof_occlusion_boxes.append(AABB(
				Vector3(min_x - 0.1, y_eave - 0.05, min_z - 0.1),
				Vector3(max_x - min_x + 0.2, thickness + 0.15, max_z - min_z + 0.2)
			))
		return

	var center_x: float = wing.get_center().x
	var center_z: float = wing.get_center().y

	var wall_u_min: float = wing.position.y if ridge_along_x else wing.position.x
	var wall_u_max: float = wing.end.y if ridge_along_x else wing.end.x
	var wall_v_min: float = wing.position.x if ridge_along_x else wing.position.y
	var wall_v_max: float = wing.end.x if ridge_along_x else wing.end.y

	var u_min: float = min_z if ridge_along_x else min_x
	var u_max: float = max_z if ridge_along_x else max_x
	var v_min: float = min_x if ridge_along_x else min_z
	var v_max: float = max_x if ridge_along_x else max_z

	var ovh_u_min: float = ext_min_z if ridge_along_x else ext_min_x
	var ovh_u_max: float = ext_max_z if ridge_along_x else ext_max_x

	var mid_u: float = center_z if ridge_along_x else center_x
	var mid_v: float = (v_min + v_max) * 0.5
	var half_wall_u: float = maxf((wall_u_max - wall_u_min) * 0.5, 0.1)
	var span_u: float = u_max - u_min
	var span_v: float = v_max - v_min

	var slope_tan: float = tan(deg_to_rad(clampf(roof_angle, 2.0, 80.0))) * roof_peak_height_scale

	var out_pos_u: Vector3 = _wing_dir(1.0, 0.0, 0.0, ridge_along_x)
	var out_neg_u: Vector3 = _wing_dir(-1.0, 0.0, 0.0, ridge_along_x)
	var out_pos_v: Vector3 = _wing_dir(0.0, 0.0, 1.0, ridge_along_x)
	var out_neg_v: Vector3 = _wing_dir(0.0, 0.0, -1.0, ridge_along_x)

	var recorded_max_y: float = y_eave + thickness

	match active_roof_type:
		RoofType.GABLE:
			var rise: float = minf(half_wall_u * slope_tan, max_allowed_rise)
			var eff_tan: float = rise / half_wall_u
			var y_peak: float = y_eave + rise
			var y_left_eave: float = y_eave - ovh_u_min * eff_tan
			var y_right_eave: float = y_eave - ovh_u_max * eff_tan
			recorded_max_y = y_peak + thickness

			_add_double_sided_tri(
				walls_mb,
				_wing_pt(wall_u_min, y_eave, wall_v_min, ridge_along_x),
				_wing_pt(wall_u_max, y_eave, wall_v_min, ridge_along_x),
				_wing_pt(mid_u, y_peak, wall_v_min, ridge_along_x),
				out_neg_v,
				wall_t
			)
			_add_double_sided_tri(
				walls_mb,
				_wing_pt(wall_u_max, y_eave, wall_v_max, ridge_along_x),
				_wing_pt(wall_u_min, y_eave, wall_v_max, ridge_along_x),
				_wing_pt(mid_u, y_peak, wall_v_max, ridge_along_x),
				out_pos_v,
				wall_t
			)

			_append_wing_slope_segment(roof_mb, u_min, y_left_eave, mid_u, y_peak, v_min, v_max, thickness, true, false, ridge_along_x)
			_append_wing_slope_segment(roof_mb, mid_u, y_peak, u_max, y_right_eave, v_min, v_max, thickness, false, true, ridge_along_x)

		RoofType.SHED:
			var raw_rise: float = (2.0 * half_wall_u) * slope_tan
			var rise: float = minf(raw_rise, max_allowed_rise)
			var eff_slope_tan: float = rise / maxf(2.0 * half_wall_u, 0.1)

			var high_at_u_min: bool = (shed_high_dir == 2 or shed_high_dir == 4)
			var y_wall_high: float = y_eave + rise
			recorded_max_y = y_wall_high + thickness

			if high_at_u_min:
				var y_high_eave: float = y_wall_high + ovh_u_min * eff_slope_tan
				var y_low_eave: float = y_eave - ovh_u_max * eff_slope_tan

				_add_double_sided_tri(
					walls_mb,
					_wing_pt(wall_u_min, y_eave, wall_v_min, ridge_along_x),
					_wing_pt(wall_u_max, y_eave, wall_v_min, ridge_along_x),
					_wing_pt(wall_u_min, y_wall_high, wall_v_min, ridge_along_x),
					out_neg_v,
					wall_t
				)
				_add_double_sided_tri(
					walls_mb,
					_wing_pt(wall_u_max, y_eave, wall_v_max, ridge_along_x),
					_wing_pt(wall_u_min, y_eave, wall_v_max, ridge_along_x),
					_wing_pt(wall_u_min, y_wall_high, wall_v_max, ridge_along_x),
					out_pos_v,
					wall_t
				)
				_add_double_sided_quad(
					walls_mb,
					_wing_pt(wall_u_min, y_eave, wall_v_max, ridge_along_x),
					_wing_pt(wall_u_min, y_eave, wall_v_min, ridge_along_x),
					_wing_pt(wall_u_min, y_wall_high, wall_v_min, ridge_along_x),
					_wing_pt(wall_u_min, y_wall_high, wall_v_max, ridge_along_x),
					out_neg_u,
					wall_t
				)
				_append_wing_slope_segment(roof_mb, u_min, y_high_eave, u_max, y_low_eave, v_min, v_max, thickness, true, true, ridge_along_x)
			else:
				var y_low_eave: float = y_eave - ovh_u_min * eff_slope_tan
				var y_high_eave: float = y_wall_high + ovh_u_max * eff_slope_tan

				_add_double_sided_tri(
					walls_mb,
					_wing_pt(wall_u_min, y_eave, wall_v_min, ridge_along_x),
					_wing_pt(wall_u_max, y_eave, wall_v_min, ridge_along_x),
					_wing_pt(wall_u_max, y_wall_high, wall_v_min, ridge_along_x),
					out_neg_v,
					wall_t
				)
				_add_double_sided_tri(
					walls_mb,
					_wing_pt(wall_u_max, y_eave, wall_v_max, ridge_along_x),
					_wing_pt(wall_u_min, y_eave, wall_v_max, ridge_along_x),
					_wing_pt(wall_u_max, y_wall_high, wall_v_max, ridge_along_x),
					out_pos_v,
					wall_t
				)
				_add_double_sided_quad(
					walls_mb,
					_wing_pt(wall_u_max, y_eave, wall_v_min, ridge_along_x),
					_wing_pt(wall_u_max, y_eave, wall_v_max, ridge_along_x),
					_wing_pt(wall_u_max, y_wall_high, wall_v_max, ridge_along_x),
					_wing_pt(wall_u_max, y_wall_high, wall_v_min, ridge_along_x),
					out_pos_u,
					wall_t
				)
				_append_wing_slope_segment(roof_mb, u_min, y_low_eave, u_max, y_high_eave, v_min, v_max, thickness, true, true, ridge_along_x)

		RoofType.GAMBREL:
			var knuckle_dist: float = half_wall_u * 0.55
			var steep_tan: float = tan(deg_to_rad(clampf(roof_angle * 1.45, 10.0, 78.0))) * roof_peak_height_scale
			var gentle_tan: float = tan(deg_to_rad(clampf(roof_angle * 0.55, 5.0, 60.0))) * roof_peak_height_scale

			var raw_knuckle_rise: float = (half_wall_u - knuckle_dist) * steep_tan
			var raw_total_rise: float = raw_knuckle_rise + knuckle_dist * gentle_tan
			var scale_f: float = minf(1.0, max_allowed_rise / maxf(raw_total_rise, 0.01))
			steep_tan *= scale_f
			gentle_tan *= scale_f

			var y_knuckle: float = y_eave + (half_wall_u - knuckle_dist) * steep_tan
			var y_peak: float = y_knuckle + knuckle_dist * gentle_tan
			var y_left_eave: float = y_eave - ovh_u_min * steep_tan
			var y_right_eave: float = y_eave - ovh_u_max * steep_tan
			recorded_max_y = y_peak + thickness

			_add_double_sided_quad(
				walls_mb,
				_wing_pt(wall_u_min, y_eave, wall_v_min, ridge_along_x),
				_wing_pt(wall_u_max, y_eave, wall_v_min, ridge_along_x),
				_wing_pt(mid_u + knuckle_dist, y_knuckle, wall_v_min, ridge_along_x),
				_wing_pt(mid_u - knuckle_dist, y_knuckle, wall_v_min, ridge_along_x),
				out_neg_v,
				wall_t
			)
			_add_double_sided_tri(
				walls_mb,
				_wing_pt(mid_u - knuckle_dist, y_knuckle, wall_v_min, ridge_along_x),
				_wing_pt(mid_u + knuckle_dist, y_knuckle, wall_v_min, ridge_along_x),
				_wing_pt(mid_u, y_peak, wall_v_min, ridge_along_x),
				out_neg_v,
				wall_t
			)
			_add_double_sided_quad(
				walls_mb,
				_wing_pt(wall_u_max, y_eave, wall_v_max, ridge_along_x),
				_wing_pt(wall_u_min, y_eave, wall_v_max, ridge_along_x),
				_wing_pt(mid_u - knuckle_dist, y_knuckle, wall_v_max, ridge_along_x),
				_wing_pt(mid_u + knuckle_dist, y_knuckle, wall_v_max, ridge_along_x),
				out_pos_v,
				wall_t
			)
			_add_double_sided_tri(
				walls_mb,
				_wing_pt(mid_u + knuckle_dist, y_knuckle, wall_v_max, ridge_along_x),
				_wing_pt(mid_u - knuckle_dist, y_knuckle, wall_v_max, ridge_along_x),
				_wing_pt(mid_u, y_peak, wall_v_max, ridge_along_x),
				out_pos_v,
				wall_t
			)

			_append_wing_slope_segment(roof_mb, u_min, y_left_eave, mid_u - knuckle_dist, y_knuckle, v_min, v_max, thickness, true, false, ridge_along_x)
			_append_wing_slope_segment(roof_mb, mid_u - knuckle_dist, y_knuckle, mid_u, y_peak, v_min, v_max, thickness, false, false, ridge_along_x)
			_append_wing_slope_segment(roof_mb, mid_u, y_peak, mid_u + knuckle_dist, y_knuckle, v_min, v_max, thickness, false, false, ridge_along_x)
			_append_wing_slope_segment(roof_mb, mid_u + knuckle_dist, y_knuckle, u_max, y_right_eave, v_min, v_max, thickness, false, true, ridge_along_x)

		RoofType.HIP:
			_append_eave_fascia_ring_at(roof_mb, min_x, max_x, min_z, max_z, y_eave, y_eave + thickness)
			var inset: float = minf(span_u, span_v) * 0.5
			var y_base: float = y_eave + thickness
			var rise: float = minf(slope_tan * inset, max_allowed_rise)
			var y_peak: float = y_base + rise
			recorded_max_y = y_peak

			var bl: Vector3 = _wing_pt(u_min, y_base, v_min, ridge_along_x)
			var fl: Vector3 = _wing_pt(u_min, y_base, v_max, ridge_along_x)
			var br: Vector3 = _wing_pt(u_max, y_base, v_min, ridge_along_x)
			var fr: Vector3 = _wing_pt(u_max, y_base, v_max, ridge_along_x)

			if span_v >= span_u:
				var r_back: Vector3 = _wing_pt(mid_u, y_peak, v_min + inset, ridge_along_x)
				var r_front: Vector3 = _wing_pt(mid_u, y_peak, v_max - inset, ridge_along_x)
				_add_oriented_quad(roof_mb, fl, bl, r_back, r_front, Vector3.UP + out_neg_u)
				_add_oriented_quad(roof_mb, br, fr, r_front, r_back, Vector3.UP + out_pos_u)
				_add_oriented_tri(roof_mb, fl, fr, r_front, Vector3.UP + out_pos_v)
				_add_oriented_tri(roof_mb, br, bl, r_back, Vector3.UP + out_neg_v)
			else:
				var r_left: Vector3 = _wing_pt(u_min + inset, y_peak, mid_v, ridge_along_x)
				var r_right: Vector3 = _wing_pt(u_max - inset, y_peak, mid_v, ridge_along_x)
				_add_oriented_quad(roof_mb, fl, fr, r_right, r_left, Vector3.UP + out_pos_v)
				_add_oriented_quad(roof_mb, br, bl, r_left, r_right, Vector3.UP + out_neg_v)
				_add_oriented_tri(roof_mb, bl, fl, r_left, Vector3.UP + out_neg_u)
				_add_oriented_tri(roof_mb, fr, br, r_right, Vector3.UP + out_pos_u)

		RoofType.DUTCH:
			_append_eave_fascia_ring_at(roof_mb, min_x, max_x, min_z, max_z, y_eave, y_eave + thickness)
			var hip_ratio: float = 0.42
			var inset_u: float = (span_u * 0.5) * hip_ratio
			var inset_v: float = minf(span_v * 0.28, inset_u)
			var y_base: float = y_eave + thickness
			var total_rise: float = minf(slope_tan * (span_u * 0.5), max_allowed_rise)
			var y_mid: float = y_base + total_rise * hip_ratio
			var y_peak: float = y_base + total_rise
			recorded_max_y = y_peak + thickness

			var bl: Vector3 = _wing_pt(u_min, y_base, v_min, ridge_along_x)
			var fl: Vector3 = _wing_pt(u_min, y_base, v_max, ridge_along_x)
			var br: Vector3 = _wing_pt(u_max, y_base, v_min, ridge_along_x)
			var fr: Vector3 = _wing_pt(u_max, y_base, v_max, ridge_along_x)

			var m_bl: Vector3 = _wing_pt(u_min + inset_u, y_mid, v_min + inset_v, ridge_along_x)
			var m_fl: Vector3 = _wing_pt(u_min + inset_u, y_mid, v_max - inset_v, ridge_along_x)
			var m_br: Vector3 = _wing_pt(u_max - inset_u, y_mid, v_min + inset_v, ridge_along_x)
			var m_fr: Vector3 = _wing_pt(u_max - inset_u, y_mid, v_max - inset_v, ridge_along_x)

			var r_back: Vector3 = _wing_pt(mid_u, y_peak, v_min + inset_v, ridge_along_x)
			var r_front: Vector3 = _wing_pt(mid_u, y_peak, v_max - inset_v, ridge_along_x)

			_add_oriented_quad(roof_mb, fl, bl, m_bl, m_fl, Vector3.UP + out_neg_u)
			_add_oriented_quad(roof_mb, br, fr, m_fr, m_br, Vector3.UP + out_pos_u)
			_add_oriented_quad(roof_mb, fl, fr, m_fr, m_fl, Vector3.UP + out_pos_v)
			_add_oriented_quad(roof_mb, br, bl, m_bl, m_br, Vector3.UP + out_neg_v)

			_add_double_sided_tri(walls_mb, m_fl, m_fr, r_front, out_pos_v, wall_t)
			_add_double_sided_tri(walls_mb, m_br, m_bl, r_back, out_neg_v, wall_t)

			var brow: float = minf(inset_v * 0.35, 0.25)
			_append_wing_slope_segment(
				roof_mb,
				u_min + inset_u, y_mid,
				mid_u, y_peak,
				v_min + inset_v - brow, v_max - inset_v + brow,
				thickness * 0.75,
				true, false,
				ridge_along_x
			)
			_append_wing_slope_segment(
				roof_mb,
				mid_u, y_peak,
				u_max - inset_u, y_mid,
				v_min + inset_v - brow, v_max - inset_v + brow,
				thickness * 0.75,
				false, true,
				ridge_along_x
			)

	if record_occlusion:
		_roof_occlusion_boxes.append(AABB(
			Vector3(min_x - 0.1, y_eave - 0.05, min_z - 0.1),
			Vector3(maxf(max_x - min_x + 0.2, 0.1), maxf(recorded_max_y - y_eave + 0.15, 0.2), maxf(max_z - min_z + 0.2, 0.1))
		))
#endregion


#region Step 5: Procedural 3D Window Mesh Generation (9 Uncrossed Window Types)
func _append_local_box(
	mb: Dictionary,
	origin: Vector3,
	right: Vector3,
	up: Vector3,
	normal: Vector3,
	x0: float, y0: float, z0: float,
	x1: float, y1: float, z1: float
) -> void:
	var lx0: float = minf(x0, x1)
	var lx1: float = maxf(x0, x1)
	var ly0: float = minf(y0, y1)
	var ly1: float = maxf(y0, y1)
	var lz0: float = minf(z0, z1)
	var lz1: float = maxf(z0, z1)

	var p000: Vector3 = origin + right * lx0 + up * ly0 + normal * lz0
	var p100: Vector3 = origin + right * lx1 + up * ly0 + normal * lz0
	var p110: Vector3 = origin + right * lx1 + up * ly1 + normal * lz0
	var p010: Vector3 = origin + right * lx0 + up * ly1 + normal * lz0

	var p001: Vector3 = origin + right * lx0 + up * ly0 + normal * lz1
	var p101: Vector3 = origin + right * lx1 + up * ly0 + normal * lz1
	var p111: Vector3 = origin + right * lx1 + up * ly1 + normal * lz1
	var p011: Vector3 = origin + right * lx0 + up * ly1 + normal * lz1

	_add_quad(mb, p001, p101, p111, p011, normal)
	_add_quad(mb, p100, p000, p010, p110, -normal)
	_add_quad(mb, p010, p011, p111, p110, up)
	_add_quad(mb, p001, p000, p100, p101, -up)
	_add_quad(mb, p101, p100, p110, p111, right)
	_add_quad(mb, p000, p001, p011, p010, -right)


func _append_local_frame_rect(
	mb: Dictionary,
	origin: Vector3,
	right: Vector3,
	up: Vector3,
	normal: Vector3,
	x0: float, y0: float,
	x1: float, y1: float,
	z0: float, z1: float,
	border_w: float
) -> void:
	var bw: float = minf(border_w, minf(x1 - x0, y1 - y0) * 0.45)
	# Bottom & Top rails
	_append_local_box(mb, origin, right, up, normal, x0, y0, z0, x1, y0 + bw, z1)
	_append_local_box(mb, origin, right, up, normal, x0, y1 - bw, z0, x1, y1, z1)
	# Left & Right stiles
	_append_local_box(mb, origin, right, up, normal, x0, y0 + bw, z0, x0 + bw, y1 - bw, z1)
	_append_local_box(mb, origin, right, up, normal, x1 - bw, y0 + bw, z0, x1, y1 - bw, z1)


func _append_local_muntin_grid(
	mb: Dictionary,
	origin: Vector3,
	right: Vector3,
	up: Vector3,
	normal: Vector3,
	x0: float, y0: float,
	x1: float, y1: float,
	z0: float, z1: float,
	cols: int,
	rows: int,
	bar_w: float
) -> void:
	var span_x: float = x1 - x0
	var span_y: float = y1 - y0
	var half_b: float = bar_w * 0.5

	for c: int in range(1, cols):
		var cx: float = x0 + (span_x * float(c) / float(cols))
		_append_local_box(mb, origin, right, up, normal, cx - half_b, y0, z0, cx + half_b, y1, z1)

	for r: int in range(1, rows):
		var ry: float = y0 + (span_y * float(r) / float(rows))
		_append_local_box(mb, origin, right, up, normal, x0, ry - half_b, z0, x1, ry + half_b, z1)


func _append_window_mesh(
	accent_mb: Dictionary,
	glass_mb: Dictionary,
	col_mb: Dictionary,
	open_origin: Vector3,
	w_right: Vector3,
	w_normal: Vector3,
	w_width: float,
	w_height: float,
	wall_t: float,
	w_type: WindowType
) -> void:
	var up := Vector3.UP
	# Window mesh has half the width (thickness) of the exterior wall, centered inside the wall depth!
	var win_depth: float = wall_t * 0.5
	var z_center: float = -wall_t * 0.5
	var z0: float = z_center - win_depth * 0.5
	var z1: float = z_center + win_depth * 0.5
	var glass_half_t: float = maxf(win_depth * 0.14, 0.008)

	var f_w: float = clampf(0.055 * frame_width_multiplier, 0.015, minf(w_width, w_height) * 0.22)
	var m_w: float = maxf(f_w * 0.52, 0.012)

	# Simple collision box sealing the window opening for physics
	_append_local_box(col_mb, open_origin, w_right, up, w_normal, 0.0, 0.0, z0, w_width, w_height, z1)

	match w_type:
		WindowType.FIXED:
			_append_local_frame_rect(accent_mb, open_origin, w_right, up, w_normal, 0.0, 0.0, w_width, w_height, z0, z1, f_w)
			var s_w: float = f_w * 0.65
			_append_local_frame_rect(
				accent_mb, open_origin, w_right, up, w_normal,
				f_w, f_w, w_width - f_w, w_height - f_w,
				z_center - win_depth * 0.38, z_center + win_depth * 0.38, s_w
			)
			var inset: float = f_w + s_w
			_append_local_box(
				glass_mb, open_origin, w_right, up, w_normal,
				inset, inset, z_center - glass_half_t,
				w_width - inset, w_height - inset, z_center + glass_half_t
			)

		WindowType.PICTURE:
			var thin_f: float = f_w * 0.65
			_append_local_frame_rect(accent_mb, open_origin, w_right, up, w_normal, 0.0, 0.0, w_width, w_height, z0, z1, thin_f)
			# Subtle exterior sill ledge
			_append_local_box(accent_mb, open_origin, w_right, up, w_normal, -0.02, 0.0, z0, w_width + 0.02, thin_f * 0.8, 0.03)
			_append_local_box(
				glass_mb, open_origin, w_right, up, w_normal,
				thin_f, thin_f, z_center - glass_half_t,
				w_width - thin_f, w_height - thin_f, z_center + glass_half_t
			)

		WindowType.COTTAGE:
			_append_local_frame_rect(accent_mb, open_origin, w_right, up, w_normal, 0.0, 0.0, w_width, w_height, z0, z1, f_w)
			var split_y: float = w_height * 0.64
			# Horizontal transom bar at 64% height
			_append_local_box(accent_mb, open_origin, w_right, up, w_normal, f_w, split_y - f_w * 0.45, z0, w_width - f_w, split_y + f_w * 0.45, z1)
			# 3-pane muntin division in the upper cottage sash
			_append_local_muntin_grid(
				accent_mb, open_origin, w_right, up, w_normal,
				f_w, split_y + f_w * 0.45, w_width - f_w, w_height - f_w,
				z_center - win_depth * 0.35, z_center + win_depth * 0.35, 3, 1, m_w
			)
			_append_local_box(
				glass_mb, open_origin, w_right, up, w_normal,
				f_w, f_w, z_center - glass_half_t,
				w_width - f_w, w_height - f_w, z_center + glass_half_t
			)

		WindowType.FRENCH_DOOR_WINDOW:
			_append_local_frame_rect(accent_mb, open_origin, w_right, up, w_normal, 0.0, 0.0, w_width, w_height, z0, z1, f_w)
			var mid_x: float = w_width * 0.5
			# Center vertical casement mullion
			_append_local_box(accent_mb, open_origin, w_right, up, w_normal, mid_x - f_w * 0.5, f_w, z0, mid_x + f_w * 0.5, w_height - f_w, z1)
			# Left & Right 2x4 muntin grids
			_append_local_muntin_grid(
				accent_mb, open_origin, w_right, up, w_normal,
				f_w, f_w, mid_x - f_w * 0.5, w_height - f_w,
				z_center - win_depth * 0.35, z_center + win_depth * 0.35, 2, 4, m_w
			)
			_append_local_muntin_grid(
				accent_mb, open_origin, w_right, up, w_normal,
				mid_x + f_w * 0.5, f_w, w_width - f_w, w_height - f_w,
				z_center - win_depth * 0.35, z_center + win_depth * 0.35, 2, 4, m_w
			)
			_append_local_box(
				glass_mb, open_origin, w_right, up, w_normal,
				f_w, f_w, z_center - glass_half_t,
				w_width - f_w, w_height - f_w, z_center + glass_half_t
			)

		WindowType.GLASS_BLOCK:
			_append_local_frame_rect(accent_mb, open_origin, w_right, up, w_normal, 0.0, 0.0, w_width, w_height, z0, z1, f_w * 0.85)
			var inner_x0: float = f_w * 0.85
			var inner_y0: float = f_w * 0.85
			var inner_x1: float = w_width - inner_x0
			var inner_y1: float = w_height - inner_y0
			var cols: int = maxi(int(roundf(w_width / 0.22)), 3)
			var rows: int = maxi(int(roundf(w_height / 0.22)), 3)
			_append_local_muntin_grid(
				accent_mb, open_origin, w_right, up, w_normal,
				inner_x0, inner_y0, inner_x1, inner_y1,
				z_center - win_depth * 0.3, z_center + win_depth * 0.3, cols, rows, m_w * 0.9
			)
			# Thick glass block slab
			_append_local_box(
				glass_mb, open_origin, w_right, up, w_normal,
				inner_x0, inner_y0, z_center - win_depth * 0.42,
				inner_x1, inner_y1, z_center + win_depth * 0.42
			)

		WindowType.PALLADIAN:
			var side_w: float = w_width * 0.24
			var side_top_y: float = w_height * 0.72
			var x_l: float = side_w
			var x_r: float = w_width - side_w

			# Outer frame and two vertical pilasters separating the 3 sections
			_append_local_frame_rect(accent_mb, open_origin, w_right, up, w_normal, 0.0, 0.0, w_width, w_height, z0, z1, f_w * 0.85)
			_append_local_box(accent_mb, open_origin, w_right, up, w_normal, x_l - f_w * 0.45, f_w * 0.85, z0, x_l + f_w * 0.45, w_height - f_w * 0.85, z1)
			_append_local_box(accent_mb, open_origin, w_right, up, w_normal, x_r - f_w * 0.45, f_w * 0.85, z0, x_r + f_w * 0.45, w_height - f_w * 0.85, z1)

			# Solid spandrel headers above the left & right sidelights (so only the center arch rises to the top)
			_append_local_box(accent_mb, open_origin, w_right, up, w_normal, f_w * 0.85, side_top_y, z0, x_l - f_w * 0.45, w_height - f_w * 0.85, z1)
			_append_local_box(accent_mb, open_origin, w_right, up, w_normal, x_r + f_w * 0.45, side_top_y, z0, w_width - f_w * 0.85, w_height - f_w * 0.85, z1)
			# Horizontal transom bar across all 3 sections at side_top_y
			_append_local_box(accent_mb, open_origin, w_right, up, w_normal, f_w * 0.85, side_top_y - f_w * 0.4, z0, w_width - f_w * 0.85, side_top_y + f_w * 0.4, z1)

			# Muntin grids in sidelights and center section
			_append_local_muntin_grid(accent_mb, open_origin, w_right, up, w_normal, f_w * 0.85, f_w * 0.85, x_l - f_w * 0.45, side_top_y - f_w * 0.4, z0, z1, 1, 3, m_w)
			_append_local_muntin_grid(accent_mb, open_origin, w_right, up, w_normal, x_r + f_w * 0.45, f_w * 0.85, w_width - f_w * 0.85, side_top_y - f_w * 0.4, z0, z1, 1, 3, m_w)
			_append_local_muntin_grid(accent_mb, open_origin, w_right, up, w_normal, x_l + f_w * 0.45, f_w * 0.85, x_r - f_w * 0.45, side_top_y - f_w * 0.4, z0, z1, 2, 3, m_w)

			# Arch spandrel corners in the top center section
			var arch_cx: float = w_width * 0.5
			var arch_cy: float = side_top_y
			var arch_rx: float = (x_r - x_l) * 0.5 - f_w * 0.45
			var arch_ry: float = (w_height - f_w * 0.85) - side_top_y
			_append_palladian_arch_spandrels(accent_mb, open_origin, w_right, up, w_normal, arch_cx, arch_cy, arch_rx, arch_ry, z0, z1)

			# Glass panes
			_append_local_box(glass_mb, open_origin, w_right, up, w_normal, f_w * 0.85, f_w * 0.85, z_center - glass_half_t, w_width - f_w * 0.85, side_top_y, z_center + glass_half_t)
			_append_local_box(glass_mb, open_origin, w_right, up, w_normal, x_l + f_w * 0.45, side_top_y, z_center - glass_half_t, x_r - f_w * 0.45, w_height - f_w * 0.85, z_center + glass_half_t)

		WindowType.BAY:
			_append_bay_window(accent_mb, glass_mb, open_origin, w_right, up, w_normal, w_width, w_height, z_center, win_depth, f_w)

		WindowType.GARDEN:
			_append_garden_window(accent_mb, glass_mb, open_origin, w_right, up, w_normal, w_width, w_height, z_center, win_depth, f_w)

		WindowType.ROUND:
			_append_round_window(accent_mb, glass_mb, open_origin, w_right, up, w_normal, w_width, w_height, z0, z1, z_center, glass_half_t, f_w, m_w)


func _append_palladian_arch_spandrels(
	mb: Dictionary,
	origin: Vector3,
	right: Vector3,
	up: Vector3,
	normal: Vector3,
	cx: float, cy: float,
	rx: float, ry: float,
	z0: float, z1: float
) -> void:
	var segs: int = 8
	for side_sign: float in [-1.0, 1.0]:
		var corner_x: float = cx + side_sign * rx
		var corner_y: float = cy + ry
		for i: int in range(segs):
			var a0: float = (PI * 0.5) * (float(i) / float(segs))
			var a1: float = (PI * 0.5) * (float(i + 1) / float(segs))
			var x0: float = cx + side_sign * cos(a0) * rx
			var y0: float = cy + sin(a0) * ry
			var x1: float = cx + side_sign * cos(a1) * rx
			var y1: float = cy + sin(a1) * ry

			var f_c: Vector3 = origin + right * corner_x + up * corner_y + normal * z1
			var f_0: Vector3 = origin + right * x0 + up * y0 + normal * z1
			var f_1: Vector3 = origin + right * x1 + up * y1 + normal * z1
			_add_oriented_tri(mb, f_c, f_0, f_1, normal)

			var b_c: Vector3 = origin + right * corner_x + up * corner_y + normal * z0
			var b_0: Vector3 = origin + right * x0 + up * y0 + normal * z0
			var b_1: Vector3 = origin + right * x1 + up * y1 + normal * z0
			_add_oriented_tri(mb, b_c, b_1, b_0, -normal)
			_add_oriented_quad(mb, b_0, b_1, f_1, f_0, Vector3(cx - x0, cy - y0, 0.0))


func _append_bay_window(
	accent_mb: Dictionary,
	glass_mb: Dictionary,
	origin: Vector3,
	right: Vector3,
	up: Vector3,
	normal: Vector3,
	w: float,
	h: float,
	z_center: float,
	win_depth: float,
	f_w: float
) -> void:
	var proj: float = minf(w * 0.26, 0.42)
	var x1: float = w * 0.24
	var x2: float = w * 0.76

	var p_wall_l: Vector3 = origin + right * 0.0 + normal * z_center
	var p_front_l: Vector3 = origin + right * x1 + normal * proj
	var p_front_r: Vector3 = origin + right * x2 + normal * proj
	var p_wall_r: Vector3 = origin + right * w + normal * z_center

	# Bottom sill platform & top roof cap of the bay window
	var cap_h: float = maxf(f_w, 0.045)
	for base_y: float in [0.0, h - cap_h]:
		var b_wl: Vector3 = p_wall_l + up * base_y
		var b_fl: Vector3 = p_front_l + up * base_y
		var b_fr: Vector3 = p_front_r + up * base_y
		var b_wr: Vector3 = p_wall_r + up * base_y
		var t_wl: Vector3 = b_wl + up * cap_h
		var t_fl: Vector3 = b_fl + up * cap_h
		var t_fr: Vector3 = b_fr + up * cap_h
		var t_wr: Vector3 = b_wr + up * cap_h

		_add_oriented_quad(accent_mb, t_wl, t_wr, t_fr, t_fl, up)
		_add_oriented_quad(accent_mb, b_fl, b_fr, b_wr, b_wl, -up)
		_add_oriented_quad(accent_mb, b_wl, b_fl, t_fl, t_wl, normal - right)
		_add_oriented_quad(accent_mb, b_fl, b_fr, t_fr, t_fl, normal)
		_add_oriented_quad(accent_mb, b_fr, b_wr, t_wr, t_fr, normal + right)

	# 3 framed window panels (Left angled, Center flat, Right angled)
	var panels: Array[Array] = [
		[p_wall_l, p_front_l],
		[p_front_l, p_front_r],
		[p_front_r, p_wall_r]
	]
	for panel: Array in panels:
		var a: Vector3 = panel[0]
		var b: Vector3 = panel[1]
		var p_len: float = a.distance_to(b)
		var p_right: Vector3 = (b - a).normalized()
		var p_norm: Vector3 = p_right.cross(up).normalized()
		if p_norm.dot(normal) < 0.0:
			p_norm = -p_norm
		var p_orig: Vector3 = a + up * cap_h
		var p_h: float = h - cap_h * 2.0
		var half_d: float = win_depth * 0.4
		var g_d: float = maxf(win_depth * 0.12, 0.008)

		_append_local_frame_rect(accent_mb, p_orig, p_right, up, p_norm, 0.0, 0.0, p_len, p_h, -half_d, half_d, f_w * 0.8)
		_append_local_box(glass_mb, p_orig, p_right, up, p_norm, f_w * 0.8, f_w * 0.8, -g_d, p_len - f_w * 0.8, p_h - f_w * 0.8, g_d)


func _append_garden_window(
	accent_mb: Dictionary,
	glass_mb: Dictionary,
	origin: Vector3,
	right: Vector3,
	up: Vector3,
	normal: Vector3,
	w: float,
	h: float,
	z_center: float,
	win_depth: float,
	f_w: float
) -> void:
	var proj: float = minf(w * 0.32, 0.42)
	var front_top_y: float = h * 0.82
	var bar: float = maxf(f_w * 0.75, 0.03)
	var g_d: float = maxf(win_depth * 0.12, 0.008)

	# Bottom shelf platform
	_append_local_box(accent_mb, origin, right, up, normal, 0.0, 0.0, z_center, w, bar, proj)
	# Wall frame
	_append_local_frame_rect(accent_mb, origin, right, up, normal, 0.0, 0.0, w, h, z_center - bar * 0.5, z_center + bar * 0.5, bar)
	# Front vertical frame + glass
	_append_local_frame_rect(accent_mb, origin, right, up, normal, 0.0, bar, w, front_top_y, proj - bar, proj, bar)
	_append_local_box(glass_mb, origin, right, up, normal, bar, bar * 2.0, proj - bar * 0.5 - g_d, w - bar, front_top_y - bar, proj - bar * 0.5 + g_d)

	# Sloped skylight glass + side rafters
	var roof_back_l: Vector3 = origin + right * bar + up * (h - bar * 0.5) + normal * z_center
	var roof_back_r: Vector3 = origin + right * (w - bar) + up * (h - bar * 0.5) + normal * z_center
	var roof_front_l: Vector3 = origin + right * bar + up * front_top_y + normal * (proj - bar * 0.5)
	var roof_front_r: Vector3 = origin + right * (w - bar) + up * front_top_y + normal * (proj - bar * 0.5)
	_add_oriented_quad(glass_mb, roof_back_l, roof_back_r, roof_front_r, roof_front_l, up + normal)
	_add_oriented_quad(glass_mb, roof_front_l, roof_front_r, roof_back_r, roof_back_l, -(up + normal))

	# Side glass trapezoids and top sloped bars
	for side_x: float in [bar * 0.5, w - bar * 0.5]:
		var s_bl: Vector3 = origin + right * side_x + up * bar + normal * z_center
		var s_fl: Vector3 = origin + right * side_x + up * bar + normal * (proj - bar)
		var s_ft: Vector3 = origin + right * side_x + up * (front_top_y - bar * 0.5) + normal * (proj - bar)
		var s_bt: Vector3 = origin + right * side_x + up * (h - bar) + normal * z_center
		_add_oriented_quad(glass_mb, s_bl, s_fl, s_ft, s_bt, right)
		_add_oriented_quad(glass_mb, s_fl, s_bl, s_bt, s_ft, -right)


func _append_round_window(
	accent_mb: Dictionary,
	glass_mb: Dictionary,
	origin: Vector3,
	right: Vector3,
	up: Vector3,
	normal: Vector3,
	w: float,
	h: float,
	z0: float,
	z1: float,
	z_center: float,
	glass_half_t: float,
	f_w: float,
	m_w: float
) -> void:
	var cx: float = w * 0.5
	var cy: float = h * 0.5
	var rx_outer: float = w * 0.5
	var ry_outer: float = h * 0.5
	var rx_inner: float = maxf(rx_outer - f_w * 1.15, 0.08)
	var ry_inner: float = maxf(ry_outer - f_w * 1.15, 0.08)

	# Fill the 4 corners outside the outer ellipse so the circular window sits cleanly inside the rectangular wall opening
	_append_palladian_arch_spandrels(accent_mb, origin, right, up, normal, cx, cy, rx_outer, ry_outer, z0, z1)
	_append_palladian_arch_spandrels(accent_mb, origin, right, up, normal, cx, cy, rx_outer, -ry_outer, z0, z1)

	# Circular ring frame (16 segments) + glass disc
	var segs: int = 16
	for i: int in range(segs):
		var a0: float = TAU * (float(i) / float(segs))
		var a1: float = TAU * (float(i + 1) / float(segs))

		var ox0: float = cx + cos(a0) * rx_outer
		var oy0: float = cy + sin(a0) * ry_outer
		var ox1: float = cx + cos(a1) * rx_outer
		var oy1: float = cy + sin(a1) * ry_outer

		var ix0: float = cx + cos(a0) * rx_inner
		var iy0: float = cy + sin(a0) * ry_inner
		var ix1: float = cx + cos(a1) * rx_inner
		var iy1: float = cy + sin(a1) * ry_inner

		# Front & back ring faces + inner rim
		var fo0: Vector3 = origin + right * ox0 + up * oy0 + normal * z1
		var fo1: Vector3 = origin + right * ox1 + up * oy1 + normal * z1
		var fi0: Vector3 = origin + right * ix0 + up * iy0 + normal * z1
		var fi1: Vector3 = origin + right * ix1 + up * iy1 + normal * z1
		_add_oriented_quad(accent_mb, fi0, fo0, fo1, fi1, normal)

		var bo0: Vector3 = origin + right * ox0 + up * oy0 + normal * z0
		var bo1: Vector3 = origin + right * ox1 + up * oy1 + normal * z0
		var bi0: Vector3 = origin + right * ix0 + up * iy0 + normal * z0
		var bi1: Vector3 = origin + right * ix1 + up * iy1 + normal * z0
		_add_oriented_quad(accent_mb, bo0, bi0, bi1, bo1, -normal)

		var inward_dir: Vector3 = (-right * cos(a0) - up * sin(a0)).normalized()
		_add_oriented_quad(accent_mb, bi0, bi1, fi1, fi0, inward_dir)

		# Glass disc sector
		var gc_f: Vector3 = origin + right * cx + up * cy + normal * (z_center + glass_half_t)
		var g0_f: Vector3 = origin + right * ix0 + up * iy0 + normal * (z_center + glass_half_t)
		var g1_f: Vector3 = origin + right * ix1 + up * iy1 + normal * (z_center + glass_half_t)
		_add_oriented_tri(glass_mb, gc_f, g0_f, g1_f, normal)

		var gc_b: Vector3 = origin + right * cx + up * cy + normal * (z_center - glass_half_t)
		var g0_b: Vector3 = origin + right * ix0 + up * iy0 + normal * (z_center - glass_half_t)
		var g1_b: Vector3 = origin + right * ix1 + up * iy1 + normal * (z_center - glass_half_t)
		_add_oriented_tri(glass_mb, gc_b, g1_b, g0_b, -normal)

	# Cross (+) muntin bars inside the round window
	_append_local_box(accent_mb, origin, right, up, normal, cx - m_w * 0.5, cy - ry_inner, z0, cx + m_w * 0.5, cy + ry_inner, z1)
	_append_local_box(accent_mb, origin, right, up, normal, cx - rx_inner, cy - m_w * 0.5, z0, cx + rx_inner, cy + m_w * 0.5, z1)
#endregion


#region Step 6: Procedural 3D Door Frame, Door Leaf Meshes & Interactive DoorComponent Spawner
func _append_door_outer_frame(
	accent_mb: Dictionary,
	open_origin: Vector3,
	w_right: Vector3,
	w_normal: Vector3,
	open_w: float,
	open_h: float,
	wall_t: float,
	frame_t: float,
	d_type: DoorType
) -> void:
	var up := Vector3.UP
	var z0: float = -wall_t - 0.015
	var z1: float = 0.015

	# Left jamb, Right jamb, and Top header bar
	_append_local_box(accent_mb, open_origin, w_right, up, w_normal, 0.0, 0.0, z0, frame_t, open_h, z1)
	_append_local_box(accent_mb, open_origin, w_right, up, w_normal, open_w - frame_t, 0.0, z0, open_w, open_h, z1)
	_append_local_box(accent_mb, open_origin, w_right, up, w_normal, frame_t, open_h - frame_t, z0, open_w - frame_t, open_h, z1)

	# Overhead sliding track rail for Barn doors
	if d_type == DoorType.BARN:
		var track_y0: float = open_h + 0.02
		var track_y1: float = open_h + 0.08
		_append_local_box(
			accent_mb, open_origin, w_right, up, w_normal,
			-open_w * 0.95, track_y0, 0.02,
			open_w * 1.95, track_y1, 0.06
		)


func _rebuild_door_components(all_doors: Array[Dictionary]) -> void:
	var old_container := get_node_or_null("DoorsContainer")
	if old_container:
		old_container.free()

	if not generate_door_nodes or all_doors.is_empty():
		return

	var scene_owner: Node = _get_scene_owner()
	var doors_root := Node3D.new()
	doors_root.name = "DoorsContainer"
	doors_root.position = Vector3(0.0, foundation_height, 0.0)
	add_child(doors_root)
	if scene_owner:
		doors_root.owner = scene_owner

	var door_counter: int = 0
	for d_info: Dictionary in all_doors:
		var open_origin: Vector3 = d_info["origin_walls_space"]
		var w_right: Vector3 = d_info["right"]
		var w_normal: Vector3 = d_info["normal"]
		var open_w: float = float(d_info["width"])
		var open_h: float = float(d_info["height"])
		var wall_t: float = float(d_info["wall_t"])
		var frame_t: float = float(d_info["frame_t"])
		var d_type: DoorType = d_info["door_type"]
		var is_dbl: bool = bool(d_info["is_double"])

		var inner_w: float = maxf(open_w - frame_t * 2.0, 0.3)
		var inner_h: float = maxf(open_h - frame_t, 0.5)
		var inner_origin: Vector3 = open_origin + w_right * frame_t

		if is_dbl and _is_door_type_double_compatible(d_type):
			var half_w: float = inner_w * 0.5
			# Left Leaf (hinged at left edge u = 0, extends +x from 0 to half_w)
			_spawn_single_door_component(
				doors_root,
				scene_owner,
				door_counter,
				inner_origin,
				w_right,
				w_normal,
				half_w,
				inner_h,
				wall_t,
				d_type,
				false
			)
			door_counter += 1
			# Right Leaf (hinged at right edge u = inner_w, extends -x from -half_w to 0)
			_spawn_single_door_component(
				doors_root,
				scene_owner,
				door_counter,
				inner_origin + w_right * inner_w,
				w_right,
				w_normal,
				half_w,
				inner_h,
				wall_t,
				d_type,
				true
			)
			door_counter += 1
		else:
			_spawn_single_door_component(
				doors_root,
				scene_owner,
				door_counter,
				inner_origin,
				w_right,
				w_normal,
				inner_w,
				inner_h,
				wall_t,
				d_type,
				false
			)
			door_counter += 1


func _spawn_single_door_component(
	doors_root: Node3D,
	scene_owner: Node,
	door_idx: int,
	hinge_origin_walls_space: Vector3,
	w_right: Vector3,
	w_normal: Vector3,
	leaf_w: float,
	leaf_h: float,
	wall_t: float,
	d_type: DoorType,
	is_right_double_leaf: bool
) -> void:
	var up := Vector3.UP
	var door_basis := Basis(w_right, up, w_normal)
	var leaf_depth: float = clampf(wall_t * 0.35, 0.04, 0.09)

	# Barn doors sit just outside the wall face so they can slide past the wall; other doors sit centered inside the wall depth
	var z_offset: float = (leaf_depth * 0.65) if (d_type == DoorType.BARN) else (-wall_t * 0.5)
	var pivot_pos: Vector3 = hinge_origin_walls_space + w_normal * z_offset

	var door_comp := DoorComponent.new()
	door_comp.name = "DoorComponent_%d" % door_idx
	door_comp.transform = Transform3D(door_basis, pivot_pos)
	door_comp.collision_layer = collision_layer
	door_comp.collision_mask = collision_mask
	door_comp.animation_time = door_animation_time

	# Configure DoorComponent motion property and offset based on DoorType (Rotating, Horizontal Sliding, or Vertical Garage Sliding)
	if d_type == DoorType.GARAGE:
		door_comp.property = "position:y"
		door_comp.open_value_offset = leaf_h * 0.92
	elif d_type == DoorType.BARN or d_type == DoorType.GLASS:
		var slide_sign: float = 1.0 if is_right_double_leaf else -1.0
		if absf(w_right.x) >= absf(w_right.z):
			door_comp.property = "position:x"
			door_comp.open_value_offset = w_right.x * slide_sign * (leaf_w * 0.95)
		else:
			door_comp.property = "position:z"
			door_comp.open_value_offset = w_right.z * slide_sign * (leaf_w * 0.95)
	else:
		door_comp.property = "rotation:y"
		door_comp.open_value_offset = (-PI * 0.5) if is_right_double_leaf else (PI * 0.5)

	# In DoorComponent's local space:
	# Left/Single leaf spans x in [0, leaf_w]; Right double leaf spans x in [-leaf_w, 0]
	var x0: float = -leaf_w if is_right_double_leaf else 0.0
	var x1: float = 0.0 if is_right_double_leaf else leaf_w
	var leaf_center_x: float = (x0 + x1) * 0.5

	# 1. Child 1: Area3D (InteractionComponent extends Area3D so it handles both Player clicks and NPC body_entered!)
	var area_3d := InteractionComponent.new()
	area_3d.name = "Area3D"
	area_3d.target_object = door_comp
	area_3d.interaction_prompt = "open"
	area_3d.collision_layer = collision_layer
	area_3d.collision_mask = collision_mask

	var area_col := CollisionShape3D.new()
	area_col.name = "CollisionShape3D"
	area_col.position = Vector3(leaf_center_x, leaf_h * 0.5, 0.0)
	var area_box := BoxShape3D.new()
	area_box.size = Vector3(
		leaf_w + door_area_extra_margin,
		leaf_h + 0.1,
		maxf(wall_t * 2.2, leaf_depth + door_area_extra_margin * 2.0)
	)
	area_col.shape = area_box
	area_3d.add_child(area_col)
	door_comp.add_child(area_3d)

	# 2. Child 2: Door (MeshInstance3D)
	var door_mi := MeshInstance3D.new()
	door_mi.name = "Door"
	door_mi.mesh = _build_door_leaf_mesh(x0, x1, leaf_h, leaf_depth, d_type, is_right_double_leaf)
	door_comp.add_child(door_mi)

	# 3. Child 3: CollisionShape3D (Physical collision shape of the door leaf)
	var body_col := CollisionShape3D.new()
	body_col.name = "CollisionShape3D"
	body_col.position = Vector3(leaf_center_x, leaf_h * 0.5, 0.0)
	var body_box := BoxShape3D.new()
	body_box.size = Vector3(leaf_w, leaf_h, leaf_depth)
	body_col.shape = body_box
	door_comp.add_child(body_col)

	# 4. Child 4: NavigationLink3D (Connects navmesh across both sides of the doorway)
	var nav_link := NavigationLink3D.new()
	nav_link.name = "NavigationLink3D"
	nav_link.position = Vector3(leaf_center_x, 0.0, -1.0)
	nav_link.start_position = Vector3.ZERO
	nav_link.end_position = Vector3(0.0, 0.0, 2.0)
	door_comp.add_child(nav_link)

	door_comp.npc_detection_area = area_3d
	door_comp.navlink = nav_link

	doors_root.add_child(door_comp)
	if scene_owner:
		door_comp.owner = scene_owner
		area_3d.owner = scene_owner
		area_col.owner = scene_owner
		door_mi.owner = scene_owner
		body_col.owner = scene_owner
		nav_link.owner = scene_owner


func _build_door_leaf_mesh(
	x0: float,
	x1: float,
	leaf_h: float,
	leaf_depth: float,
	d_type: DoorType,
	is_right_double_leaf: bool
) -> ArrayMesh:
	var accent_mb: Dictionary = _create_mesh_buffers()
	var glass_mb: Dictionary = _create_mesh_buffers()

	var orig := Vector3.ZERO
	var right := Vector3.RIGHT
	var up := Vector3.UP
	var norm := Vector3.BACK

	var w: float = x1 - x0
	var half_d: float = leaf_depth * 0.5
	var recess_d: float = half_d * 0.48
	var glass_d: float = maxf(half_d * 0.28, 0.008)
	var stile_w: float = clampf(w * 0.16 * frame_width_multiplier, 0.05, w * 0.28)
	var bar_w: float = maxf(stile_w * 0.35, 0.018)

	match d_type:
		DoorType.FLUSH:
			_append_local_box(accent_mb, orig, right, up, norm, x0, 0.0, -half_d, x1, leaf_h, half_d)
			_append_door_handle(accent_mb, orig, right, up, norm, x0, x1, leaf_h, half_d, is_right_double_leaf)

		DoorType.PANEL:
			# Outer stiles, top/bottom/mid rails, center vertical mullion, and recessed inner panels
			_append_local_frame_rect(accent_mb, orig, right, up, norm, x0, 0.0, x1, leaf_h, -half_d, half_d, stile_w)
			var mid_x: float = (x0 + x1) * 0.5
			var rail_y1: float = leaf_h * 0.42
			var rail_y2: float = leaf_h * 0.50
			_append_local_box(accent_mb, orig, right, up, norm, x0 + stile_w, rail_y1, -half_d, x1 - stile_w, rail_y2, half_d)
			_append_local_box(accent_mb, orig, right, up, norm, mid_x - stile_w * 0.4, stile_w, -half_d, mid_x + stile_w * 0.4, leaf_h - stile_w, half_d)
			# Recessed core panel
			_append_local_box(accent_mb, orig, right, up, norm, x0 + stile_w, stile_w, -recess_d, x1 - stile_w, leaf_h - stile_w, recess_d)
			_append_door_handle(accent_mb, orig, right, up, norm, x0, x1, leaf_h, half_d, is_right_double_leaf)

		DoorType.FRENCH:
			var bot_rail: float = maxf(stile_w * 1.4, 0.14)
			_append_local_box(accent_mb, orig, right, up, norm, x0, 0.0, -half_d, x1, bot_rail, half_d)
			_append_local_box(accent_mb, orig, right, up, norm, x0, leaf_h - stile_w, -half_d, x1, leaf_h, half_d)
			_append_local_box(accent_mb, orig, right, up, norm, x0, bot_rail, -half_d, x0 + stile_w, leaf_h - stile_w, half_d)
			_append_local_box(accent_mb, orig, right, up, norm, x1 - stile_w, bot_rail, -half_d, x1, leaf_h - stile_w, half_d)

			_append_local_muntin_grid(
				accent_mb, orig, right, up, norm,
				x0 + stile_w, bot_rail, x1 - stile_w, leaf_h - stile_w,
				-half_d * 0.75, half_d * 0.75, 2, 4, bar_w
			)
			_append_local_box(
				glass_mb, orig, right, up, norm,
				x0 + stile_w, bot_rail, -glass_d,
				x1 - stile_w, leaf_h - stile_w, glass_d
			)
			_append_door_handle(accent_mb, orig, right, up, norm, x0, x1, leaf_h, half_d, is_right_double_leaf)

		DoorType.DUTCH:
			var split_y: float = leaf_h * 0.50
			var gap: float = 0.012
			# Bottom half (recessed panel door)
			_append_local_frame_rect(accent_mb, orig, right, up, norm, x0, 0.0, x1, split_y - gap, -half_d, half_d, stile_w)
			_append_local_box(accent_mb, orig, right, up, norm, x0 + stile_w, stile_w, -recess_d, x1 - stile_w, split_y - gap - stile_w, recess_d)
			# Shelf ledge between Dutch halves
			_append_local_box(accent_mb, orig, right, up, norm, x0, split_y - gap, -half_d * 1.25, x1, split_y + gap, half_d * 1.25)
			# Top half (windowed with 2x2 muntin grid)
			_append_local_frame_rect(accent_mb, orig, right, up, norm, x0, split_y + gap, x1, leaf_h, -half_d, half_d, stile_w)
			_append_local_muntin_grid(
				accent_mb, orig, right, up, norm,
				x0 + stile_w, split_y + gap + stile_w, x1 - stile_w, leaf_h - stile_w,
				-half_d * 0.75, half_d * 0.75, 2, 2, bar_w
			)
			_append_local_box(
				glass_mb, orig, right, up, norm,
				x0 + stile_w, split_y + gap + stile_w, -glass_d,
				x1 - stile_w, leaf_h - stile_w, glass_d
			)
			_append_door_handle(accent_mb, orig, right, up, norm, x0, x1, leaf_h, half_d, is_right_double_leaf)

		DoorType.BARN:
			# Outer frame + vertical plank backing
			_append_local_frame_rect(accent_mb, orig, right, up, norm, x0, 0.0, x1, leaf_h, -half_d, half_d, stile_w)
			_append_local_box(accent_mb, orig, right, up, norm, x0 + stile_w, stile_w, -recess_d, x1 - stile_w, leaf_h - stile_w, recess_d)
			# Mid horizontal rail
			var mid_y: float = leaf_h * 0.48
			_append_local_box(accent_mb, orig, right, up, norm, x0 + stile_w, mid_y - stile_w * 0.45, -half_d, x1 - stile_w, mid_y + stile_w * 0.45, half_d)
			# Diagonal X-brace bars in the bottom half
			_append_diagonal_brace(accent_mb, x0 + stile_w, stile_w, x1 - stile_w, mid_y - stile_w * 0.45, half_d, bar_w * 1.4)
			_append_diagonal_brace(accent_mb, x1 - stile_w, stile_w, x0 + stile_w, mid_y - stile_w * 0.45, half_d, bar_w * 1.4)
			# Top barn-door hanger straps
			for strap_x: float in [x0 + stile_w * 0.6, x1 - stile_w * 0.6]:
				_append_local_box(accent_mb, orig, right, up, norm, strap_x - 0.025, leaf_h - 0.12, -half_d * 1.3, strap_x + 0.025, leaf_h + 0.08, half_d * 1.3)

		DoorType.LOUVERED:
			_append_local_frame_rect(accent_mb, orig, right, up, norm, x0, 0.0, x1, leaf_h, -half_d, half_d, stile_w)
			var mid_y: float = leaf_h * 0.48
			_append_local_box(accent_mb, orig, right, up, norm, x0 + stile_w, mid_y - stile_w * 0.45, -half_d, x1 - stile_w, mid_y + stile_w * 0.45, half_d)
			var slat_step: float = 0.075
			for section: Vector2 in [Vector2(stile_w, mid_y - stile_w * 0.45), Vector2(mid_y + stile_w * 0.45, leaf_h - stile_w)]:
				var sy: float = section.x + 0.02
				while sy + 0.03 <= section.y:
					_append_local_box(
						accent_mb, orig, right, up, norm,
						x0 + stile_w, sy, -half_d * 0.7,
						x1 - stile_w, sy + 0.028, half_d * 0.7
					)
					sy += slat_step
			_append_door_handle(accent_mb, orig, right, up, norm, x0, x1, leaf_h, half_d, is_right_double_leaf)

		DoorType.GLASS:
			var slim_w: float = maxf(stile_w * 0.55, 0.035)
			_append_local_frame_rect(accent_mb, orig, right, up, norm, x0, 0.0, x1, leaf_h, -half_d, half_d, slim_w)
			_append_local_box(
				glass_mb, orig, right, up, norm,
				x0 + slim_w, slim_w, -glass_d,
				x1 - slim_w, leaf_h - slim_w, glass_d
			)
			# Vertical pull bar handle
			var hx: float = (x0 + slim_w + 0.06) if is_right_double_leaf else (x1 - slim_w - 0.06)
			_append_local_box(accent_mb, orig, right, up, norm, hx - 0.015, leaf_h * 0.38, -half_d * 1.6, hx + 0.015, leaf_h * 0.62, half_d * 1.6)

		DoorType.GARAGE:
			# 4 stacked horizontal garage sections with top window row
			var sections: int = 4
			var sec_h: float = leaf_h / float(sections)
			var frame_b: float = maxf(stile_w * 0.65, 0.045)
			var cols: int = maxi(int(roundf(w / 0.65)), 2)
			var cell_w: float = (w - frame_b * float(cols + 1)) / float(cols)

			for s_i: int in range(sections):
				var sy0: float = float(s_i) * sec_h
				var sy1: float = sy0 + sec_h - 0.008
				_append_local_frame_rect(accent_mb, orig, right, up, norm, x0, sy0, x1, sy1, -half_d, half_d, frame_b)
				for c_i: int in range(cols):
					var cx0: float = x0 + frame_b + float(c_i) * (cell_w + frame_b)
					var cx1: float = cx0 + cell_w
					if c_i > 0:
						_append_local_box(accent_mb, orig, right, up, norm, cx0 - frame_b, sy0 + frame_b, -half_d, cx0, sy1 - frame_b, half_d)
					if s_i == sections - 1:
						# Top garage section has glass windows
						_append_local_box(glass_mb, orig, right, up, norm, cx0, sy0 + frame_b, -glass_d, cx1, sy1 - frame_b, glass_d)
					else:
						# Lower sections have recessed solid panels
						_append_local_box(accent_mb, orig, right, up, norm, cx0, sy0 + frame_b, -recess_d, cx1, sy1 - frame_b, recess_d)

	return _commit_two_surface_mesh(accent_mb, accent_material, glass_mb, window_material)


func _append_door_handle(
	mb: Dictionary,
	orig: Vector3,
	right: Vector3,
	up: Vector3,
	norm: Vector3,
	x0: float,
	x1: float,
	leaf_h: float,
	half_d: float,
	is_right_double_leaf: bool
) -> void:
	var w: float = x1 - x0
	var hx: float = (x0 + minf(0.09, w * 0.18)) if is_right_double_leaf else (x1 - minf(0.09, w * 0.18))
	var hy: float = clampf(0.95, leaf_h * 0.35, leaf_h * 0.55)
	_append_local_box(mb, orig, right, up, norm, hx - 0.02, hy - 0.03, -half_d * 1.75, hx + 0.02, hy + 0.03, half_d * 1.75)


func _append_diagonal_brace(
	mb: Dictionary,
	xa: float, ya: float,
	xb: float, yb: float,
	half_d: float,
	bar_w: float
) -> void:
	var dir_2d: Vector2 = Vector2(xb - xa, yb - ya).normalized()
	var perp_2d := Vector2(-dir_2d.y, dir_2d.x) * (bar_w * 0.5)

	var v0_f := Vector3(xa + perp_2d.x, ya + perp_2d.y, half_d)
	var v1_f := Vector3(xa - perp_2d.x, ya - perp_2d.y, half_d)
	var v2_f := Vector3(xb - perp_2d.x, yb - perp_2d.y, half_d)
	var v3_f := Vector3(xb + perp_2d.x, yb + perp_2d.y, half_d)
	_add_oriented_quad(mb, v0_f, v1_f, v2_f, v3_f, Vector3.BACK)

	var v0_b := Vector3(xa + perp_2d.x, ya + perp_2d.y, -half_d)
	var v1_b := Vector3(xa - perp_2d.x, ya - perp_2d.y, -half_d)
	var v2_b := Vector3(xb - perp_2d.x, yb - perp_2d.y, -half_d)
	var v3_b := Vector3(xb + perp_2d.x, yb + perp_2d.y, -half_d)
	_add_oriented_quad(mb, v1_b, v0_b, v3_b, v2_b, Vector3.FORWARD)
#endregion


#region Step 7: Roof, Wall Panel & Low-Level Mesh Buffer Helpers
func _add_double_sided_tri(mb: Dictionary, v0: Vector3, v1: Vector3, v2: Vector3, out_normal: Vector3, thickness: float) -> void:
	_add_oriented_tri(mb, v0, v1, v2, out_normal)
	var in_offset: Vector3 = -out_normal.normalized() * thickness
	_add_oriented_tri(mb, v1 + in_offset, v0 + in_offset, v2 + in_offset, -out_normal)


func _add_double_sided_quad(mb: Dictionary, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, out_normal: Vector3, thickness: float) -> void:
	_add_oriented_quad(mb, v0, v1, v2, v3, out_normal)
	var in_offset: Vector3 = -out_normal.normalized() * thickness
	_add_oriented_quad(mb, v1 + in_offset, v0 + in_offset, v3 + in_offset, v2 + in_offset, -out_normal)


func _coalesce_rectangles_2d(input_rects: Array[Rect2]) -> Array[Rect2]:
	var rects: Array[Rect2] = input_rects.duplicate()
	var merged_any: bool = true
	while merged_any:
		merged_any = false
		for i: int in range(rects.size()):
			for j: int in range(i + 1, rects.size()):
				var r1: Rect2 = rects[i]
				var r2: Rect2 = rects[j]
				if absf(r1.position.y - r2.position.y) < 0.02 and absf(r1.size.y - r2.size.y) < 0.02:
					if absf(r1.end.x - r2.position.x) < 0.02 or absf(r2.end.x - r1.position.x) < 0.02:
						rects[i] = r1.merge(r2)
						rects.remove_at(j)
						merged_any = true
						break
				if absf(r1.position.x - r2.position.x) < 0.02 and absf(r1.size.x - r2.size.x) < 0.02:
					if absf(r1.end.y - r2.position.y) < 0.02 or absf(r2.end.y - r1.position.y) < 0.02:
						rects[i] = r1.merge(r2)
						rects.remove_at(j)
						merged_any = true
						break
			if merged_any:
				break
	return rects


func _intervals_overlap(a0: float, a1: float, b0: float, b1: float) -> bool:
	return minf(a1, b1) - maxf(a0, b0) > 0.25


func _wing_pt(u: float, y: float, v: float, ridge_along_x: bool) -> Vector3:
	if ridge_along_x:
		return Vector3(v, y, u)
	return Vector3(u, y, v)


func _wing_dir(du: float, dy: float, dv: float, ridge_along_x: bool) -> Vector3:
	if ridge_along_x:
		return Vector3(dv, dy, du).normalized()
	return Vector3(du, dy, dv).normalized()


func _append_wing_slope_segment(
	mb: Dictionary,
	u0: float, y0: float,
	u1: float, y1: float,
	v_min: float, v_max: float,
	thickness: float,
	cap_u0_eave: bool,
	cap_u1_eave: bool,
	ridge_along_x: bool
) -> void:
	var b0_back: Vector3 = _wing_pt(u0, y0, v_min, ridge_along_x)
	var b0_front: Vector3 = _wing_pt(u0, y0, v_max, ridge_along_x)
	var b1_back: Vector3 = _wing_pt(u1, y1, v_min, ridge_along_x)
	var b1_front: Vector3 = _wing_pt(u1, y1, v_max, ridge_along_x)

	var t0_back: Vector3 = _wing_pt(u0, y0 + thickness, v_min, ridge_along_x)
	var t0_front: Vector3 = _wing_pt(u0, y0 + thickness, v_max, ridge_along_x)
	var t1_back: Vector3 = _wing_pt(u1, y1 + thickness, v_min, ridge_along_x)
	var t1_front: Vector3 = _wing_pt(u1, y1 + thickness, v_max, ridge_along_x)

	var out_pos_u: Vector3 = _wing_dir(1.0, 0.0, 0.0, ridge_along_x)
	var out_neg_u: Vector3 = _wing_dir(-1.0, 0.0, 0.0, ridge_along_x)
	var out_pos_v: Vector3 = _wing_dir(0.0, 0.0, 1.0, ridge_along_x)
	var out_neg_v: Vector3 = _wing_dir(0.0, 0.0, -1.0, ridge_along_x)

	_add_oriented_quad(mb, t0_front, t0_back, t1_back, t1_front, Vector3.UP)
	_add_oriented_quad(mb, b0_back, b0_front, b1_front, b1_back, Vector3.DOWN)
	_add_oriented_quad(mb, b0_front, b1_front, t1_front, t0_front, out_pos_v)
	_add_oriented_quad(mb, b1_back, b0_back, t0_back, t1_back, out_neg_v)

	if cap_u0_eave:
		_add_oriented_quad(mb, b0_back, b0_front, t0_front, t0_back, out_neg_u)
	if cap_u1_eave:
		_add_oriented_quad(mb, b1_front, b1_back, t1_back, t1_front, out_pos_u)


func _append_eave_fascia_ring_at(mb: Dictionary, min_x: float, max_x: float, min_z: float, max_z: float, y0: float, y1: float) -> void:
	_add_quad(
		mb,
		Vector3(min_x, y0, min_z),
		Vector3(max_x, y0, min_z),
		Vector3(max_x, y0, max_z),
		Vector3(min_x, y0, max_z),
		Vector3.DOWN
	)
	_add_quad(
		mb,
		Vector3(min_x, y0, max_z),
		Vector3(max_x, y0, max_z),
		Vector3(max_x, y1, max_z),
		Vector3(min_x, y1, max_z),
		Vector3.BACK
	)
	_add_quad(
		mb,
		Vector3(max_x, y0, min_z),
		Vector3(min_x, y0, min_z),
		Vector3(min_x, y1, min_z),
		Vector3(max_x, y1, min_z),
		Vector3.FORWARD
	)
	_add_quad(
		mb,
		Vector3(max_x, y0, max_z),
		Vector3(max_x, y0, min_z),
		Vector3(max_x, y1, min_z),
		Vector3(max_x, y1, max_z),
		Vector3.RIGHT
	)
	_add_quad(
		mb,
		Vector3(min_x, y0, min_z),
		Vector3(min_x, y0, max_z),
		Vector3(min_x, y1, max_z),
		Vector3(min_x, y1, min_z),
		Vector3.LEFT
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


func _commit_two_surface_mesh(mb_a: Dictionary, mat_a: Material, mb_b: Dictionary, mat_b: Material) -> ArrayMesh:
	var arr_mesh := ArrayMesh.new()

	var verts_a: PackedVector3Array = mb_a["vertices"]
	if not verts_a.is_empty():
		var arrays_a := []
		arrays_a.resize(Mesh.ARRAY_MAX)
		arrays_a[Mesh.ARRAY_VERTEX] = verts_a
		arrays_a[Mesh.ARRAY_NORMAL] = mb_a["normals"]
		arrays_a[Mesh.ARRAY_TEX_UV] = mb_a["uvs"]
		arrays_a[Mesh.ARRAY_INDEX] = mb_a["indices"]
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays_a)
		if mat_a:
			arr_mesh.surface_set_material(arr_mesh.get_surface_count() - 1, mat_a)

	var verts_b: PackedVector3Array = mb_b["vertices"]
	if not verts_b.is_empty():
		var arrays_b := []
		arrays_b.resize(Mesh.ARRAY_MAX)
		arrays_b[Mesh.ARRAY_VERTEX] = verts_b
		arrays_b[Mesh.ARRAY_NORMAL] = mb_b["normals"]
		arrays_b[Mesh.ARRAY_TEX_UV] = mb_b["uvs"]
		arrays_b[Mesh.ARRAY_INDEX] = mb_b["indices"]
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays_b)
		if mat_b:
			arr_mesh.surface_set_material(arr_mesh.get_surface_count() - 1, mat_b)

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


#region Binary Resource Saving (Meshes, Window Meshes, Door Meshes & Collision Shapes)
func save_resources_to_disk() -> void:
	var edited_root: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	if not edited_root or edited_root.scene_file_path.is_empty():
		return

	var base_dir: String = edited_root.scene_file_path.get_base_dir()
	var scene_name: String = edited_root.scene_file_path.get_file().get_basename()
	var save_dir: String = "%s/%s_%s" % [base_dir, save_subfolder_name, scene_name]

	if not DirAccess.dir_exists_absolute(save_dir):
		DirAccess.make_dir_recursive_absolute(save_dir)

	var resources_to_save: Array[Dictionary] = [
		{"suffix": "FoundationMesh", "res": baked_foundation_mesh},
		{"suffix": "WallsMesh", "res": baked_walls_mesh},
		{"suffix": "RoofMesh", "res": baked_roof_mesh},
		{"suffix": "WindowsMesh", "res": baked_windows_mesh},
		{"suffix": "FoundationCol", "res": baked_foundation_col},
		{"suffix": "WallsCol", "res": baked_walls_col},
		{"suffix": "RoofCol", "res": baked_roof_col},
		{"suffix": "WindowsCol", "res": baked_windows_col}
	]

	for item: Dictionary in resources_to_save:
		var r: Resource = item["res"]
		if r:
			var res_path: String = "%s/%s_%s_%d.res" % [save_dir, name, item["suffix"], seed_value]
			if ResourceSaver.save(r, res_path, ResourceSaver.FLAG_COMPRESS) == OK:
				r.take_over_path(res_path)

	var doors_root := get_node_or_null("DoorsContainer")
	if doors_root:
		var d_idx: int = 0
		for child: Node in doors_root.get_children():
			var door_mi := child.get_node_or_null("Door") as MeshInstance3D
			if door_mi and door_mi.mesh:
				var d_path: String = "%s/%s_DoorMesh_%d_%d.res" % [save_dir, name, d_idx, seed_value]
				if ResourceSaver.save(door_mi.mesh, d_path, ResourceSaver.FLAG_COMPRESS) == OK:
					door_mi.mesh.take_over_path(d_path)
			d_idx += 1
#endregion
