extends SceneTree

const Catalog = preload("res://addons/unit_balance/catalog.gd")
const Store = preload("res://addons/unit_balance/draft_store.gd")
const Preview = preload("res://addons/unit_balance/preview.gd")
const Columns = preload("res://addons/unit_balance/columns.gd")
const BalancePanel = preload("res://addons/unit_balance/panel.gd")
const ROOT := "res://.godot/unit_balance_tests"
var failures: Array[String] = []
var checks := 0


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	var catalog := Catalog.new()
	catalog.scan()
	check("res://resources/enemy_raider.tres" in catalog.enemies, "Root Raider is discovered")
	check(catalog.enemies.size() >= 13, "All enemy templates are discovered")
	var store := Store.new()
	store.recovery_path = ""
	for path in catalog.enemies + catalog.items:
		store.add_resource(path)
	for path in catalog.enemies:
		var actual := TacticalCharacter.new()
		actual.definition = load(path)
		actual.current_health = actual.get_max_health()
		var preview := Preview.calculate(store, path)
		check(preview.hp == actual.get_max_health(), "HP parity " + path)
		check(preview.armor == actual.get_max_armor(), "Armor parity " + path)
		check(is_equal_approx(preview.move, actual.get_movement_range()), "Movement parity " + path)
		check(preview.initiative == actual.get_initiative(), "Initiative parity " + path)
		for ability in actual.get_abilities():
			if ability == null or not ability.has_damage():
				continue
			var selected := Preview.calculate(store, path, ability.resource_path)
			check(selected.available == actual.can_use_ability(ability), "Availability parity " + ability.display_name)
			if selected.available:
				check(selected.per_hit == ability.calculate_hit_damage(actual), "Per-hit parity " + ability.display_name)
				check(selected.total == ability.calculate_damage(actual), "Total parity " + ability.display_name)
				check(selected.range == ability.get_effective_range(actual), "Range parity " + ability.display_name)
		actual.free()
	var goblin := "res://resources/enemies/goblin_warrior.tres"
	var sword := "res://resources/items/weapons/goblin_sword.tres"
	var old_damage: int = load(sword).weapon_damage
	var before := Preview.calculate(store, goblin)
	store.set_field(sword, "weapon_damage", old_damage + 7)
	check(load(sword).weapon_damage == old_damage, "Draft does not modify cached shared item")
	check(Preview.calculate(store, goblin).per_hit == before.per_hit + 7, "Item draft updates dependent preview")
	store.history.undo()
	check(not store.is_dirty(sword), "Undo returns item to clean state")
	store.history.redo()
	check(Preview.calculate(store, goblin).per_hit == before.per_hit + 7, "Redo updates dependent preview")
	store.history.undo()
	var state: Dictionary = store.states[goblin]
	var empty := store.equipment_state(state, ItemDefinition.EquipmentSlot.WEAPON, "")
	store.change("Remove weapon", {goblin: empty})
	check(not Preview.calculate(store, goblin).available, "Missing weapon is unavailable, not misleading damage")
	store.history.undo()
	var shield := "res://resources/items/offhand/wooden_shield.tres"
	var bow := "res://resources/items/weapons/short_bow.tres"
	store.set_field(bow, "weapon_handedness", ItemDefinition.WeaponHandedness.TWO_HANDED)
	var shield_state := store.equipment_state(state, 3, shield)
	var bow_state := store.equipment_state(shield_state, 0, bow)
	check(shield not in bow_state.starting_equipment and sword not in bow_state.starting_equipment and bow in bow_state.starting_equipment, "Two-handed replacement displaces weapon and offhand")
	check(bow not in store.equipment_state(bow_state, 3, shield).starting_equipment, "Offhand replacement displaces two-handed weapon")
	check(bow not in store.equipment_state(bow_state, 3, "").starting_equipment, "Clearing reserved offhand also removes its two-handed weapon")
	store.history.undo()
	# Synthetic fixtures exercise persistence without modifying authored game assets.
	var fixture_item := ItemDefinition.new()
	fixture_item.display_name = "Fixture Sword"
	fixture_item.weapon_damage = 12
	ResourceSaver.save(fixture_item, ROOT + "/sword.tres")
	var fixture := EnemyDefinition.new()
	fixture.display_name = "Fixture Enemy"
	fixture.constitution = 5
	fixture.base_health_override = 35
	fixture.starting_equipment.assign([load(ROOT + "/sword.tres")])
	fixture.abilities.assign([load("res://resources/abilities/multi_attack.tres")])
	ResourceSaver.save(fixture, ROOT + "/enemy.tres")
	var other := fixture.duplicate() as EnemyDefinition
	other.display_name = "Other Enemy"
	ResourceSaver.save(other, ROOT + "/other.tres")
	var fixture_store := Store.new()
	fixture_store.recovery_path = ROOT + "/recovery.cfg"
	fixture_store.add_resource(ROOT + "/enemy.tres")
	fixture_store.add_resource(ROOT + "/other.tres")
	fixture_store.add_resource(ROOT + "/sword.tres")
	fixture_store.set_field(ROOT + "/sword.tres", "modifiers", [{"stat": 7, "operation": 0, "value": 5.0}, {"stat": 1, "operation": 1, "value": 0.5}, {"stat": 4, "operation": 0, "value": 1000.0}])
	var fixture_preview := Preview.calculate(fixture_store, ROOT + "/enemy.tres")
	check(fixture_preview.hp == 70, "HP override scales with effective Constitution")
	check(fixture_preview.move == UnitStat.get_scaling_rules().maximum_movement_range, "Movement preview uses game ceiling")
	check(fixture_preview.hits > 1 and fixture_preview.total == fixture_preview.per_hit * fixture_preview.hits, "Multi-hit preview uses potential total")
	check(Preview.calculate(fixture_store, ROOT + "/other.tres").hp == 70, "Shared draft affects every enemy")
	fixture_store.set_field(ROOT + "/enemy.tres", "strength", 31)
	var saved := fixture_store.save_all()
	check(saved.failed.is_empty() and saved.conflicts.is_empty() and saved.saved.size() == 2, "Only changed resources save")
	var loaded := ResourceLoader.load(ROOT + "/enemy.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as EnemyDefinition
	check(loaded.strength == 31 and loaded.starting_equipment[0].resource_path == ROOT + "/sword.tres", "Save/reload preserves values and external item reference")
	check(fixture_store.dirty_paths().is_empty(), "Successful save marks drafts clean")
	fixture_store.history.undo()
	check(fixture_store.is_dirty(ROOT + "/enemy.tres"), "Undo after saving is a new unsaved change")
	fixture_store.set_field(ROOT + "/enemy.tres", "strength", 42)
	var external := loaded.duplicate() as EnemyDefinition
	external.strength = 99
	external.body_color = Color.PURPLE
	ResourceSaver.save(external, ROOT + "/enemy.tres")
	var conflict := fixture_store.save_all()
	check(ROOT + "/enemy.tres" in conflict.conflicts and fixture_store.is_dirty(ROOT + "/enemy.tres"), "External file change blocks save and keeps draft")
	var recovered := Store.new()
	recovered.recovery_path = fixture_store.recovery_path
	for path in fixture_store.states:
		recovered.add_resource(path)
	check(recovered.restore_recovery() == 1 and recovered.states[ROOT + "/enemy.tres"].strength == 42, "Recovery restores unsaved draft")
	check(ROOT + "/enemy.tres" in recovered.conflicts(), "Recovery retains conflict baseline")
	var overwritten := fixture_store.save_all([ROOT + "/enemy.tres"])
	check(overwritten.conflicts.is_empty() and overwritten.failed.is_empty(), "Explicit conflict overwrite succeeds")
	loaded = ResourceLoader.load(ROOT + "/enemy.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	check(loaded.strength == 42 and loaded.body_color == Color.PURPLE, "Overwrite preserves unrelated fields from external changes")
	fixture_store.set_field(ROOT + "/enemy.tres", "strength", 55)
	fixture_store.reload_paths([ROOT + "/enemy.tres"])
	check(fixture_store.states[ROOT + "/enemy.tres"].strength == 42 and not fixture_store.history.has_undo(), "Reload discards draft and clears undo")
	fixture_store.set_field(ROOT + "/enemy.tres", "strength", 50)
	var cached := load(ROOT + "/enemy.tres") as EnemyDefinition
	cached.strength = 61
	check(ROOT + "/enemy.tres" in fixture_store.conflicts(), "Unsaved Inspector changes also cause a conflict")
	fixture_store.reload_paths([ROOT + "/enemy.tres"])
	var removed_path := ROOT + "/removed_fixture.tres"
	ResourceSaver.save(EnemyDefinition.new(), removed_path)
	fixture_store.add_resource(removed_path)
	fixture_store.set_field(removed_path, "strength", 20)
	DirAccess.remove_absolute(removed_path)
	var failed_save := fixture_store.save_all([removed_path])
	check(not failed_save.failed.is_empty() and fixture_store.is_dirty(removed_path), "Failed save retains dirty draft and reports missing resource")
	fixture_store.states.erase(removed_path)
	fixture_store.baselines.erase(removed_path)
	fixture_store.hashes.erase(removed_path)
	fixture_store.history.clear_history()
	# UI integration in a real scene tree, with fixtures and isolated preferences.
	var panel := BalancePanel.new()
	panel.catalog_root = ROOT
	panel.persist_preferences = false
	panel.preferences.set_value("table", "groups", ["Identity", "Base stats", "Equipment", "Results", "Item"])
	panel.store.recovery_path = ""
	root.add_child(panel)
	await process_frame
	panel.size = Vector2(1280, 800)
	panel.grid.select_cell(0, 2)
	var first_path: String = panel.grid.active_path
	var initial_strength: int = panel.store.states[first_path].strength
	check(panel.paste_text("7\t8\n9\t10"), "Rectangular paste accepted")
	await process_frame
	check(panel.store.states[first_path].strength == 7 and panel.store.states[first_path].dexterity == 8, "Rectangular paste updates target cells")
	panel.store.history.undo()
	check(panel.store.states[first_path].strength == initial_strength, "One undo restores entire rectangle")
	var invalid_before: Dictionary = panel.store.states.duplicate(true)
	check(not panel.paste_text("11\tbad\n12\t13") and panel.store.states == invalid_before, "Invalid paste is atomic")
	var calculated: Dictionary = Columns.enemies().filter(func(c): return c.key == "hp")[0]
	check(not panel.apply_values([first_path], calculated, "500"), "Calculated cells reject edits")
	var strength_column: Dictionary = Columns.enemies()[2]
	check(not panel.apply_values([first_path], strength_column, "1.5"), "Integer stats reject fractions")
	check(not panel.apply_values([first_path], strength_column, "nan"), "Stats reject non-finite values")
	panel.sort_key = "strength"
	panel.sort_ascending = false
	panel._refresh()
	check(panel.grid.active_path == first_path and panel.grid.active_key == "strength", "Sorting preserves path/key selection")
	panel.search.text = "no match"
	panel._refresh()
	panel.search.text = ""
	panel._refresh()
	check(panel.grid.active_path == first_path, "Filtering preserves selection")
	var right := InputEventKey.new()
	right.keycode = KEY_RIGHT
	right.pressed = true
	panel.grid._gui_input(right)
	check(panel.grid.active_key == "dexterity", "Keyboard arrow navigates cells")
	panel.grid.horizontal.value = 400
	check(panel.grid.cell_at(Vector2(10, 50)).x == 0, "Name column remains pinned when horizontally scrolled")
	if "--capture" in OS.get_cmdline_user_args():
		panel.grid.select_cell(0, 0)
		for dimensions in [Vector2i(1280, 800), Vector2i(900, 650)]:
			root.size = dimensions
			panel.size = dimensions
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ROOT + "/table_%d.png" % dimensions.x)
	panel.free()
	fixture_store.history.clear_history()
	store.history.clear_history()
	await process_frame
	print("UNIT_BALANCE_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
