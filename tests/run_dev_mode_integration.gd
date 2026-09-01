extends SceneTree

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var manager := (load("res://main.tscn") as PackedScene).instantiate() as MapManager
	root.add_child(manager)
	await process_frame
	(manager.level_buttons.get_child(0) as Button).pressed.emit()
	await process_frame
	var battle := manager.current_battle
	var suffix := str(Time.get_ticks_usec())
	var save_path := "user://dev_integration_%s.json" % suffix
	var recovery_path := "user://dev_integration_recovery_%s.json" % suffix
	battle._dev_save_repository = DevSaveRepository.new(save_path, recovery_path)

	battle._on_dev_button_pressed()
	await process_frame
	_check(battle.dev_mode_panel.visible, "Dev should open the expanded drawer")
	_check(battle.dev_mode_panel.tabs.get_tab_count() == 4, "Dev drawer should expose Unit, Add, Saves, and AI History")
	_check(battle.dev_mode_panel.add_grid.get_child_count() == 10, "Add tab should expose every unit archetype")
	_check(battle.inventory_button.disabled, "Normal inventory interaction should pause while Dev is open")
	_check(battle.levels_button.disabled, "Level navigation should pause while Dev is open")
	_check(battle.end_turn_button.disabled and battle.end_turn_button.text == "Dev Mode", "Turn execution should pause while Dev is open")

	var selected := battle._characters[0] as TacticalCharacter
	battle._select_dev_unit(selected)
	var shared_strength := selected.definition.strength
	battle._on_dev_stat_changed("strength", 61)
	_check(selected.strength_override == 61, "Stat edits should apply immediately")
	_check(selected.definition.strength == shared_strength, "Stat edits must not mutate the shared resource")
	var move_target := Vector2i(0, 0)
	_check(battle._move_dev_unit(selected, move_target), "Direct Dev movement should accept an empty cell")
	_check(selected.grid_cell == move_target, "Direct Dev movement should update the logical cell")

	var before_add := battle._characters.size()
	_check(not battle._add_dev_unit_at("res://scenes/enemies/orc.tscn", move_target), "Add mode should reject occupied cells")
	_check(battle._add_dev_unit_at("res://scenes/enemies/orc.tscn", Vector2i(11, 11)), "Add mode should instantiate a valid archetype")
	_check(battle._characters.size() == before_add + 1, "Adding should grow the runtime roster")
	var orc := battle._dev_selected_unit
	var orc_id := orc.dev_runtime_id
	_check(orc.definition.display_name == "Orc", "The added archetype should retain its definition")
	battle._on_dev_faction_changed(CharacterDefinition.Faction.FRIENDLY)
	_check(orc.is_friendly(), "Faction changes should apply immediately")
	var inventory_before := battle.general_inventory.capture_slot_paths()
	var axe := load("res://resources/items/orc_axe.tres") as ItemDefinition
	battle._on_dev_equipment_changed(ItemDefinition.EquipmentSlot.WEAPON, axe)
	_check(orc.get_equipped_weapon() == axe, "Dev equipment should assign from the catalog")
	_check(battle.general_inventory.capture_slot_paths() == inventory_before, "Dev equipment must not consume inventory")
	var heal := load("res://resources/abilities/heal.tres") as AbilityDefinition
	var abilities: Array[AbilityDefinition] = [heal]
	battle._on_dev_abilities_changed(abilities)
	_check(orc.get_abilities().has(heal), "Explicit Dev abilities should update the live loadout")
	var slow := load("res://resources/statuses/slow.tres") as StatusEffectDefinition
	selected.apply_status(slow, heal, orc)
	selected.get_active_statuses()[0].remaining_turns = 1
	var duplicate_item := load("res://resources/items/iron_sword.tres") as ItemDefinition
	battle.general_inventory.replace_item_at(20, duplicate_item)
	battle.general_inventory.replace_item_at(87, duplicate_item)
	battle.tactical_camera.position = Vector2(321, 222)
	battle.tactical_camera.zoom = Vector2(1.25, 1.25)

	battle.dev_mode_panel.save_name_input.text = "Integration"
	battle._on_dev_save_requested("Integration")
	var saved_snapshot := battle._dev_save_repository.get_named("integration")
	_check(not saved_snapshot.is_empty(), "Named save should persist a live snapshot")
	selected.set_dev_current_health(1)
	var selected_id := selected.dev_runtime_id
	battle._on_dev_load_requested("Integration")
	await process_frame
	await process_frame
	var restored := manager.current_battle
	_check(restored != battle, "Loading should transactionally reconstruct the battle")
	_check(restored.map_definition == manager.levels[0], "Loading should restore the saved level")
	var restored_selected := _find_unit(restored, selected_id)
	_check(is_instance_valid(restored_selected), "Stable unit IDs should survive loading")
	_check(restored_selected.current_health != 1, "Loading should restore saved HP")
	_check(restored_selected.grid_cell == move_target, "Loading should restore moved positions")
	_check(restored_selected.get_active_statuses().size() == 1, "Loading should restore active statuses")
	_check(restored_selected.get_active_statuses()[0].remaining_turns == 1, "Loading should restore status duration")
	_check(restored_selected.get_active_statuses()[0].source == heal, "Loading should restore a resource status source")
	_check(restored_selected.get_active_statuses()[0].source_unit.dev_runtime_id == orc_id, "Loading should restore the status source unit")
	_check(restored.general_inventory.get_item_at(20) == duplicate_item, "Loading should preserve the first duplicate inventory cell")
	_check(restored.general_inventory.get_item_at(87) == duplicate_item, "Loading should preserve the second duplicate inventory cell")
	_check(restored.tactical_camera.position == Vector2(321, 222), "Loading should restore camera position")
	_check(restored.tactical_camera.zoom == Vector2(1.25, 1.25), "Loading should restore camera zoom")
	_check(FileAccess.file_exists(recovery_path), "Loading should create an automatic recovery snapshot")

	var invalid := restored.capture_dev_snapshot()
	invalid.units[0].scene_path = "res://missing_dev_unit.tscn"
	restored._request_dev_snapshot_load(invalid, "")
	await process_frame
	_check(manager.current_battle == restored, "An invalid save should leave the current battle untouched")
	var cross_level := restored.capture_dev_snapshot()
	cross_level.level_definition = manager.levels[1].resource_path
	manager._on_dev_snapshot_load_requested(cross_level, restored)
	await process_frame
	await process_frame
	_check(manager.current_battle.map_definition == manager.levels[1], "A valid named snapshot should be able to switch levels")
	_check(is_instance_valid(_find_unit(manager.current_battle, selected_id)), "Cross-level loading should retain the saved roster")

	manager.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(recovery_path))
	if _failed:
		quit(1)
	else:
		print("DEV_MODE_INTEGRATION_OK")
		quit(0)


func _find_unit(battle: TacticalBattle, id: String) -> TacticalCharacter:
	for unit in battle._characters:
		if unit.dev_runtime_id == id:
			return unit
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
