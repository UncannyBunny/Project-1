@tool
## Orchestrates ordered runtime world generation and user:// caching:
## Terrain -> Roads -> Houses -> Scene Populators (Trees) -> MultiMesh Populators (Grass) -> Per-Chunk NavMeshes.
## Pauses the SceneTree during generation while keeping 3D physics active for raycasting, and displays a dual-progress-bar loading UI.
class_name WorldGenerationManager extends Node

signal generation_started
signal generation_progress(overall_pct: float, overall_text: String, task_pct: float, task_text: String)
signal generation_finished

@export_group("Editor Actions")
@export_tool_button("Preview / Generate World in Editor", "Play") var btn_editor_generate: Callable:
	get:
		return editor_generate_world
@export_tool_button("Clear Generated Nodes (Prep for Git)", "Clear") var btn_editor_clear: Callable:
	get:
		return clear_all_generated_nodes
@export_tool_button("Wipe user:// World Cache", "Remove") var btn_wipe_cache: Callable:
	get:
		return wipe_user_cache

@export_group("Generation Pipeline Targets")
## The TerrainGenerator node in this level. If left empty, auto-discovers the first TerrainGenerator in the scene.
@export var terrain_generator: TerrainGenerator
## Ordered list of road/path projectors. If empty, auto-discovers all ToolPathProjector nodes in the scene.
@export var road_projectors: Array[ToolPathProjector] = []
## Ordered list of procedural houses. If empty, auto-discovers all ProceduralFloorplanHouse / ProceduralHouse nodes.
@export var procedural_houses: Array[Node3D] = []
## Populators that spawn scenes/colliders (e.g., Trees, Rocks, Bushes) — runs BEFORE grass so grass avoids tree trunks!
@export var scene_populators: Array[MultiMeshPopulator] = []
## Populators that spawn MultiMeshes (e.g., ProceduralGrass) — runs AFTER trees and houses!
@export var grass_populators: Array[MultiMeshPopulator] = []

@export_group("Runtime & Cache Settings")
## Automatically generates/loads the world when the scene starts in-game
@export var generate_on_ready: bool = true
## Whether to bake/load per-chunk NavigationRegion3D navmeshes as the final stage
@export var bake_chunk_navmeshes: bool = true
## Increment this number whenever you change the level layout (roads, house positions, terrain settings) to force cache regeneration
@export var cache_version: int = 1
## Subfolder inside user://world_cache/ for this level. Uses scene file basename if left empty.
@export var cache_level_id: String = ""
## Automatically clears generated preview nodes right before saving the scene in the Editor so your .tscn stays tiny for GitHub
@export var strip_generated_nodes_on_editor_save: bool = true

# Runtime state
var _is_generating: bool = false
var _was_tree_paused_before: bool = false

# Dual-Progress-Bar Runtime UI references
var _ui_layer: CanvasLayer = null
var _title_label: Label = null
var _overall_label: Label = null
var _overall_bar: ProgressBar = null
var _overall_time_label: Label = null
var _task_label: Label = null
var _task_bar: ProgressBar = null
var _task_time_label: Label = null
var _start_time_msec: int = 0
var _task_start_time_msec: int = 0
var _last_task_stage_name: String = ""


func _ready() -> void:
	# Always process even when the SceneTree is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Engine.is_editor_hint():
		return
	if generate_on_ready:
		# Defer by 1 frame so all nodes in the level scene have finished their _enter_tree / _ready setup
		call_deferred(&"run_world_generation_pipeline", false)


func _notification(what: int) -> void:
	if Engine.is_editor_hint() and what == NOTIFICATION_EDITOR_PRE_SAVE:
		if strip_generated_nodes_on_editor_save:
			clear_all_generated_nodes()


#region Editor Helper Buttons
func editor_generate_world() -> void:
	if _is_generating:
		return
	run_world_generation_pipeline(true)


func clear_all_generated_nodes() -> void:
	if _is_generating:
		push_warning("WorldGenerationManager: Cannot clear while generation is in progress.")
		return

	_auto_discover_targets()

	for pop: MultiMeshPopulator in grass_populators:
		if is_instance_valid(pop) and pop.has_method(&"clear_objects"):
			pop.clear_objects()

	for pop: MultiMeshPopulator in scene_populators:
		if is_instance_valid(pop) and pop.has_method(&"clear_objects"):
			pop.clear_objects()

	for road: ToolPathProjector in road_projectors:
		if is_instance_valid(road) and road.has_method(&"clear_generated_nodes"):
			road.clear_generated_nodes()

	for house: Node3D in procedural_houses:
		if is_instance_valid(house) and house.has_method(&"clear_cached_preview"):
			house.call(&"clear_cached_preview")

	if is_instance_valid(terrain_generator) and terrain_generator.has_method(&"clear_terrain"):
		terrain_generator.call(&"clear_terrain")

	print("WorldGenerationManager: All generated meshes, chunks, and colliders cleared from scene tree.")


func wipe_user_cache() -> void:
	var dir_path: String = get_level_cache_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		print("WorldGenerationManager: Cache directory '%s' is already empty." % dir_path)
		return

	var dir := DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir():
				dir.remove(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	print("WorldGenerationManager: Wiped all cached resources in '%s'." % dir_path)
#endregion


#region Main Ordered Pipeline
func run_world_generation_pipeline(is_editor_preview: bool = false) -> void:
	if _is_generating:
		return
	_is_generating = true
	generation_started.emit()

	_auto_discover_targets()

	var cache_dir: String = get_level_cache_dir()
	if not DirAccess.dir_exists_absolute(cache_dir):
		DirAccess.make_dir_recursive_absolute(cache_dir)

	var is_cache_valid: bool = _check_and_prepare_manifest(cache_dir)

	# Pause everything else in the game while keeping 3D physics active so raycasts and StaticBody3Ds work!
	if not is_editor_preview:
		_was_tree_paused_before = get_tree().paused
		get_tree().paused = true
		PhysicsServer3D.set_active(true)
		_create_runtime_loading_ui(is_cache_valid)
	else:
		PhysicsServer3D.set_active(true)

	_start_time_msec = Time.get_ticks_msec()
	_task_start_time_msec = _start_time_msec
	_last_task_stage_name = ""

	# Calculate total weighted stages for smooth Overall Progress Bar
	# 1: Terrain (20%), 2: Roads (15%), 3: Houses (10%), 4: Scene Populators (20%), 5: Grass Populators (15%), 6: NavMeshes (20%)
	await get_tree().process_frame

	# =========================================================================
	# STAGE 1: TERRAIN GENERATION / CACHE LOAD (0% -> 20%)
	# =========================================================================
	if is_instance_valid(terrain_generator):
		_update_ui_progress(0.0, "Stage 1/6: Building Terrain...", 0.0, "Initializing Terrain...")
		var terrain_cb := func(t_pct: float, t_text: String) -> void:
			var ov_pct: float = lerpf(0.0, 20.0, clampf(t_pct / 100.0, 0.0, 1.0))
			_update_ui_progress(ov_pct, "Stage 1/6: Building Terrain...", t_pct, t_text)

		if terrain_generator.has_method(&"generate_or_load_cached"):
			await terrain_generator.generate_or_load_cached(cache_dir, is_cache_valid, is_editor_preview, terrain_cb)
		else:
			terrain_generator.generate_terrain()

		await _wait_physics_sync(2)

	# =========================================================================
	# STAGE 2: ROADS & PATH PROJECTORS (20% -> 35%)
	# =========================================================================
	var road_count: int = road_projectors.size()
	if road_count > 0:
		for r_idx: int in range(road_count):
			var road: ToolPathProjector = road_projectors[r_idx]
			if not is_instance_valid(road):
				continue

			var base_ov: float = 20.0 + (float(r_idx) / float(road_count)) * 15.0
			var span_ov: float = 15.0 / float(road_count)
			var r_label: String = "Stage 2/6: Projecting Roads (%d/%d: %s)..." % [r_idx + 1, road_count, road.name]

			var road_cb := func(t_pct: float, t_text: String) -> void:
				var ov_pct: float = base_ov + (clampf(t_pct / 100.0, 0.0, 1.0) * span_ov)
				_update_ui_progress(ov_pct, r_label, t_pct, t_text)

			await road.generate_or_load_cached(cache_dir, is_cache_valid, is_editor_preview, road_cb)
			# Sync physics after each road so subsequent intersecting roads or decorations see its collider
			await _wait_physics_sync(2)

	# =========================================================================
	# STAGE 3: PROCEDURAL HOUSES (35% -> 45%)
	# =========================================================================
	var house_count: int = procedural_houses.size()
	if house_count > 0:
		for h_idx: int in range(house_count):
			var house: Node3D = procedural_houses[h_idx]
			if not is_instance_valid(house):
				continue

			var pct: float = (float(h_idx) / float(house_count)) * 100.0
			var ov_pct: float = lerpf(35.0, 45.0, float(h_idx) / float(house_count))
			_update_ui_progress(
				ov_pct,
				"Stage 3/6: Constructing Buildings (%d/%d)..." % [h_idx + 1, house_count],
				pct,
				"Building %s..." % house.name
			)
			await get_tree().process_frame

			if house.has_method(&"generate_or_load_cached"):
				await house.call(&"generate_or_load_cached", cache_dir, is_cache_valid, is_editor_preview)
			elif house.has_method(&"generate_house"):
				house.call(&"generate_house")

			# Tag house static bodies so populators know to keep trees/grass away from them
			_ensure_house_obstacle_groups(house)

		await _wait_physics_sync(2)

	# =========================================================================
	# STAGE 4: SCENE POPULATORS (TREES / ROCKS / PROPS) (45% -> 65%)
	# =========================================================================
	var s_pop_count: int = scene_populators.size()
	if s_pop_count > 0:
		for p_idx: int in range(s_pop_count):
			var pop: MultiMeshPopulator = scene_populators[p_idx]
			if not is_instance_valid(pop):
				continue

			var base_ov: float = 45.0 + (float(p_idx) / float(s_pop_count)) * 20.0
			var span_ov: float = 20.0 / float(s_pop_count)
			var p_label: String = "Stage 4/6: Populating Objects (%d/%d: %s)..." % [p_idx + 1, s_pop_count, pop.name]

			var pop_cb := func(t_pct: float, t_text: String) -> void:
				var ov_pct: float = base_ov + (clampf(t_pct / 100.0, 0.0, 1.0) * span_ov)
				_update_ui_progress(ov_pct, p_label, t_pct, t_text)

			if pop.has_method(&"generate_or_load_cached"):
				await pop.generate_or_load_cached(cache_dir, is_cache_valid, is_editor_preview, pop_cb)
			else:
				await pop.populate_surface()

			await _wait_physics_sync(2)

	# =========================================================================
	# STAGE 5: MULTIMESH POPULATORS (GRASS / FOLIAGE) (65% -> 80%)
	# =========================================================================
	var g_pop_count: int = grass_populators.size()
	if g_pop_count > 0:
		for g_idx: int in range(g_pop_count):
			var g_pop: MultiMeshPopulator = grass_populators[g_idx]
			if not is_instance_valid(g_pop):
				continue

			var base_ov: float = 65.0 + (float(g_idx) / float(g_pop_count)) * 15.0
			var span_ov: float = 15.0 / float(g_pop_count)
			var g_label: String = "Stage 5/6: Populating Foliage (%d/%d: %s)..." % [g_idx + 1, g_pop_count, g_pop.name]

			var g_cb := func(t_pct: float, t_text: String) -> void:
				var ov_pct: float = base_ov + (clampf(t_pct / 100.0, 0.0, 1.0) * span_ov)
				_update_ui_progress(ov_pct, g_label, t_pct, t_text)

			if g_pop.has_method(&"generate_or_load_cached"):
				await g_pop.generate_or_load_cached(cache_dir, is_cache_valid, is_editor_preview, g_cb)
			else:
				await g_pop.populate_surface()

		await _wait_physics_sync(1)

	# =========================================================================
	# STAGE 6: PER-CHUNK NAVIGATION MESH BAKING / LOADING (80% -> 100%)
	# =========================================================================
	if bake_chunk_navmeshes and is_instance_valid(terrain_generator):
		_update_ui_progress(80.0, "Stage 6/6: Baking Chunk NavMeshes...", 0.0, "Preparing NavigationRegions...")
		var nav_cb := func(t_pct: float, t_text: String) -> void:
			var ov_pct: float = lerpf(80.0, 99.0, clampf(t_pct / 100.0, 0.0, 1.0))
			_update_ui_progress(ov_pct, "Stage 6/6: Baking Chunk NavMeshes...", t_pct, t_text)

		if terrain_generator.has_method(&"bake_or_load_chunk_navmeshes"):
			await terrain_generator.bake_or_load_chunk_navmeshes(cache_dir, is_cache_valid, is_editor_preview, nav_cb)

		await _wait_physics_sync(2)

	# Save valid manifest stamp if we just built the cache
	if not is_cache_valid and not is_editor_preview:
		_write_manifest(cache_dir)

	_update_ui_progress(100.0, "World Ready!", 100.0, "Complete!")
	await get_tree().process_frame

	if not is_editor_preview:
		await _close_runtime_loading_ui()
		get_tree().paused = _was_tree_paused_before

	_is_generating = false
	generation_finished.emit()
#endregion


#region Auto-Discovery, Physics Sync & Cache Manifest Helpers
func get_level_cache_dir() -> String:
	var id_str: String = cache_level_id.strip_edges()
	if id_str.is_empty():
		var root_node: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
		if root_node and not root_node.scene_file_path.is_empty():
			id_str = root_node.scene_file_path.get_file().get_basename()
		else:
			id_str = "default_level"
	return "user://world_cache/%s" % id_str


func _compute_world_signature() -> String:
	var parts: PackedStringArray = []
	parts.append("v=%d" % cache_version)

	if is_instance_valid(terrain_generator):
		parts.append("tg=%s_%s_%d_%d" % [
			str(terrain_generator.terrain_size),
			str(terrain_generator.chunk_grid),
			terrain_generator.width_detail,
			terrain_generator.depth_detail
		])

	for road: ToolPathProjector in road_projectors:
		if is_instance_valid(road) and road.curve:
			parts.append("rd=%s_%d_%d_%.2f" % [
				road.name,
				road.seed_value,
				road.curve.get_point_count(),
				road.curve.get_baked_length()
			])

	for house: Node3D in procedural_houses:
		if is_instance_valid(house):
			var h_seed: Variant = house.get(&"seed_value")
			parts.append("hs=%s_%s_%s" % [house.name, str(house.global_position), str(h_seed)])

	for pop: MultiMeshPopulator in scene_populators:
		if is_instance_valid(pop):
			parts.append("sp=%s_%d_%.3f_%.2f" % [pop.name, pop.seed_value, pop.density_per_m2, pop.spacing])

	for gpop: MultiMeshPopulator in grass_populators:
		if is_instance_valid(gpop):
			parts.append("gp=%s_%d_%.3f" % [gpop.name, gpop.seed_value, gpop.density_per_m2])

	return "|".join(parts).sha256_text()


func _check_and_prepare_manifest(cache_dir: String) -> bool:
	var manifest_path: String = "%s/manifest.cfg" % cache_dir
	if not FileAccess.file_exists(manifest_path):
		return false

	var cfg := ConfigFile.new()
	if cfg.load(manifest_path) != OK:
		return false

	var saved_sig: String = str(cfg.get_value("cache", "signature", ""))
	var current_sig: String = _compute_world_signature()
	return saved_sig == current_sig


func _write_manifest(cache_dir: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("cache", "version", cache_version)
	cfg.set_value("cache", "signature", _compute_world_signature())
	cfg.set_value("cache", "timestamp", Time.get_datetime_string_from_system())
	cfg.save("%s/manifest.cfg" % cache_dir)


func _wait_physics_sync(frames: int = 2) -> void:
	PhysicsServer3D.set_active(true)
	for i: int in range(maxi(frames, 1)):
		await get_tree().physics_frame


func _auto_discover_targets() -> void:
	var root_node: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	if not is_instance_valid(root_node):
		root_node = get_parent()
	if not is_instance_valid(root_node):
		return

	if not is_instance_valid(terrain_generator):
		for n: Node in root_node.find_children("*", "TerrainGenerator", true, false):
			if n is TerrainGenerator:
				terrain_generator = n as TerrainGenerator
				break

	if road_projectors.is_empty():
		for n: Node in root_node.find_children("*", "ToolPathProjector", true, false):
			if n is ToolPathProjector:
				road_projectors.append(n as ToolPathProjector)

	if procedural_houses.is_empty():
		for n: Node in root_node.find_children("*", "", true, false):
			if n is ProceduralFloorplanHouse or n is ProceduralHouse:
				procedural_houses.append(n as Node3D)

	if scene_populators.is_empty() and grass_populators.is_empty():
		for n: Node in root_node.find_children("*", "MultiMeshPopulator", true, false):
			if n is MultiMeshPopulator:
				var pop := n as MultiMeshPopulator
				if pop is ProceduralGrass or pop.object_scenes.is_empty():
					grass_populators.append(pop)
				else:
					scene_populators.append(pop)


func _ensure_house_obstacle_groups(house: Node3D) -> void:
	for child: Node in house.find_children("*", "StaticBody3D", true, false):
		if child is StaticBody3D:
			var sb := child as StaticBody3D
			# Skip moving door panels so we don't mark them as static building shells if unneeded
			if sb.get_parent() and sb.get_parent().name.begins_with("Door"):
				continue
			for grp: StringName in [&"house", &"building", &"no_grass"]:
				if not sb.is_in_group(grp):
					sb.add_to_group(grp)
#endregion


#region Runtime Dual-Progress-Bar Loading UI
func _create_runtime_loading_ui(is_loading_from_cache: bool) -> void:
	if is_instance_valid(_ui_layer):
		_ui_layer.queue_free()

	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "WorldGenLoadingLayer"
	_ui_layer.layer = 125
	_ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.07, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_layer.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540.0, 240.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.12, 0.15, 0.96)
	style.border_color = Color(0.28, 0.31, 0.38, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 20.0
	style.content_margin_bottom = 20.0
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "Loading Cached World..." if is_loading_from_cache else "Generating World (First-Time Setup)..."
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_title_label)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	_overall_label = Label.new()
	_overall_label.text = "Overall Progress:"
	vbox.add_child(_overall_label)

	_overall_bar = ProgressBar.new()
	_overall_bar.min_value = 0.0
	_overall_bar.max_value = 100.0
	_overall_bar.value = 0.0
	_overall_bar.custom_minimum_size = Vector2(480.0, 24.0)
	vbox.add_child(_overall_bar)

	_overall_time_label = Label.new()
	_overall_time_label.text = "Time Elapsed: 00:00   |   Estimated Remaining: --:--"
	_overall_time_label.add_theme_Color_override("font_color", Color(0.75, 0.78, 0.82))
	_overall_time_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_overall_time_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 6.0)
	vbox.add_child(spacer)

	_task_label = Label.new()
	_task_label.text = "Current Task: Initializing..."
	vbox.add_child(_task_label)

	_task_bar = ProgressBar.new()
	_task_bar.min_value = 0.0
	_task_bar.max_value = 100.0
	_task_bar.value = 0.0
	_task_bar.custom_minimum_size = Vector2(480.0, 24.0)
	vbox.add_child(_task_bar)

	_task_time_label = Label.new()
	_task_time_label.text = "Task Elapsed: 00:00   |   Task Remaining: --:--"
	_task_time_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	_task_time_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_task_time_label)

	get_tree().root.add_child(_ui_layer)


func _update_ui_progress(
	overall_pct: float,
	overall_text: String,
	task_pct: float,
	task_text: String
) -> void:
	var now_msec: int = Time.get_ticks_msec()
	if overall_text != _last_task_stage_name:
		_last_task_stage_name = overall_text
		_task_start_time_msec = now_msec

	generation_progress.emit(overall_pct, overall_text, task_pct, task_text)

	if not is_instance_valid(_ui_layer):
		return

	if is_instance_valid(_overall_bar):
		_overall_bar.value = clampf(overall_pct, 0.0, 100.0)
	if is_instance_valid(_overall_label):
		_overall_label.text = overall_text
	if is_instance_valid(_task_bar):
		_task_bar.value = clampf(task_pct, 0.0, 100.0)
	if is_instance_valid(_task_label):
		_task_label.text = task_text

	var overall_elapsed_sec: float = float(now_msec - _start_time_msec) / 1000.0
	if is_instance_valid(_overall_time_label):
		var ov_eta_str: String = "--:--"
		if overall_pct > 1.5 and overall_Elapsed_valid(overall_elapsed_sec):
			var ov_rem: float = maxf((overall_elapsed_sec * (100.0 / overall_pct)) - overall_elapsed_sec, 0.0)
			ov_eta_str = _format_seconds_mm_ss(ov_rem)
		_overall_time_label.text = "Time Elapsed: %s   |   Estimated Remaining: %s" % [
			_format_seconds_mm_ss(overall_elapsed_sec),
			ov_eta_str
		]

	var task_elapsed_sec: float = float(now_msec - _task_start_time_msec) / 1000.0
	if is_instance_valid(_task_time_label):
		var tk_eta_str: String = "--:--"
		if task_pct > 2.0 and task_elapsed_sec > 0.05:
			var tk_rem: float = maxf((task_elapsed_sec * (100.0 / task_pct)) - task_elapsed_sec, 0.0)
			tk_eta_str = _format_seconds_mm_ss(tk_rem)
		_task_time_label.text = "Task Elapsed: %s   |   Task Remaining: %s" % [
			_format_seconds_mm_ss(task_elapsed_sec),
			tk_eta_str
		]


func overall_Elapsed_valid(sec: float) -> bool:
	return sec > 0.1


func _format_seconds_mm_ss(seconds: float) -> String:
	var total_sec: int = maxi(int(roundf(seconds)), 0)
	var mins: int = total_sec / 60
	var secs: int = total_sec % 60
	return "%02d:%02d" % [mins, secs]


func _close_runtime_loading_ui() -> void:
	if not is_instance_valid(_ui_layer):
		return
	var bg := _ui_layer.get_child(0) as CanvasItem
	if is_instance_valid(bg):
		var tw: Tween = create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(bg, "modulate:a", 0.0, 0.25)
		await tw.finished
	if is_instance_valid(_ui_layer):
		_ui_layer.queue_free()
		_ui_layer = null
#endregion
