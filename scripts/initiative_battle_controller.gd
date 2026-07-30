class_name TacticalBattle
extends Node2D

const OpportunityAttackSystemScript = preload("res://scripts/opportunity_attack_system.gd")
const BattleMapDefinitionScript = preload("res://scripts/battle_map_definition.gd")
const BattleMapScript = preload("res://scripts/battle_map.gd")

signal return_to_level_select_requested

@export_category("Battle Map")
@export var map_definition: BattleMapDefinitionScript
@export var center_camera_on_start := true
@export_category("Developer Tools")
@export var enable_dev_tools := true
@export_range(1, 10, 1) var ai_debug_candidate_count := 5
@export_range(1, 100, 1) var ai_debug_history_limit := 30

@onready var map_container: Node2D = $MapContainer
@onready var turn_manager: TurnManager = $TurnManager
@onready var tactical_camera: TacticalCameraController = $TacticalCamera
@onready var turn_order_bar: TurnOrderBar = $HUD/TurnOrderBar
@onready var ability_bar: AbilityBar = $HUD/AbilityBar
@onready var general_inventory: GeneralInventory = $GeneralInventory
@onready var inventory_button: Button = $HUD/InventoryButton
@onready var levels_button: Button = $HUD/LevelsButton
@onready var inventory_screen: InventoryScreen = $HUD/InventoryScreen
@onready var return_to_levels_dialog: ConfirmationDialog = $HUD/ReturnToLevelsDialog
@onready var turn_status: Label = $HUD/TurnPanel/Margin/VBox/TurnStatus
@onready var movement_status: Label = $HUD/TurnPanel/Margin/VBox/MovementStatus
@onready var end_turn_button: Button = $HUD/TurnPanel/Margin/VBox/EndTurnButton
@onready var dev_button: Button = $HUD/DevButton
@onready var dev_history_panel: PanelContainer = $HUD/DevHistoryPanel
@onready var ai_debug_label: Label = $HUD/DevHistoryPanel/Margin/VBox/HistoryScroll/DebugText

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
var _reachable_cells: Dictionary = {}
var _ability_range_cells: Dictionary = {}
var _ability_target_cells: Dictionary = {}
var _hovered_cell := Vector2i.ZERO
var _has_hovered_cell := false
var _movement_locked := true
var _last_mouse_screen_position := Vector2.ZERO
var _has_mouse_screen_position := false
var _ai_debug_history: Array[String] = []
var _combat_over := false
var _combat_result_text := ""
var _return_dialog_paused_battle := false


func _ready() -> void:
	levels_button.pressed.connect(_on_levels_button_pressed)
	return_to_levels_dialog.confirmed.connect(_on_return_to_levels_confirmed)
	return_to_levels_dialog.canceled.connect(_on_return_to_levels_canceled)
	if not _instantiate_battle_map():
		_combat_over = true
		_combat_result_text = "Invalid Level"
		_movement_locked = true
		_refresh_ability_bar()
		_update_turn_hud()
		return
	_pathfinder = GridPathfinder.new(grid.grid_size)
	_enemy_ai_planner = EnemyAIPlanner.new()
	_ability_targeting = AbilityTargeting.new(grid.grid_size)
	_ability_executor = AbilityExecutor.new()
	add_child(_ability_executor)
	turn_manager.turn_starting.connect(_on_turn_starting)
	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.turn_ended.connect(_on_turn_ended)
	turn_manager.turn_order_changed.connect(_on_turn_order_changed)
	turn_manager.round_started.connect(_on_round_started)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	ability_bar.ability_selected.connect(_on_ability_selected)
	inventory_button.toggled.connect(_on_inventory_button_toggled)
	inventory_screen.closed.connect(_on_inventory_screen_closed)
	dev_button.pressed.connect(_on_dev_button_pressed)
	terrain.terrain_changed.connect(_on_terrain_changed)

	for child in characters_container.get_children():
		if child is TacticalCharacter:
			var character := child as TacticalCharacter
			_characters.append(character)
			character.initialize(grid)
			character.movement_remaining_changed.connect(
				_on_unit_movement_changed.bind(character)
			)
			character.ability_availability_changed.connect(
				_on_unit_ability_availability_changed.bind(character)
			)
			character.cell_entered.connect(_on_character_cell_entered)
			character.defeated.connect(_on_character_defeated)
			character.equipment_changed.connect(
				_on_character_equipment_changed.bind(character)
			)
	inventory_screen.setup(general_inventory, _get_living_friendlies())
	_initialize_walls()
	terrain.initialize(grid, _get_wall_cells())

	if center_camera_on_start:
		tactical_camera.position = grid.position + grid.get_local_bounds().get_center()
	dev_button.visible = enable_dev_tools
	dev_history_panel.visible = false
	_refresh_ai_debug_history()
	if not _check_combat_end():
		turn_manager.start_combat(_characters)
	_update_turn_hud()


func _exit_tree() -> void:
	_resume_after_return_dialog()


func shutdown_battle() -> void:
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


func _process(_delta: float) -> void:
	if not _movement_locked and turn_manager.is_player_turn() and _has_mouse_screen_position:
		if _selected_ability != null:
			_update_ability_hover(_screen_to_world(_last_mouse_screen_position))
		elif _selected_character != null and _selected_character == turn_manager.current_unit:
			_update_hover(_screen_to_world(_last_mouse_screen_position))


func _unhandled_input(event: InputEvent) -> void:
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
		blocked_cells
	)
	if path.size() > 1:
		_begin_friendly_move(path)


func _select_character(character: TacticalCharacter) -> void:
	if not turn_manager.is_player_turn() or character != turn_manager.current_unit:
		return
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
		_get_blocked_cells(_selected_character)
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
		_get_blocked_cells(_selected_character)
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
	_selected_character = caster
	_selected_ability = ability
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
	ability_bar.set_selected(ability)


func _cancel_ability_targeting() -> void:
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
		return
	var is_valid := _ability_target_cells.has(cell)
	var wall_cells := _get_wall_cells()
	var affected_cells: Array[Vector2i] = []
	var trajectory_cells: Array[Vector2i] = []
	if is_valid:
		affected_cells = _ability_targeting.get_affected_cells(
			_selected_character.grid_cell,
			cell,
			_selected_ability,
			wall_cells
		)
		if _selected_ability.shape == AbilityDefinition.Shape.LINE_FROM_CASTER:
			trajectory_cells = _ability_targeting.get_trajectory_cells(
				_selected_character.grid_cell,
				cell,
				wall_cells
			)
	if (
		_selected_ability.delivery_type == AbilityDefinition.DeliveryType.PROJECTILE
		and _ability_range_cells.has(cell)
	):
		trajectory_cells = _ability_executor.projectile_delivery.get_preview(
			_selected_character.grid_cell,
			cell,
			wall_cells
		)
	grid.show_ability_preview(cell, affected_cells, trajectory_cells, is_valid)


func _handle_ability_click(global_mouse: Vector2) -> void:
	var target_cell := _get_ability_cell_at_global_point(global_mouse)
	if not _ability_target_cells.has(target_cell):
		return
	_begin_ability_cast(target_cell)


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
		_get_wall_cells()
	)
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


func _begin_friendly_move(path: Array[Vector2i]) -> void:
	if _movement_locked or _selected_character != turn_manager.current_unit:
		return
	var path_cost := _pathfinder.get_path_cost(path)
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
		and moving_character.current_health <= 0
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
	if not executed and unit == turn_manager.current_unit and unit.current_health > 0:
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
			_get_wall_cells()
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
			blocked_cells
		)
	if path.size() < 2:
		return false
	var path_cost := _pathfinder.get_path_cost(path)
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

	var step_cost := _pathfinder.get_step_cost(current_cell, next_cell)
	return mover.spend_movement(step_cost)


func _update_ai_debug(
	unit: TacticalCharacter,
	plan: EnemyTurnPlan,
	status: String = "Chosen"
) -> void:
	if not enable_dev_tools:
		return
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
	_ai_debug_history.append("\n".join(lines))
	while _ai_debug_history.size() > ai_debug_history_limit:
		_ai_debug_history.remove_at(0)
	_refresh_ai_debug_history()


func _on_dev_button_pressed() -> void:
	if not enable_dev_tools:
		return
	dev_history_panel.visible = not dev_history_panel.visible


func _on_levels_button_pressed() -> void:
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
		and not _selected_ability.can_be_used_by(character)
	):
		_cancel_ability_targeting()
	if character == turn_manager.current_unit:
		_refresh_ability_bar()
		_update_turn_hud()
	if character == _selected_character and not _movement_locked:
		_refresh_reachable_cells()


func _on_character_equipment_changed(
	_slot: ItemDefinition.EquipmentSlot,
	_item: ItemDefinition,
	character: TacticalCharacter
) -> void:
	_on_inventory_equipment_updated(character)


func _refresh_ai_debug_history() -> void:
	if ai_debug_label == null:
		return
	if _ai_debug_history.is_empty():
		ai_debug_label.text = "No AI decisions recorded yet.\nEnd a friendly turn to let an enemy act."
		return
	var newest_first: Array[String] = []
	for index in range(_ai_debug_history.size() - 1, -1, -1):
		newest_first.append(_ai_debug_history[index])
	ai_debug_label.text = "\n\n────────────────────────────────────────\n\n".join(newest_first)


func _on_turn_starting(unit: TacticalCharacter) -> void:
	if _combat_over:
		return
	terrain.apply_trigger(unit, TileTriggeredEffectDefinition.Trigger.TURN_START)


func _on_turn_started(unit: TacticalCharacter) -> void:
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
	if not _combat_over and character == turn_manager.current_unit:
		turn_manager.end_current_turn()


func _on_unit_movement_changed(_remaining: float, _maximum: float, unit: TacticalCharacter) -> void:
	if unit == turn_manager.current_unit:
		_update_turn_hud()


func _on_unit_ability_availability_changed(_available: bool, unit: TacticalCharacter) -> void:
	if unit == turn_manager.current_unit:
		_refresh_ability_bar()
		_update_turn_hud()


func _set_movement_locked(value: bool) -> void:
	_movement_locked = true if _combat_over else value
	_refresh_ability_bar()
	_update_turn_hud()


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
		turn_status.text = _combat_result_text
		movement_status.text = ""
		end_turn_button.text = "Battle Ended"
		end_turn_button.disabled = true
		return
	var unit := turn_manager.current_unit
	if unit == null:
		turn_status.text = "No Active Unit"
		movement_status.text = ""
		end_turn_button.disabled = true
		return

	turn_status.text = "%s's Turn | Round %d" % [unit.name, turn_manager.round_number]
	if unit.is_friendly():
		movement_status.text = "%s | Move %.2f / %.2f | Ability %s" % [
			unit.name,
			unit.remaining_movement,
			unit.get_movement_range(),
			"Ready" if unit.ability_available else "Used",
		]
		end_turn_button.text = "End Turn"
		end_turn_button.disabled = _movement_locked
	else:
		movement_status.text = "%s is acting..." % unit.name
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
	return true


func _get_living_friendlies() -> Array[TacticalCharacter]:
	var friendlies: Array[TacticalCharacter] = []
	for character in _characters:
		if is_instance_valid(character) and character.is_friendly() and character.current_health > 0:
			friendlies.append(character)
	return friendlies


func _get_character_at(cell: Vector2i) -> TacticalCharacter:
	for character in _characters:
		if is_instance_valid(character) and character.grid_cell == cell:
			return character
	return null


func _get_character_at_global_point(point: Vector2) -> TacticalCharacter:
	for character in _characters:
		if is_instance_valid(character) and character.contains_global_point(point):
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
		if is_instance_valid(character) and character != except_character:
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
