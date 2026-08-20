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

	var first_friend := first_battle.characters_container.get_node("FriendA") as TacticalCharacter
	first_friend.apply_damage(5)
	var first_inventory_item := first_battle.general_inventory.get_items()[0]
	_check(first_battle.general_inventory.take_item(first_inventory_item), "the first battle inventory should be mutable at runtime")
	_check(first_battle.general_inventory.get_items().size() == 6, "the first battle should retain its own inventory state")
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
	_check(second_battle.general_inventory.get_items().size() == 7, "a new level should receive fresh General Inventory contents")
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
