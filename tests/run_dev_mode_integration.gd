extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_pause_resume_dirty_and_unit_operations()
	paused = false
	await _test_delete_authored_units_then_restart()
	paused = false
	_test_enemy_removal_and_save_round_trip()
	paused = false
	await _test_atomic_cross_map_load()
	paused = false
	if _failures.is_empty():
		print("ALL_DEV_MODE_INTEGRATION_OK")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_pause_resume_dirty_and_unit_operations() -> void:
	var hidden_battle := _spawn_battle(false)
	_check(hidden_battle.initialization_succeeded, "hidden-controls battle initializes")
	_check(hidden_battle.dev_button.visible, "legacy enable_dev_tools false no longer hides Dev")
	hidden_battle._on_dev_button_pressed()
	_check(hidden_battle._dev_open and paused, "legacy false also permits opening Dev")
	hidden_battle._on_dev_play_requested()
	_remove_now(hidden_battle)

	var battle := _spawn_battle(true)
	_check(battle.initialization_succeeded, "developer battle initializes")
	_check(battle.dev_button.visible, "enable_dev_tools true shows Dev")
	battle._on_dev_button_pressed()
	_check(paused, "opening Dev pauses the scene tree")
	_check(battle.dev_mode_panel.visible, "opening Dev shows the drawer")
	_check(not battle.names_button.disabled, "Names remains available while Dev is paused")
	_check(battle.dev_button.disabled, "Dev cannot be reopened while its drawer is active")
	_check(battle.inventory_button.disabled, "Inventory remains blocked while Dev is active")
	_check(battle.restart_button.disabled, "Restart remains blocked while Dev is active")
	_check(battle.levels_button.disabled, "Levels remains blocked while Dev is active")
	var dirty_before_names := battle._dev_dirty
	battle.names_button.button_pressed = false
	_check(paused, "toggling names does not resume Dev Mode")
	_check(battle._dev_dirty == dirty_before_names, "toggling names does not mark setup dirty")
	_check(battle.names_button.text == "Names: Off", "the Dev-accessible toggle reflects its hidden state")
	for character in battle._characters:
		_check(not character.is_unit_name_visible(), "the toggle hides every existing unit name")
	_test_dev_camera_middle_pan(battle)
	var drawer_rect := battle.dev_mode_panel.drawer.get_global_rect()
	_check(drawer_rect.position == Vector2.ZERO, "drawer anchors to the upper-left corner")
	_check(is_equal_approx(drawer_rect.size.x, 466.0), "drawer keeps its compact width")
	_check(is_equal_approx(drawer_rect.size.y, battle.dev_mode_panel.size.y), "drawer fills the available window height")
	_test_ai_log_copy(battle)
	_test_heal_selected_unit(battle)
	var exact_payload := battle.capture_save_payload(false)
	_check(ScenarioSaveStore.validate_payload(exact_payload).ok, "clean paused battle validates as an exact snapshot")
	battle._on_dev_play_requested()
	_check(not paused, "Resume continues the exact battle")
	_check(
		battle.tactical_camera.process_mode == Node.PROCESS_MODE_PAUSABLE,
		"Resume returns the camera to normal pausable processing"
	)

	battle._on_dev_button_pressed()
	var initial_count := battle._characters.size()
	_check(battle._is_valid_dev_cell(Vector2i(0, 0)), "empty in-bounds cells accept units")
	_check(not battle._is_valid_dev_cell(Vector2i(-1, 0)), "out-of-bounds cells reject units")
	_check(not battle._is_valid_dev_cell(Vector2i(4, 9)), "occupied cells reject units")
	battle._add_dev_unit(battle.dev_tool_catalog.unit_scenes[7], Vector2i(0, 0))
	_check(battle._characters.size() == initial_count + 1, "palette placement adds one unit")
	var added := battle.dev_mode_panel.get_selected_unit()
	_check(not added.is_unit_name_visible(), "Dev-added units inherit the current hidden-name setting")
	battle.names_button.button_pressed = true
	_check(added.is_unit_name_visible(), "showing names updates a Dev-added unit immediately")
	_check(not added.scenario_unit_id.is_empty(), "added units receive stable IDs")
	added.set_grid_cell_immediate(Vector2i(1, 0))
	_check(added.starting_grid_cell == Vector2i(1, 0), "developer movement updates restart placement")
	battle._on_dev_delete_selected()
	_check(battle._characters.size() == initial_count, "Delete removes the selected unit without confirmation")

	var emitted_payloads: Array[Dictionary] = []
	battle.battle_reload_requested.connect(func(payload: Dictionary) -> void:
		emitted_payloads.append(payload)
	)
	var selected := battle._characters[0]
	selected.set_dev_stat_override(UnitStat.Type.CONSTITUTION, 42.0)
	battle._on_dev_setup_changed()
	_check(battle.dev_mode_panel.play_button.text == "Restart & Play", "dirty setup labels the restart action")
	selected.current_health = selected.get_max_health() - 1
	battle.dev_mode_panel.select_unit(selected)
	battle.dev_mode_panel.heal_unit_button.pressed.emit()
	_check(battle.dev_mode_panel.play_button.text == "Restart & Play", "runtime healing preserves an existing dirty setup")
	battle._on_dev_play_requested()
	_check(emitted_payloads.size() == 1, "dirty Play requests a battle rebuild")
	if emitted_payloads.size() == 1:
		_check(emitted_payloads[0].runtime.fresh_start, "dirty Play emits a canonical fresh setup")
		_check(emitted_payloads[0].metadata.round == 1, "dirty Play restarts at round one")
	_check(not paused, "dirty standalone Play does not leave the tree paused")
	selected.apply_damage(7)
	selected._set_runtime_grid_cell_immediate(Vector2i(0, 0))
	battle.turn_manager.round_number = 5
	battle.restart_button.pressed.emit()
	_check(emitted_payloads.size() == 2, "the standalone Restart button requests a battle rebuild")
	if emitted_payloads.size() == 2:
		var restart_payload := emitted_payloads[1]
		_check(restart_payload.runtime.fresh_start, "Restart emits a fresh-start payload")
		_check(restart_payload.metadata.round == 1, "Restart discards the current round")
		var selected_setup: Dictionary = {}
		for unit_setup in restart_payload.setup.units:
			if unit_setup.id == selected.scenario_unit_id:
				selected_setup = unit_setup
				break
		_check(not selected_setup.is_empty(), "Restart preserves the configured unit")
		if not selected_setup.is_empty():
			_check(
				int(selected_setup.stat_overrides.constitution) == 42,
				"Restart preserves developer-authored stat overrides"
			)
			_check(
				selected_setup.cell == [selected.starting_grid_cell.x, selected.starting_grid_cell.y],
				"Restart uses the configured starting cell instead of the runtime cell"
			)
	_check(not paused, "the standalone Restart button does not pause the tree")
	_remove_now(battle)


func _test_delete_authored_units_then_restart() -> void:
	var manager := (load("res://main.tscn") as PackedScene).instantiate() as MapManager
	root.add_child(manager)
	var map := load("res://resources/maps/goblin_skirmish.tres") as BattleMapDefinition
	_check(manager.load_level(map), "delete-restart battle loads")
	var source := manager.current_battle
	_check(
		await _open_dev_at_stable_boundary(source),
		"delete-restart flow reaches a stable Dev Mode boundary"
	)
	if not source._dev_open:
		_remove_now(manager)
		return

	var removed_current := source.turn_manager.current_unit
	var removed_queued: TacticalCharacter
	for candidate in source.turn_manager.turn_order:
		if candidate != removed_current and not candidate.is_friendly():
			removed_queued = candidate
			break
	_check(removed_current != null and removed_queued != null, "delete-restart flow finds current and queued authored units")
	if removed_current == null or removed_queued == null:
		_remove_now(manager)
		return
	var removed_ids := [
		removed_current.scenario_unit_id,
		removed_queued.scenario_unit_id,
	]

	source.dev_mode_panel.select_unit(removed_current)
	source._on_dev_delete_selected()
	_check(source.turn_manager.current_unit == null, "deleting the active unit clears the obsolete active turn")
	_check(not source.turn_manager.turn_order.has(removed_current), "the active unit leaves turn order before queue_free")
	source.dev_mode_panel.select_unit(removed_queued)
	source._on_dev_delete_selected()
	_check(not source.turn_manager.turn_order.has(removed_queued), "a queued unit leaves turn order before queue_free")
	await process_frame
	_check(not is_instance_valid(removed_current), "the deleted active unit is freed before restart")
	_check(not is_instance_valid(removed_queued), "the deleted queued unit is freed before restart")

	source._on_dev_play_requested()
	await process_frame
	var replacement := manager.current_battle
	_check(replacement != null and replacement != source, "Restart & Play replaces the edited battle")
	if replacement != null and replacement != source:
		_check(replacement.turn_manager.round_number == 1, "the replacement starts at round one")
		for removed_id in removed_ids:
			_check(_find_unit(replacement, removed_id) == null, "deleted stable ID %s stays removed" % removed_id)
		for ordered_unit in replacement.turn_manager.turn_order:
			_check(is_instance_valid(ordered_unit), "replacement turn order contains only valid units")
			_check(replacement._characters.has(ordered_unit), "replacement turn order contains only registered battle units")
	_check(not paused, "Restart & Play resumes after deleting authored units")
	_remove_now(manager)


func _test_ai_log_copy(battle: TacticalBattle) -> void:
	var panel := battle.dev_mode_panel
	_check(panel.copy_ai_log_button.disabled, "Copy Logs is disabled before the first AI decision")
	var older_entry := (
		"Round 1 | Goblin Warrior | Defensive\n"
		+ "Planning: 5.1 ms | Cache: 2 hits, 0 misses\n"
		+ "1. Guard — 62.0"
	)
	var newer_entry := (
		"Round 2 | Goblin Scout | Aggressive\n"
		+ "Planning: 8.2 ms | Cache: 4 hits, 1 miss\n"
		+ "1. Arrow Shot — 83.5\n2. Move — 41.0"
	)
	battle._ai_debug_history.assign([older_entry, newer_entry])
	battle._refresh_ai_debug_history()
	var retained_history := (
		newer_entry
		+ "\n\n────────────────────────────────────────\n\n"
		+ older_entry
	)
	_check(not panel.copy_ai_log_button.disabled, "the first retained AI decision enables Copy Logs")
	_check(panel.ai_log_entries.get_child_count() == 2, "the AI Log creates one clickable row per retained decision")
	var newest_button := panel.ai_log_entries.get_child(0) as Button
	var oldest_button := panel.ai_log_entries.get_child(1) as Button
	_check(
		newest_button.text
		== "Round 2 | Goblin Scout | Aggressive — Planning: 8.2 ms | Cache: 4 hits, 1 miss",
		"the AI Log displays compact retained decisions newest first"
	)
	_check(
		oldest_button.text
		== "Round 1 | Goblin Warrior | Defensive — Planning: 5.1 ms | Cache: 2 hits, 0 misses",
		"the AI Log keeps compact older decisions below newer ones"
	)
	_check(
		newest_button.tooltip_text.contains("Restore to immediately before"),
		"AI Log entries explain their checkpoint action"
	)
	_check(
		newest_button.tooltip_text.contains(newer_entry),
		"AI Log entry tooltips retain the full decision diagnostics"
	)

	var clipboard_available := DisplayServer.get_name() != "headless"
	var previous_clipboard := DisplayServer.clipboard_get() if clipboard_available else ""
	var current_unit_before := battle.turn_manager.current_unit
	var round_before := battle.turn_manager.round_number
	var dirty_before := panel._dirty
	var runtime_before: Dictionary = battle.capture_save_payload(false).runtime.duplicate(true)
	panel.copy_ai_log_button.pressed.emit()
	_check(panel._ai_history_copy_text == retained_history, "Copy Logs retains the displayed history as its exact clipboard payload")
	if clipboard_available:
		_check(
			DisplayServer.clipboard_get().replace("\r\n", "\n") == retained_history,
			"Copy Logs copies the displayed retained history exactly apart from platform newline representation"
		)
	_check(
		panel.status_label.text == "AI logs copied. Paste them into your LLM chat.",
		"Copy Logs shows paste-ready success feedback"
	)
	_check(paused, "copying AI logs keeps Dev mode paused")
	_check(battle.turn_manager.current_unit == current_unit_before, "copying AI logs does not change the active unit")
	_check(battle.turn_manager.round_number == round_before, "copying AI logs does not change the round")
	_check(panel._dirty == dirty_before, "copying AI logs does not change setup-dirty state")
	_check(
		battle.capture_save_payload(false).runtime == runtime_before,
		"copying AI logs does not change exact-save runtime state"
	)
	if clipboard_available:
		DisplayServer.clipboard_set(previous_clipboard)


func _test_dev_camera_middle_pan(battle: TacticalBattle) -> void:
	var camera := battle.tactical_camera
	_check(camera.is_dev_mode_pan_enabled(), "Dev mode enables middle-button camera panning")
	_check(
		camera.process_mode == Node.PROCESS_MODE_ALWAYS,
		"the camera keeps processing while Dev mode pauses combat"
	)
	var starting_position := camera.position
	var starting_zoom := camera.zoom
	var middle_press := InputEventMouseButton.new()
	middle_press.button_index = MOUSE_BUTTON_MIDDLE
	middle_press.pressed = true
	camera._input(middle_press)
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(48.0, -24.0)
	camera._input(drag)
	var middle_release := InputEventMouseButton.new()
	middle_release.button_index = MOUSE_BUTTON_MIDDLE
	middle_release.pressed = false
	camera._input(middle_release)
	_check(
		camera.position == starting_position - drag.relative / starting_zoom.x,
		"middle-button dragging pans the map while Dev mode is active"
	)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	camera._input(wheel)
	_check(camera.zoom == starting_zoom, "Dev mode still blocks wheel zoom")


func _test_heal_selected_unit(battle: TacticalBattle) -> void:
	var friendly: TacticalCharacter
	var enemy: TacticalCharacter
	for character in battle._characters:
		if character.is_friendly() and friendly == null:
			friendly = character
		elif not character.is_friendly() and enemy == null:
			enemy = character
	_check(friendly != null and enemy != null, "heal test finds both factions")
	if friendly == null or enemy == null:
		return
	battle.dev_mode_panel.select_unit(friendly)
	var saw_damage := false
	var saw_no_damage := false
	for entry in battle.dev_mode_panel.ability_entries.get_children():
		var ability := entry.get_meta("ability") as AbilityDefinition
		var breakdown := entry.get_node("DamageBreakdown") as Label
		_check(ability != null and breakdown != null, "each Dev ability row exposes its damage breakdown")
		if ability == null or breakdown == null:
			continue
		_check(
			breakdown.text == ability.get_damage_calculation_description(friendly),
			"Dev ability rows use the selected unit's live calculation"
		)
		if ability.has_damage():
			saw_damage = true
		else:
			saw_no_damage = true
	_check(saw_damage, "the Dev ability list shows damaging calculations")
	_check(saw_no_damage, "the Dev ability list labels non-damaging abilities")

	var heal_button := battle.dev_mode_panel.heal_unit_button
	battle.dev_mode_panel.clear_unit_selection()
	_check(heal_button.disabled, "Heal is disabled without a selected unit")

	var burning := load("res://resources/statuses/burning.tres") as StatusEffectDefinition
	var heal_targets: Array[TacticalCharacter] = [friendly, enemy]
	for unit: TacticalCharacter in heal_targets:
		var maximum_health: int = unit.get_max_health()
		battle.dev_mode_panel.select_unit(unit)
		_check(heal_button.disabled, "Heal is disabled for a full-health unit")
		unit.current_health = maximum_health - 7
		unit.reset_movement()
		unit.spend_movement(1.0)
		unit.reset_ability_action()
		unit.spend_ability_action()
		unit.reset_opportunity_reaction()
		unit.spend_opportunity_reaction()
		var status_source: TacticalCharacter = enemy if unit == friendly else friendly
		_check(unit.apply_status(burning, null, status_source), "heal test applies a retained status")
		battle.dev_mode_panel.select_unit(unit)
		_check(not heal_button.disabled, "Heal is enabled for a wounded living unit")
		_check(
			battle.dev_mode_panel.derived_stats.text.begins_with(
				"Health: %d / %d" % [unit.current_health, maximum_health]
			),
			"the Unit tab shows current and maximum health"
		)
		var health_events: Array[Array] = []
		unit.health_changed.connect(func(current: int, maximum: int) -> void:
			health_events.append([current, maximum])
		, CONNECT_ONE_SHOT)
		var movement_before: float = unit.remaining_movement
		var action_before: bool = unit.ability_available
		var reaction_before: bool = unit.opportunity_reaction_available
		var statuses_before: Array[ActiveStatus] = unit.get_active_statuses()
		var equipment_before: Array[ItemDefinition] = unit.get_equipped_items()
		heal_button.pressed.emit()
		_check(unit.current_health == maximum_health, "Heal restores the selected unit to full health")
		_check(health_events.size() == 1, "Heal emits one health update")
		_check(heal_button.disabled, "Heal disables after reaching full health")
		_check(is_equal_approx(unit.remaining_movement, movement_before), "Heal does not change movement")
		_check(unit.ability_available == action_before, "Heal does not change action availability")
		_check(unit.opportunity_reaction_available == reaction_before, "Heal does not change reaction availability")
		_check(unit.get_active_statuses() == statuses_before, "Heal does not change statuses")
		_check(unit.get_equipped_items() == equipment_before, "Heal does not change equipment")
		_check(battle.dev_mode_panel.play_button.text == "Resume", "Heal does not mark a clean setup dirty")
		var exact_payload := battle.capture_save_payload(false)
		var saved_health := -1
		for runtime_unit in exact_payload.runtime.units:
			if runtime_unit.id == unit.scenario_unit_id:
				saved_health = int(runtime_unit.current_health)
				break
		_check(saved_health == maximum_health, "exact saves preserve healed health")

	friendly.current_health = 0
	battle.dev_mode_panel.select_unit(friendly)
	_check(heal_button.disabled, "Heal is disabled for a defeated unit")
	battle._on_dev_heal_selected()
	_check(friendly.current_health == 0, "Heal does not revive a defeated unit")
	friendly.current_health = friendly.get_max_health()
	battle.dev_mode_panel.select_unit(friendly)


func _test_enemy_removal_and_save_round_trip() -> void:
	var manager := (load("res://main.tscn") as PackedScene).instantiate() as MapManager
	root.add_child(manager)
	var map := load("res://resources/maps/goblin_skirmish.tres") as BattleMapDefinition
	_check(manager.load_level(map), "enemy-removal battle loads")
	var battle := manager.current_battle
	var active := battle.turn_manager.current_unit
	var enemies: Array[TacticalCharacter] = []
	for unit in battle._characters:
		if not unit.is_friendly():
			enemies.append(unit)
	_check(active != null and not enemies.is_empty(), "enemy-removal battle finds both factions")
	if active == null or enemies.is_empty():
		_remove_now(manager)
		return

	var removed_enemy := enemies[0]
	var removed_id := removed_enemy.scenario_unit_id
	var active_id := active.scenario_unit_id
	var vacated_cell := removed_enemy.grid_cell
	var burning := load("res://resources/statuses/burning.tres") as StatusEffectDefinition
	_check(active.apply_status(burning, null, removed_enemy), "a living enemy can be retained as a status source")
	for enemy in enemies:
		enemy.apply_damage(enemy.current_health)
		_check(not enemy.is_present_on_map(), "defeated enemies leave the tactical map")
		_check(not enemy.visible, "defeated enemies disappear immediately")
		_check(battle._characters.has(enemy), "defeated enemies remain in saved battle state")
		_check(enemy.get_parent() == battle.characters_container, "defeated enemies retain their scene node")

	_check(battle._combat_over and battle._combat_result_text == "Victory", "defeating the final enemy still wins the battle")
	_check(not battle.turn_manager.get_rotating_order().has(removed_enemy), "defeated enemies leave the visible turn order")
	_check(battle._get_character_at(vacated_cell) == null, "a removed enemy no longer occupies its cell")
	_check(
		battle._get_character_at_global_point(removed_enemy.global_position + Vector2(0.0, -29.0)) == null,
		"a removed enemy no longer intercepts pointer hit testing"
	)
	var blocked := battle._get_blocked_cells(active)
	_check(not blocked.has(vacated_cell), "a removed enemy no longer blocks movement")
	var path := battle._pathfinder.find_path(active.grid_cell, vacated_cell, INF, blocked)
	_check(not path.is_empty() and path[path.size() - 1] == vacated_cell, "the vacated enemy cell is traversable")

	active._set_runtime_grid_cell_immediate(vacated_cell)
	var exact_payload := battle.capture_save_payload(false)
	_check(ScenarioSaveStore.validate_payload(exact_payload).ok, "an exact save permits a living unit on a removed enemy cell")
	_check(manager.reload_battle_from_payload(exact_payload, battle), "the removed-enemy exact save reloads")
	var restored := manager.current_battle
	var restored_enemy := _find_unit(restored, removed_id)
	var restored_active := _find_unit(restored, active_id)
	_check(restored_enemy != null and restored_active != null, "exact load retains stable unit IDs")
	if restored_enemy != null and restored_active != null:
		_check(restored_enemy.current_health == 0, "exact load restores defeated enemy health")
		_check(not restored_enemy.visible and not restored_enemy.is_present_on_map(), "exact load keeps defeated enemies absent")
		_check(restored_active.grid_cell == vacated_cell, "exact load restores the reused enemy cell")
		_check(not restored._get_blocked_cells(restored_active).has(vacated_cell), "restored removed enemies do not block their cell")
		var statuses := restored_active.get_active_statuses()
		_check(not statuses.is_empty(), "exact load restores statuses sourced by a defeated enemy")
		if not statuses.is_empty():
			_check(statuses[0].source_unit == restored_enemy, "exact load reconnects the removed status source")

	var fresh_payload := restored.capture_save_payload(true)
	_check(manager.reload_battle_from_payload(fresh_payload, restored), "Restart & Play setup reloads after enemy removal")
	var restarted_enemy := _find_unit(manager.current_battle, removed_id)
	_check(restarted_enemy != null, "fresh restart retains the configured enemy")
	if restarted_enemy != null:
		_check(restarted_enemy.current_health == restarted_enemy.get_max_health(), "fresh restart restores enemy health")
		_check(restarted_enemy.visible and restarted_enemy.is_present_on_map(), "fresh restart returns the enemy to the map")

	var button_source := manager.current_battle
	var button_source_id := button_source.get_instance_id()
	var button_active := _find_unit(button_source, active_id)
	var button_enemy: TacticalCharacter
	for candidate in button_source._characters:
		if not candidate.is_friendly() and candidate != button_active:
			button_enemy = candidate
			break
	_check(button_active != null and button_enemy != null, "Restart button fixture finds configured units")
	if button_active != null and button_enemy != null:
		button_active.set_dev_stat_override(UnitStat.Type.CONSTITUTION, 37.0)
		var configured_health := button_active.get_max_health()
		var configured_cell := button_active.starting_grid_cell
		var starting_inventory_count := button_source.general_inventory.get_items().size()
		button_active.apply_damage(9)
		button_active._set_runtime_grid_cell_immediate(Vector2i(0, 0))
		button_active.apply_status(burning, null, button_enemy)
		button_source.general_inventory.add_item(
			load("res://resources/items/goblin_club.tres") as ItemDefinition
		)
		button_source.turn_manager.round_number = 6
		var button_enemy_id := button_enemy.scenario_unit_id
		button_enemy.apply_damage(button_enemy.current_health)
		button_source.restart_button.pressed.emit()
		var button_replacement := manager.current_battle
		var replacement_active := _find_unit(button_replacement, active_id)
		var replacement_enemy := _find_unit(button_replacement, button_enemy_id)
		_check(button_replacement.get_instance_id() != button_source_id, "Restart button replaces the battle instance")
		_check(button_replacement.map_definition == map, "Restart button keeps the current map")
		_check(button_replacement.turn_manager.round_number == 1, "Restart button returns combat to round one")
		_check(replacement_active != null, "Restart button preserves configured units")
		if replacement_active != null:
			_check(replacement_active.constitution_override == 37, "Restart button preserves developer-authored stats")
			_check(replacement_active.current_health == configured_health, "Restart button restores full configured health")
			_check(replacement_active.grid_cell == configured_cell, "Restart button restores the configured starting cell")
			_check(replacement_active.get_active_statuses().is_empty(), "Restart button clears runtime statuses")
		_check(
			replacement_enemy != null and replacement_enemy.current_health == replacement_enemy.get_max_health(),
			"Restart button restores defeated units"
		)
		_check(
			button_replacement.general_inventory.get_items().size() == starting_inventory_count,
			"Restart button restores starting inventory"
		)
		_check(not button_replacement.return_to_levels_dialog.visible, "Restart button does not open a confirmation dialog")
		_check(not paused, "Restart button leaves battle processing unpaused")
	_remove_now(manager)


func _test_atomic_cross_map_load() -> void:
	var target_fixture := _spawn_battle(true, "res://resources/maps/terrain_showcase.tres")
	var terrain_payload := target_fixture.capture_save_payload(true)
	_remove_now(target_fixture)

	var manager := (load("res://main.tscn") as PackedScene).instantiate() as MapManager
	root.add_child(manager)
	var goblin_map := load("res://resources/maps/goblin_skirmish.tres") as BattleMapDefinition
	_check(manager.load_level(goblin_map), "source battle loads")
	var source := manager.current_battle
	var invalid := terrain_payload.duplicate(true)
	invalid.map_definition = "res://resources/maps/missing.tres"
	_check(not manager.reload_battle_from_payload(invalid, source), "invalid payload is rejected")
	_check(manager.current_battle == source, "failed load retains the exact current battle")
	source._on_dev_play_requested()

	_check(manager.reload_battle_from_payload(terrain_payload, source), "configured cross-map save loads")
	_check(manager.current_battle != source, "successful load swaps the battle instance")
	_check(manager.current_battle.map_definition.resource_path == "res://resources/maps/terrain_showcase.tres", "cross-map load uses the saved map")
	_check(manager.current_battle.initialization_succeeded, "replacement initializes before source removal")
	_check(not paused, "successful load resumes immediately")
	_check(manager.current_battle.turn_manager.round_number == 1, "fresh edited load begins on round one")

	var exact_source := manager.current_battle
	_check(
		await _open_dev_at_stable_boundary(exact_source),
		"exact save reaches a stable Dev Mode boundary"
	)
	var active := exact_source.turn_manager.current_unit
	var status_source: TacticalCharacter
	for candidate in exact_source._characters:
		if candidate != active:
			status_source = candidate
			break
	active.current_health -= 9
	active.spend_movement(1.5)
	active.spend_ability_action()
	active.spend_opportunity_reaction()
	active.apply_status(
		load("res://resources/statuses/burning.tres") as StatusEffectDefinition,
		load("res://resources/abilities/fireball.tres") as AbilityDefinition,
		status_source
	)
	exact_source.general_inventory.add_item(
		load("res://resources/items/goblin_club.tres") as ItemDefinition
	)
	exact_source.turn_manager.round_number = 3
	var active_id := active.scenario_unit_id
	var status_source_id := status_source.scenario_unit_id
	var saved_health := active.current_health
	var saved_movement := active.remaining_movement
	var exact_payload := exact_source.capture_save_payload(false)
	var exact_reload_ok := manager.reload_battle_from_payload(exact_payload, exact_source)
	_check(
		exact_reload_ok,
		"an exact mid-battle snapshot reloads (%s)" % exact_source.dev_mode_panel.status_label.text
	)
	var exact_replacement := manager.current_battle
	var restored_active := exact_replacement.turn_manager.current_unit
	_check(restored_active.scenario_unit_id == active_id, "exact load restores the active stable unit ID")
	_check(exact_replacement.turn_manager.round_number == 3, "exact load restores the round")
	_check(restored_active.current_health == saved_health, "exact load restores current health")
	_check(is_equal_approx(restored_active.remaining_movement, saved_movement), "exact load restores remaining movement")
	_check(not restored_active.ability_available, "exact load restores the spent action")
	_check(not restored_active.opportunity_reaction_available, "exact load restores the spent reaction")
	_check(exact_replacement.general_inventory.capture_state() == exact_payload.runtime.inventory, "exact load restores ordered general inventory")
	var restored_statuses := restored_active.get_active_statuses()
	_check(restored_statuses.size() == 1, "exact load restores active statuses")
	if restored_statuses.size() == 1:
		_check(restored_statuses[0].source is AbilityDefinition, "exact load restores a status resource source")
		_check(restored_statuses[0].source_unit.scenario_unit_id == status_source_id, "exact load reconnects status source units by stable ID")
	_check(not paused, "exact load also resumes immediately")

	var completed_source := manager.current_battle
	completed_source._combat_over = true
	completed_source._combat_result_text = "Victory"
	completed_source._movement_locked = true
	completed_source.turn_manager.stop_combat()
	completed_source._on_dev_button_pressed()
	var completed_payload := completed_source.capture_save_payload(false)
	_check(manager.reload_battle_from_payload(completed_payload, completed_source), "completed battles reload")
	_check(manager.current_battle._combat_over, "completed battle flag round-trips")
	_check(manager.current_battle._combat_result_text == "Victory", "completed battle result round-trips")
	_check(manager.current_battle.turn_manager.current_unit == null, "completed battle restores without an active turn")
	_remove_now(manager)
	if is_instance_valid(source):
		source.free()


func _open_dev_at_stable_boundary(battle: TacticalBattle) -> bool:
	battle._on_dev_button_pressed()
	for _frame in range(600):
		if battle._dev_open:
			return true
		await process_frame
	return false


func _spawn_battle(
	dev_tools_enabled: bool,
	map_path := "res://resources/maps/goblin_skirmish.tres"
) -> TacticalBattle:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.enable_dev_tools = dev_tools_enabled
	battle.map_definition = load(map_path) as BattleMapDefinition
	root.add_child(battle)
	return battle


func _find_unit(battle: TacticalBattle, stable_id: String) -> TacticalCharacter:
	for unit in battle._characters:
		if unit.scenario_unit_id == stable_id:
			return unit
	return null


func _remove_now(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
