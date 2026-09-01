@tool
extends McpTestSuite


func suite_name() -> String:
	return "dev_mode"


func test_content_catalog_discovers_runtime_editable_assets() -> void:
	var units := DevContentCatalog.get_unit_entries()
	var items := DevContentCatalog.get_items()
	var abilities := DevContentCatalog.get_abilities()
	assert_eq(units.size(), 10, "Dev catalog should discover every reusable unit scene")
	assert_eq(items.size(), 14, "Dev catalog should discover every saved item")
	assert_eq(abilities.size(), 13, "Dev catalog should discover every saved ability")
	assert_true(units.any(func(entry: Dictionary) -> bool: return entry.name == "Orc"), "Orc should be addable")
	assert_true(units.any(func(entry: Dictionary) -> bool: return entry.name == "Goblin Shaman"), "Shaman should be addable")


func test_runtime_overrides_do_not_mutate_shared_definition() -> void:
	var scene := load("res://scenes/enemies/orc.tscn") as PackedScene
	var first := track(scene.instantiate()) as TacticalCharacter
	var second := track(scene.instantiate()) as TacticalCharacter
	var original_strength := first.definition.strength
	var original_faction := first.definition.faction
	first.set_dev_base_stats({"strength": 77})
	first.set_dev_faction(CharacterDefinition.Faction.FRIENDLY)
	assert_eq(first.strength_override, 77, "Dev stats should be per-instance overrides")
	assert_true(first.is_friendly(), "Faction override should affect runtime allegiance")
	assert_eq(first.definition.strength, original_strength, "Shared stats must remain unchanged")
	assert_eq(second.get_base_stat(UnitStat.Type.STRENGTH), float(original_strength), "Sibling instances must remain isolated")
	assert_eq(second.definition.faction, original_faction, "Shared faction must remain unchanged")


func test_inventory_slot_snapshot_preserves_duplicates_and_empty_cells() -> void:
	var inventory := track(GeneralInventory.new()) as GeneralInventory
	var sword := load("res://resources/items/iron_sword.tres") as ItemDefinition
	var slots: Array = []
	slots.resize(GeneralInventory.CAPACITY)
	slots.fill(null)
	slots[2] = sword.resource_path
	slots[91] = sword.resource_path
	assert_true(inventory.restore_slot_paths(slots), "A valid 100-cell snapshot should restore")
	assert_eq(inventory.get_item_at(2), sword, "The first duplicate should retain its exact cell")
	assert_eq(inventory.get_item_at(91), sword, "The second duplicate should retain its exact cell")
	assert_eq(inventory.capture_slot_paths(), slots, "Capturing should preserve empty cells and duplicates")


func test_turn_reconciliation_preserves_or_replaces_current_unit() -> void:
	var manager := track(TurnManager.new()) as TurnManager
	var fast := _make_unit(20)
	var slow := _make_unit(10)
	manager.start_combat([slow, fast])
	assert_eq(manager.current_unit, fast, "The fastest unit should begin")
	assert_false(manager.reconcile_units([slow, fast]), "Reordering should preserve a valid current unit")
	fast.set_dev_current_health(0)
	assert_true(manager.reconcile_units([slow, fast]), "Defeating the current unit should select a replacement")
	assert_eq(manager.current_unit, slow, "The next living unit should become current")


func test_named_save_repository_overwrite_delete_and_recovery() -> void:
	var suffix := str(Time.get_ticks_usec())
	var path := "user://dev_test_%s.json" % suffix
	var recovery := "user://dev_test_recovery_%s.json" % suffix
	var repository := DevSaveRepository.new(path, recovery)
	assert_true(repository.save_named("Alpha", {"snapshot_version": 1, "value": 1}), "Named save should write")
	assert_true(repository.save_named("alpha", {"snapshot_version": 1, "value": 2}), "Names should overwrite case-insensitively")
	assert_eq(repository.list_saves().size(), 1, "Case-insensitive overwrite should not duplicate rows")
	assert_eq(repository.get_named("ALPHA").value, 2, "Overwrite should retain the newest snapshot")
	assert_true(repository.write_recovery({"snapshot_version": 1, "value": 3}), "Recovery should write")
	assert_eq(repository.get_recovery().value, 3, "Recovery should round-trip")
	assert_true(repository.delete_named("Alpha"), "Named save should delete")
	assert_true(repository.list_saves().is_empty(), "Deleted save should disappear")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(recovery))


func _make_unit(speed: int) -> TacticalCharacter:
	var definition := CharacterDefinition.new()
	definition.speed = speed
	var unit := track(TacticalCharacter.new()) as TacticalCharacter
	unit.definition = definition
	unit._ready()
	return unit
