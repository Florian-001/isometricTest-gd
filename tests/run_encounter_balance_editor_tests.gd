extends SceneTree

const EncounterPanel = preload("res://addons/encounter_balance/panel.gd")
const SKELETON := "res://scenes/enemies/skeleton_archer.tscn"
var failures: Array[String] = []
var checks := 0


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count := 4) -> void:
	for index in range(count):
		await process_frame


func _run() -> void:
	if not Engine.is_editor_hint():
		push_error("Run this suite with --editor --script.")
		quit(1)
		return
	await create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
	var live = EditorInterface.get_editor_main_screen().get_node_or_null("EncounterBalance")
	check(live != null, "Encounter Balance registers its main screen")
	if live == null:
		quit(1)
		return
	EditorInterface.set_main_screen_editor("Encounter Balance")
	await frames()
	check(live.visible and live.grid.rows.size() == 15, "Workspace opens on the active Ascent run")
	var directory := "res://.godot/encounter_balance_tests/editor_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("fixture.tres")
	var source := load("res://resources/run/default_run.tres") as RunConfig
	var config := source.duplicate() as RunConfig
	config.floor_overrides = []
	config.elite_floor_overrides = []
	ResourceSaver.save(config, path)
	var uid := ResourceUID.create_id()
	ResourceSaver.set_uid(path, uid)
	var panel := EncounterPanel.new()
	panel.catalog_root = directory
	panel.selected_run = path
	panel.persist_preferences = false
	panel.store.recovery_path = directory.path_join("recovery.cfg")
	EditorInterface.get_editor_main_screen().add_child(panel)
	panel.hide()
	await frames()
	panel.grid.select_cell(1, panel.grid.column_index_for("normal_cr"))
	panel._edit_cell(panel.grid.active_path, panel.grid.columns[panel.grid.column_index_for("normal_cr")])
	await frames()
	var dialogs := panel.get_children().filter(func(child): return child is ConfirmationDialog and child.visible)
	check(dialogs.size() == 1, "CR cell opens a real edit dialog")
	if not dialogs.is_empty():
		var input: LineEdit = dialogs[0].find_children("*", "LineEdit", true, false)[0]
		input.text = "13"
		dialogs[0].confirmed.emit()
		dialogs[0].hide()
	await frames()
	panel._edit_cell(panel.grid.active_path, panel.grid.columns[panel.grid.column_index_for("normal_pool")])
	await frames()
	dialogs = panel.get_children().filter(func(child): return child is ConfirmationDialog and child.visible)
	check(dialogs.size() == 1, "Pool cell opens a real multi-select picker")
	if not dialogs.is_empty():
		var dialog: ConfirmationDialog = dialogs[0]
		var checks_ui := dialog.find_children("*", "CheckBox", true, false)
		check(checks_ui.size() >= 13 and checks_ui.any(func(check_box): return check_box.icon != null), "Picker contains enemy variants and thumbnails")
		for check_box in checks_ui:
			check_box.button_pressed = check_box.get_meta("scene_path") == SKELETON
		var filter: LineEdit = dialog.find_children("*", "LineEdit", true, false)[0]
		filter.text = "Skeleton Archer"
		filter.text_changed.emit(filter.text)
		await frames()
		var filtered := dialog.find_children("*", "CheckBox", true, false)
		check(filtered.size() == 1 and filtered[0].button_pressed, "Search finds selected enemy by authored name")
		filter.text = "goblin"
		filter.text_changed.emit(filter.text)
		await frames()
		dialog.confirmed.emit()
		dialog.hide()
	await frames()
	var draft := panel.store.draft(path) as RunConfig
	check(draft.floor_overrides[0].combat_rating == 13 and draft.floor_overrides[0].enemy_pool == [load(SKELETON)], "Picker retains hidden selections across searches")
	check(load(path).floor_overrides.is_empty(), "Dialog edits stay in drafts")
	var result: Dictionary = panel.save_changes()
	check(result.saved == [path] and result.failed.is_empty(), "Editor Save All saves only the fixture")
	check(ResourceLoader.get_resource_uid(path) == uid and load(path).floor_overrides[0].combat_rating == 13, "Editor save preserves UID and refreshes gameplay cache")
	EditorInterface.edit_resource(load(path))
	await frames()
	var properties := EditorInterface.get_inspector().find_children("*", "EditorProperty", true, false)
	check(properties.any(func(property): return property.get_edited_property() == "elite_floor_overrides"), "Inspector exposes the elite override list")
	panel.store.edit_cells(path, [{"floor": 2, "key": "elite_cr", "value": 14}])
	await frames()
	var saved_resource := load(path) as RunConfig
	var original_gold := saved_resource.starting_gold
	saved_resource.starting_gold += 1
	result = panel.save_changes()
	check(result.conflicts == [path] and panel.store.is_dirty(path), "Inspector conflict opens without discarding the draft")
	dialogs = panel.get_children().filter(func(child): return child is ConfirmationDialog and child.visible)
	check(dialogs.size() == 1 and dialogs[0].ok_button_text == "Overwrite these drafts", "Conflict dialog offers explicit overwrite and reload")
	saved_resource.starting_gold = original_gold
	if not dialogs.is_empty():
		dialogs[0].custom_action.emit("reload")
	await frames()
	check(panel.store.dirty_paths().is_empty(), "Conflict reload clears only the selected drafts")
	panel.store.edit_cells(path, [{"floor": 2, "key": "elite_cr", "value": 14}])
	var plugin = load("res://addons/encounter_balance/plugin.gd").new()
	plugin.panel = panel
	check(not plugin._get_unsaved_status("").is_empty() and plugin._get_unsaved_status("res://main.tscn").is_empty(), "Close flow reports external-resource drafts")
	plugin._save_external_data()
	check(panel.store.dirty_paths().is_empty() and load(path).elite_floor_overrides[0].combat_rating == 14, "Godot external-resource save flow persists drafts")
	panel.store.edit_cells(path, [{"floor": 2, "key": "elite_cr", "value": 15}])
	plugin._exit_tree()
	await frames()
	var recovered = load("res://addons/encounter_balance/draft_store.gd").new()
	recovered.recovery_path = directory.path_join("recovery.cfg")
	check(recovered.restore_recovery() == 1 and recovered.draft(path).elite_floor_overrides[0].combat_rating == 15, "Plugin disable preserves unsaved drafts for next start")
	recovered.history.clear_history()
	plugin.panel = null
	plugin.free()
	EditorInterface.edit_resource(null)
	await frames()
	print("ENCOUNTER_BALANCE_EDITOR_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
