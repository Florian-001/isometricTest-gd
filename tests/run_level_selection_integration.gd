extends SceneTree

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene := load("res://main.tscn") as PackedScene
	var manager := main_scene.instantiate() as MapManager
	root.add_child(manager)
	await process_frame

	_check(manager.current_battle == null, "startup should wait for a level selection")
	_check(manager.level_select.visible, "the level selector should be visible at startup")
	_check(not manager.has_node("Grid"), "Main should not contain map-specific battlefield nodes")
	_check(manager.levels.size() == 2, "Main should expose exactly two configured levels")
	_check(manager.level_buttons.get_child_count() == 2, "the selector should create one button per level")
	_check(manager.levels[0].display_name == "Terrain Showcase", "Terrain Showcase should be the first level")
	_check(manager.levels[1].display_name == "Goblin Skirmish", "Goblin Skirmish should be the second level")

	(manager.level_buttons.get_child(0) as Button).pressed.emit()
	await process_frame
	var first_battle := manager.current_battle
	_check(is_instance_valid(first_battle), "selecting Terrain Showcase should create a battle")
	_check(not manager.level_select.visible, "selecting a level should hide the selector")
	_check(first_battle.map_definition == manager.levels[0], "the battle should receive the selected map definition")
	_check(first_battle.battle_map.name == "TerrainShowcase", "the selected map scene should be instantiated")
	_check(first_battle.terrain.get_child_count() == 6, "Terrain Showcase should preserve all six special tiles")
	_check(first_battle.walls_container.get_child_count() == 3, "Terrain Showcase should preserve all three walls")
	_check(first_battle.characters_container.get_child_count() == 4, "Terrain Showcase should preserve all four units")
	_check(manager.unit_names_visible, "a new app session should default unit names to visible")
	_check(first_battle.names_button.button_pressed, "the first battle should show the pressed Names toggle")
	for child in first_battle.characters_container.get_children():
		if child is TacticalCharacter:
			var name_label := child.get_node("UnitNameLabel") as Label
			_check(name_label.text == str(child.name), "world labels should show each map instance name")
			_check(name_label.visible, "unit names should begin visible on the first map")
	first_battle.names_button.button_pressed = false
	_check(not manager.unit_names_visible, "the map manager should retain the hidden-name session preference")
	_check(first_battle.names_button.text == "Names: Off", "the first battle toggle should show Names: Off")

	var first_friend := first_battle.characters_container.get_node("FriendA") as TacticalCharacter
	first_friend.apply_damage(5)
	var first_inventory_item := first_battle.general_inventory.get_items()[0]
	_check(first_battle.general_inventory.take_item(first_inventory_item), "the first battle inventory should be mutable at runtime")
	_check(first_battle.general_inventory.get_items().size() == 8, "the first battle should retain its own inventory state")
	var active_before_dialog := first_battle.turn_manager.current_unit
	first_battle.levels_button.pressed.emit()
	await process_frame
	_check(first_battle.return_to_levels_dialog.visible, "Levels should open a confirmation dialog")
	_check(paused, "the confirmation dialog should pause battle processing")
	first_battle.return_to_levels_dialog.canceled.emit()
	first_battle.return_to_levels_dialog.hide()
	_check(not paused, "cancelling should resume battle processing")
	_check(manager.current_battle == first_battle, "cancelling should preserve the current battle")
	_check(first_battle.turn_manager.current_unit == active_before_dialog, "cancelling should preserve the active turn")

	first_battle.levels_button.pressed.emit()
	first_battle.return_to_levels_dialog.confirmed.emit()
	await process_frame
	_check(manager.current_battle == null, "confirming should discard the current battle")
	_check(manager.level_select.visible, "confirming should return to the level selector")

	(manager.level_buttons.get_child(1) as Button).pressed.emit()
	await process_frame
	var second_battle := manager.current_battle
	_check(is_instance_valid(second_battle), "selecting Goblin Skirmish should create a battle")
	_check(second_battle.map_definition == manager.levels[1], "the second battle should receive Goblin Skirmish")
	_check(not second_battle.unit_names_visible, "a new map should inherit the session name preference")
	_check(not second_battle.names_button.button_pressed, "the inherited hidden state should update the HUD toggle")
	_check(second_battle.general_inventory.get_items().size() == 9, "a new level should receive fresh General Inventory contents including both two-handed melee weapons")
	_check(second_battle.grid.grid_size == Vector2i(12, 12), "Goblin Skirmish should use a 12x12 grid")
	_check(second_battle.terrain.get_child_count() == 0, "Goblin Skirmish should have no special tiles")
	_check(second_battle.walls_container.get_child_count() == 0, "Goblin Skirmish should have no walls")

	var friendlies: Array[TacticalCharacter] = []
	var enemies: Array[TacticalCharacter] = []
	for child in second_battle.characters_container.get_children():
		if child is TacticalCharacter:
			if child.is_friendly():
				friendlies.append(child)
			else:
				enemies.append(child)
	_check(friendlies.size() == 2, "Goblin Skirmish should contain two friendly units")
	_check(enemies.size() == 3, "Goblin Skirmish should contain three enemies")
	_check((second_battle.characters_container.get_node("FriendA") as TacticalCharacter).current_health == 48, "a newly selected map should create fresh friendly runtime state")
	_check((second_battle.characters_container.get_node("FriendA") as TacticalCharacter).starting_grid_cell == Vector2i(4, 9), "FriendA should use the requested Goblin Skirmish cell")
	_check((second_battle.characters_container.get_node("FriendB") as TacticalCharacter).starting_grid_cell == Vector2i(7, 9), "FriendB should use the requested Goblin Skirmish cell")
	var expected_enemy_cells := [Vector2i(3, 2), Vector2i(6, 2), Vector2i(9, 2)]
	var actual_enemy_cells: Array[Vector2i] = []
	for enemy in enemies:
		actual_enemy_cells.append(enemy.starting_grid_cell)
		_check(enemy.definition.display_name == "Goblin Warrior", "every Goblin Skirmish enemy should use the Goblin Warrior archetype")
		var weapon := enemy.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON)
		_check(weapon != null and weapon.display_name == "Goblin Sword", "every Goblin Warrior should use its default Sword")
	actual_enemy_cells.sort()
	expected_enemy_cells.sort()
	_check(actual_enemy_cells == expected_enemy_cells, "Goblin Warriors should use the requested opposite-side formation")

	var restart_unit := friendlies[0]
	var restart_unit_id := restart_unit.scenario_unit_id
	var restart_starting_cell := restart_unit.starting_grid_cell
	var starting_equipment := _item_paths(restart_unit.get_equipped_items())
	var starting_inventory := second_battle.general_inventory.capture_state()
	var starting_map_path := second_battle.map_definition.resource_path
	var starting_instance_id := second_battle.get_instance_id()
	var starting_active_id := second_battle.turn_manager.current_unit.scenario_unit_id
	var burning := load("res://resources/statuses/burning.tres") as StatusEffectDefinition
	restart_unit.apply_damage(5)
	restart_unit._set_runtime_grid_cell_immediate(Vector2i(0, 0))
	_check(restart_unit.apply_status(burning), "restart fixture should apply a runtime status")
	second_battle.turn_manager.round_number = 4
	var active_before_restart := second_battle.turn_manager.current_unit
	active_before_restart.reset_movement()
	active_before_restart.spend_movement(1.0)
	active_before_restart.reset_ability_action()
	active_before_restart.spend_ability_action()
	active_before_restart.reset_opportunity_reaction()
	active_before_restart.spend_opportunity_reaction()
	var runtime_item: ItemDefinition
	for item in second_battle.general_inventory.get_items():
		if not starting_equipment.has(item.resource_path):
			runtime_item = item
			break
	_check(runtime_item != null, "restart fixture should find alternate runtime equipment")
	if runtime_item != null:
		_check(second_battle.general_inventory.take_item(runtime_item), "restart fixture should remove an inventory item")
		for replaced in restart_unit.equip_item(runtime_item):
			second_battle.general_inventory.add_item(replaced)
	var defeated_enemy := enemies[0] if enemies[0] != active_before_restart else enemies[1]
	var defeated_enemy_id := defeated_enemy.scenario_unit_id
	defeated_enemy.apply_damage(defeated_enemy.current_health)
	_check(not defeated_enemy.is_present_on_map(), "restart fixture should remove a defeated enemy")
	_check(second_battle.general_inventory.capture_state() != starting_inventory, "restart fixture should alter runtime inventory")
	second_battle.restart_button.pressed.emit()
	await process_frame

	var restarted_battle := manager.current_battle
	_check(is_instance_valid(restarted_battle), "Restart should create a replacement battle")
	_check(restarted_battle.get_instance_id() != starting_instance_id, "Restart should replace the old battle instance")
	_check(not restarted_battle.unit_names_visible, "Restart should preserve the session name preference")
	_check(not restarted_battle.names_button.button_pressed, "Restart should keep the Names toggle off")
	_check(restarted_battle.map_definition.resource_path == starting_map_path, "Restart should keep the current map")
	_check(restarted_battle.turn_manager.round_number == 1, "Restart should return combat to round one")
	_check(restarted_battle.turn_manager.current_unit.scenario_unit_id == starting_active_id, "Restart should rebuild the initial turn order")
	_check(restarted_battle.turn_manager.current_unit.ability_available, "Restart should restore the active unit's ability action")
	_check(restarted_battle.turn_manager.current_unit.opportunity_reaction_available, "Restart should restore the active unit's reaction")
	_check(
		is_equal_approx(
			restarted_battle.turn_manager.current_unit.remaining_movement,
			restarted_battle.turn_manager.current_unit.get_movement_range()
		),
		"Restart should restore the active unit's movement"
	)
	var restarted_unit := _find_unit(restarted_battle, restart_unit_id)
	_check(restarted_unit != null, "Restart should preserve configured units")
	if restarted_unit != null:
		_check(restarted_unit.current_health == restarted_unit.get_max_health(), "Restart should restore full health")
		_check(restarted_unit.grid_cell == restart_starting_cell, "Restart should restore the configured starting cell")
		_check(restarted_unit.get_active_statuses().is_empty(), "Restart should clear runtime statuses")
		_check(_item_paths(restarted_unit.get_equipped_items()) == starting_equipment, "Restart should restore starting equipment")
	var restarted_enemy := _find_unit(restarted_battle, defeated_enemy_id)
	_check(restarted_enemy != null and restarted_enemy.current_health == restarted_enemy.get_max_health(), "Restart should restore defeated units")
	_check(restarted_enemy != null and restarted_enemy.is_present_on_map(), "Restart should return defeated units to the map")
	_check(restarted_battle.general_inventory.capture_state() == starting_inventory, "Restart should restore starting inventory")
	_check(not restarted_battle.return_to_levels_dialog.visible, "Restart should not open a confirmation dialog")
	_check(not paused, "Restart should leave battle processing unpaused")
	second_battle = restarted_battle

	manager.return_to_level_select()
	await process_frame
	manager.queue_free()
	await process_frame
	if _failed:
		quit(1)
	else:
		print("LEVEL_SELECTION_INTEGRATION_OK")
		quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _find_unit(battle: TacticalBattle, unit_id: String) -> TacticalCharacter:
	for unit in battle._characters:
		if unit.scenario_unit_id == unit_id:
			return unit
	return null


func _item_paths(items: Array[ItemDefinition]) -> Array[String]:
	var paths: Array[String] = []
	for item in items:
		if item != null:
			paths.append(item.resource_path)
	return paths
