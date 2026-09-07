extends SceneTree

const CHECKPOINT_TIMEOUT_MSEC := 5000

var _failed := false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_panel_entries()
	await _test_checkpoint_restore_and_branching()
	paused = false
	if _failed:
		quit(1)
	else:
		print("AI_LOG_CHECKPOINT_INTEGRATION_OK")
		quit(0)


func _test_panel_entries() -> void:
	var panel := (load("res://scenes/dev_mode_panel.tscn") as PackedScene).instantiate() as DevModePanel
	root.add_child(panel)
	await process_frame
	_check(panel.ai_log_empty_state.visible, "the authored AI Log empty state starts visible")
	_check(panel.ai_log_entries.get_child_count() == 0, "the authored AI Log entry container starts empty")
	_check(panel.copy_ai_log_button.disabled, "Copy Logs starts disabled")
	var entries: Array[String] = [
		"Round 1 · Older Enemy · General AI\n\nChosen in 2 ms: Hold position\nSearch details",
		"Round 2 · Newer Enemy · Aggressive AI\nChosen in 4 ms: Use Fireball\nCache details",
	]
	var requested_indices: Array[int] = []
	panel.ai_history_restore_requested.connect(func(history_index: int) -> void:
		requested_indices.append(history_index)
	)
	panel.set_ai_history(entries)
	_check(not panel.ai_log_empty_state.visible, "adding AI history hides the empty state")
	_check(panel.ai_log_entries.get_child_count() == 2, "each AI decision receives a clickable row")
	var newest_button := panel.ai_log_entries.get_child(0) as Button
	var oldest_button := panel.ai_log_entries.get_child(1) as Button
	_check(
		newest_button.text == "Round 2 · Newer Enemy · Aggressive AI — Chosen in 4 ms: Use Fireball",
		"AI decisions display a compact newest-first summary"
	)
	_check(
		oldest_button.text == "Round 1 · Older Enemy · General AI — Chosen in 2 ms: Hold position",
		"compact summaries use the first two non-empty log lines"
	)
	_check(is_equal_approx(newest_button.custom_minimum_size.y, 36.0), "AI decision rows use the compact height")
	_check(newest_button.autowrap_mode == TextServer.AUTOWRAP_OFF, "AI decision summaries stay on one line")
	_check(newest_button.clip_text, "AI decision summaries remain within the drawer width")
	_check(
		newest_button.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS,
		"long AI decision summaries trim with an ellipsis"
	)
	_check(panel.ai_log_entries.get_theme_constant("separation") == 4, "compact AI decision rows use reduced spacing")
	_check(
		newest_button.tooltip_text.begins_with("Restore to immediately before this AI decision\n\n"),
		"AI decision rows explain their restore behavior"
	)
	_check(
		newest_button.tooltip_text.contains(entries[1]),
		"AI decision tooltips retain the complete diagnostic text"
	)
	newest_button.pressed.emit()
	oldest_button.pressed.emit()
	_check(requested_indices == [1, 0], "clickable rows emit their chronological history index")
	_check(
		panel._ai_history_copy_text
		== "%s%s%s" % [entries[1], DevModePanel.AI_LOG_SEPARATOR, entries[0]],
		"Copy Logs keeps the prior newest-first plain-text format"
	)
	panel.set_ai_history(entries, 0)
	newest_button = panel.ai_log_entries.get_child(0) as Button
	oldest_button = panel.ai_log_entries.get_child(1) as Button
	_check(oldest_button.button_pressed, "the selected checkpoint uses the pressed button style")
	_check(not newest_button.button_pressed and not newest_button.disabled, "future logs stay visible and clickable")
	_check(newest_button.tooltip_text.begins_with("Future log"), "future logs explain that they remain selectable")
	panel.open_panel(DevModePanel.AI_LOG_TAB)
	_check(panel.tabs.current_tab == DevModePanel.AI_LOG_TAB, "the panel can open directly on AI Log")
	var overflow_entries: Array[String] = []
	for index in range(30):
		overflow_entries.append(
			"Round %d · Enemy %d · General AI\nChosen in 1 ms: Hold\nFull details %d"
			% [index + 1, index + 1, index + 1]
		)
	panel.set_ai_history(overflow_entries)
	await process_frame
	await process_frame
	panel.restore_ai_history_scroll_position(180)
	await process_frame
	var retained_scroll_position := panel.get_ai_history_scroll_position()
	_check(retained_scroll_position > 0, "the compact AI Log can scroll through a long history")
	panel.set_ai_history(overflow_entries, 10)
	await process_frame
	_check(
		panel.get_ai_history_scroll_position() == retained_scroll_position,
		"rebuilding AI decision rows preserves the current scroll position"
	)
	root.remove_child(panel)
	panel.free()


func _test_checkpoint_restore_and_branching() -> void:
	var manager := (load("res://main.tscn") as PackedScene).instantiate() as MapManager
	root.add_child(manager)
	await process_frame
	_check(manager.levels.size() >= 2, "checkpoint fixture exposes Goblin Skirmish")
	if manager.levels.size() < 2 or not manager.load_level(manager.levels[1]):
		_check(false, "checkpoint fixture loads Goblin Skirmish")
		_remove_manager(manager)
		return
	await process_frame
	var battle := manager.current_battle
	_check(is_instance_valid(battle) and battle.initialization_succeeded, "checkpoint battle initializes")
	if not is_instance_valid(battle) or not battle.initialization_succeeded:
		_remove_manager(manager)
		return
	var enemy := _first_unit(battle, false)
	var friendly := _first_unit(battle, true)
	_check(enemy != null and friendly != null, "checkpoint fixture finds both factions")
	if enemy == null or friendly == null:
		_remove_manager(manager)
		return
	battle.ai_debug_history_limit = 2
	battle.turn_manager.current_unit = enemy
	battle.turn_manager.current_index = battle.turn_manager.turn_order.find(enemy)
	battle._movement_locked = true
	enemy.reset_movement()
	enemy.reset_ability_action()
	var plan := EnemyTurnPlan.new()
	plan.sequence = EnemyTurnPlan.Sequence.HOLD
	plan.end_cell = enemy.grid_cell
	battle._update_ai_debug(enemy, plan)

	enemy._set_runtime_grid_cell_immediate(Vector2i(0, 0))
	enemy.apply_damage(5)
	enemy.spend_movement(1.0)
	enemy.spend_ability_action()
	var burning := load("res://resources/statuses/burning.tres") as StatusEffectDefinition
	var fireball := load("res://resources/abilities/fireball.tres") as AbilityDefinition
	enemy.apply_status(burning, fireball, friendly)
	var removed_inventory_item := battle.general_inventory.get_items()[0]
	battle.general_inventory.take_item(removed_inventory_item)
	battle.turn_manager.round_number = 2
	plan.end_cell = enemy.grid_cell
	battle._update_ai_debug(enemy, plan)
	var target_health := enemy.current_health
	var target_cell := enemy.grid_cell
	var target_movement := enemy.remaining_movement
	var target_inventory_count := battle.general_inventory.get_items().size()
	var target_weapon := enemy.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON)
	var target_enemy_id := enemy.scenario_unit_id

	enemy._set_runtime_grid_cell_immediate(Vector2i(1, 0))
	enemy.apply_damage(7)
	enemy.unequip_item(ItemDefinition.EquipmentSlot.WEAPON)
	battle.general_inventory.take_item(battle.general_inventory.get_items()[0])
	battle.turn_manager.round_number = 3
	plan.end_cell = enemy.grid_cell
	battle._update_ai_debug(enemy, plan)
	_check(battle._ai_debug_history.size() == 2, "AI history obeys its configured limit")
	_check(battle._ai_debug_checkpoints.size() == 2, "checkpoint trimming stays aligned with log trimming")
	battle.ai_debug_history_limit = 30
	for filler_index in range(28):
		battle._ai_debug_history.insert(
			0,
			"Round %d · Earlier Enemy · General AI\nChosen in 1 ms: Hold\nEarlier details"
			% (filler_index + 1)
		)
		battle._ai_debug_checkpoints.insert(
			0,
			battle._ai_debug_checkpoints[0].duplicate(true)
		)
	var full_history_count := battle._ai_debug_history.size()
	var selected_history_index := full_history_count - 2
	var newest_history_index := full_history_count - 1
	battle._refresh_ai_debug_history()

	battle.turn_manager.current_unit = friendly
	battle.turn_manager.current_index = battle.turn_manager.turn_order.find(friendly)
	battle._movement_locked = false
	battle._open_dev_mode(DevModePanel.AI_LOG_TAB)
	_check(paused, "Dev mode pauses before selecting a checkpoint")
	await process_frame
	await process_frame
	battle.dev_mode_panel.restore_ai_history_scroll_position(20)
	await process_frame
	var expected_scroll_position := battle.dev_mode_panel.get_ai_history_scroll_position()
	_check(expected_scroll_position > 0, "checkpoint coverage starts from a nonzero AI Log scroll position")
	var source_id := battle.get_instance_id()
	var valid_newest_checkpoint := battle._ai_debug_checkpoints[newest_history_index]
	battle._ai_debug_checkpoints[newest_history_index] = valid_newest_checkpoint.duplicate(true)
	battle._ai_debug_checkpoints[newest_history_index]["map_definition"] = "res://missing_checkpoint_map.tres"
	var newest_button := battle.dev_mode_panel.ai_log_entries.get_child(0) as Button
	newest_button.pressed.emit()
	await process_frame
	_check(manager.current_battle == battle, "an invalid checkpoint leaves the current battle in place")
	_check(paused and battle._dev_open, "an invalid checkpoint leaves Dev mode paused and usable")
	_check(
		battle.dev_mode_panel.get_ai_history_scroll_position() == expected_scroll_position,
		"an invalid checkpoint keeps the AI Log viewport in place"
	)
	_check(
		battle.dev_mode_panel.status_label.text.begins_with("Checkpoint restore failed:"),
		"an invalid checkpoint reports its validation error"
	)
	battle._ai_debug_checkpoints[newest_history_index] = valid_newest_checkpoint

	var oldest_button := battle.dev_mode_panel.ai_log_entries.get_child(1) as Button
	oldest_button.pressed.emit()
	await process_frame
	await process_frame
	var restored := manager.current_battle
	_check(is_instance_valid(restored) and restored.get_instance_id() != source_id, "clicking a log transactionally replaces the battle")
	if not is_instance_valid(restored) or restored.get_instance_id() == source_id:
		_remove_manager(manager)
		return
	var restored_enemy := _find_unit(restored, target_enemy_id)
	_check(restored_enemy != null, "checkpoint restoration preserves stable unit IDs")
	if restored_enemy != null:
		_check(restored_enemy.current_health == target_health, "checkpoint restoration restores health")
		_check(restored_enemy.grid_cell == target_cell, "checkpoint restoration restores position")
		_check(is_equal_approx(restored_enemy.remaining_movement, target_movement), "checkpoint restoration restores remaining movement")
		_check(not restored_enemy.ability_available, "checkpoint restoration restores spent actions")
		_check(restored_enemy.get_active_statuses().size() == 1, "checkpoint restoration restores statuses")
		_check(restored_enemy.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON) == target_weapon, "checkpoint restoration restores runtime equipment")
	_check(restored.general_inventory.get_items().size() == target_inventory_count, "checkpoint restoration restores inventory")
	_check(restored.turn_manager.round_number == 2, "checkpoint restoration restores the round")
	_check(restored.turn_manager.current_unit == restored_enemy, "checkpoint restoration returns to the logged enemy turn")
	_check(restored._ai_debug_history.size() == full_history_count, "rewinding keeps newer logs until Resume")
	_check(restored._ai_debug_checkpoints.size() == full_history_count, "rewinding keeps newer checkpoints aligned until Resume")
	_check(restored._pending_ai_history_cutoff == selected_history_index, "rewinding records the selected pending branch point")
	_check(paused and restored._dev_open, "the replacement reopens Dev mode paused")
	_check(restored.dev_mode_panel.tabs.current_tab == DevModePanel.AI_LOG_TAB, "the replacement reopens on AI Log")
	_check(
		restored.dev_mode_panel.get_ai_history_scroll_position() == expected_scroll_position,
		"checkpoint restoration keeps the prior AI Log viewport position"
	)
	_check(
		restored.dev_mode_panel.status_label.text.contains("All logs remain available until Resume"),
		"the restored panel explains deferred timeline truncation"
	)
	_check(
		restored.dev_mode_panel.ai_log_entries.get_child_count() == full_history_count,
		"all newer log rows remain visible above the selection"
	)
	var future_button := restored.dev_mode_panel.ai_log_entries.get_child(0) as Button
	var selected_button := restored.dev_mode_panel.ai_log_entries.get_child(1) as Button
	_check(selected_button.button_pressed, "the restored checkpoint remains visually selected")
	_check(not future_button.disabled, "a future checkpoint remains clickable before Resume")
	_check(
		restored.dev_mode_panel._ai_history_copy_text.contains(
			restored._ai_debug_history[newest_history_index]
		),
		"Copy Logs includes future entries while the branch is pending"
	)

	var first_restore_id := restored.get_instance_id()
	future_button.pressed.emit()
	await process_frame
	await process_frame
	restored = manager.current_battle
	_check(restored.get_instance_id() != first_restore_id, "a future log can become the selected restore point")
	_check(restored._ai_debug_history.size() == full_history_count, "changing the selected checkpoint still keeps all logs")
	_check(restored._pending_ai_history_cutoff == newest_history_index, "changing selection updates the pending branch point")
	_check(
		restored.dev_mode_panel.get_ai_history_scroll_position() == expected_scroll_position,
		"changing the selected checkpoint keeps the AI Log viewport position"
	)
	_check(
		(restored.dev_mode_panel.ai_log_entries.get_child(0) as Button).button_pressed,
		"the newly selected future checkpoint is visibly marked"
	)

	(restored.dev_mode_panel.ai_log_entries.get_child(1) as Button).pressed.emit()
	await process_frame
	await process_frame
	restored = manager.current_battle
	_check(restored._ai_debug_history.size() == full_history_count, "selecting the older checkpoint again still preserves future logs")
	_check(restored._pending_ai_history_cutoff == selected_history_index, "the older checkpoint becomes the pending branch again")
	_check(
		restored.dev_mode_panel.get_ai_history_scroll_position() == expected_scroll_position,
		"reselecting the older checkpoint keeps the AI Log viewport position"
	)

	restored.dev_mode_panel.play_button.pressed.emit()
	_check(restored._ai_debug_history.size() == selected_history_index + 1, "Resume synchronously discards logs newer than the selected checkpoint")
	_check(restored._ai_debug_checkpoints.size() == selected_history_index + 1, "Resume discards matching future checkpoints")
	_check(restored._pending_ai_history_cutoff == -1, "Resume clears the pending branch marker")
	_check(not paused and not restored._dev_open, "Resume leaves the restored checkpoint and unpauses combat")
	var deadline := Time.get_ticks_msec() + CHECKPOINT_TIMEOUT_MSEC
	while (
		Time.get_ticks_msec() < deadline
		and is_instance_valid(restored)
		and restored._ai_debug_history.size() < selected_history_index + 2
	):
		await process_frame
	_check(restored._ai_debug_history.size() == selected_history_index + 2, "resuming replans once and appends one new log to the committed timeline")
	_remove_manager(manager)


func _first_unit(battle: TacticalBattle, friendly: bool) -> TacticalCharacter:
	for unit in battle._characters:
		if is_instance_valid(unit) and unit.is_friendly() == friendly:
			return unit
	return null


func _find_unit(battle: TacticalBattle, unit_id: String) -> TacticalCharacter:
	for unit in battle._characters:
		if is_instance_valid(unit) and unit.scenario_unit_id == unit_id:
			return unit
	return null


func _remove_manager(manager: MapManager) -> void:
	paused = false
	if not is_instance_valid(manager):
		return
	if is_instance_valid(manager.current_battle):
		manager.current_battle.shutdown_battle()
	root.remove_child(manager)
	manager.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
