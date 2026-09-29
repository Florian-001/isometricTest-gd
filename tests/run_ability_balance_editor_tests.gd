extends SceneTree

var checks := 0
var failures: Array[String] = []


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
	var panel = EditorInterface.get_editor_main_screen().get_node_or_null("AbilityBalance")
	check(panel != null, "Ability Balance registers its main screen")
	if panel == null:
		quit(1)
		return
	EditorInterface.set_main_screen_editor("Ability Balance")
	await process_frame
	check(panel.visible and panel.tabs.get_tab_title(0) == "Active Abilities", "Ability workspace opens")
	check(panel.grid.rows.size() >= 24, "Active editor tab contains authored abilities")
	# Use a separate panel/store so real recovery drafts and preferences are untouched.
	var fixture_panel = load("res://addons/ability_balance/panel.gd").new()
	fixture_panel.persist_preferences = false
	fixture_panel.store.recovery_path = ""
	fixture_panel.catalog_root = "res://.godot/ability_balance_tests"
	EditorInterface.get_editor_main_screen().add_child(fixture_panel)
	fixture_panel.hide()
	var path := "res://.godot/ability_balance_tests/editor_fixture.tres"
	var fixture := AbilityDefinition.new()
	fixture.display_name = "Editor fixture"
	fixture.effects.append(KnockbackEffectDefinition.new())
	ResourceSaver.save(fixture, path)
	var uid := ResourceUID.create_id()
	ResourceSaver.set_uid(path, uid)
	check(ResourceLoader.get_resource_uid(path) == uid, "Fixture has authored UID")
	fixture_panel.refresh_catalog()
	fixture_panel.grid.select_cell(fixture_panel.grid.row_index_for(path), 0)
	await process_frame
	var effect_buttons = fixture_panel.details.find_children("*", "Button", true, false).filter(func(button): return button.text.begins_with("Distance:"))
	check(effect_buttons.size() == 1, "Known nested effect exposes property controls")
	if not effect_buttons.is_empty():
		effect_buttons[0].pressed.emit()
		await process_frame
		var edits = fixture_panel.get_children().filter(func(child): return child is ConfirmationDialog and child.visible)
		check(edits.size() == 1, "Nested property opens value dialog")
		if not edits.is_empty():
			var input = edits[0].find_children("*", "LineEdit", true, false)[0]
			input.text = "4"
			edits[0].confirmed.emit()
			edits[0].hide()
	check(load(path).effects[0].distance == 2, "Editor effects stay in drafts")
	var result: Dictionary = fixture_panel.save_changes()
	check(result.saved == [path], "Save All saves only fixture")
	check(ResourceLoader.get_resource_uid(path) == uid, "Save preserves authored UID")
	check(load(path).effects[0].distance == 4, "Save refreshes embedded effect cache")
	fixture_panel.tabs.current_tab = 1
	await process_frame
	check(fixture_panel.grid.columns[0].key == "display_name", "Passive name stays frozen first")
	fixture_panel._show_column_picker()
	await process_frame
	var picker = fixture_panel.get_children().filter(func(child): return child is AcceptDialog)[0]
	check(picker.checkboxes.has("passive_id") and picker.checkboxes.has("validation"), "Passive column dialog uses correct schema")
	picker.hide()
	fixture_panel._pick_resource({"resource_type": "StatusEffectDefinition", "title": "Status"}, func(_value): pass)
	await process_frame
	var dialogs = fixture_panel.get_children().filter(func(child): return child is ConfirmationDialog and child.visible)
	check(not dialogs.is_empty(), "Typed status picker opens")
	for dialog in dialogs:
		dialog.hide()
	fixture_panel.queue_free()
	await process_frame
	print("ABILITY_BALANCE_EDITOR_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
