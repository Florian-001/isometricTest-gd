extends SceneTree

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
	await create_timer(2).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
	var main := EditorInterface.get_editor_main_screen()
	var panel = main.get_node_or_null("UnitBalance")
	check(panel != null, "Unit Balance plugin registers its main screen")
	if panel == null:
		quit(1)
		return
	EditorInterface.set_main_screen_editor("Unit Balance")
	await process_frame
	check(panel.is_visible_in_tree(), "Unit Balance tab opens")
	check(panel.grid.rows.size() >= 13, "Editor table contains enemy templates")
	check(panel.store.dirty_paths().is_empty(), "Opening the table does not modify resources")
	var original_columns: Array = panel.column_visibility.enemies.duplicate()
	panel._show_column_picker()
	await process_frame
	var column_picker = panel.get_children().filter(func(child): return child is AcceptDialog)[0]
	check(column_picker.visible and column_picker.checkboxes.has("combat_rating"), "Editor opens individual column checklist")
	check(not column_picker.no_results.visible, "Editor checklist initially displays its groups")
	column_picker.toggle_column("combat_rating", false)
	check(not panel.grid.columns.any(func(column): return column.key == "combat_rating") and column_picker.visible, "Editor column toggle applies without closing picker")
	check(panel.store.dirty_paths().is_empty(), "Editor visibility change does not dirty resources")
	column_picker.hide()
	panel.set_visible_columns("enemies", original_columns)
	await process_frame
	panel.grid.select_cell(0, 0)
	await process_frame
	check(panel.details.get_child_count() > 3, "Selecting an enemy displays loadout and calculations")
	# Work only in temporary fixture resources already created by the data suite.
	var fixture_path := "res://.godot/unit_balance_tests/editor_fixture.tres"
	var fixture := EnemyDefinition.new()
	fixture.display_name = "Editor Fixture"
	ResourceSaver.save(fixture, fixture_path)
	var fixture_uid := ResourceUID.create_id()
	ResourceSaver.set_uid(fixture_path, fixture_uid)
	check(ResourceLoader.get_resource_uid(fixture_path) == fixture_uid, "Editor fixture has an authored resource UID")
	panel.store.add_resource(fixture_path)
	panel.store.set_field(fixture_path, "strength", 21)
	await process_frame
	check(panel.store.is_dirty(fixture_path), "Editor edit remains staged")
	check(load(fixture_path).strength == 10, "Editor draft leaves original cached resource unchanged")
	panel.store.history.undo()
	check(not panel.store.is_dirty(fixture_path), "Editor undo returns to baseline")
	panel.store.history.redo()
	var save_result: Dictionary = panel.save_changes()
	check(save_result.saved == [fixture_path], "Editor Save All saves only the fixture")
	check(load(fixture_path).strength == 21, "Editor Save All refreshes cached resource")
	check(ResourceLoader.get_resource_uid(fixture_path) == fixture_uid, "Editor Save All preserves the authored resource UID")
	panel.store.history.clear_history()
	# Test the actual selection picker and dialogs without changing authored data.
	panel._pick("Test equipment picker", panel.catalog.items, func(_value): pass)
	await process_frame
	var dialog: ConfirmationDialog
	for child in panel.get_children():
		if child is ConfirmationDialog:
			dialog = child
	check(dialog != null and dialog.visible, "Searchable resource picker opens")
	if dialog != null:
		var filter := dialog.find_children("*", "LineEdit", true, false)[0] as LineEdit
		var list := dialog.find_children("*", "ItemList", true, false)[0] as ItemList
		filter.text = "goblin_sword.tres"
		filter.text_changed.emit(filter.text)
		check(list.item_count == 1, "Resource picker filters by path")
		filter.text = "not an item"
		filter.text_changed.emit(filter.text)
		check(dialog.get_ok_button().disabled, "Empty resource search cannot submit")
		dialog.hide()
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		EditorInterface.set_distraction_free_mode(true)
		EditorInterface.get_base_control().get_window().mode = Window.MODE_WINDOWED
		EditorInterface.get_base_control().get_window().size = Vector2i(1440, 900)
		for dimensions in [Vector2i(1440, 900), Vector2i(1000, 760)]:
			EditorInterface.get_base_control().get_window().size = dimensions
			await create_timer(0.4).timeout
			panel.tabs.current_tab = 0
			panel.grid.select_cell(0, 0)
			await process_frame
			RenderingServer.force_draw()
			root.get_texture().get_image().save_png("res://.godot/unit_balance_tests/editor_enemies_%d.png" % dimensions.x)
		panel.tabs.current_tab = 1
		panel.grid.select_cell(0, 0)
		await process_frame
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png("res://.godot/unit_balance_tests/editor_items.png")
	print("UNIT_BALANCE_EDITOR_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
