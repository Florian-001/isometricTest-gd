extends SceneTree

const Store = preload("res://addons/encounter_balance/draft_store.gd")
const Model = preload("res://addons/encounter_balance/model.gd")
const Catalog = preload("res://addons/encounter_balance/catalog.gd")
const EncounterPanel = preload("res://addons/encounter_balance/panel.gd")
const SKELETON := "res://scenes/enemies/skeleton_archer.tscn"
const GOBLIN := "res://scenes/enemies/goblin_archer.tscn"
var directory := "res://.godot/encounter_balance_tests/data_%d" % Time.get_ticks_usec()
var failures: Array[String] = []
var checks := 0


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func fixture(name: String, shared := "") -> String:
	var source := load("res://resources/run/default_run.tres") as RunConfig
	var config := source.duplicate() as RunConfig
	config.display_name = name
	config.combat_stages = []
	for stage in source.combat_stages:
		config.combat_stages.append(stage.duplicate())
	config.floor_overrides = []
	config.elite_floor_overrides = []
	if not shared.is_empty():
		config.floor_overrides = [load(shared)]
	var path := directory.path_join(name + ".tres")
	check(ResourceSaver.save(config, path) == OK, "Save disposable config " + name)
	check(ResourceSaver.set_uid(path, ResourceUID.create_id()) == OK, "Assign fixture UID")
	return path


func new_store(path: String):
	var store := Store.new()
	store.recovery_path = ""
	store.add_resource(path)
	return store


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	_test_parse_and_catalog()
	_test_drafts_and_preview()
	_test_shared_and_recovery()
	_test_conflicts_and_failure()
	await _test_panel()
	print("ENCOUNTER_BALANCE_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_parse_and_catalog() -> void:
	for text in ["0", "-1", "1.5", "bad", ""]:
		check(Model.parse("normal_cr", text).has("error"), "Reject nonpositive/noninteger CR " + text)
	check(Model.parse("elite_cr", "23").value == 23, "Parse exact elite CR")
	check(Model.parse("normal_pool", " " + SKELETON + ";" + SKELETON).value == [SKELETON], "Pool paths trim whitespace and deduplicate without weighting")
	for text in ["", "res://missing.tscn", "res://scenes/friendlies/warrior.tscn", "res://resources/enemies/rat.tres"]:
		check(Model.parse("normal_pool", text).has("error"), "Reject invalid pool " + text)
	check(Model.parse("stage", "Goblins").has("error"), "Read-only fields cannot paste")
	var catalog := Catalog.new()
	catalog.scan()
	check("res://resources/run/default_run.tres" in catalog.runs and "res://resources/run/five_combats.tres" in catalog.runs, "Discover both authored runs")
	check(catalog.enemies.has("res://scenes/enemies/goblin_warrior_club.tscn") and catalog.enemies.has("res://scenes/enemies/goblin_warrior.tscn"), "Different enemy scene variants remain available")
	check(catalog.enemies[GOBLIN].cr == load("res://resources/enemies/goblin_archer.tres").combat_rating, "Picker CR comes from the authored enemy definition")
	check(not catalog.enemies.has("res://scenes/friendlies/warrior.tscn"), "Picker excludes friendly units")


func _test_drafts_and_preview() -> void:
	var path := fixture("drafts")
	var store = new_store(path)
	var uid := ResourceLoader.get_resource_uid(path)
	var base := RunCombatProgression.resolve_floor(load(path), 5)
	check(store.edit_cells(path, [{"floor": 5, "key": "normal_cr", "value": 9}, {"floor": 5, "key": "normal_pool", "value": [SKELETON]}]), "Create embedded normal override in one edit")
	check(load(path).floor_overrides.is_empty(), "Draft edits leave cached gameplay resources untouched")
	var draft := store.draft(path) as RunConfig
	check(Model.settings(draft, 5).cr == 9 and Model.settings(draft, 5, true).cr == 9, "Elite inherits normal draft CR")
	check(Model.settings(draft, 5, true).pool == [load(SKELETON)], "Elite inherits normal draft pool")
	check(store.edit_cells(path, [{"floor": 5, "key": "elite_cr", "value": 11}]), "Create independent elite CR")
	draft = store.draft(path)
	check(Model.settings(draft, 5, true).cr == 11 and Model.settings(draft, 5, true).pool == [load(SKELETON)], "Elite CR-only override retains pool inheritance")
	var before := Store.capture(load(path))
	var template := draft.elite_encounters[0].battle_map as BattleMapTemplateDefinition
	var template_before := Store.capture(template)
	var preview := Model.preview(draft, 5, true, 0, 0)
	check(preview.error.is_empty() and preview.total_cr == 11 and preview.unused == 0 and preview.roster[SKELETON].count == 11, "Preview uses elite draft and exact affordable roster")
	check(preview == Model.preview(draft, 5, true, 0, 0), "Same preview seed is deterministic")
	check(Store.capture(template) == template_before and Store.capture(load(path)) == before, "Preview does not mutate cached templates or configs")
	store.history.undo()
	check(Model.settings(store.draft(path), 5, true).cr == 9, "Undo restores inheritance")
	store.history.redo()
	check(Model.settings(store.draft(path), 5, true).cr == 11, "Redo restores explicit elite CR")
	store.edit_cells(path, [{"floor": 5, "key": "elite_cr", "reset": true}])
	check(Model.settings(store.draft(path), 5, true).cr_source == "normal", "Per-field reset disables elite override")
	store.edit_cells(path, [{"floor": 5, "key": "normal_cr", "reset": true}])
	check(Model.settings(store.draft(path), 5).cr == base.combat_rating and Model.settings(store.draft(path), 5).pool == [load(SKELETON)], "Normal CR reset preserves independent pool override")
	store.edit_cells(path, [{"floor": 5, "key": "elite_cr", "value": 20}])
	preview = Model.preview(store.draft(path), 5, true, 0, 0)
	check(preview.total_cr == 15 and preview.unused == 5 and preview.capacity == 15, "Preview exposes spawn capacity and unspent budget")
	var result: Dictionary = store.save_all()
	check(result.saved == [path] and result.failed.is_empty(), "Valid drafts with warnings can save")
	check(ResourceLoader.get_resource_uid(path) == uid, "Save preserves resource UID")
	var restored := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as RunConfig
	check(restored.elite_floor_overrides[0].combat_rating == 20 and restored.floor_overrides[0].enemy_pool == [load(SKELETON)], "Embedded overrides survive save/reload")
	check(restored.combat_stages[0].resource_path == load(path).combat_stages[0].resource_path, "Stage links are preserved")
	store.history.undo()
	check(not store.dirty_paths().is_empty(), "Undo after save creates an unsaved edit")
	store.reload_paths(store.dirty_paths())
	check(store.dirty_paths().is_empty() and not store.history.has_undo(), "Revert clears drafts and undo history")
	store.history.clear_history()


func _test_shared_and_recovery() -> void:
	var override := RunCombatFloorOverride.new()
	override.floor = 6
	override.override_cr = true
	override.combat_rating = 4
	override.override_enemy_pool = true
	override.enemy_pool = [load(SKELETON)]
	var shared := directory.path_join("shared.tres")
	ResourceSaver.save(override, shared)
	var first := fixture("shared_owner_a", shared)
	var second := fixture("shared_owner_b", shared)
	var store = new_store(first)
	store.add_resource(second)
	store.recovery_path = directory.path_join("recovery.cfg")
	store.edit_cells(first, [{"floor": 6, "key": "normal_cr", "value": 5}])
	check(store.dirty_paths() == [shared], "External override edits dirty only the shared resource")
	check(Model.settings(store.draft(second), 6).cr == 5 and load(shared).combat_rating == 4, "Every owner sees isolated shared draft without editing cached resource")
	check(store.source_path(first, 6, false) == shared, "Shared source path is available to UI")
	var recovered := Store.new()
	recovered.recovery_path = store.recovery_path
	check(recovered.restore_recovery() == 3, "Shared-only recovery includes both clean owners")
	check(recovered.dirty_paths() == [shared] and Model.settings(recovered.draft(second), 6).cr == 5, "Recovery restores shared identity and values")
	var result: Dictionary = recovered.save_all()
	check(result.saved == [shared] and load(shared).combat_rating == 5, "Saving shared draft refreshes the shared cached resource")
	check(load(first).floor_overrides[0].resource_path == shared and load(second).floor_overrides[0].resource_path == shared, "Owners keep external links")
	recovered.edit_cells(first, [{"floor": 5, "key": "elite_cr", "value": 7}, {"floor": 6, "key": "normal_cr", "value": 6}])
	result = recovered.save_all()
	check(result.saved.size() == 2 and result.saved[0] == shared and result.saved[1] == first, "Shared overrides save before dirty owners")
	var disk_owner := ResourceLoader.load(first, "", ResourceLoader.CACHE_MODE_IGNORE) as RunConfig
	check(disk_owner.floor_overrides[0].resource_path == shared and disk_owner.elite_floor_overrides[0].combat_rating == 7, "Mixed embedded/external save preserves links")
	recovered.edit_cells(first, [{"floor": 6, "key": "normal_cr", "value": 7}])
	var changed_disk := ResourceLoader.load(shared, "", ResourceLoader.CACHE_MODE_IGNORE) as RunCombatFloorOverride
	changed_disk.floor = 16
	ResourceSaver.save(changed_disk, shared)
	result = recovered.save_all([shared])
	check(result.saved.is_empty() and not result.failed.is_empty() and recovered.is_dirty(shared), "Overwrite validates merged external fields and all owners before writing")
	store.history.clear_history()
	recovered.history.clear_history()


func _test_conflicts_and_failure() -> void:
	var path := fixture("conflict")
	var store = new_store(path)
	store.edit_cells(path, [{"floor": 2, "key": "normal_cr", "value": 9}])
	var external := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as RunConfig
	external.starting_gold = 777
	ResourceSaver.save(external, path)
	var result: Dictionary = store.save_all()
	check(result.conflicts == [path] and result.saved.is_empty(), "Disk changes block implicit overwrite")
	result = store.save_all([path])
	check(result.saved == [path] and load(path).starting_gold == 777, "Explicit overwrite preserves unrelated disk fields")
	store.history.undo()
	check(store.draft(path).starting_gold == 777, "Undo after merged save also preserves unrelated disk fields")
	store.history.redo()
	store.edit_cells(path, [{"floor": 2, "key": "normal_cr", "value": 1}, {"floor": 2, "key": "normal_pool", "value": [GOBLIN]}])
	result = store.save_all()
	check(result.saved.is_empty() and not result.failed.is_empty() and store.is_dirty(path), "Unaffordable roster blocks save and retains draft")
	var valid_path := fixture("valid_alongside_invalid")
	store.add_resource(valid_path)
	store.edit_cells(valid_path, [{"floor": 3, "key": "normal_cr", "value": 12}])
	result = store.save_all()
	check(result.saved == [valid_path] and store.is_dirty(path), "Unrelated valid drafts still save when another run is invalid")
	store.reload_paths([path])
	check(store.dirty_paths().is_empty(), "Conflict reload discards selected draft")
	store.edit_cells(path, [{"floor": 2, "key": "normal_cr", "value": 10}])
	# An unsaved Inspector change is also an external conflict.
	var inspector_resource := load(path) as RunConfig
	inspector_resource.starting_gold = 888
	check(store.conflicts() == [path], "Unsaved Inspector edits are detected")
	inspector_resource.starting_gold = 777
	store.recovery_path = directory.path_join("removed_recovery.cfg")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	result = store.save_all()
	check(not result.failed.is_empty() and store.is_dirty(path) and FileAccess.file_exists(store.recovery_path), "Missing-file failure preserves recovery")
	store.history.clear_history()


func _test_panel() -> void:
	var path := fixture("panel")
	var panel := EncounterPanel.new()
	panel.catalog_root = directory
	panel.selected_run = path
	panel.persist_preferences = false
	panel.store.recovery_path = ""
	root.add_child(panel)
	await process_frame
	check(panel.grid.rows.size() == 15 and panel.grid.columns.size() == 7, "Table shows all floor and normal/elite columns")
	var column: Dictionary = panel.grid.columns[panel.grid.column_index_for("normal_cr")]
	check(panel.apply_values([EncounterPanel.row_id(2), EncounterPanel.row_id(3)], column, "9"), "Bulk edit applies to selected visible floors")
	await process_frame
	check(Model.settings(panel.store.draft(path), 2).cr == 9 and Model.settings(panel.store.draft(path), 3).cr == 9, "Bulk values are exact and floor-specific")
	panel.grid.select_cell(1, panel.grid.column_index_for("normal_cr"))
	var before: Dictionary = panel.store.states[path].duplicate(true)
	check(not panel.paste_text("10\tres://missing.tscn") and panel.store.states[path] == before, "Invalid rectangular paste is atomic")
	check(panel.paste_text("10\t" + SKELETON + "\t12\t" + GOBLIN), "Paste normal and elite settings in one rectangle")
	await process_frame
	panel.grid.select_cell(1, panel.grid.column_index_for("normal_pool"))
	check(panel.grid.copy_text() == SKELETON, "Pool copy returns scene paths without inherited labels")
	panel.store.history.undo()
	check(panel.store.states[path] == before, "Undo restores all pasted cells together")
	panel.store.history.redo()
	await process_frame
	panel._reset_selected()
	check(Model.settings(panel.store.draft(path), 2).pool_source == "stage", "Reset selected pool preserves CR and restores stage inheritance")
	panel.search.text = "Floor 2"
	panel.search.text_changed.emit(panel.search.text)
	check(panel.grid.rows.size() == 1, "Table search filters visible floors")
	panel.floor_picker.value = 3
	check(panel.search.text.is_empty() and panel.grid.active_path == EncounterPanel.row_id(3), "Preview floor selector reveals a previously filtered floor")
	panel.type_picker.item_selected.emit(1)
	panel.floor_picker.value = 4
	check(panel.preview_elite and panel.grid.active_key == "elite_pool", "Changing preview floor preserves the chosen encounter type")
	panel.select_run("res://resources/run/five_combats.tres")
	panel.store.add_resource("res://resources/run/five_combats.tres")
	panel._refresh()
	check(panel.grid.rows.size() == 5 and panel.grid.columns.size() == 5 and panel.type_picker.disabled, "Linear runs show only normal settings")
	panel.free()
	await process_frame
