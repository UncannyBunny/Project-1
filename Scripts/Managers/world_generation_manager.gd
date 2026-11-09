@tool
## Orchestrates ordered runtime & editor world generation and user:// caching:
## Terrain -> Roads -> Scene Populators (Trees) -> MultiMesh Populators (Grass) -> Per-Chunk NavMeshes.
## (Procedural houses are saved directly in the scene so manual edits are never overwritten.)
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
@export var terrain_generator: TerrainGenerator
@export var road_projectors: Array[ToolPathProjector] = []
@export var scene_populators: Array[MultiMeshPopulator] = []
@export var grass_populators: Array[MultiMeshPopulator] = []

@export_group("First-Time Generation Loading UI")
## Container shown only when the world is being generated for the first time
@export var generation_loading_container: CanvasItem
@export var generation_overall_bar: ProgressBar
@export var generation_overall_label: RichTextLabel
@export var generation_task_bar: ProgressBar
@export var generation_task_label: RichTextLabel
@export var overall_generating_text: String = "Generating world..."

@export_group("Cached World Loading UI (From Menu / Save Slot)")
## Container shown when loading an already-generated world from the menu (stays hidden on death/loop reload)
@export var cached_loading_container: CanvasItem
@export var cached_overall_bar: ProgressBar

@export_group("Runtime & Cache Settings")
@export var generate_on_ready: bool = true
@export var bake_chunk_navmeshes: bool = true
@export var cache_version: int = 1
@export var cache_level_id: String = ""
@export var strip_generated_nodes_on_editor_save: bool = true

# Tracks when the level scene exits so we can distinguish a direct scene reload (death/loop reset)
# from loading the level fresh via the Main Menu / Save Slot.
static var _last_level_exit_frame: int = -1000
static var _last_level_scene_path: String = ""

var _is_generating: bool = false
var _cancel_requested: bool = false
var _was_tree_paused_before: bool = false
var _active_ui_mode: int = 0 # 0 = None (Silent Reload), 1 = First-Time Dual Bar, 2 = Cached Single Bar

# Editor popup references
var _editor_dialog: AcceptDialog = null
var _ed_overall_label: Label = null
var _ed_overall_bar: ProgressBar = null
var _ed_task_label: Label = null
var _ed_task_bar: ProgressBar = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hide_all_runtime_loading_containers()

	if Engine.is_editor_hint():
		return
	if generate_on_ready:
		call_deferred(&"run_world_generation_pipeline", false)


func _exit_tree() -> void:
	_close_editor_progress_popup()
	if not Engine.is_editor_hint():
		_last_level_exit_frame = Engine.get_process_frames()
		var root_node: Node = get_tree().current_scene
		if root_node:
			_last_level_scene_path = root_node.scene_file_path


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

	if is_instance_valid(terrain_generator) and terrain_generator.has_method(&"clear_terrain"):
		terrain_generator.call(&"clear_terrain")

	print("WorldGenerationManager: Cleared terrain, roads, and populators (scene houses were kept intact).")


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
	_cancel_requested = false
	generation_started.emit()

	_auto_discover_targets()
	_ensure_existing_houses_obstacle_groups()

	var cache_dir: String = get_level_cache_dir()
	if not DirAccess.dir_exists_absolute(cache_dir):
		DirAccess.make_dir_recursive_absolute(cache_dir)

	var is_cache_valid: bool = _check_and_prepare_manifest(cache_dir)
	var is_scene_reload: bool = _is_reloading_same_scene()

	if not is_editor_preview:
		_was_tree_paused_before = get_tree().paused
		get_tree().paused = true
		PhysicsServer3D.set_active(true)
		_setup_runtime_loading_ui(is_cache_valid, is_scene_reload)
	else:
		PhysicsServer3D.set_active(true)
		_create_editor_progress_popup()

	await get_tree().process_frame

	# =========================================================================
	# STAGE 1: TERRAIN (0% -> 25%)
	# =========================================================================
	if is_instance_valid(terrain_generator) and not _cancel_requested:
		var stage_text := "Generating terrain..."
		_update_ui_progress(0.0, overall_generating_text, 0.0, stage_text)
		var terrain_cb := func(t_pct: float, _t_text: String) -> void:
			var ov_pct: float = lerpf(0.0, 25.0, clampf(t_pct / 100.0, 0.0, 1.0))
			_update_ui_progress(ov_pct, overall_generating_text, t_pct, stage_text)

		if terrain_generator.has_method(&"generate_or_load_cached"):
			await terrain_generator.call(&"generate_or_load_cached", cache_dir, is_cache_valid, is_editor_preview, terrain_cb)
		else:
			await terrain_generator.generate_terrain()

		await _wait_physics_sync(2)

	# =========================================================================
	# STAGE 2: ROADS & PATH PROJECTORS (25% -> 45%)
	# =========================================================================
	var road_count: int = road_projectors.size()
	if road_count > 0 and not _cancel_requested:
		var stage_text := "Projecting roads..."
		for r_idx: int in range(road_count):
			if _cancel_requested:
				break
			var road: ToolPathProjector = road_projectors[r_idx]
			if not is_instance_valid(road):
				continue

			var base_ov: float = 25.0 + (float(r_idx) / float(road_count)) * 20.0
			var span_ov: float = 20.0 / float(road_count)
			var base_task: float = (float(r_idx) / float(road_count)) * 100.0
			var span_task: float = 100.0 / float(road_count)

			var road_cb := func(t_pct: float, _t_text: String) -> void:
				var norm_t: float = clampf(t_pct / 100.0, 0.0, 1.0)
				_update_ui_progress(base_ov + norm_t * span_ov, overall_generating_text, base_task + norm_t * span_task, stage_text)

			if road.has_method(&"generate_or_load_cached"):
				await road.call(&"generate_or_load_cached", cache_dir, is_cache_valid, is_editor_preview, road_cb)
			elif road.has_method(&"build_complete_path"):
				_update_ui_progress(base_ov, overall_generating_text, base_task, stage_text)
				await get_tree().process_frame
				await road.build_complete_path()

			await _wait_physics_sync(2)

	# =========================================================================
	# STAGE 3: SCENE POPULATORS (TREES / ROCKS / PROPS) (45% -> 65%)
	# =========================================================================
	var s_pop_count: int = scene_populators.size()
	if s_pop_count > 0 and not _cancel_requested:
		var stage_text := "Placing objects..."
		for p_idx: int in range(s_pop_count):
			if _cancel_requested:
				break
			var pop: MultiMeshPopulator = scene_populators[p_idx]
			if not is_instance_valid(pop):
				continue

			var base_ov: float = 45.0 + (float(p_idx) / float(s_pop_count)) * 20.0
			var span_ov: float = 20.0 / float(s_pop_count)
			var base_task: float = (float(p_idx) / float(s_pop_count)) * 100.0
			var span_task: float = 100.0 / float(s_pop_count)

			var pop_cb := func(t_pct: float, _t_text: String) -> void:
				var norm_t: float = clampf(t_pct / 100.0, 0.0, 1.0)
				_update_ui_progress(base_ov + norm_t * span_ov, overall_generating_text, base_task + norm_t * span_task, stage_text)

			if pop.has_method(&"generate_or_load_cached"):
				await pop.call(&"generate_or_load_cached", cache_dir, is_cache_valid, is_editor_preview, pop_cb)
			else:
				await pop.populate_surface()

			await _wait_physics_sync(2)

	# =========================================================================
	# STAGE 4: MULTIMESH POPULATORS (GRASS / FOLIAGE) (65% -> 80%)
	# =========================================================================
	var g_pop_count: int = grass_populators.size()
	if g_pop_count > 0 and not _cancel_requested:
		var stage_text := "Adding foliage..."
		for g_idx: int in range(g_pop_count):
			if _cancel_requested:
				break
			var g_pop: MultiMeshPopulator = grass_populators[g_idx]
			if not is_instance_valid(g_pop):
				continue

			var base_ov: float = 65.0 + (float(g_idx) / float(g_pop_count)) * 15.0
			var span_ov: float = 15.0 / float(g_pop_count)
			var base_task: float = (float(g_idx) / float(g_pop_count)) * 100.0
			var span_task: float = 100.0 / float(g_pop_count)

			var g_cb := func(t_pct: float, _t_text: String) -> void:
				var norm_t: float = clampf(t_pct / 100.0, 0.0, 1.0)
				_update_ui_progress(base_ov + norm_t * span_ov, overall_generating_text, base_task + norm_t * span_task, stage_text)

			if g_pop.has_method(&"generate_or_load_cached"):
				await g_pop.call(&"generate_or_load_cached", cache_dir, is_cache_valid, is_editor_preview, g_cb)
			else:
				await g_pop.populate_surface()

		await _wait_physics_sync(1)

	# =========================================================================
	# STAGE 5: PER-CHUNK NAVIGATION MESH BAKING / LOADING (80% -> 100%)
	# =========================================================================
	if bake_chunk_navmeshes and is_instance_valid(terrain_generator) and not _cancel_requested:
		var stage_text := "Building navigation regions..."
		_update_ui_progress(80.0, overall_generating_text, 0.0, stage_text)
		var nav_cb := func(t_pct: float, _t_text: String) -> void:
			var ov_pct: float = lerpf(80.0, 99.0, clampf(t_pct / 100.0, 0.0, 1.0))
			_update_ui_progress(ov_pct, overall_generating_text, t_pct, stage_text)

		if terrain_generator.has_method(&"bake_or_load_chunk_navmeshes"):
			await terrain_generator.call(&"bake_or_load_chunk_navmeshes", cache_dir, is_cache_valid, is_editor_preview, nav_cb)

		await _wait_physics_sync(2)

	if not _cancel_requested and not is_cache_valid and not is_editor_preview:
		_write_manifest(cache_dir)

	if _cancel_requested:
		push_warning("WorldGenerationManager: World generation canceled by user.")
	else:
		_update_ui_progress(100.0, overall_generating_text, 100.0, "Complete")
		await get_tree().process_frame

	if not is_editor_preview:
		_hide_all_runtime_loading_containers()
		get_tree().paused = _was_tree_paused_before
		
		var loop_mgr: Node = get_node_or_null("/root/LoopManager")
		if loop_mgr and loop_mgr.has_method(&"preload_current_loop_scene"):
			loop_mgr.call(&"preload_current_loop_scene")
	else:
		_close_editor_progress_popup()

	_is_generating = false
	generation_finished.emit()
#endregion


#region Scene Reload Detection & User UI Node Management
func _is_reloading_same_scene() -> bool:
	var loop_mgr: Node = get_node_or_null("/root/LoopManager")
	if loop_mgr and bool(loop_mgr.get("_is_resetting")):
		return true

	var root_node: Node = get_tree().current_scene
	var cur_path: String = root_node.scene_file_path if root_node else ""
	var frames_since_exit: int = Engine.get_process_frames() - _last_level_exit_frame
	if not cur_path.is_empty() and cur_path == _last_level_scene_path and frames_since_exit <= 5:
		return true

	return false


func _setup_runtime_loading_ui(is_cache_valid: bool, is_scene_reload: bool) -> void:
	_hide_all_runtime_loading_containers()

	if is_scene_reload and is_cache_valid:
		_active_ui_mode = 0
		return

	if not is_cache_valid:
		_active_ui_mode = 1
		if is_instance_valid(generation_loading_container):
			generation_loading_container.process_mode = Node.PROCESS_MODE_ALWAYS
			generation_loading_container.visible = true
		if is_instance_valid(generation_overall_bar):
			generation_overall_bar.value = 0.0
		if is_instance_valid(generation_task_bar):
			generation_task_bar.value = 0.0
		if is_instance_valid(generation_overall_label) and not overall_generating_text.is_empty():
			generation_overall_label.text = overall_generating_text
		if is_instance_valid(generation_task_label):
			generation_task_label.text = ""
	else:
		_active_ui_mode = 2
		if is_instance_valid(cached_loading_container):
			cached_loading_container.process_mode = Node.PROCESS_MODE_ALWAYS
			cached_loading_container.visible = true
		if is_instance_valid(cached_overall_bar):
			cached_overall_bar.value = 0.0


func _hide_all_runtime_loading_containers() -> void:
	_active_ui_mode = 0
	if is_instance_valid(generation_loading_container):
		generation_loading_container.visible = false
	if is_instance_valid(cached_loading_container):
		cached_loading_container.visible = false


func _update_ui_progress(
	overall_pct: float,
	overall_text: String,
	task_pct: float,
	task_text: String
) -> void:
	generation_progress.emit(overall_pct, overall_text, task_pct, task_text)

	var clamped_ov: float = clampf(overall_pct, 0.0, 100.0)
	var clamped_tk: float = clampf(task_pct, 0.0, 100.0)

	if _active_ui_mode == 1:
		if is_instance_valid(generation_overall_bar):
			generation_overall_bar.value = clamped_ov
		if is_instance_valid(generation_overall_label) and not overall_text.is_empty():
			generation_overall_label.text = overall_text
		if is_instance_valid(generation_task_bar):
			generation_task_bar.value = clamped_tk
		if is_instance_valid(generation_task_label):
			generation_task_label.text = task_text

	elif _active_ui_mode == 2:
		if is_instance_valid(cached_overall_bar):
			cached_overall_bar.value = clamped_ov

	if is_instance_valid(_editor_dialog):
		if is_instance_valid(_ed_overall_bar):
			_ed_overall_bar.value = clamped_ov
		if is_instance_valid(_ed_overall_label):
			_ed_overall_label.text = overall_text
		if is_instance_valid(_ed_task_bar):
			_ed_task_bar.value = clamped_tk
		if is_instance_valid(_ed_task_label):
			_ed_task_label.text = task_text
#endregion


#region Editor Progress Popup (Simplified)
func _create_editor_progress_popup() -> void:
	_close_editor_progress_popup()

	_editor_dialog = AcceptDialog.new()
	_editor_dialog.title = "Generating World Preview..."
	_editor_dialog.dialog_hide_on_ok = false
	_editor_dialog.get_ok_button().text = "Cancel"
	_editor_dialog.unresizable = true
	_editor_dialog.size = Vector2i(440, 180)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(410.0, 120.0)
	vbox.add_theme_constant_override("separation", 6)

	_ed_overall_label = Label.new()
	_ed_overall_label.text = overall_generating_text
	vbox.add_child(_ed_overall_label)

	_ed_overall_bar = ProgressBar.new()
	_ed_overall_bar.min_value = 0.0
	_ed_overall_bar.max_value = 100.0
	_ed_overall_bar.value = 0.0
	_ed_overall_bar.custom_minimum_size = Vector2(400.0, 22.0)
	vbox.add_child(_ed_overall_bar)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 4.0)
	vbox.add_child(spacer)

	_ed_task_label = Label.new()
	_ed_task_label.text = "Initializing..."
	vbox.add_child(_ed_task_label)

	_ed_task_bar = ProgressBar.new()
	_ed_task_bar.min_value = 0.0
	_ed_task_bar.max_value = 100.0
	_ed_task_bar.value = 0.0
	_ed_task_bar.custom_minimum_size = Vector2(400.0, 22.0)
	vbox.add_child(_ed_task_bar)

	_editor_dialog.add_child(vbox)
	_editor_dialog.confirmed.connect(_on_editor_popup_cancel_pressed)
	_editor_dialog.canceled.connect(_on_editor_popup_cancel_pressed)

	get_tree().root.add_child(_editor_dialog)
	_editor_dialog.popup_centered()


func _on_editor_popup_cancel_pressed() -> void:
	_cancel_requested = true
	_is_generating = false
	_close_editor_progress_popup()


func _close_editor_progress_popup() -> void:
	if is_instance_valid(_editor_dialog):
		_editor_dialog.hide()
		_editor_dialog.queue_free()
		_editor_dialog = null
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
	# Priority 1: Search children/descendants of WorldGenerationManager itself
	# Priority 2: Fallback to scene root if none are parented directly under WorldGenerationManager
	var search_roots: Array[Node] = [self]
	var scene_root: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	if is_instance_valid(scene_root) and scene_root != self:
		search_roots.append(scene_root)
	elif is_instance_valid(get_parent()) and get_parent() != self:
		search_roots.append(get_parent())

	if not is_instance_valid(terrain_generator):
		for root_n: Node in search_roots:
			for n: Node in root_n.find_children("*", "TerrainGenerator", true, false):
				if n is TerrainGenerator:
					terrain_generator = n as TerrainGenerator
					break
			if is_instance_valid(terrain_generator):
				break

	road_projectors = road_projectors.filter(func(r: ToolPathProjector) -> bool: return is_instance_valid(r))
	scene_populators = scene_populators.filter(func(p: MultiMeshPopulator) -> bool: return is_instance_valid(p))
	grass_populators = grass_populators.filter(func(p: MultiMeshPopulator) -> bool: return is_instance_valid(p))

	for root_n: Node in search_roots:
		var is_self_branch: bool = (root_n == self)

		if is_self_branch or road_projectors.is_empty():
			for n: Node in root_n.find_children("*", "ToolPathProjector", true, false):
				if n is ToolPathProjector and not road_projectors.has(n as ToolPathProjector):
					road_projectors.append(n as ToolPathProjector)

		if is_self_branch or (scene_populators.is_empty() and grass_populators.is_empty()):
			for n: Node in root_n.find_children("*", "MultiMeshPopulator", true, false):
				if n is MultiMeshPopulator:
					var pop := n as MultiMeshPopulator
					if pop is ProceduralGrass or pop.object_scenes.is_empty():
						if not grass_populators.has(pop):
							grass_populators.append(pop)
					else:
						if not scene_populators.has(pop):
							scene_populators.append(pop)


## Ensures any pre-existing houses saved in the scene still have the obstacle groups needed by Trees, Grass, and NavMeshes
func _ensure_existing_houses_obstacle_groups() -> void:
	var root_node: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	if not is_instance_valid(root_node):
		return

	for n: Node in root_node.find_children("*", "", true, false):
		if n is ProceduralFloorplanHouse or n is ProceduralHouse:
			for child: Node in n.find_children("*", "StaticBody3D", true, false):
				if child is StaticBody3D:
					var sb := child as StaticBody3D
					if sb is DoorComponent or (sb.get_parent() and sb.get_parent() is DoorComponent):
						continue
					for grp: StringName in [&"house", &"building", &"no_grass"]:
						if not sb.is_in_group(grp):
							sb.add_to_group(grp)
#endregion
