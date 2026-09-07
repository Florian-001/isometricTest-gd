extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var manager := (load("res://main.tscn") as PackedScene).instantiate() as MapManager
	root.add_child(manager)
	await process_frame
	_check(manager.unit_names_visible, "a new app session defaults names to visible")

	var goblin_map := load("res://resources/maps/goblin_skirmish.tres") as BattleMapDefinition
	_check(manager.load_level(goblin_map), "the unit-name fixture loads Goblin Skirmish")
	await process_frame
	var battle := manager.current_battle
	_check(battle.names_button.text == "Names: On", "the initial HUD button reports Names: On")
	_check(battle.names_button.button_pressed, "the initial HUD toggle is pressed")
	_check_unit_labels(battle, true)

	var exact_before := battle.capture_save_payload(false)
	battle.names_button.button_pressed = false
	_check(not manager.unit_names_visible, "the battle reports its toggle to the session owner")
	_check(battle.names_button.text == "Names: Off", "the HUD button reports Names: Off")
	_check_unit_labels(battle, false)
	_check(
		battle.capture_save_payload(false) == exact_before,
		"toggling names does not enter the scenario save payload"
	)

	battle.restart_button.pressed.emit()
	await process_frame
	battle = manager.current_battle
	_check(not battle.unit_names_visible, "Restart preserves the hidden-name session preference")
	_check(not battle.names_button.button_pressed, "the restarted HUD toggle remains off")
	_check_unit_labels(battle, false)

	manager.return_to_level_select()
	await process_frame
	var terrain_map := load("res://resources/maps/terrain_showcase.tres") as BattleMapDefinition
	_check(manager.load_level(terrain_map), "the unit-name fixture changes maps")
	await process_frame
	battle = manager.current_battle
	_check(not battle.unit_names_visible, "changing maps preserves the session preference")
	_check_unit_labels(battle, false)

	battle._open_dev_mode()
	_check(paused, "Dev Mode remains paused while names are hidden")
	_check(not battle.names_button.disabled, "Names remains usable above the Dev input blocker")
	_check(battle.dev_button.disabled, "Dev remains blocked while already open")
	_check(battle.inventory_button.disabled, "Inventory remains blocked while Dev is open")
	_check(battle.restart_button.disabled, "Restart remains blocked while Dev is open")
	_check(battle.levels_button.disabled, "Levels remains blocked while Dev is open")
	var dirty_before := battle._dev_dirty
	await _click_control(battle.names_button)
	_check(battle.names_button.button_pressed, "the Names button receives clicks above the Dev input blocker")
	_check(paused, "showing names does not resume Dev Mode")
	_check(battle._dev_dirty == dirty_before, "showing names does not mark setup dirty")
	_check_unit_labels(battle, true)
	battle.names_button.button_pressed = false

	var add_cell := _find_open_cell(battle)
	_check(add_cell.x >= 0, "the Dev fixture finds an open cell")
	if add_cell.x >= 0:
		battle._add_dev_unit(battle.dev_tool_catalog.unit_scenes[0], add_cell)
		var added := battle.dev_mode_panel.get_selected_unit()
		_check(is_instance_valid(added), "Dev Mode adds a selected unit")
		if is_instance_valid(added):
			var added_label := added.get_node("UnitNameLabel") as Label
			_check(not added.is_unit_name_visible(), "a Dev-added unit inherits hidden names")
			_check(not added_label.visible, "the Dev-added authored label is hidden")
			_check(added_label.text == str(added.name), "the Dev-added label uses its assigned instance name")

	paused = false
	manager.queue_free()
	await process_frame
	if _failures.is_empty():
		print("UNIT_NAMES_INTEGRATION_OK")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _check_unit_labels(battle: TacticalBattle, expected_visible: bool) -> void:
	for character in battle._characters:
		if not is_instance_valid(character):
			continue
		var label := character.get_node_or_null("UnitNameLabel") as Label
		_check(label != null, "%s contains the authored name label" % character.name)
		if label == null:
			continue
		_check(label.text == str(character.name), "%s displays its instance name" % character.name)
		_check(label.visible == expected_visible, "%s follows the global visibility state" % character.name)


func _find_open_cell(battle: TacticalBattle) -> Vector2i:
	for y in range(battle.grid.grid_size.y):
		for x in range(battle.grid.grid_size.x):
			var cell := Vector2i(x, y)
			if battle._is_valid_dev_cell(cell):
				return cell
	return Vector2i(-1, -1)


func _click_control(control: Control) -> void:
	var center := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	Input.parse_input_event(motion)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = center
	press.global_position = center
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = center
	release.global_position = center
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
