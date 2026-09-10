class_name TacticalBattle
extends Node2D

const OpportunityAttackSystemScript = preload("res://scripts/opportunity_attack_system.gd")
const BattleMapDefinitionScript = preload("res://scripts/battle_map_definition.gd")
const BattleMapScript = preload("res://scripts/battle_map.gd")
const AbilityCasterMovementScript = preload("res://scripts/ability_caster_movement.gd")
const DEV_AI_RESTORE_CONTEXT := "_dev_ai_history_restore"
const ABILITY_SHORTCUT_ACTIONS := [
	&"battle_ability_1",
	&"battle_ability_2",
	&"battle_ability_3",
	&"battle_ability_4",
	&"battle_ability_5",
	&"battle_ability_6",
	&"battle_ability_7",
	&"battle_ability_8",
	&"battle_ability_9",
]

signal return_to_level_select_requested
signal battle_reload_requested(payload: Dictionary)
signal unit_name_visibility_changed(visible: bool)
signal battle_finished(victory: bool, party_results: Array[Dictionary], inventory: Array[String])

## Optional run entry state. Assigned before this battle enters the scene tree.
var run_party_input: Array[Dictionary] = []
var run_inventory_input: Array[String] = []
var run_encounter: RunEncounterDefinition
## Active run room; carried through developer reloads by MapManager.
var run_node_id: int = -1
## Live party health for a developer fresh restart, keyed by stable unit ID.
var run_restart_health_input: Dictionary = {}
## Concrete generated roster, committed by RunController before a run battle opens.
var template_setup_input: Dictionary = {}
var initialization_error: String = ""
var _run_result_emitted := false
var _combat_finalized := false
var _pending_defeated_turn_unit: TacticalCharacter
var _combat_finalization_queued := false

@export_category("Battle Map")
@export var map_definition: BattleMapDefinitionScript
@export var center_camera_on_start := true
@export_category("Battle Presentation")
@export var unit_names_visible := true
@export_category("Developer Tools")
## Deprecated compatibility property. Developer tools are always available.
var enable_dev_tools := true
@export var dev_tool_catalog: DevToolCatalog
@export_range(1, 10, 1) var ai_debug_candidate_count := 5
@export_range(1, 100, 1) var ai_debug_history_limit := 30

@onready var map_container: Node2D = $MapContainer
@onready var turn_manager: TurnManager = $TurnManager
@onready var tactical_camera: TacticalCameraController = $TacticalCamera
@onready var turn_order_bar: TurnOrderBar = $HUD/TurnOrderBar
@onready var ability_bar: AbilityBar = $HUD/AbilityBar
@onready var target_selection_panel: AbilityTargetSelectionPanel = $HUD/AbilityTargetSelectionPanel
@onready var general_inventory: GeneralInventory = $GeneralInventory
@onready var names_button: Button = $HUD/TopRightActions/NamesButton
@onready var inventory_button: Button = $HUD/TopRightActions/InventoryButton
@onready var restart_button: Button = $HUD/TopRightActions/RestartButton
@onready var levels_button: Button = $HUD/TopRightActions/LevelsButton
@onready var inventory_screen: InventoryScreen = $HUD/InventoryScreen
@onready var return_to_levels_dialog: ConfirmationDialog = $HUD/ReturnToLevelsDialog
@onready var end_turn_button: Button = $HUD/EndTurnButton
@onready var dev_button: Button = $HUD/TopRightActions/DevButton
@onready var dev_mode_panel: DevModePanel = $HUD/DevModePanel
@onready var dev_terrain_editor: DevTerrainEditor = $DevTerrainEditor

var _pathfinder: GridPathfinder
var _enemy_ai_planner: EnemyAIPlanner
var _ability_targeting: AbilityTargeting
var _ability_executor: AbilityExecutor
var battle_map: BattleMapScript
var grid: IsometricGrid
var terrain: TacticalTerrain
var walls_container: Node2D
var characters_container: Node2D
var _characters: Array[TacticalCharacter] = []
var _walls: Array[TacticalWall] = []
var _selected_character: TacticalCharacter
var _selected_ability: AbilityDefinition
var _selected_hit_targets: Array[TacticalCharacter] = []
var _reachable_cells: Dictionary = {}
var _ability_range_cells: Dictionary = {}
var _ability_target_cells: Dictionary = {}
var _hovered_cell := Vector2i.ZERO
var _has_hovered_cell := false
var _movement_locked := true
var _last_mouse_screen_position := Vector2.ZERO
var _has_mouse_screen_position := false
var _ai_debug_history: Array[String] = []
var _ai_debug_checkpoints: Array[Dictionary] = []
var _combat_over := false
var _combat_result_text := ""
var _return_dialog_paused_battle := false
var pending_restore_payload: Dictionary = {}
var _dev_open := false
var _dev_dirty := false
var _dev_open_pending := false
var _dev_drag_unit: TacticalCharacter
var _dev_drag_origin := Vector2i.ZERO
var _dev_drag_start_screen := Vector2.ZERO
var _dev_dragging := false
var _dev_palette_scene: PackedScene
var _restored_ai_turn_pending := false
var _pending_ai_history_cutoff := -1
var _pending_ai_history_scroll_position := -1
var initialization_succeeded := false
var _token_view_enabled := false
var _token_view_has_focus := true
var _held_token_ctrl_locations: Dictionary = {}


func _ready() -> void:
	get_window().focus_exited.connect(_on_token_view_focus_exited)
	get_window().focus_entered.connect(_on_token_view_focus_entered)
	_sync_token_view()
	var ai_restore_context: Dictionary = {}
	var raw_ai_restore_context: Variant = pending_restore_payload.get(DEV_AI_RESTORE_CONTEXT, {})
	if raw_ai_restore_context is Dictionary:
		ai_restore_context = raw_ai_restore_context
	restart_button.pressed.connect(_on_restart_button_pressed)
	levels_button.pressed.connect(_on_levels_button_pressed)
	return_to_levels_dialog.confirmed.connect(_on_return_to_levels_confirmed)
	return_to_levels_dialog.canceled.connect(_on_return_to_levels_canceled)
	names_button.toggled.connect(_on_names_button_toggled)
	if not _instantiate_battle_map():
		_combat_over = true
		_combat_result_text = "Invalid Level"
		_movement_locked = true
		_refresh_ability_bar()
		_update_turn_hud()
		return
	var authored_environment := _capture_environment_setup()
	if map_definition is BattleMapTemplateDefinition and pending_restore_payload.is_empty():
		if not _prepare_template_characters():
			return
	if run_encounter != null:
		if pending_restore_payload.is_empty() and not _prepare_run_characters():
			return
		restart_button.hide()
		levels_button.text = "Save & Exit"
		return_to_levels_dialog.dialog_text = "Return to the menu? This encounter will restart from its entry checkpoint when you continue."
	if not pending_restore_payload.is_empty():
		var pending_setup: Dictionary = pending_restore_payload.get("setup", {})
		_replace_units_from_setup(pending_setup.get("units", []))
		_replace_environment_from_setup(pending_setup)
	_pathfinder = GridPathfinder.new(grid.grid_size)
	_enemy_ai_planner = EnemyAIPlanner.new()
	_ability_targeting = AbilityTargeting.new(grid.grid_size)
	_ability_executor = AbilityExecutor.new()
	_ability_executor.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_ability_executor)
	turn_manager.turn_starting.connect(_on_turn_starting)
	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.turn_ended.connect(_on_turn_ended)
	turn_manager.turn_order_changed.connect(_on_turn_order_changed)
	turn_manager.round_started.connect(_on_round_started)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	ability_bar.ability_selected.connect(_on_ability_selected)
	target_selection_panel.fire_requested.connect(_begin_selected_targets_cast)
	target_selection_panel.cancel_requested.connect(_cancel_ability_targeting)
	target_selection_panel.target_removed.connect(_remove_hit_target)
	inventory_button.toggled.connect(_on_inventory_button_toggled)
	inventory_screen.closed.connect(_on_inventory_screen_closed)
	dev_button.pressed.connect(_on_dev_button_pressed)
	dev_mode_panel.play_requested.connect(_on_dev_play_requested)
	dev_mode_panel.save_requested.connect(_on_dev_save_requested)
	dev_mode_panel.load_payload_requested.connect(_on_dev_load_payload_requested)
	dev_mode_panel.ai_history_restore_requested.connect(_on_ai_history_restore_requested)
	dev_mode_panel.selected_unit_deleted.connect(_on_dev_delete_selected)
	dev_mode_panel.selected_unit_heal_requested.connect(_on_dev_heal_selected)
	dev_mode_panel.unit_setup_changed.connect(_on_dev_setup_changed)
	dev_mode_panel.unit_palette_drag_started.connect(_on_dev_palette_drag_started)
	dev_mode_panel.terrain_brush_changed.connect(_on_dev_terrain_brush_changed)
	dev_mode_panel.terrain_undo_requested.connect(dev_terrain_editor.undo)
	dev_mode_panel.terrain_redo_requested.connect(dev_terrain_editor.redo)
	dev_mode_panel.terrain_reset_requested.connect(dev_terrain_editor.reset_to_map)
	dev_mode_panel.active_tab_changed.connect(_on_dev_active_tab_changed)
	dev_terrain_editor.environment_refresh_requested.connect(_refresh_environment_after_edit)
	dev_terrain_editor.environment_changed.connect(_on_dev_setup_changed)
	dev_terrain_editor.history_changed.connect(dev_mode_panel.set_terrain_history_state)
	dev_terrain_editor.message_requested.connect(dev_mode_panel.show_message)
	terrain.terrain_changed.connect(_on_terrain_changed)

	_collect_and_initialize_characters()
	if run_encounter != null:
		if pending_restore_payload.is_empty():
			_restore_run_party()
		elif bool(pending_restore_payload.get("runtime", {}).get("fresh_start", false)):
			_restore_run_restart_party()
	_apply_unit_name_visibility()
	_initialize_walls()
	terrain.initialize(grid, _get_wall_cells())
	dev_terrain_editor.setup(
		grid,
		terrain,
		walls_container,
		_characters,
		authored_environment
	)

	if center_camera_on_start:
		tactical_camera.position = grid.position + grid.get_local_bounds().get_center()
	dev_button.show()
	dev_mode_panel.setup(dev_tool_catalog, terrain.palette)
	dev_mode_panel.close_panel()
	_restore_ai_history_context(ai_restore_context)
	_refresh_ai_debug_history()
	var runtime_restored := true
	if not pending_restore_payload.is_empty() and not bool(
		pending_restore_payload.get("runtime", {}).get("fresh_start", false)
	):
		runtime_restored = _restore_runtime_state(pending_restore_payload.get("runtime", {}))
	elif not _check_combat_end():
		turn_manager.start_combat(_characters)
	if not runtime_restored:
		return
	inventory_screen.setup(general_inventory, _get_living_friendlies())
	_update_turn_hud()
	initialization_succeeded = true
	if _combat_over:
		_queue_run_result()
	if not ai_restore_context.is_empty():
		_restored_ai_turn_pending = (
			not _combat_over
			and is_instance_valid(turn_manager.current_unit)
			and not turn_manager.current_unit.is_friendly()
		)
		_open_restored_ai_checkpoint.call_deferred()


func _exit_tree() -> void:
	dev_terrain_editor.cancel_stroke()
	if grid != null:
		grid.clear_dev_brush_preview()
	if _dev_open and get_tree() != null:
		tactical_camera.set_dev_mode_pan_enabled(false)
		get_tree().paused = false
	_resume_after_return_dialog()


func shutdown_battle() -> void:
	_clear_hit_selection()
	if _dev_open and get_tree() != null:
		tactical_camera.set_dev_mode_pan_enabled(false)
		get_tree().paused = false
	_dev_open = false
	dev_terrain_editor.cancel_stroke()
	if grid != null:
		grid.clear_dev_brush_preview()
	_resume_after_return_dialog()
	if _combat_over and turn_manager.current_unit == null:
		return
	_combat_over = true
	_movement_locked = true
	_selected_character = null
	_selected_ability = null
	turn_manager.stop_combat()
	if grid != null:
		grid.clear_overlays()
	set_process(false)


func _instantiate_battle_map() -> bool:
	if map_definition == null or map_definition.map_scene == null:
		push_error("TacticalBattle requires a configured BattleMapDefinition.")
		return false
	var instance := map_definition.map_scene.instantiate()
	if not instance is BattleMapScript:
		instance.free()
		push_error("Level scene must use BattleMap as its root type.")
		return false
	map_container.add_child(instance)
	battle_map = instance as BattleMapScript
	if not battle_map.is_configured():
		push_error("Level scene is missing one or more required map containers.")
		return false
	grid = battle_map.get_grid()
	terrain = battle_map.get_terrain()
	walls_container = battle_map.get_walls()
	characters_container = battle_map.get_characters()
	return true


func _replace_units_from_setup(raw_units) -> void:
	if not raw_units is Array:
		return
	for child in characters_container.get_children():
		if child is TacticalCharacter:
			characters_container.remove_child(child)
			child.free()
	for raw_state in raw_units:
		if not raw_state is Dictionary:
			continue
		var state: Dictionary = raw_state
		var scene_path := str(state.get("scene", ""))
		var unit_scene := load(scene_path) as PackedScene
		if unit_scene == null:
			continue
		var instance := unit_scene.instantiate()
		if not instance is TacticalCharacter:
			instance.free()
			continue
		var character := instance as TacticalCharacter
		character.name = str(state.get("name", "Unit"))
		character.apply_setup_state(state)
		characters_container.add_child(character)


func _collect_and_initialize_characters() -> void:
	_characters.clear()
	var used_ids := {}
	for child in characters_container.get_children():
		if not child is TacticalCharacter:
			continue
		var character := child as TacticalCharacter
		if run_encounter != null and character.is_friendly():
			character.permanent_defeat = true
		character.scenario_unit_id = _make_unique_unit_id(character, used_ids)
		used_ids[character.scenario_unit_id] = true
		_characters.append(character)
		character.initialize(grid)
		character.set_unit_name_visible(unit_names_visible)
		character.set_token_view_enabled(_token_view_enabled)
		_connect_character(character)


func _connect_character(character: TacticalCharacter) -> void:
	character.passive_context_changed.connect(_queue_passive_refresh)
	character.passive_abilities_changed.connect(_queue_passive_refresh)
	character.class_progression_changed.connect(_on_character_class_progression_changed.bind(character))
	character.movement_remaining_changed.connect(
		_on_unit_movement_changed.bind(character)
	)
	character.ability_availability_changed.connect(
		_on_unit_ability_availability_changed.bind(character)
	)
	character.statuses_changed.connect(
		_on_character_statuses_changed.bind(character)
	)
	character.cell_entered.connect(_on_character_cell_entered)
	character.defeated.connect(_on_character_defeated)
	character.form_changed.connect(_on_character_form_changed)
	character.equipment_changed.connect(
		_on_character_equipment_changed.bind(character)
	)


func _make_unique_unit_id(character: TacticalCharacter, used_ids: Dictionary) -> String:
	var base := character.scenario_unit_id.strip_edges()
	if base.is_empty():
		base = str(character.name).to_snake_case()
	if base.is_empty():
		base = "unit"
	var candidate := base
	var suffix := 2
	while used_ids.has(candidate):
		candidate = "%s_%d" % [base, suffix]
		suffix += 1
	return candidate


func capture_save_payload(fresh_start := false) -> Dictionary:
	var setup_units: Array[Dictionary] = []
	var runtime_units: Array[Dictionary] = []
	for character in _characters:
		if not is_instance_valid(character):
			continue
		var setup := character.capture_setup_state()
		if fresh_start and run_encounter != null and character.is_friendly():
			setup.complete_equipment = true
			setup.equipment = character.capture_runtime_state().equipped_items
		setup_units.append(setup)
		if not fresh_start:
			runtime_units.append(character.capture_runtime_state())
	var wall_cells: Array[Array] = []
	for cell: Vector2i in _get_wall_cells().keys():
		wall_cells.append([cell.x, cell.y])
	wall_cells.sort_custom(func(a: Array, b: Array) -> bool:
		return int(a[1]) < int(b[1]) or (int(a[1]) == int(b[1]) and int(a[0]) < int(b[0]))
	)
	var environment := _capture_environment_setup()
	var runtime := {"fresh_start": true} if fresh_start else {
		"fresh_start": false,
		"units": runtime_units,
		"inventory": general_inventory.capture_state(),
		"turn": turn_manager.capture_state(_characters, _is_dev_stable()),
		"combat_over": _combat_over,
		"combat_result": _combat_result_text,
		"combat_finalized": _combat_finalized,
		"movement_locked": _movement_locked,
	}
	return {
		"schema_version": ScenarioSaveStore.SCHEMA_VERSION,
		"map_definition": map_definition.get_save_path() if map_definition != null else "",
		"metadata": {
			"name": "",
			"map_name": map_definition.display_name if map_definition != null else "Unknown Map",
			"round": 1 if fresh_start else turn_manager.round_number,
			"saved_at": "",
		},
		"setup": {
			"grid_size": [grid.grid_size.x, grid.grid_size.y],
			"wall_cells": wall_cells,
			"terrain": environment.terrain,
			"walls": environment.walls,
			"units": setup_units,
		},
		"runtime": runtime,
	}


func _restore_runtime_state(runtime: Dictionary) -> bool:
	var units_by_id := {}
	for character in _characters:
		units_by_id[character.scenario_unit_id] = character
	for raw_state in runtime.get("units", []):
		if not raw_state is Dictionary:
			continue
		var state: Dictionary = raw_state
		var character := units_by_id.get(str(state.get("id", ""))) as TacticalCharacter
		if character != null:
			character.restore_runtime_state(state, units_by_id)
	general_inventory.restore_state(runtime.get("inventory", []))
	_combat_over = bool(runtime.get("combat_over", false))
	_combat_result_text = str(runtime.get("combat_result", ""))
	_combat_finalized = bool(runtime.get("combat_finalized", false)) and _combat_over
	_movement_locked = bool(runtime.get("movement_locked", _combat_over))
	if not turn_manager.restore_state(runtime.get("turn", {}), units_by_id):
		push_error("Could not restore the saved turn order.")
		_combat_over = true
		_movement_locked = true
		return false
	if not _combat_over and turn_manager.is_player_turn():
		_selected_character = turn_manager.current_unit
		_refresh_reachable_cells()
	else:
		clear_selection()
	_refresh_ability_bar()
	_update_turn_hud()
	return true


func _input(event: InputEvent) -> void:
	_track_token_view_input(event)
	_sync_token_view()
	if _handle_battle_shortcut(event):
		get_viewport().set_input_as_handled()
		return
	if not _dev_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if dev_mode_panel.blocks_board_shortcuts():
			return
		if event.keycode == KEY_DELETE and dev_mode_panel.can_delete_selected_with_shortcut():
			_on_dev_delete_selected()
		elif event.keycode == KEY_ESCAPE:
			_on_dev_play_requested()
		return
	if not event is InputEventMouse:
		return
	if dev_mode_panel.has_open_dialog():
		return
	var mouse_event := event as InputEventMouse
	if dev_mode_panel.is_terrain_tab_active():
		_handle_dev_terrain_input(event)
		return
	if not dev_mode_panel.is_unit_tab_active():
		return
	if _dev_palette_scene != null:
		if event is InputEventMouseMotion:
			_preview_dev_drop(mouse_event.position, null)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_finish_palette_drop(mouse_event.position)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_unit_drag(mouse_event.position)
		else:
			_finish_unit_drag(mouse_event.position)
	elif event is InputEventMouseMotion and is_instance_valid(_dev_drag_unit):
		if mouse_event.position.distance_to(_dev_drag_start_screen) >= 6.0:
			_dev_dragging = true
			_preview_dev_drop(mouse_event.position, _dev_drag_unit)


func _handle_battle_shortcut(event: InputEvent) -> bool:
	var ends_turn := event.is_action_pressed(&"battle_end_turn")
	var requested_slot := -1
	if not ends_turn:
		for slot_index in range(ABILITY_SHORTCUT_ACTIONS.size()):
			if event.is_action_pressed(ABILITY_SHORTCUT_ACTIONS[slot_index]):
				requested_slot = slot_index
				break
	if not ends_turn and requested_slot < 0:
		return false

	# Battle keys stay consumed while an overlay blocks their gameplay action so
	# keyboard focus cannot pass Space through to Restart, Levels, or another HUD button.
	if (
		_dev_open
		or get_tree() == null
		or get_tree().paused
		or inventory_screen.visible
		or return_to_levels_dialog.visible
	):
		return true
	var is_echo := event is InputEventKey and (event as InputEventKey).echo
	if ends_turn:
		if not is_echo:
			_on_end_turn_pressed()
		return true
	if not is_echo:
		ability_bar.activate_slot(requested_slot)
	return true


func _handle_dev_terrain_input(event: InputEventMouse) -> void:
	var screen_position := event.position
	if event is InputEventMouseMotion:
		if dev_mode_panel.is_pointer_over_drawer(screen_position):
			grid.clear_dev_brush_preview()
			return
		var motion := event as InputEventMouseMotion
		var cell := grid.global_to_grid(_screen_to_world(screen_position))
		var force_erase := bool(motion.button_mask & MOUSE_BUTTON_MASK_RIGHT)
		var preview := dev_terrain_editor.get_brush_preview(cell, force_erase)
		grid.show_dev_brush_preview(cell, preview.color, preview.valid)
		if motion.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT):
			dev_terrain_editor.update_stroke(cell, force_erase)
		return
	if not event is InputEventMouseButton:
		return
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT and button.button_index != MOUSE_BUTTON_RIGHT:
		return
	var force_erase := button.button_index == MOUSE_BUTTON_RIGHT
	if button.pressed:
		if dev_mode_panel.is_pointer_over_drawer(screen_position):
			return
		var cell := grid.global_to_grid(_screen_to_world(screen_position))
		dev_terrain_editor.begin_stroke(cell, force_erase)
		var preview := dev_terrain_editor.get_brush_preview(cell, force_erase)
		grid.show_dev_brush_preview(cell, preview.color, preview.valid)
	else:
		dev_terrain_editor.end_stroke()


func _begin_unit_drag(screen_position: Vector2) -> void:
	if dev_mode_panel.is_pointer_over_drawer(screen_position):
		return
	var character := _get_character_at_global_point(_screen_to_world(screen_position))
	if character == null:
		dev_mode_panel.clear_unit_selection()
		grid.clear_overlays()
		return
	_dev_drag_unit = character
	_dev_drag_origin = character.grid_cell
	_dev_drag_start_screen = screen_position
	_dev_dragging = false
	dev_mode_panel.select_unit(character)
	grid.show_reachable(character.grid_cell, {})


func _finish_unit_drag(screen_position: Vector2) -> void:
	if not is_instance_valid(_dev_drag_unit):
		return
	var character := _dev_drag_unit
	_dev_drag_unit = null
	if not _dev_dragging:
		grid.show_reachable(character.grid_cell, {})
		return
	var cell := grid.global_to_grid(_screen_to_world(screen_position))
	if dev_mode_panel.is_pointer_over_drawer(screen_position) or not _is_valid_dev_cell(cell, character):
		dev_mode_panel.show_message("That cell is blocked or occupied.", true)
	else:
		character.set_grid_cell_immediate(cell)
		_on_dev_setup_changed()
		dev_mode_panel.show_message("Moved %s." % _character_display_name(character))
	grid.clear_overlays()
	grid.show_reachable(character.grid_cell, {})


func _preview_dev_drop(screen_position: Vector2, except_character: TacticalCharacter) -> void:
	if dev_mode_panel.is_pointer_over_drawer(screen_position):
		grid.clear_overlays()
		return
	var cell := grid.global_to_grid(_screen_to_world(screen_position))
	var origin := except_character.grid_cell if is_instance_valid(except_character) else cell
	grid.show_ability_targets(origin, {}, {})
	grid.show_ability_preview(cell, [], [], _is_valid_dev_cell(cell, except_character))


func _finish_palette_drop(screen_position: Vector2) -> void:
	var unit_scene := _dev_palette_scene
	_dev_palette_scene = null
	grid.clear_overlays()
	if dev_mode_panel.is_pointer_over_drawer(screen_position):
		dev_mode_panel.show_message("Drag a unit onto the board.", true)
		return
	var cell := grid.global_to_grid(_screen_to_world(screen_position))
	if not _is_valid_dev_cell(cell):
		dev_mode_panel.show_message("That cell is blocked or occupied.", true)
		return
	_add_dev_unit(unit_scene, cell)


func _add_dev_unit(unit_scene: PackedScene, cell: Vector2i) -> void:
	if unit_scene == null:
		return
	var instance := unit_scene.instantiate()
	if not instance is TacticalCharacter:
		instance.free()
		dev_mode_panel.show_message("The selected scene is not a tactical unit.", true)
		return
	var character := instance as TacticalCharacter
	character.starting_grid_cell = cell
	character.scenario_unit_id = _new_dev_unit_id(unit_scene)
	if run_encounter != null and character.is_friendly():
		character.permanent_defeat = true
	characters_container.add_child(character, true)
	character.initialize(grid)
	character.set_unit_name_visible(unit_names_visible)
	character.set_token_view_enabled(_token_view_enabled)
	_connect_character(character)
	_characters.append(character)
	dev_terrain_editor.set_characters(_characters)
	dev_mode_panel.select_unit(character)
	_on_dev_setup_changed()
	dev_mode_panel.show_message("Added %s." % _character_display_name(character))


func _new_dev_unit_id(unit_scene: PackedScene) -> String:
	var base := "%s_%d" % [
		unit_scene.resource_path.get_file().get_basename().to_snake_case(),
		Time.get_ticks_msec(),
	]
	var candidate := base
	var suffix := 2
	while _has_scenario_unit_id(candidate):
		candidate = "%s_%d" % [base, suffix]
		suffix += 1
	return candidate


func _has_scenario_unit_id(candidate: String) -> bool:
	for character in _characters:
		if is_instance_valid(character) and character.scenario_unit_id == candidate:
			return true
	return false


func _is_valid_dev_cell(cell: Vector2i, except_character: TacticalCharacter = null) -> bool:
	if not grid.is_in_bounds(cell) or _get_wall_cells().has(cell):
		return false
	for character in _characters:
		if is_instance_valid(character) and character != except_character and character.grid_cell == cell:
			return false
	return true


func _character_display_name(character: TacticalCharacter) -> String:
	return (
		character.definition.display_name
		if character.definition != null
		else str(character.name)
	)


func _track_token_view_input(event: InputEvent) -> void:
	if not _token_view_has_focus or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.keycode != KEY_CTRL and key.physical_keycode != KEY_CTRL:
		return
	# Input's aggregate Ctrl state can be released while the other Ctrl is held.
	if key.pressed:
		_held_token_ctrl_locations[key.location] = true
	else:
		_held_token_ctrl_locations.erase(key.location)


func _sync_token_view() -> void:
	var enabled := _token_view_has_focus and (
		not _held_token_ctrl_locations.is_empty()
		or Input.is_action_pressed(&"battle_token_view")
	)
	if _token_view_enabled == enabled:
		return
	_token_view_enabled = enabled
	for character in _characters:
		if is_instance_valid(character):
			character.set_token_view_enabled(enabled)
	_has_hovered_cell = false
	if (initialization_succeeded and not _dev_open and not get_tree().paused
		and not _movement_locked and turn_manager.is_player_turn() and _has_mouse_screen_position):
		var point := _screen_to_world(_last_mouse_screen_position)
		if _selected_ability != null:
			_update_ability_hover(point)
		elif _selected_character == turn_manager.current_unit:
			_update_hover(point)


func _on_token_view_focus_exited() -> void:
	_token_view_has_focus = false
	_held_token_ctrl_locations.clear()
	_sync_token_view()


func _on_token_view_focus_entered() -> void:
	_token_view_has_focus = true
	_sync_token_view()


func _process(_delta: float) -> void:
	_sync_token_view()
	if is_instance_valid(_pending_defeated_turn_unit) and not _ability_executor.is_resolving():
		var defeated_unit := _pending_defeated_turn_unit
		_pending_defeated_turn_unit = null
		_end_defeated_current_unit(defeated_unit)
	if _combat_over and not _combat_finalized:
		_queue_run_result()
	if _dev_open or get_tree().paused:
		return
	if target_selection_panel.visible and not _movement_locked:
		_refresh_hit_target_selection()
	if not _movement_locked and turn_manager.is_player_turn() and _has_mouse_screen_position:
		if _selected_ability != null:
			_update_ability_hover(_screen_to_world(_last_mouse_screen_position))
		elif _selected_character != null and _selected_character == turn_manager.current_unit:
			_update_hover(_screen_to_world(_last_mouse_screen_position))


func _unhandled_input(event: InputEvent) -> void:
	if _dev_open or get_tree().paused:
		return
	if inventory_screen.visible:
		if event.is_action_pressed("ui_cancel"):
			inventory_screen.close_screen()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouse:
		_last_mouse_screen_position = event.position
		_has_mouse_screen_position = true

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not _movement_locked and turn_manager.is_player_turn():
			if _selected_ability != null:
				_cancel_ability_targeting()
			else:
				clear_selection()
		get_viewport().set_input_as_handled()
		return

	if _movement_locked or not turn_manager.is_player_turn():
		return

	if event is InputEventMouseMotion:
		if _selected_ability != null:
			_update_ability_hover(_screen_to_world(event.position))
		elif _selected_character != null:
			_update_hover(_screen_to_world(event.position))

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_left_click(_screen_to_world(event.position))
		get_viewport().set_input_as_handled()


func clear_selection() -> void:
	_clear_hit_selection()
	_selected_character = null
	_selected_ability = null
	_reachable_cells.clear()
	_ability_range_cells.clear()
	_ability_target_cells.clear()
	_has_hovered_cell = false
	grid.clear_overlays()
	_update_turn_hud()


func _handle_left_click(global_mouse: Vector2) -> void:
	if _selected_ability != null:
		_handle_ability_click(global_mouse)
		return

	var clicked_character := _get_character_at_global_point(global_mouse)
	if clicked_character != null:
		if clicked_character == turn_manager.current_unit and clicked_character.is_friendly():
			_select_character(clicked_character)
		return

	var cell := grid.global_to_grid(global_mouse)
	if not grid.is_in_bounds(cell):
		clear_selection()
		return

	clicked_character = _get_character_at(cell)
	if clicked_character != null:
		if clicked_character == turn_manager.current_unit and clicked_character.is_friendly():
			_select_character(clicked_character)
		return

	if _selected_character == null or not _reachable_cells.has(cell):
		return

	var blocked_cells := _get_blocked_cells(_selected_character)
	var path := _pathfinder.find_path(
		_selected_character.grid_cell,
		cell,
		_selected_character.remaining_movement,
		blocked_cells, {}, PassiveAbilityResolver.ignores_movement_modifiers(_selected_character)
	)
	if path.size() > 1:
		_begin_friendly_move(path)


func _select_character(character: TacticalCharacter) -> void:
	if not turn_manager.is_player_turn() or character != turn_manager.current_unit:
		return
	_clear_hit_selection()
	_selected_character = character
	_selected_ability = null
	_ability_range_cells.clear()
	_ability_target_cells.clear()
	ability_bar.set_selected(null)
	_refresh_reachable_cells()
	_has_hovered_cell = false
	grid.clear_path()
	_update_turn_hud()


func _refresh_reachable_cells() -> void:
	if (
		_selected_character == null
		or not turn_manager.is_player_turn()
		or _selected_character != turn_manager.current_unit
	):
		clear_selection()
		return
	_pathfinder.set_grid_size(grid.grid_size)
	_reachable_cells = _pathfinder.get_reachable(
		_selected_character.grid_cell,
		_selected_character.remaining_movement,
		_get_blocked_cells(_selected_character), PassiveAbilityResolver.ignores_movement_modifiers(_selected_character)
	)
	grid.show_reachable(_selected_character.grid_cell, _reachable_cells)


func _update_hover(global_mouse: Vector2) -> void:
	var cell := grid.global_to_grid(global_mouse)
	if _has_hovered_cell and cell == _hovered_cell:
		return

	_has_hovered_cell = true
	_hovered_cell = cell
	if not grid.is_in_bounds(cell) or cell == _selected_character.grid_cell or not _reachable_cells.has(cell):
		grid.clear_path()
		return

	var path := _pathfinder.find_path(
		_selected_character.grid_cell,
		cell,
		_selected_character.remaining_movement,
		_get_blocked_cells(_selected_character), {}, PassiveAbilityResolver.ignores_movement_modifiers(_selected_character)
	)
	if path.size() > 1:
		grid.show_path(cell, path)
	else:
		grid.clear_path()


func _on_ability_selected(ability: AbilityDefinition) -> void:
	var caster := turn_manager.current_unit
	if (
		_movement_locked
		or not turn_manager.is_player_turn()
		or not is_instance_valid(caster)
		or not caster.ability_available
		or ability == null
		or not ability.can_be_used_by(caster)
		or not caster.get_abilities().has(ability)
	):
		return
	if _selected_ability == ability:
		_cancel_ability_targeting()
		return
	_clear_hit_selection()
	_selected_character = caster
	_selected_ability = ability
	_refresh_ability_targets()
	ability_bar.set_selected(ability)
	if ability.selects_per_hit():
		target_selection_panel.configure(ability)
		_refresh_hit_target_selection()


func _refresh_ability_targets() -> void:
	var caster := _selected_character
	var ability := _selected_ability
	_has_hovered_cell = false
	_ability_targeting.set_grid_size(grid.grid_size)
	_ability_range_cells = _ability_targeting.get_cells_in_range(caster, ability)
	_ability_target_cells = _ability_targeting.get_valid_target_cells(
		caster,
		ability,
		_characters,
		_get_wall_cells()
	)
	grid.show_ability_targets(caster.grid_cell, _ability_range_cells, _ability_target_cells)


func _cancel_ability_targeting() -> void:
	_clear_hit_selection()
	_selected_ability = null
	_ability_range_cells.clear()
	_ability_target_cells.clear()
	_has_hovered_cell = false
	ability_bar.set_selected(null)
	var caster := turn_manager.current_unit
	if is_instance_valid(caster) and caster.is_friendly() and not _movement_locked:
		_select_character(caster)
	else:
		grid.clear_overlays()


func _update_ability_hover(global_mouse: Vector2) -> void:
	var cell := _get_ability_cell_at_global_point(global_mouse)
	if _has_hovered_cell and cell == _hovered_cell:
		return
	_has_hovered_cell = true
	_hovered_cell = cell
	if not grid.is_in_bounds(cell):
		grid.clear_ability_preview()
		ability_bar.reset_damage_previews()
		return
	ability_bar.reset_damage_previews()
	var is_valid := _ability_target_cells.has(cell)
	var wall_cells := _get_wall_cells()
	var affected_cells: Array[Vector2i] = []
	var trajectory_cells: Array[Vector2i] = []
	var effect_origin := _selected_character.grid_cell
	var caster_movement_path: Array[Vector2i] = []
	if _selected_ability.moves_caster() and _ability_range_cells.has(cell):
		caster_movement_path = _ability_targeting.get_caster_movement_path(
			_selected_character,
			cell,
			_selected_ability,
			_characters,
			wall_cells
		)
		if not caster_movement_path.is_empty():
			effect_origin = AbilityCasterMovementScript.get_landing_cell(caster_movement_path)
			trajectory_cells.assign(caster_movement_path)
	if is_valid:
		affected_cells = _ability_targeting.get_affected_cells(
			effect_origin,
			cell,
			_selected_ability,
			wall_cells,
			_selected_character
		)
		if (
			_selected_ability.shape == AbilityDefinition.Shape.LINE_FROM_CASTER
			and not _selected_ability.moves_caster()
		):
			trajectory_cells = _ability_targeting.get_trajectory_cells(
				effect_origin,
				cell,
				wall_cells
			)
	if (
		_selected_ability.delivery_type == AbilityDefinition.DeliveryType.PROJECTILE
		and _ability_range_cells.has(cell)
		and (not _selected_ability.moves_caster() or not caster_movement_path.is_empty())
	):
		var projectile_path := _ability_executor.projectile_delivery.get_preview(
			effect_origin,
			cell,
			wall_cells
		)
		if trajectory_cells.is_empty():
			trajectory_cells.assign(projectile_path)
		else:
			for index in range(1, projectile_path.size()):
				trajectory_cells.append(projectile_path[index])
	if is_valid:
		ability_bar.set_damage_preview(_selected_character, _selected_ability, effect_origin)
		for effect in _selected_ability.effects:
			if effect is KnockbackEffectDefinition:
				var snapshot := AIBoardSnapshot.from_battle(_characters, grid.grid_size, wall_cells)
				var pushes := EnemyAIPlanner.new().get_knockback_preview(_selected_character,
					_selected_ability, cell, snapshot, _ability_targeting)
				for push in pushes:
					trajectory_cells.append_array(push.path)
					if not affected_cells.has(push.landing):
						affected_cells.append(push.landing)
					if is_instance_valid(push.collision_unit) and not affected_cells.has(push.collision_cell):
						affected_cells.append(push.collision_cell)
				break
	grid.show_ability_preview(cell, affected_cells, trajectory_cells, is_valid)


func _handle_ability_click(global_mouse: Vector2) -> void:
	var target_cell := _get_ability_cell_at_global_point(global_mouse)
	if not _ability_target_cells.has(target_cell):
		return
	if _selected_ability.selects_per_hit():
		_append_hit_target(_get_character_at(target_cell))
		return
	_begin_ability_cast(target_cell)


func _clear_hit_selection() -> void:
	_selected_hit_targets.clear()
	if is_instance_valid(target_selection_panel):
		target_selection_panel.hide()


func _append_hit_target(target: TacticalCharacter) -> void:
	if (_movement_locked or not turn_manager.is_player_turn()
		or _selected_ability == null or not _selected_ability.selects_per_hit()
		or _selected_character != turn_manager.current_unit
		or _selected_hit_targets.size() >= _selected_ability.get_hit_count()):
		return
	if not _selected_ability.allow_repeated_targets and _selected_hit_targets.has(target):
		return
	if not _ability_executor.can_select_hit_target(_selected_character, _selected_ability, target,
		_characters, grid, _ability_targeting, _get_wall_cells()):
		return
	_selected_hit_targets.append(target)
	_refresh_hit_target_selection()


func _remove_hit_target(index: int) -> void:
	if _movement_locked or index < 0 or index >= _selected_hit_targets.size():
		return
	_selected_hit_targets.remove_at(index)
	_refresh_hit_target_selection()


func _refresh_hit_target_selection() -> void:
	if _selected_ability == null or not _selected_ability.selects_per_hit():
		_clear_hit_selection()
		return
	var valid: Array[bool] = []
	var walls := _get_wall_cells()
	for target in _selected_hit_targets:
		valid.append(is_instance_valid(target) and _ability_executor.can_select_hit_target(_selected_character, _selected_ability,
			target, _characters, grid, _ability_targeting, walls))
	var can_fire := (not _movement_locked and turn_manager.is_player_turn()
		and _selected_character == turn_manager.current_unit
		and _ability_executor.can_execute_targets(_selected_character, _selected_ability,
			_selected_hit_targets, _characters, grid, _ability_targeting, walls))
	target_selection_panel.set_targets(_selected_hit_targets, valid, can_fire)


func _begin_selected_targets_cast() -> void:
	if (_movement_locked or _dev_open or get_tree().paused or inventory_screen.visible
		or not turn_manager.is_player_turn() or _selected_character != turn_manager.current_unit
		or not _ability_executor.can_execute_targets(_selected_character, _selected_ability,
			_selected_hit_targets, _characters, grid, _ability_targeting, _get_wall_cells())):
		return
	var caster := _selected_character
	var ability := _selected_ability
	var targets: Array[TacticalCharacter] = _selected_hit_targets.duplicate()
	_clear_hit_selection()
	_set_movement_locked(true)
	grid.clear_overlays()
	var cast_succeeded := await _ability_executor.execute_targets(caster, ability, targets,
		_characters, grid, _ability_targeting, _get_wall_cells())
	_finish_ability_cast(caster, cast_succeeded)


func _begin_ability_cast(target_cell: Vector2i) -> void:
	if _movement_locked or _selected_ability == null:
		return
	var caster := _selected_character
	var ability := _selected_ability
	if caster != turn_manager.current_unit or not caster.ability_available:
		return

	_set_movement_locked(true)
	grid.clear_overlays()
	var cast_succeeded := await _ability_executor.execute(
		caster,
		ability,
		target_cell,
		_characters,
		grid,
		_ability_targeting,
		_get_wall_cells(),
		Callable(self, "_before_ability_movement_step")
	)
	_finish_ability_cast(caster, cast_succeeded)


func _finish_ability_cast(caster: TacticalCharacter, cast_succeeded: bool) -> void:
	_clear_hit_selection()
	_selected_ability = null
	_ability_range_cells.clear()
	_ability_target_cells.clear()
	_has_hovered_cell = false
	ability_bar.set_selected(null)
	if cast_succeeded and is_instance_valid(caster) and caster == turn_manager.current_unit and caster.current_health > 0:
		_set_movement_locked(false)
		_select_character(caster)
	else:
		_set_movement_locked(false)
	_refresh_ability_bar()
	_update_turn_hud()
	if is_instance_valid(caster) and caster.is_bone_pile and caster == turn_manager.current_unit:
		_end_defeated_current_unit.call_deferred(caster)


func _begin_friendly_move(path: Array[Vector2i]) -> void:
	if _movement_locked or _selected_character != turn_manager.current_unit:
		return
	var path_cost := _pathfinder.get_path_cost(path, PassiveAbilityResolver.ignores_movement_modifiers(_selected_character))
	if not _selected_character.can_afford_path(path_cost):
		return

	_set_movement_locked(true)
	var moving_character := _selected_character
	grid.clear_overlays()
	await moving_character.move_along(
		path,
		Callable(self, "_before_character_movement_step")
	)
	var can_continue := (
		is_instance_valid(moving_character)
		and moving_character == turn_manager.current_unit
		and moving_character.current_health > 0
		and not moving_character.is_bone_pile
	)
	_set_movement_locked(not can_continue)
	if can_continue:
		_selected_character = moving_character
		_has_hovered_cell = false
		_refresh_reachable_cells()
		_update_turn_hud()
	elif (
		is_instance_valid(moving_character)
		and moving_character == turn_manager.current_unit
		and (moving_character.current_health <= 0 or moving_character.is_bone_pile)
	):
		call_deferred("_end_defeated_current_unit", moving_character)


func _on_end_turn_pressed() -> void:
	if _movement_locked or not turn_manager.is_player_turn():
		return
	_set_movement_locked(true)
	_selected_ability = null
	clear_selection()
	turn_manager.end_current_turn()


func _run_enemy_unit_turn(unit: TacticalCharacter) -> void:
	if _combat_over or unit != turn_manager.current_unit:
		return
	grid.show_reachable(unit.grid_cell, {})

	var plan := _enemy_ai_planner.choose_plan(
		unit,
		_characters,
		_pathfinder,
		_ability_targeting,
		_get_wall_cells(),
		terrain.get_definitions(),
		turn_manager.get_rotating_order()
	)
	_update_ai_debug(unit, plan)
	var executed := await _execute_enemy_plan(unit, plan)
	if not executed and unit == turn_manager.current_unit and unit.current_health > 0 and not unit.is_bone_pile:
		# Signals or future dynamic effects can make a forecast stale. Replan once from
		# the live state; a second invalidation safely ends the turn.
		plan = _enemy_ai_planner.choose_plan(
			unit,
			_characters,
			_pathfinder,
			_ability_targeting,
			_get_wall_cells(),
			terrain.get_definitions(),
			turn_manager.get_rotating_order()
		)
		_update_ai_debug(unit, plan, "Replanned")
		await _execute_enemy_plan(unit, plan)

	grid.clear_overlays()
	if unit == turn_manager.current_unit:
		call_deferred("_finish_enemy_turn", unit)


func _finish_enemy_turn(unit: TacticalCharacter) -> void:
	if not _combat_over and unit == turn_manager.current_unit:
		turn_manager.end_current_turn()


func _execute_enemy_plan(unit: TacticalCharacter, plan: EnemyTurnPlan) -> bool:
	if unit != turn_manager.current_unit or plan == null:
		return false
	if not plan.pre_cast_path.is_empty():
		var pre_destination := plan.pre_cast_path[plan.pre_cast_path.size() - 1]
		if not await _move_enemy_to(unit, pre_destination, plan.pre_cast_path):
			return false

	if plan.ability != null:
		if not _enemy_ai_planner.respects_taunt(
			unit, unit.grid_cell, plan.ability, plan.target_cell,
			AIBoardSnapshot.from_battle(_characters, grid.grid_size, _get_wall_cells()),
			_ability_targeting
		):
			return false
		if not _ability_executor.can_execute(
			unit,
			plan.ability,
			plan.target_cell,
			_characters,
			grid,
			_ability_targeting,
			_get_wall_cells()
		):
			return false
		grid.clear_overlays()
		var cast_succeeded := await _ability_executor.execute(
			unit,
			plan.ability,
			plan.target_cell,
			_characters,
			grid,
			_ability_targeting,
			_get_wall_cells(),
			Callable(self, "_before_ability_movement_step")
		)
		if not cast_succeeded:
			return false

	if not plan.post_cast_path.is_empty() and unit.current_health > 0:
		var post_destination := plan.post_cast_path[plan.post_cast_path.size() - 1]
		if not await _move_enemy_to(unit, post_destination, plan.post_cast_path):
			return false
	return unit == turn_manager.current_unit


func _move_enemy_to(
	unit: TacticalCharacter,
	destination: Vector2i,
	preferred_path: Array[Vector2i] = []
) -> bool:
	if unit.grid_cell == destination:
		return true
	var blocked_cells := _get_blocked_cells(unit)
	var path := preferred_path.duplicate()
	if (
		path.is_empty()
		or path[0] != unit.grid_cell
		or path[path.size() - 1] != destination
		or not _pathfinder.is_path_walkable(path, blocked_cells)
	):
		path = _pathfinder.find_path(
			unit.grid_cell,
			destination,
			unit.remaining_movement,
			blocked_cells, {}, PassiveAbilityResolver.ignores_movement_modifiers(unit)
		)
	if path.size() < 2:
		return false
	var path_cost := _pathfinder.get_path_cost(path, PassiveAbilityResolver.ignores_movement_modifiers(unit))
	if not unit.can_afford_path(path_cost):
		return false
	if unit != turn_manager.current_unit:
		return false
	grid.clear_overlays()
	await unit.move_along(path, Callable(self, "_before_character_movement_step"))
	return unit.current_health > 0 and unit.grid_cell == destination


func _before_character_movement_step(
	mover: TacticalCharacter,
	current_cell: Vector2i,
	next_cell: Vector2i
) -> bool:
	if not await _resolve_step_opportunity_attacks(mover, current_cell, next_cell):
		return false
	if not mover.can_move():
		return false
	var step_cost := _pathfinder.get_step_cost(current_cell, next_cell, PassiveAbilityResolver.ignores_movement_modifiers(mover))
	return mover.spend_movement(step_cost)


func _before_ability_movement_step(
	mover: TacticalCharacter,
	current_cell: Vector2i,
	next_cell: Vector2i
) -> bool:
	return (
		await _resolve_step_opportunity_attacks(mover, current_cell, next_cell)
		and mover.can_move()
	)


func _resolve_step_opportunity_attacks(
	mover: TacticalCharacter,
	current_cell: Vector2i,
	next_cell: Vector2i
) -> bool:
	if (
		not is_instance_valid(mover)
		or mover.current_health <= 0
		or mover != turn_manager.current_unit
	):
		return false
	var wall_cells := _get_wall_cells()
	for attacker in turn_manager.turn_order:
		if not OpportunityAttackSystemScript.can_trigger(
			attacker,
			mover,
			current_cell,
			next_cell,
			wall_cells
		):
			continue
		var ability := OpportunityAttackSystemScript.get_opportunity_attack_ability(attacker)
		await _ability_executor.execute_opportunity_attack(
			attacker,
			ability,
			current_cell,
			_characters,
			grid,
			_ability_targeting,
			wall_cells
		)
		if not is_instance_valid(mover) or mover.current_health <= 0:
			return false
	return true


func _update_ai_debug(
	unit: TacticalCharacter,
	plan: EnemyTurnPlan,
	status: String = "Chosen"
) -> void:
	var effective_profile := unit.get_enemy_ai_profile()
	var profile_name := effective_profile.display_name if effective_profile != null else "General AI"
	var lines: Array[String] = [
		"Round %d · %s · %s" % [turn_manager.round_number, unit.name, profile_name],
		"%s in %d ms: %s" % [status, _enemy_ai_planner.last_planning_duration_ms, plan.get_debug_summary()],
		"Search: %d candidates in %d ms · %d threat states in %d ms" % [
			_enemy_ai_planner.last_candidate_count,
			_enemy_ai_planner.last_candidate_generation_duration_ms,
			_enemy_ai_planner.last_threat_evaluation_count,
			_enemy_ai_planner.last_threat_evaluation_duration_ms,
		],
		"Cache: %d reachability searches / %d hits / %d exact replies" % [
			_enemy_ai_planner.last_reachability_search_count,
			_enemy_ai_planner.last_cache_hit_count,
			_enemy_ai_planner.last_exact_reply_count,
		],
		"Top candidates:",
	]
	var count := mini(ai_debug_candidate_count, _enemy_ai_planner.ranked_candidates.size())
	for index in range(count):
		lines.append("%d. %s" % [index + 1, _enemy_ai_planner.ranked_candidates[index].get_debug_summary()])
	while _ai_debug_checkpoints.size() < _ai_debug_history.size():
		_ai_debug_checkpoints.append({})
	_ai_debug_history.append("\n".join(lines))
	_ai_debug_checkpoints.append(_capture_ai_debug_checkpoint())
	while _ai_debug_history.size() > ai_debug_history_limit:
		_ai_debug_history.remove_at(0)
		if not _ai_debug_checkpoints.is_empty():
			_ai_debug_checkpoints.remove_at(0)
	_refresh_ai_debug_history()


func _capture_ai_debug_checkpoint() -> Dictionary:
	var checkpoint := capture_save_payload(false)
	var runtime: Dictionary = checkpoint.get("runtime", {})
	var turn: Dictionary = runtime.get("turn", {})
	# AI planning has completed, but no movement or ability has started yet. Mark
	# this self-consistent instant as restorable even though it is an enemy turn.
	turn["action_boundary"] = true
	runtime["turn"] = turn
	checkpoint["runtime"] = runtime
	return checkpoint


func _on_dev_button_pressed() -> void:
	if _dev_open:
		return
	if not _is_dev_stable():
		_dev_open_pending = true
		dev_button.text = "Dev…"
		dev_button.tooltip_text = "Dev mode will open after the current action"
		return
	_open_dev_mode()


func _is_dev_stable() -> bool:
	if _ability_executor.is_resolving():
		return false
	for character in _characters:
		if is_instance_valid(character) and character.is_moving:
			return false
	if _combat_over:
		return _combat_finalized
	return not _movement_locked and turn_manager.is_player_turn()


func report_reload_failed(message: String) -> void:
	if not is_inside_tree():
		return
	_dev_open = true
	_set_dev_blocked_actions_disabled(true)
	tactical_camera.set_dev_mode_pan_enabled(true)
	dev_mode_panel.open_panel()
	dev_mode_panel.show_message(message, true)
	get_tree().paused = true


func _open_dev_mode(initial_tab := DevModePanel.UNIT_TAB) -> void:
	_clear_hit_selection()
	_dev_open_pending = false
	dev_button.text = "Dev"
	dev_button.tooltip_text = "Pause and edit the current scenario"
	_dev_open = true
	_set_dev_blocked_actions_disabled(true)
	_dev_dirty = false
	_dev_drag_unit = null
	_dev_palette_scene = null
	dev_terrain_editor.clear_history()
	_selected_ability = null
	ability_bar.set_selected(null)
	if inventory_screen.visible:
		inventory_button.set_pressed_no_signal(false)
		inventory_screen.close_screen()
	grid.clear_overlays()
	grid.clear_dev_brush_preview()
	dev_mode_panel.set_dirty(false)
	dev_mode_panel.select_unit(
		turn_manager.current_unit if is_instance_valid(turn_manager.current_unit) else null
	)
	dev_mode_panel.open_panel(initial_tab)
	tactical_camera.set_dev_mode_pan_enabled(true)
	get_tree().paused = true


func _on_dev_play_requested() -> void:
	if not _dev_open:
		return
	dev_terrain_editor.end_stroke()
	if _dev_dirty:
		_restored_ai_turn_pending = false
		_pending_ai_history_cutoff = -1
		_pending_ai_history_scroll_position = -1
		var fresh_payload := capture_save_payload(true)
		var validation := ScenarioSaveStore.validate_payload(fresh_payload)
		if not validation.ok:
			dev_mode_panel.show_message("Cannot start: %s" % " ".join(validation.errors), true)
			return
		tactical_camera.set_dev_mode_pan_enabled(false)
		dev_mode_panel.close_panel()
		_dev_open = false
		_set_dev_blocked_actions_disabled(false)
		battle_reload_requested.emit(validation.payload)
		if is_inside_tree() and not _dev_open:
			get_tree().paused = false
		return
	var resume_restored_enemy := _restored_ai_turn_pending
	_commit_pending_ai_history_branch()
	_restored_ai_turn_pending = false
	var restored_enemy := turn_manager.current_unit
	tactical_camera.set_dev_mode_pan_enabled(false)
	dev_terrain_editor.cancel_stroke()
	grid.clear_dev_brush_preview()
	dev_mode_panel.close_panel()
	_dev_open = false
	_set_dev_blocked_actions_disabled(false)
	get_tree().paused = false
	if (
		resume_restored_enemy
		and not _combat_over
		and is_instance_valid(restored_enemy)
		and restored_enemy == turn_manager.current_unit
		and not restored_enemy.is_friendly()
	):
		_set_movement_locked(true)
		call_deferred("_run_enemy_unit_turn", restored_enemy)
	elif not _combat_over and turn_manager.is_player_turn():
		_select_character(turn_manager.current_unit)


func _on_dev_save_requested(replace_path: String) -> void:
	if not _dev_open:
		return
	dev_terrain_editor.end_stroke()
	var payload := capture_save_payload(_dev_dirty)
	var validation := ScenarioSaveStore.validate_payload(payload)
	if not validation.ok:
		dev_mode_panel.show_message("Cannot save: %s" % " ".join(validation.errors), true)
		return
	dev_mode_panel.persist_payload(validation.payload, replace_path)


func _on_dev_load_payload_requested(payload: Dictionary) -> void:
	if not _dev_open:
		return
	dev_terrain_editor.cancel_stroke()
	grid.clear_dev_brush_preview()
	tactical_camera.set_dev_mode_pan_enabled(false)
	dev_mode_panel.close_panel()
	_dev_open = false
	_set_dev_blocked_actions_disabled(false)
	battle_reload_requested.emit(payload)
	if is_inside_tree() and not _dev_open:
		get_tree().paused = false


func _on_ai_history_restore_requested(history_index: int) -> void:
	if not _dev_open:
		return
	if (
		history_index < 0
		or history_index >= _ai_debug_history.size()
		or history_index >= _ai_debug_checkpoints.size()
		or _ai_debug_checkpoints[history_index].is_empty()
	):
		dev_mode_panel.show_message("This AI log does not have a restorable checkpoint.", true)
		_refresh_ai_debug_history()
		return
	var validation := ScenarioSaveStore.validate_payload(
		_ai_debug_checkpoints[history_index].duplicate(true)
	)
	if not validation.ok:
		dev_mode_panel.show_message(
			"Checkpoint restore failed: %s" % " ".join(validation.errors),
			true
		)
		_refresh_ai_debug_history()
		return
	var payload: Dictionary = validation.payload
	_pending_ai_history_scroll_position = dev_mode_panel.get_ai_history_scroll_position()
	payload[DEV_AI_RESTORE_CONTEXT] = {
		"entries": _ai_debug_history.duplicate(),
		"checkpoints": _ai_debug_checkpoints.duplicate(true),
		"selected_history_index": history_index,
		"scroll_vertical": _pending_ai_history_scroll_position,
	}
	dev_terrain_editor.cancel_stroke()
	grid.clear_dev_brush_preview()
	tactical_camera.set_dev_mode_pan_enabled(false)
	dev_mode_panel.close_panel()
	_dev_open = false
	_set_dev_blocked_actions_disabled(false)
	battle_reload_requested.emit(payload)
	if not is_inside_tree():
		return
	if _dev_open:
		dev_mode_panel.tabs.current_tab = DevModePanel.AI_LOG_TAB
		dev_mode_panel.restore_ai_history_scroll_position(
			_pending_ai_history_scroll_position
		)
	else:
		get_tree().paused = false


func _restore_ai_history_context(context: Dictionary) -> void:
	if context.is_empty():
		return
	var raw_entries: Array = context.get("entries", [])
	var raw_checkpoints: Array = context.get("checkpoints", [])
	var retained_count := mini(raw_entries.size(), raw_checkpoints.size())
	for index in range(retained_count):
		if not raw_checkpoints[index] is Dictionary:
			continue
		_ai_debug_history.append(str(raw_entries[index]))
		_ai_debug_checkpoints.append((raw_checkpoints[index] as Dictionary).duplicate(true))
	var selected_history_index := int(context.get("selected_history_index", -1))
	_pending_ai_history_cutoff = (
		selected_history_index
		if selected_history_index >= 0 and selected_history_index < _ai_debug_history.size()
		else -1
	)
	_pending_ai_history_scroll_position = maxi(int(context.get("scroll_vertical", 0)), 0)


func _commit_pending_ai_history_branch() -> void:
	if _pending_ai_history_cutoff < 0:
		return
	var retained_count := _pending_ai_history_cutoff + 1
	while _ai_debug_history.size() > retained_count:
		_ai_debug_history.pop_back()
	while _ai_debug_checkpoints.size() > retained_count:
		_ai_debug_checkpoints.pop_back()
	_pending_ai_history_cutoff = -1
	_pending_ai_history_scroll_position = -1
	_refresh_ai_debug_history()


func _open_restored_ai_checkpoint() -> void:
	if not is_inside_tree() or not initialization_succeeded:
		return
	_open_dev_mode(DevModePanel.AI_LOG_TAB)
	dev_mode_panel.restore_ai_history_scroll_position(
		_pending_ai_history_scroll_position
	)
	dev_mode_panel.show_message(
		"Restored to before the selected AI decision. All logs remain available until Resume."
	)


func _on_dev_setup_changed() -> void:
	_queue_passive_refresh()
	_dev_dirty = true
	dev_mode_panel.set_dirty(true)


func _on_dev_delete_selected() -> void:
	if not _dev_open:
		return
	var character := dev_mode_panel.get_selected_unit()
	if not is_instance_valid(character):
		return
	if _selected_character == character:
		clear_selection()
	if _dev_drag_unit == character:
		_dev_drag_unit = null
		_dev_dragging = false
	turn_manager.remove_unit(character)
	_characters.erase(character)
	dev_terrain_editor.set_characters(_characters)
	characters_container.remove_child(character)
	character.queue_free()
	dev_mode_panel.clear_unit_selection()
	grid.clear_overlays()
	_on_dev_setup_changed()
	_update_turn_hud()
	dev_mode_panel.show_message("Unit deleted. Restart is required.")


func _on_dev_heal_selected() -> void:
	if not _dev_open:
		return
	var character := dev_mode_panel.get_selected_unit()
	if not is_instance_valid(character):
		return
	var maximum_health := character.get_max_health()
	if character.current_health <= 0 or character.current_health >= maximum_health:
		dev_mode_panel.select_unit(character)
		return
	character.heal(maximum_health - character.current_health)
	dev_mode_panel.select_unit(character)
	dev_mode_panel.show_message("Selected unit restored to full health.")


func _on_dev_palette_drag_started(unit_scene: PackedScene) -> void:
	if not _dev_open or not dev_mode_panel.is_unit_tab_active():
		return
	_dev_palette_scene = unit_scene


func _on_dev_terrain_brush_changed(kind: int, brush_resource: Resource) -> void:
	dev_terrain_editor.set_brush(kind, brush_resource)


func _on_dev_active_tab_changed(_tab_index: int) -> void:
	dev_terrain_editor.end_stroke()
	_dev_drag_unit = null
	_dev_palette_scene = null
	grid.clear_overlays()
	grid.clear_dev_brush_preview()


func set_unit_names_visible(value: bool) -> void:
	unit_names_visible = value
	_apply_unit_name_visibility()


func _apply_unit_name_visibility() -> void:
	if is_instance_valid(names_button):
		names_button.set_pressed_no_signal(unit_names_visible)
		names_button.text = "Names: On" if unit_names_visible else "Names: Off"
		names_button.tooltip_text = (
			"Hide unit names below units"
			if unit_names_visible
			else "Show unit names below units"
		)
	for character in _characters:
		if is_instance_valid(character):
			character.set_unit_name_visible(unit_names_visible)


func _on_names_button_toggled(value: bool) -> void:
	set_unit_names_visible(value)
	unit_name_visibility_changed.emit(value)


func _set_dev_blocked_actions_disabled(disabled: bool) -> void:
	dev_button.disabled = disabled
	inventory_button.disabled = disabled
	restart_button.disabled = disabled
	levels_button.disabled = disabled


func _on_restart_button_pressed() -> void:
	if run_encounter != null:
		return
	_cancel_ability_targeting()
	var fresh_payload := capture_save_payload(true)
	var validation := ScenarioSaveStore.validate_payload(fresh_payload)
	if not validation.ok:
		report_reload_failed("Restart failed: %s" % " ".join(validation.errors))
		return
	battle_reload_requested.emit(validation.payload)


func _on_levels_button_pressed() -> void:
	_cancel_ability_targeting()
	if not _return_dialog_paused_battle:
		_return_dialog_paused_battle = true
		get_tree().paused = true
	return_to_levels_dialog.popup_centered()


func _on_return_to_levels_confirmed() -> void:
	_resume_after_return_dialog()
	shutdown_battle()
	return_to_level_select_requested.emit()


func _on_return_to_levels_canceled() -> void:
	_resume_after_return_dialog()


func _resume_after_return_dialog() -> void:
	if not _return_dialog_paused_battle:
		return
	_return_dialog_paused_battle = false
	if get_tree() != null:
		get_tree().paused = false


func _on_inventory_button_toggled(open: bool) -> void:
	if open:
		_cancel_ability_targeting()
		var preferred_character := _selected_character
		if not is_instance_valid(preferred_character) or not preferred_character.is_friendly():
			var current_unit := turn_manager.current_unit
			preferred_character = current_unit if is_instance_valid(current_unit) and current_unit.is_friendly() else null
		inventory_screen.open_for(preferred_character)
	else:
		inventory_screen.close_screen()


func _on_inventory_screen_closed() -> void:
	inventory_button.set_pressed_no_signal(false)


func _on_inventory_equipment_updated(character: TacticalCharacter) -> void:
	if (
		character == _selected_character
		and _selected_ability != null
		and (not character.get_abilities().has(_selected_ability)
			or not _selected_ability.can_be_used_by(character))
	):
		_cancel_ability_targeting()
	if character == turn_manager.current_unit:
		_refresh_ability_bar()
		_update_turn_hud()
	if character == _selected_character and not _movement_locked:
		if _selected_ability == null:
			_refresh_reachable_cells()
		else:
			_refresh_ability_targets()
			_update_ability_hover(get_global_mouse_position())
			if _selected_ability.selects_per_hit():
				_refresh_hit_target_selection()


func _on_character_equipment_changed(
	_slot: ItemDefinition.EquipmentSlot,
	_item: ItemDefinition,
	character: TacticalCharacter
) -> void:
	_on_inventory_equipment_updated(character)


func _on_character_class_progression_changed(character: TacticalCharacter) -> void:
	if character == _selected_character and _selected_ability != null and not character.get_abilities().has(_selected_ability):
		_cancel_ability_targeting()
	if character == turn_manager.current_unit:
		_refresh_ability_bar()
		_update_turn_hud()


func _refresh_ai_debug_history() -> void:
	if dev_mode_panel == null:
		return
	dev_mode_panel.set_ai_history(_ai_debug_history, _pending_ai_history_cutoff)


func _on_turn_starting(unit: TacticalCharacter) -> void:
	if _combat_over:
		return
	terrain.apply_trigger(unit, TileTriggeredEffectDefinition.Trigger.TURN_START)


func _on_turn_started(unit: TacticalCharacter) -> void:
	_clear_hit_selection()
	if _combat_over:
		return
	_selected_ability = null
	_ability_range_cells.clear()
	_ability_target_cells.clear()
	turn_order_bar.rebuild(turn_manager.get_rotating_order(), unit)
	if unit.is_friendly():
		_set_movement_locked(false)
		_select_character(unit)
	else:
		_set_movement_locked(true)
		clear_selection()
		grid.show_reachable(unit.grid_cell, {})
		_run_enemy_unit_turn(unit)
	_refresh_ability_bar()
	_update_turn_hud()


func _on_turn_ended(_unit: TacticalCharacter) -> void:
	_clear_hit_selection()
	grid.clear_overlays()


func _on_turn_order_changed(order: Array[TacticalCharacter]) -> void:
	turn_order_bar.rebuild(order, turn_manager.current_unit)


func _on_round_started(_round_number: int) -> void:
	_update_turn_hud()


func _on_character_defeated(character: TacticalCharacter) -> void:
	turn_manager.notify_unit_state_changed()
	if character.is_friendly():
		inventory_screen.setup(general_inventory, _get_living_friendlies())
	if _check_combat_end():
		return
	if character == turn_manager.current_unit and not character.is_moving:
		call_deferred("_end_defeated_current_unit", character)


func _on_character_form_changed(character: TacticalCharacter) -> void:
	turn_manager.notify_unit_state_changed()
	_queue_passive_refresh()
	if character.is_bone_pile and character == turn_manager.current_unit and not character.is_moving and not _movement_locked:
		_end_defeated_current_unit.call_deferred(character)


func _on_character_cell_entered(
	character: TacticalCharacter,
	_cell: Vector2i
) -> void:
	terrain.apply_trigger(character, TileTriggeredEffectDefinition.Trigger.ENTER)


func _on_terrain_changed(
	_definitions: Dictionary,
	movement_cost_multipliers: Dictionary
) -> void:
	if _pathfinder != null:
		_pathfinder.set_cell_cost_multipliers(movement_cost_multipliers)


func _end_defeated_current_unit(character: TacticalCharacter) -> void:
	if _ability_executor.is_resolving():
		_pending_defeated_turn_unit = character
		return
	if (is_instance_valid(character) and not _combat_over and character == turn_manager.current_unit
		and (character.current_health <= 0 or character.is_bone_pile)):
		turn_manager.end_current_turn()


func _on_unit_movement_changed(_remaining: float, _maximum: float, unit: TacticalCharacter) -> void:
	if unit == turn_manager.current_unit:
		_update_turn_hud()


func _on_unit_ability_availability_changed(_available: bool, unit: TacticalCharacter) -> void:
	if unit == turn_manager.current_unit:
		if not _available and _selected_ability != null:
			_cancel_ability_targeting()
		_refresh_ability_bar()
		_update_turn_hud()


func _on_character_statuses_changed(unit: TacticalCharacter) -> void:
	if unit != turn_manager.current_unit:
		return
	if unit.is_stunned() and _selected_ability != null:
		_cancel_ability_targeting()
	if (
		unit.is_friendly()
		and unit == _selected_character
		and not _movement_locked
	):
		_refresh_reachable_cells()
	_refresh_ability_bar()
	_update_turn_hud()


func _set_movement_locked(value: bool) -> void:
	_movement_locked = true if _combat_over else value
	_refresh_ability_bar()
	_update_turn_hud()
	if _dev_open_pending and _is_dev_stable():
		_open_dev_mode.call_deferred()


func _refresh_ability_bar() -> void:
	if ability_bar == null or turn_manager == null:
		return
	var unit := turn_manager.current_unit
	var enabled := (
		not _movement_locked
		and turn_manager.is_player_turn()
		and is_instance_valid(unit)
		and unit.ability_available
	)
	ability_bar.rebuild(unit, enabled)
	ability_bar.set_selected(_selected_ability)


func _update_turn_hud() -> void:
	if turn_manager == null or end_turn_button == null:
		return
	if _combat_over:
		end_turn_button.text = "Battle Ended"
		end_turn_button.disabled = true
		return
	var unit := turn_manager.current_unit
	if unit == null:
		end_turn_button.text = "Waiting..."
		end_turn_button.disabled = true
		return

	if unit.is_friendly():
		end_turn_button.text = "End Turn [Space]"
		end_turn_button.disabled = _movement_locked
	else:
		end_turn_button.text = "Enemy Turn..."
		end_turn_button.disabled = true


func _check_combat_end() -> bool:
	if _combat_over:
		return true
	var has_living_friendlies := false
	var has_living_enemies := false
	for character in _characters:
		if not is_instance_valid(character) or character.current_health <= 0:
			continue
		if character.is_friendly():
			has_living_friendlies = true
		else:
			has_living_enemies = true
	if has_living_friendlies and has_living_enemies:
		return false

	_combat_over = true
	if has_living_friendlies:
		_combat_result_text = "Victory"
	elif has_living_enemies:
		_combat_result_text = "Defeat"
	else:
		_combat_result_text = "Battle Ended"
	_movement_locked = true
	turn_manager.stop_combat()
	clear_selection()
	_refresh_ability_bar()
	_queue_run_result()
	return true


func _prepare_template_characters() -> bool:
	var template := map_definition as BattleMapTemplateDefinition
	var party_root: Node
	var party: Array[TacticalCharacter] = []
	var party_slots := run_party_input.size()
	if run_encounter != null and not run_encounter.chief_node_name.is_empty():
		return _fail_template("Named-chief encounters require an authored map, not a generated template.")
	if run_encounter == null:
		if template.standalone_party == null or not template.standalone_party.can_instantiate():
			return _fail_template("Assign a Standalone Party scene to this map template.")
		party_root = template.standalone_party.instantiate()
		for child in party_root.get_children():
			if child is TacticalCharacter:
				if child.definition == null or not child.is_friendly():
					party_root.free()
					return _fail_template("Standalone Party combatants must have friendly definitions.")
				party.append(child)
		party_slots = party.size()
		if party_slots == 0:
			party_root.free()
			return _fail_template("Standalone Party must contain friendly TacticalCharacter children.")
	var setup := template_setup_input
	if run_encounter == null:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		setup = TemplateEncounterSetup.create(template, party_slots, rng)
		if not str(setup.get("error", "")).is_empty():
			party_root.free()
			return _fail_template(setup.error)
	var error := TemplateEncounterSetup.validate_saved(template, setup, party_slots)
	if not error.is_empty():
		if party_root != null:
			party_root.free()
		return _fail_template(error)
	var spawns := battle_map.get_node("SpawnTiles") as BattleSpawnTiles
	for index in range(party.size()):
		var character := party[index]
		character.owner = null
		party_root.remove_child(character)
		character.starting_grid_cell = spawns.friendly_cells[index]
		characters_container.add_child(character)
	if party_root != null:
		party_root.free()
	for entry in setup.enemies:
		var scene := load(str(entry.scene)) as PackedScene
		var character := scene.instantiate() as TacticalCharacter
		character.name = str(entry.name)
		character.scenario_unit_id = str(entry.id)
		character.starting_grid_cell = Vector2i(int(entry.cell[0]), int(entry.cell[1]))
		characters_container.add_child(character)
	return true


func _fail_template(message: String) -> bool:
	initialization_error = message
	_combat_over = true
	_movement_locked = true
	_combat_result_text = "Invalid Template"
	push_error(message)
	_refresh_ability_bar()
	_update_turn_hud()
	return false


func _prepare_run_characters() -> bool:
	var spawns := battle_map.get_node_or_null("PartySpawns")
	var template_spawns := battle_map.get_node_or_null("SpawnTiles") as BattleSpawnTiles
	var is_template := map_definition is BattleMapTemplateDefinition
	if not is_template and (spawns == null or spawns.get_child_count() < run_party_input.size()):
		push_error("Run encounter needs an authored spawn for every original party member.")
		return false
	for child in characters_container.get_children():
		if not child is TacticalCharacter:
			continue
		var character := child as TacticalCharacter
		if character.is_friendly():
			characters_container.remove_child(character)
			character.free()
			continue
		if not run_encounter.chief_node_name.is_empty() and str(character.name) != run_encounter.chief_node_name:
			continue
		for stat in ["constitution", "strength", "dexterity", "intelligence"]:
			var override_value := int(character.get(stat + "_override"))
			var base := override_value if override_value >= 0 else int(character.definition.get(stat))
			character.set(stat + "_override", ceili(base * run_encounter.enemy_multiplier))
		if not run_encounter.chief_node_name.is_empty():
			character.name = run_encounter.chief_display_name
	var friendly_index := 0
	for index in range(run_party_input.size()):
		var member: Dictionary = run_party_input[index]
		if bool(member.get("lost", false)):
			continue
		var setup: Dictionary = member.setup.duplicate(true)
		var scene := load(str(setup.scene)) as PackedScene
		var character := scene.instantiate() as TacticalCharacter
		var spawn := spawns.get_child(index) as RunSpawnPoint if not is_template else null
		if character == null or (not is_template and spawn == null):
			push_error("Run party scene or spawn is invalid.")
			return false
		var cell := template_spawns.friendly_cells[index] if is_template else spawn.grid_cell
		setup.cell = [cell.x, cell.y]
		setup.complete_equipment = true
		setup.equipment = member.equipment
		character.apply_setup_state(setup)
		character.permanent_defeat = true
		character.name = str(member.name)
		characters_container.add_child(character)
		if is_template:
			# Preserve party IDs if a generated enemy happens to use the same ID.
			characters_container.move_child(character, friendly_index)
			friendly_index += 1
	return true


func _restore_run_party() -> void:
	general_inventory.restore_state(run_inventory_input)
	for character in _characters:
		if not character.is_friendly():
			character.heal(character.get_max_health())
			continue
		for member in run_party_input:
			if str(member.id) == character.scenario_unit_id:
				var runtime := character.capture_runtime_state()
				runtime.current_health = int(member.health)
				runtime.statuses = []
				character.restore_runtime_state(runtime, {})
				break


func _restore_run_restart_party() -> void:
	general_inventory.restore_state(run_inventory_input)
	for character in _characters:
		if not character.is_friendly():
			continue
		# Fresh scene instances already reset statuses, actions and enemy health.
		# Preserve live party health, including defeat; restoration clamps to the
		# edited maximum without carrying temporary Constitution bonuses forward.
		var runtime := character.capture_runtime_state()
		runtime.current_health = int(run_restart_health_input.get(character.scenario_unit_id, character.get_max_health()))
		runtime.statuses = []
		character.restore_runtime_state(runtime, {})


func capture_run_party() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var included_ids := {}
	for character in _characters:
		if not is_instance_valid(character) or not character.is_friendly():
			continue
		var equipment: Array[String] = []
		if character.current_health > 0:
			for item in character.get_equipped_items():
				equipment.append(item.resource_path)
		var persistent_max := character.get_max_health_without_statuses()
		included_ids[character.scenario_unit_id] = true
		result.append({"id": character.scenario_unit_id, "health": mini(character.current_health, persistent_max),
			"max_health": persistent_max, "equipment": equipment,
			"class_levels": CharacterClassProgression.to_data(character.get_class_levels())})
	# Developer deletion is a loss of that member, not an incomplete run result.
	for member in run_party_input:
		if not included_ids.has(str(member.id)) and not bool(member.get("lost", false)):
			result.append({"id": str(member.id), "health": 0,
				"max_health": int(member.get("max_health", 1)), "equipment": []})
	return result


## Deferred so synchronous area/status effects finish before restoration.
## Animated abilities (including aborted casts and nested reactions) and movement
## keep this pending until their outer resolution has actually returned.
func _queue_run_result() -> void:
	if _combat_finalization_queued or not _combat_over:
		return
	_combat_finalization_queued = true
	_finalize_combat.call_deferred()


func _finalize_combat() -> void:
	_combat_finalization_queued = false
	if not _combat_over:
		return
	if not _combat_finalized:
		if _ability_executor.is_resolving():
			return
		for character in _characters:
			if is_instance_valid(character) and character.is_moving:
				return
		_combat_finalized = true
		for character in _characters:
			if is_instance_valid(character):
				character.remove_battle_end_statuses()
			if is_instance_valid(character) and character.current_health > 0:
				character.restore_armor()
		if _dev_open_pending:
			_open_dev_mode.call_deferred()
	_publish_run_result()


func _publish_run_result() -> void:
	if run_encounter == null or _run_result_emitted:
		return
	_run_result_emitted = true
	_emit_run_result.call_deferred(not _get_living_friendlies().is_empty())


func _emit_run_result(_victory: bool) -> void:
	# A multi-target effect may also defeat the last friendly after combat ends.
	var victory := not _get_living_friendlies().is_empty()
	var results := capture_run_party()
	if not run_party_input.is_empty():
		# Developer-added allies are encounter units, not new persistent members.
		# A helper surviving cannot continue a run whose original party is lost.
		victory = false
		for member in run_party_input:
			for result in results:
				if str(result.id) == str(member.id) and int(result.health) > 0:
					victory = true
					break
	battle_finished.emit(victory, results, general_inventory.capture_state())


func _get_living_friendlies() -> Array[TacticalCharacter]:
	var friendlies: Array[TacticalCharacter] = []
	for character in _characters:
		if is_instance_valid(character) and character.is_friendly() and character.current_health > 0:
			friendlies.append(character)
	return friendlies


func _get_character_at(cell: Vector2i) -> TacticalCharacter:
	for character in _characters:
		if (
			is_instance_valid(character)
			and character.is_present_on_map()
			and character.grid_cell == cell
		):
			return character
	return null


func _get_character_at_global_point(point: Vector2) -> TacticalCharacter:
	for character in _characters:
		if (
			is_instance_valid(character)
			and character.is_present_on_map()
			and character.contains_global_point(point)
		):
			return character
	return null


func _get_ability_cell_at_global_point(point: Vector2) -> Vector2i:
	var hovered_character := _get_character_at_global_point(point)
	if is_instance_valid(hovered_character) and hovered_character.current_health > 0:
		return hovered_character.grid_cell
	return grid.global_to_grid(point)


func _get_blocked_cells(except_character: TacticalCharacter = null) -> Dictionary:
	var blocked: Dictionary = _get_wall_cells()
	for character in _characters:
		if (
			is_instance_valid(character)
			and character != except_character
			and character.is_present_on_map()
		):
			blocked[character.grid_cell] = true
	return blocked


func _get_traversed_path(
	planned_path: Array[Vector2i],
	reached_cell: Vector2i
) -> Array[Vector2i]:
	var traversed: Array[Vector2i] = []
	for cell in planned_path:
		traversed.append(cell)
		if cell == reached_cell:
			break
	return traversed


func _initialize_walls() -> void:
	_walls.clear()
	var occupied_start_cells: Dictionary = {}
	for character in _characters:
		occupied_start_cells[character.starting_grid_cell] = character.name
	var accepted_cells: Dictionary = {}
	for child in walls_container.get_children():
		if not child is TacticalWall:
			continue
		var wall := child as TacticalWall
		wall.initialize(grid)
		_walls.append(wall)
		if not grid.is_in_bounds(wall.grid_cell):
			push_warning("Ignoring wall %s: cell %s is outside the grid." % [wall.name, wall.grid_cell])
		elif occupied_start_cells.has(wall.grid_cell):
			push_warning("Ignoring wall %s: cell %s is occupied by %s's starting position." % [wall.name, wall.grid_cell, occupied_start_cells[wall.grid_cell]])
		elif accepted_cells.has(wall.grid_cell):
			push_warning("Ignoring duplicate wall %s at cell %s." % [wall.name, wall.grid_cell])
		else:
			accepted_cells[wall.grid_cell] = true


func _refresh_environment_after_edit() -> void:
	_initialize_walls()
	terrain.initialize(grid, _get_wall_cells(), false)


func _capture_environment_setup() -> Dictionary:
	var terrain_entries: Array[Dictionary] = []
	if terrain != null:
		for child in terrain.get_children():
			if not child is TacticalTile:
				continue
			var tile := child as TacticalTile
			if tile.definition == null or tile.definition.resource_path.is_empty():
				continue
			terrain_entries.append({
				"cell": [tile.grid_cell.x, tile.grid_cell.y],
				"definition": tile.definition.resource_path,
			})
	var wall_entries: Array[Dictionary] = []
	if walls_container != null:
		for child in walls_container.get_children():
			if child is TacticalWall:
				wall_entries.append((child as TacticalWall).capture_setup_state())
	terrain_entries.sort_custom(_setup_entry_cell_less)
	wall_entries.sort_custom(_setup_entry_cell_less)
	return {"terrain": terrain_entries, "walls": wall_entries}


func _replace_environment_from_setup(setup: Dictionary) -> void:
	if setup.has("terrain"):
		terrain.replace_setup_state(setup.get("terrain", []), false)
	if not setup.has("walls"):
		return
	for child in walls_container.get_children():
		if child is TacticalWall:
			walls_container.remove_child(child)
			child.queue_free()
	for raw_entry in setup.get("walls", []):
		if not raw_entry is Dictionary:
			continue
		var wall := TacticalWall.new()
		wall.apply_setup_state(raw_entry)
		wall.name = "Wall_%d_%d" % [wall.grid_cell.x, wall.grid_cell.y]
		walls_container.add_child(wall)


func _setup_entry_cell_less(a: Dictionary, b: Dictionary) -> bool:
	var a_cell: Array = a.get("cell", [0, 0])
	var b_cell: Array = b.get("cell", [0, 0])
	return int(a_cell[1]) < int(b_cell[1]) or (
		int(a_cell[1]) == int(b_cell[1]) and int(a_cell[0]) < int(b_cell[0])
	)


func _get_wall_cells() -> Dictionary:
	var cells: Dictionary = {}
	var character_start_cells: Dictionary = {}
	for character in _characters:
		if is_instance_valid(character):
			character_start_cells[character.starting_grid_cell] = true
	for wall in _walls:
		if (
			is_instance_valid(wall)
			and grid.is_in_bounds(wall.grid_cell)
			and not character_start_cells.has(wall.grid_cell)
			and not cells.has(wall.grid_cell)
		):
			cells[wall.grid_cell] = true
	return cells


func _screen_to_world(screen_position: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_position


var _passive_refresh_pending := false


func _queue_passive_refresh() -> void:
	if not _passive_refresh_pending:
		_passive_refresh_pending = true
		_refresh_passive_context.call_deferred()


func _refresh_passive_context() -> void:
	_passive_refresh_pending = false
	if not is_node_ready():
		return
	_refresh_ability_bar()
	_update_turn_hud()
	_has_hovered_cell = false
	if is_instance_valid(_selected_character) and not _movement_locked and _selected_ability == null and not _dev_open:
		_refresh_reachable_cells()
	if inventory_screen != null and inventory_screen.visible:
		inventory_screen._refresh_character_details()
	if dev_mode_panel != null and dev_mode_panel.visible:
		dev_mode_panel._refresh_selected_unit()
