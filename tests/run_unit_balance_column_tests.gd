extends SceneTree

const Visibility = preload("res://addons/unit_balance/column_visibility.gd")
const BalancePanel = preload("res://addons/unit_balance/panel.gd")
const ROOT := "res://.godot/unit_balance_column_tests"
var checks := 0
var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func keys(panel: Control) -> Array:
	return panel.grid.columns.map(func(column): return column.key)


func _run() -> void:
	root.gui_embed_subwindows = true
	DirAccess.make_dir_recursive_absolute(ROOT)
	var config := ConfigFile.new()
	var original_defaults := Visibility.read_preferences(config)
	check(original_defaults.enemies == Visibility.defaults("enemies"), "Default enemy results overview")
	check(original_defaults.items.size() == Visibility.definitions("items").size(), "Default item view includes every column")
	config.set_value("table", "groups", ["Base stats", "Equipment", "Item"])
	var migrated := Visibility.read_preferences(config)
	check("strength" in migrated.enemies and "slot_0" in migrated.enemies and "hp" not in migrated.enemies, "Legacy enabled groups migrate exactly")
	check("display_name" in migrated.enemies and "combat_rating" in migrated.enemies, "Migration retains formerly mandatory identity columns")
	check(migrated.items == original_defaults.items, "Legacy item view is preserved")
	Visibility.write_preferences(config, {"enemies": ["strength", "display_name"], "items": ["armor"]})
	var restored := Visibility.read_preferences(config)
	check(restored.enemies == ["display_name", "strength"], "Individual preferences override legacy groups")
	check(restored.items == ["display_name", "armor"], "Item preferences are independent")
	check(Visibility.normalize("enemies", ["hp", "stale", "hp", "strength"]) == ["display_name", "strength", "hp"], "Unknown keys and duplicates are removed, authored order is retained")
	check(Visibility.normalize("items", []) == ["display_name"], "Name column cannot be hidden")
	# Isolated fixtures ensure tests cannot alter the user's resources or preferences.
	var enemy := EnemyDefinition.new()
	enemy.display_name = "Column Fixture"
	enemy.strength = 6
	enemy.dexterity = 7
	ResourceSaver.save(enemy, ROOT + "/enemy.tres")
	var second := enemy.duplicate() as EnemyDefinition
	second.display_name = "Second Fixture"
	ResourceSaver.save(second, ROOT + "/second.tres")
	var item := ItemDefinition.new()
	item.display_name = "Column Item"
	ResourceSaver.save(item, ROOT + "/item.tres")
	var initial := ConfigFile.new()
	initial.set_value("table", "groups", ["Identity", "Results", "Item"])
	initial.set_value("table", "attacks", {})
	initial.set_value("table", "split", 220)
	var prefs_path := ROOT + "/preferences.cfg"
	initial.save(prefs_path)
	var panel := BalancePanel.new()
	panel.preferences_path = prefs_path
	panel.catalog_root = ROOT
	panel.store.recovery_path = ""
	root.add_child(panel)
	await process_frame
	check(keys(panel) == Visibility.defaults("enemies"), "Panel migrates actual legacy preference file")
	var migrated_file := ConfigFile.new()
	migrated_file.load(prefs_path)
	check(migrated_file.has_section_key("table", "enemies_columns") and migrated_file.has_section_key("table", "items_columns"), "Migration persists separate table selections")
	panel._show_column_picker()
	await process_frame
	var picker = panel.get_children().filter(func(child): return child is AcceptDialog)[0]
	check(picker.visible and picker.checkboxes.size() == Visibility.definitions("enemies").size(), "Picker lists every enemy column")
	check(not picker.no_results.visible and picker.group_boxes.values().all(func(box): return box.visible), "Empty search displays the full checklist")
	check(picker.checkboxes.display_name.disabled and picker.checkboxes.display_name.button_pressed, "Name is checked and locked")
	picker.checkboxes.combat_rating.button_pressed = false
	check("combat_rating" not in keys(panel) and picker.visible, "Individual toggle updates immediately without closing picker")
	picker.checkboxes.strength.button_pressed = true
	check("strength" in keys(panel), "Hidden base stat can be shown individually")
	check(picker.group_checks["Base stats"].text.contains("1/7"), "Partial group reports visible count")
	picker.search.text = "strength"
	picker.search.text_changed.emit(picker.search.text)
	check(picker.checkboxes.strength.visible and picker.checkboxes.effective_strength.visible and not picker.checkboxes.hp.visible, "Search matches full stat keys as well as labels")
	check(not picker.group_boxes.Results.visible and picker.group_boxes["Base stats"].visible, "Search hides groups with no matches")
	picker.search.text = "no-such-column"
	picker.search.text_changed.emit(picker.search.text)
	check(picker.no_results.visible, "Empty search result explains why checklist is empty")
	picker.search.text = ""
	picker.search.text_changed.emit(picker.search.text)
	check(not picker.no_results.visible and picker.checkboxes.values().all(func(box): return box.visible), "Clearing search restores every column checkbox")
	picker.search.text = "strength"
	picker.search.text_changed.emit(picker.search.text)
	picker.group_checks["Base stats"].button_pressed = true
	check(Visibility.definitions("enemies").filter(func(column): return column.group == "Base stats").all(func(column): return column.key in keys(panel)), "Group toggle includes members hidden by search")
	picker.group_checks["Base stats"].button_pressed = false
	check("strength" not in keys(panel) and "dexterity" not in keys(panel), "Group toggle hides entire group")
	picker.apply_preset("all")
	check(keys(panel).size() == Visibility.definitions("enemies").size(), "Show all includes all enemy columns")
	picker.apply_preset("none")
	check(keys(panel) == ["display_name"], "Hide optional leaves fixed name only")
	picker.apply_preset("defaults")
	check(keys(panel) == Visibility.defaults("enemies"), "Reset defaults restores overview even while search is active")
	check(picker.visible and picker.search.text == "strength", "Presets keep picker and search open")
	picker.hide()
	await process_frame
	panel.set_visible_columns("enemies", ["strength", "dexterity", "speed"])
	panel.grid.select_cell(0, panel.grid.column_index_for("strength"))
	var selected_path: String = panel.grid.active_path
	panel.sort_key = "strength"
	panel.sort_ascending = false
	panel.store.set_field(selected_path, "speed", 12)
	await process_frame
	var draft_before: Dictionary = panel.store.states.duplicate(true)
	var dirty_before: Array = panel.store.dirty_paths()
	var history_version: int = panel.store.history.get_version()
	panel.set_visible_columns("enemies", ["dexterity", "speed"])
	check(panel.grid.active_key == "display_name" and panel.grid.anchor_key == "display_name", "Hiding active cell safely collapses selected columns to name")
	check(panel.grid.active_path == selected_path and selected_path in panel.grid.selected, "Column visibility preserves selected rows")
	check(panel.sort_key == "display_name" and panel.sort_ascending, "Hidden sort column falls back to name")
	check(panel.store.states == draft_before and panel.store.dirty_paths() == dirty_before and panel.store.history.get_version() == history_version, "Visibility leaves drafts, dirty state, and undo history unchanged")
	panel.grid.select_cell(0, 1)
	panel.grid.select_cell(1, 2, true)
	var copied: PackedStringArray = panel.grid.copy_text().split("\n")
	check(copied.size() == 2 and copied[0].split("\t").size() == 2, "Rectangular copy includes only visible columns")
	panel.grid.select_cell(0, 1)
	check(panel.paste_text("17\t18\n19\t20"), "Rectangular paste works across formerly nonadjacent columns")
	check(panel.store.states[selected_path].dexterity == 17 and panel.store.states[selected_path].speed == 18 and panel.store.states[selected_path].strength == 6, "Paste modifies visible destinations only")
	panel.store.history.undo()
	check(panel.store.states == draft_before, "One undo restores the rectangle without changing visibility")
	panel.grid.select_cell(0, 1)
	var arrow := InputEventKey.new()
	arrow.keycode = KEY_RIGHT
	arrow.pressed = true
	panel.grid._gui_input(arrow)
	check(panel.grid.active_key == "speed", "Keyboard navigation skips hidden columns")
	panel.grid.select_cell(0, 1)
	panel.grid.select_cell(1, 2, true)
	panel.set_visible_columns("enemies", ["speed"])
	check(panel.grid.active_key == "display_name" and panel.grid.anchor_key == "display_name", "Hiding rectangle anchor cannot select unintended cells")
	panel.set_visible_columns("enemies", Visibility.definitions("enemies").map(func(column): return column.key))
	panel.grid.horizontal.value = 900
	panel.set_visible_columns("enemies", [])
	check(panel.grid.horizontal.value == 0, "Scroll offset clamps when columns disappear")
	check(panel.grid.cell_at(Vector2(10, 50)).x == 0, "Name remains the frozen first column")
	panel.set_visible_columns("enemies", ["hp", "strength"])
	panel.tabs.current_tab = 1
	check(keys(panel) == Visibility.defaults("items"), "Enemy choices do not affect Items tab")
	panel._show_column_picker()
	await process_frame
	picker = panel.get_children().filter(func(child): return child is AcceptDialog)[0]
	check(picker.table == "items" and picker.checkboxes.size() == Visibility.definitions("items").size(), "Items tab has its own full checklist")
	picker.apply_preset("none")
	check(keys(panel) == ["display_name"], "Item optional columns can all be hidden")
	picker.apply_preset("defaults")
	check(keys(panel) == Visibility.defaults("items"), "Item defaults restore all columns")
	picker.toggle_column("weapon_damage", false)
	picker.hide()
	await process_frame
	panel.tabs.current_tab = 0
	check(keys(panel) == ["display_name", "strength", "hp"], "Switching tabs restores enemy choices")
	panel.free()
	await process_frame
	var reopened := BalancePanel.new()
	reopened.catalog_root = ROOT
	reopened.preferences_path = prefs_path
	reopened.store.recovery_path = ""
	root.add_child(reopened)
	await process_frame
	check(keys(reopened) == ["display_name", "strength", "hp"], "Enemy preferences survive reopening")
	reopened.tabs.current_tab = 1
	check("weapon_damage" not in keys(reopened) and "armor" in keys(reopened), "Independent item preferences survive reopening")
	check(reopened.store.dirty_paths().is_empty(), "Column preferences never save fixture drafts")
	if "--capture" in OS.get_cmdline_user_args():
		for dimensions in [Vector2i(1440, 900), Vector2i(1000, 760)]:
			root.mode = Window.MODE_WINDOWED
			root.size = dimensions
			root.content_scale_size = dimensions
			reopened.size = dimensions
			reopened.tabs.current_tab = 0
			reopened._show_column_picker()
			await process_frame
			await process_frame
			RenderingServer.force_draw()
			root.get_texture().get_image().save_png(ROOT + "/picker_%d.png" % dimensions.x)
			for child in reopened.get_children():
				if child is AcceptDialog:
					child.hide()
			await process_frame
	reopened.free()
	await process_frame
	print("UNIT_BALANCE_COLUMN_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
