@tool
extends McpTestSuite

const TacticalCharacterScript = preload("res://scripts/initiative_actor.gd")
const TurnManagerScript = preload("res://scripts/initiative_turn_manager.gd")
const TEST_SAVE_DIRECTORY := "user://dev_saves_codex_test"

var _test_save_paths: Array[String] = []


func suite_name() -> String:
	return "dev_mode"


func teardown() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.paused = false
	for path in _test_save_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_test_save_paths.clear()
	var test_directory := ProjectSettings.globalize_path(TEST_SAVE_DIRECTORY)
	if DirAccess.dir_exists_absolute(test_directory):
		DirAccess.remove_absolute(test_directory)


func test_editor_authored_drawer_and_catalog_are_complete() -> void:
	var catalog := load("res://resources/dev_tool_catalog.tres") as DevToolCatalog
	assert_true(catalog != null, "the Battle Inspector catalog should load")
	assert_eq(catalog.unit_scenes.size(), 15, "the unit palette includes both bandits alongside the thirteen existing scenes")
	assert_eq(catalog.abilities.size(), 22, "the ability editor includes Counter and Swipe alongside the existing abilities")
	assert_eq(catalog.items.size(), 20, "the equipment editor includes Long Sword and Spear alongside the eighteen existing items")
	assert_eq(catalog.wall_styles.size(), 2, "the terrain editor should contain both configured wall styles")
	for unit_scene in catalog.unit_scenes:
		var unit := track(unit_scene.instantiate())
		assert_true(unit.has_node("UnitNameLabel"), "%s should author its reusable name label" % unit_scene.resource_path)
		var label := unit.get_node("UnitNameLabel") as Label
		assert_eq(label.mouse_filter, Control.MOUSE_FILTER_IGNORE, "unit name labels must not intercept board input")

	var battle := track((load("res://scenes/battle.tscn") as PackedScene).instantiate())
	assert_eq(battle.dev_tool_catalog, catalog, "Battle should receive the catalog through its Inspector property")
	assert_true(battle.has_node("HUD/DevModePanel"), "Battle should instance the focused developer drawer")
	assert_false(battle.get_node("HUD/DevModePanel").visible, "developer controls should begin hidden")
	assert_true(battle.has_node("HUD/DevModePanel/Drawer/Margin/Main/Tabs/Unit"), "the drawer should author the Unit tab")
	assert_true(battle.has_node("HUD/DevModePanel/Drawer/Margin/Main/Tabs/Terrain"), "the drawer should author the Terrain tab")
	assert_true(battle.has_node("DevTerrainEditor"), "Battle should author the focused terrain editing controller")
	assert_true(
		battle.has_node("HUD/DevModePanel/Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/UnitHeader/HealUnitButton"),
		"the Unit tab should author the Heal to Full control"
	)
	assert_true(battle.has_node("HUD/DevModePanel/Drawer/Margin/Main/Tabs/Saves"), "the drawer should author the Saves tab")
	assert_true(battle.has_node("HUD/DevModePanel/Drawer/Margin/Main/Tabs/AILog"), "the drawer should retain the AI Log tab")
	assert_true(
		battle.has_node("HUD/DevModePanel/Drawer/Margin/Main/Tabs/AILog/AILogActions/CopyAILogButton"),
		"the AI Log tab should author its Copy Logs action above the history"
	)
	assert_true(
		battle.has_node("HUD/DevModePanel/Drawer/Margin/Main/Tabs/AILog/AILogScroll/AILogContent/EmptyState"),
		"the AI Log tab should author its empty state"
	)
	assert_true(
		battle.has_node("HUD/DevModePanel/Drawer/Margin/Main/Tabs/AILog/AILogScroll/AILogContent/AILogEntries"),
		"the AI Log tab should author its clickable entry container"
	)
	assert_eq(battle.process_mode, Node.PROCESS_MODE_ALWAYS, "the developer controller should keep processing while paused")
	assert_eq(battle.get_node("MapContainer").process_mode, Node.PROCESS_MODE_PAUSABLE, "battle-map processing should pause in Dev mode")
	assert_eq(battle.get_node("TacticalCamera").process_mode, Node.PROCESS_MODE_PAUSABLE, "camera input should pause in Dev mode")


func test_unit_setup_edits_are_instance_only_and_support_empty_slots() -> void:
	var unit := _make_unit("res://scenes/friendlies/friend_a.tscn", "friend_a")
	var template_strength := unit.definition.strength
	unit.set_dev_stat_override(UnitStat.Type.STRENGTH, 31.0)
	assert_eq(unit.strength_override, 31, "a stat edit should create a per-instance override")
	assert_eq(unit.definition.strength, template_strength, "a stat edit must not mutate the shared template")
	unit.clear_dev_stat_override(UnitStat.Type.STRENGTH)
	assert_eq(unit.strength_override, -1, "stat reset should restore template inheritance")

	var arrow := load("res://resources/abilities/arrow.tres") as AbilityDefinition
	var chosen: Array[AbilityDefinition] = [arrow]
	unit.set_dev_ability_loadout(chosen)
	assert_true(unit.override_template_abilities, "ability edits should enable a complete instance loadout")
	assert_eq(unit.get_abilities(), chosen, "ability checkboxes should set the selected loadout")
	unit.reset_dev_ability_loadout()
	assert_false(unit.override_template_abilities, "ability reset should restore class unlocks")
	assert_eq(unit.get_abilities(), [arrow], "ability reset should use the equipped ranged weapon attack")

	unit.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, null)
	assert_true(unit.use_complete_equipment_override, "equipment edits should switch to complete-loadout mode")
	assert_eq(unit.get_equipped_weapon(), null, "complete-loadout mode should preserve an explicitly empty weapon slot")
	var setup := unit.capture_setup_state()
	assert_true(setup.complete_equipment, "the empty slot should be explicit in saved setup state")

	var restored := _make_unit("res://scenes/friendlies/friend_a.tscn", "restored")
	restored.apply_setup_state(setup)
	restored._ready()
	assert_eq(restored.get_equipped_weapon(), null, "an inherited weapon slot should restore as empty")
	assert_eq(
		restored.get_equipped_items().size(),
		unit.get_equipped_items().size(),
		"all remaining non-empty equipment slots should round-trip"
	)
	restored.reset_dev_equipment_to_template()
	assert_false(restored.use_complete_equipment_override, "equipment reset should disable complete-loadout mode")
	var template_weapon: ItemDefinition
	for item in restored.definition.starting_equipment:
		if item != null and item.slot == ItemDefinition.EquipmentSlot.WEAPON:
			template_weapon = item
			break
	assert_eq(restored.get_equipped_weapon(), template_weapon, "equipment reset should restore the shared template weapon")


func test_selected_unit_ability_damage_breakdowns_use_live_values() -> void:
	var unit := _make_unit("res://scenes/friendlies/friend_a.tscn", "damage_preview")
	unit.set_dev_stat_override(UnitStat.Type.DEXTERITY, 12.0)
	unit.set_dev_stat_override(UnitStat.Type.INTELLIGENCE, 12.0)
	var fireball := load("res://resources/abilities/fireball.tres") as AbilityDefinition
	var arrow := load("res://resources/abilities/arrow.tres") as AbilityDefinition
	var heal := load("res://resources/abilities/heal.tres") as AbilityDefinition

	assert_eq(
		fireball.get_damage_calculation_description(unit),
		"Damage: 32 = 20 innate + 12 effective Intelligence × 100%",
		"damage details should show the live stat value, percentage, and total"
	)
	assert_eq(
		arrow.get_damage_calculation_description(unit),
		"Damage: 17 = 10 weapon + 12 effective Dexterity × 60% (rounded from 17.2)",
		"damage details should show weapon damage and explain final rounding"
	)
	assert_eq(
		heal.get_damage_calculation_description(unit),
		"No damage",
		"non-damaging abilities should state that they deal no damage"
	)


func test_runtime_state_round_trip_preserves_actions_status_sources_and_equipment() -> void:
	var unit := _make_unit("res://scenes/friendlies/friend_a.tscn", "unit_a")
	var source_unit := _make_unit("res://scenes/enemies/goblin_warrior.tscn", "source_enemy")
	unit.set_grid_cell_immediate(Vector2i(4, 6))
	unit.set_facing(TacticalCharacter.Facing.LEFT)
	unit.current_health = unit.get_max_health() - 7
	unit.reset_movement()
	unit.spend_movement(1.5)
	unit.reset_ability_action()
	unit.spend_ability_action()
	unit.reset_opportunity_reaction()
	unit.spend_opportunity_reaction()
	var burning := load("res://resources/statuses/burning.tres") as StatusEffectDefinition
	var source_ability := load("res://resources/abilities/fireball.tres") as AbilityDefinition
	unit.apply_status(burning, source_ability, source_unit)
	var captured := unit.capture_runtime_state()

	var restored := _make_unit("res://scenes/friendlies/friend_a.tscn", "unit_a")
	restored.restore_runtime_state(captured, {
		"unit_a": restored,
		"source_enemy": source_unit,
	})
	assert_eq(restored.grid_cell, Vector2i(4, 6), "runtime position should round-trip")
	assert_eq(restored.current_facing, TacticalCharacter.Facing.LEFT, "runtime facing should round-trip")
	assert_eq(restored.current_health, unit.current_health, "current health should round-trip")
	assert_true(is_equal_approx(restored.remaining_movement, unit.remaining_movement), "remaining movement should round-trip")
	assert_false(restored.ability_available, "spent action availability should round-trip")
	assert_false(restored.opportunity_reaction_available, "spent reaction availability should round-trip")
	assert_eq(restored.get_equipped_items(), unit.get_equipped_items(), "runtime equipment should round-trip in slot order")
	var statuses := restored.get_active_statuses()
	assert_eq(statuses.size(), 1, "active statuses should round-trip")
	assert_eq(statuses[0].definition, burning, "status definitions should restore from resource paths")
	assert_eq(statuses[0].source, source_ability, "status resource sources should restore")
	assert_eq(statuses[0].source_unit, source_unit, "status source-unit references should restore by stable ID")


func test_turn_manager_round_trip_preserves_order_round_and_current_unit() -> void:
	var friendly := _make_unit("res://scenes/friendlies/friend_a.tscn", "friendly")
	var enemy := _make_unit("res://scenes/enemies/goblin_warrior.tscn", "enemy")
	var units: Array[TacticalCharacter] = [friendly, enemy]
	var manager := track(TurnManagerScript.new()) as TurnManager
	manager.start_combat(units)
	manager.end_current_turn()
	var captured := manager.capture_state(units, true)
	var restored := track(TurnManagerScript.new()) as TurnManager
	assert_true(restored.restore_state(captured, {"friendly": friendly, "enemy": enemy}), "a valid turn state should restore")
	assert_eq(restored.turn_order, manager.turn_order, "ordered stable unit IDs should restore exact turn order")
	assert_eq(restored.current_unit, manager.current_unit, "the active unit should restore by stable ID")
	assert_eq(restored.round_number, manager.round_number, "the round number should round-trip")
	assert_true(captured.action_boundary, "turn snapshots should identify the stable action boundary")


func test_schema_rejects_duplicate_ids_missing_factions_and_map_mismatches() -> void:
	var payload := _fresh_payload()
	assert_true(ScenarioSaveStore.validate_payload(payload).ok, "a configured two-faction scenario should validate")

	var duplicate := payload.duplicate(true)
	duplicate.setup.units[1].id = duplicate.setup.units[0].id
	assert_false(ScenarioSaveStore.validate_payload(duplicate).ok, "duplicate stable IDs should be rejected")
	var one_faction := payload.duplicate(true)
	one_faction.setup.units.remove_at(1)
	assert_false(ScenarioSaveStore.validate_payload(one_faction).ok, "a setup without both factions should be rejected")
	var wrong_map_shape := payload.duplicate(true)
	wrong_map_shape.setup.grid_size = [11, 12]
	assert_false(ScenarioSaveStore.validate_payload(wrong_map_shape).ok, "saved geometry should match its map definition")
	var missing_resource := payload.duplicate(true)
	missing_resource.setup.units[0].abilities = ["res://resources/abilities/missing.tres"]
	assert_false(ScenarioSaveStore.validate_payload(missing_resource).ok, "missing catalog resources should be rejected")


func test_schema_allows_reusing_a_defeated_enemy_runtime_cell() -> void:
	var payload := _fresh_payload()
	payload.runtime = {
		"fresh_start": false,
		"units": [
			{
				"id": "friendly",
				"cell": [4, 2],
				"current_health": 100,
				"equipped_items": [],
				"statuses": [],
			},
			{
				"id": "enemy",
				"cell": [4, 2],
				"current_health": 0,
				"equipped_items": [],
				"statuses": [],
			},
		],
		"inventory": [],
		"turn": {
			"round": 1,
			"action_boundary": true,
			"current_index": 0,
			"current_unit": "friendly",
			"order": ["friendly", "enemy"],
			"scene_order": ["friendly", "enemy"],
		},
		"combat_over": false,
		"combat_result": "",
		"movement_locked": false,
	}
	assert_true(
		ScenarioSaveStore.validate_payload(payload).ok,
		"a living unit should be allowed to reuse a defeated enemy's runtime cell"
	)

	var living_overlap := payload.duplicate(true)
	living_overlap.runtime.units[1].current_health = 1
	assert_false(
		ScenarioSaveStore.validate_payload(living_overlap).ok,
		"two living units should still be rejected in the same runtime cell"
	)

	var defeated_friendly_overlap := payload.duplicate(true)
	defeated_friendly_overlap.runtime.units[0].current_health = 0
	defeated_friendly_overlap.runtime.units[1].current_health = 1
	assert_false(
		ScenarioSaveStore.validate_payload(defeated_friendly_overlap).ok,
		"a defeated friendly should continue reserving its runtime cell"
	)


func test_save_listing_rename_delete_corruption_and_atomic_replace() -> void:
	var payload := _fresh_payload()
	var created := ScenarioSaveStore.save_new(payload, TEST_SAVE_DIRECTORY)
	assert_true(created.ok, "a valid scenario should save through a temporary replacement")
	if not created.ok:
		return
	var path := str(created.path)
	_test_save_paths.append(path)
	assert_true(ScenarioSaveStore.rename_save(path, "Regression Snapshot", TEST_SAVE_DIRECTORY).ok, "inline rename should update the save")

	var invalid := payload.duplicate(true)
	invalid.setup.units[1].id = invalid.setup.units[0].id
	assert_false(ScenarioSaveStore.replace_save(path, invalid, TEST_SAVE_DIRECTORY).ok, "an invalid replacement should be rejected before touching the old save")
	var retained := ScenarioSaveStore.load_save(path, TEST_SAVE_DIRECTORY)
	assert_true(retained.ok, "a failed replacement should retain the previous valid file")
	assert_eq(retained.payload.metadata.name, "Regression Snapshot", "failed replacement should retain prior metadata")

	var replacement := payload.duplicate(true)
	replacement.metadata.round = 4
	assert_true(ScenarioSaveStore.replace_save(path, replacement, TEST_SAVE_DIRECTORY).ok, "explicit Replace should atomically update a valid entry")
	assert_eq(ScenarioSaveStore.load_save(path, TEST_SAVE_DIRECTORY).payload.metadata.name, "Regression Snapshot", "Replace should retain the inline name")

	var corrupt_path := "%s/corrupt.json" % TEST_SAVE_DIRECTORY
	_test_save_paths.append(corrupt_path)
	var corrupt_file := FileAccess.open(corrupt_path, FileAccess.WRITE)
	assert_true(corrupt_file != null, "the corruption fixture should be writable")
	if corrupt_file != null:
		corrupt_file.store_string("{broken")
		corrupt_file.close()
	var entries := ScenarioSaveStore.list_saves(TEST_SAVE_DIRECTORY)
	assert_eq(entries.size(), 2, "dynamic listing should include valid and corrupt JSON files")
	var corrupt_found := false
	for entry in entries:
		if entry.status == "corrupt":
			corrupt_found = true
			assert_false(str(entry.error).is_empty(), "corrupt entries should include an actionable error")
	assert_true(corrupt_found, "corrupt saves should remain visible as disabled entries")
	assert_true(ScenarioSaveStore.delete_save(path, TEST_SAVE_DIRECTORY).ok, "save deletion should remove the selected entry")
	assert_false(FileAccess.file_exists(path), "deleted saves should no longer exist")


func _make_unit(scene_path: String, stable_id: String) -> TacticalCharacter:
	var scene := load(scene_path) as PackedScene
	var unit := track(scene.instantiate()) as TacticalCharacter
	unit.scenario_unit_id = stable_id
	unit._ready()
	return unit


func _fresh_payload() -> Dictionary:
	return {
		"schema_version": ScenarioSaveStore.SCHEMA_VERSION,
		"map_definition": "res://resources/maps/goblin_skirmish.tres",
		"metadata": {
			"name": "",
			"map_name": "Goblin Skirmish",
			"round": 1,
			"saved_at": "",
		},
		"setup": {
			"grid_size": [12, 12],
			"wall_cells": [],
			"units": [
				_setup_for("res://scenes/friendlies/friend_a.tscn", "friendly", Vector2i(4, 9)),
				_setup_for("res://scenes/enemies/goblin_warrior.tscn", "enemy", Vector2i(4, 2)),
			],
		},
		"runtime": {"fresh_start": true},
	}


func _setup_for(scene_path: String, stable_id: String, cell: Vector2i) -> Dictionary:
	var scene := load(scene_path) as PackedScene
	var unit := scene.instantiate() as TacticalCharacter
	unit.scenario_unit_id = stable_id
	unit.starting_grid_cell = cell
	var setup := unit.capture_setup_state()
	unit.free()
	return setup
