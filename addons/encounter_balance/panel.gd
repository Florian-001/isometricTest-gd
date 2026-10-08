@tool
extends VBoxContainer

const Catalog = preload("res://addons/encounter_balance/catalog.gd")
const Store = preload("res://addons/encounter_balance/draft_store.gd")
const Model = preload("res://addons/encounter_balance/model.gd")
const Grid = preload("res://addons/unit_balance/balance_grid.gd")

var catalog := Catalog.new()
var store := Store.new()
var grid := Grid.new()
var run_picker := OptionButton.new()
var search := LineEdit.new()
var summary := Label.new()
var status := Label.new()
var details := VBoxContainer.new()
var floor_picker := SpinBox.new()
var type_picker := OptionButton.new()
var layout_picker := OptionButton.new()
var seed_picker := SpinBox.new()
var selected_run := "res://resources/run/default_run.tres"
var catalog_root := "res://resources"
var scene_root := "res://scenes/enemies"
var sort_key := "display_name"
var sort_ascending := true
var preview_elite := false
var encounter_index := 0
var refresh_queued := false
var save_button: Button
var undo_button: Button
var redo_button: Button
var persist_preferences := true
var preferences_path := "res://.godot/encounter_balance/preferences.cfg"
var preferences := ConfigFile.new()
var report := {"errors": [], "warnings": []}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	if persist_preferences and preferences.load(preferences_path) == OK:
		selected_run = preferences.get_value("table", "run", selected_run)
		sort_key = preferences.get_value("table", "sort_key", sort_key)
		sort_ascending = preferences.get_value("table", "sort_ascending", true)
	var heading := HBoxContainer.new()
	add_child(heading)
	var title := Label.new()
	title.text = "ENCOUNTER BALANCE"
	title.add_theme_font_size_override("font_size", 22)
	heading.add_child(title)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading.add_child(summary)
	var toolbar := HFlowContainer.new()
	add_child(toolbar)
	save_button = _button(toolbar, "Save All", func(): save_changes())
	_button(toolbar, "Revert All…", _confirm_revert)
	undo_button = _button(toolbar, "Undo", func(): store.history.undo())
	redo_button = _button(toolbar, "Redo", func(): store.history.redo())
	_button(toolbar, "Refresh", refresh_catalog)
	_button(toolbar, "Set selected…", _bulk_edit)
	_button(toolbar, "Reset selected field", _reset_selected)
	_button(toolbar, "Copy", func(): DisplayServer.clipboard_set(grid.copy_text()))
	_button(toolbar, "Paste", func(): paste_text(DisplayServer.clipboard_get()))
	var filter_bar := HBoxContainer.new()
	add_child(filter_bar)
	run_picker.custom_minimum_size.x = 260
	filter_bar.add_child(run_picker)
	run_picker.item_selected.connect(func(index): select_run(str(run_picker.get_item_metadata(index))))
	search.placeholder_text = "Search floors, stages, units, or validation…"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_bar.add_child(search)
	search.text_changed.connect(func(_text): _refresh())
	var hint := Label.new()
	hint.text = "[stage] inherits the stage • Elite [normal] follows normal combat • [override] is explicit • Save All applies drafts."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color("9eb7d1"))
	add_child(hint)
	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	split.add_child(grid)
	var lower := VBoxContainer.new()
	lower.custom_minimum_size.y = 230
	split.add_child(lower)
	var controls := HFlowContainer.new()
	lower.add_child(controls)
	_label(controls, "Preview floor")
	floor_picker.min_value = 1
	floor_picker.max_value = 15
	controls.add_child(floor_picker)
	floor_picker.value_changed.connect(func(value):
		if not search.text.is_empty():
			search.text = ""
			_refresh()
		var key := grid.active_key
		if key.begins_with("normal_") or key.begins_with("elite_"):
			key = ("elite_" if preview_elite else "normal_") + key.get_slice("_", 1)
		grid.select_cell(grid.row_index_for(row_id(int(value))), grid.column_index_for(key))
	)
	type_picker.add_item("Normal")
	type_picker.add_item("Elite")
	controls.add_child(type_picker)
	type_picker.item_selected.connect(func(index):
		preview_elite = index == 1
		encounter_index = 0
		_rebuild_details()
	)
	layout_picker.custom_minimum_size.x = 230
	controls.add_child(layout_picker)
	layout_picker.item_selected.connect(func(index):
		encounter_index = index
		_rebuild_details()
	)
	_label(controls, "Seed")
	seed_picker.min_value = 0
	seed_picker.max_value = 2147483647
	seed_picker.custom_minimum_size.x = 125
	controls.add_child(seed_picker)
	seed_picker.value_changed.connect(func(_value): _rebuild_details())
	_button(controls, "Next sample", func(): seed_picker.value += 1)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lower.add_child(scroll)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 8)
	scroll.add_child(details)
	split.split_offset = int(preferences.get_value("table", "split", 0))
	split.dragged.connect(func(offset):
		preferences.set_value("table", "split", offset)
		_save_preferences()
	)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	grid.selection_changed.connect(func():
		if grid.active_key.begins_with("normal_") or grid.active_key.begins_with("elite_"):
			var elite := grid.active_key.begins_with("elite_")
			if preview_elite != elite:
				encounter_index = 0
			preview_elite = elite
		_rebuild_details()
	)
	grid.edit_requested.connect(_edit_cell)
	grid.sort_requested.connect(func(key):
		sort_ascending = not sort_ascending if sort_key == key else true
		sort_key = key
		_refresh()
		_save_preferences()
	)
	grid.paste_requested.connect(paste_text)
	grid.undo_requested.connect(func(): store.history.undo())
	grid.redo_requested.connect(func(): store.history.redo())
	store.changed.connect(_schedule_refresh)
	refresh_catalog()
	var recovered := store.restore_recovery() if not store.recovery_path.is_empty() else 0
	_refresh()
	_message("Recovered %d resource drafts. Review and save, or Revert All." % recovered if recovered > 0 else "Double-click / Enter to edit • Shift-click: rectangle • Ctrl-click: rows • Ctrl+C/V: copy/paste")


static func row_id(floor_number: int) -> String:
	return "floor:%02d" % floor_number


func refresh_catalog() -> void:
	catalog.scan(catalog_root, scene_root)
	for path in catalog.runs:
		store.add_resource(path)
	store.refresh_clean()
	run_picker.clear()
	if selected_run not in catalog.runs and not catalog.runs.is_empty():
		selected_run = catalog.runs[0]
	for path in catalog.runs:
		var config := store.draft(path) as RunConfig
		var index := run_picker.item_count
		run_picker.add_item(("● " if _run_dirty(path) else "") + config.display_name + " — " + path.get_file())
		run_picker.set_item_metadata(index, path)
		if path == selected_run:
			run_picker.select(index)
	_refresh()


func select_run(path: String) -> void:
	selected_run = path
	for index in range(run_picker.item_count):
		if str(run_picker.get_item_metadata(index)) == path:
			run_picker.select(index)
	grid.active_path = ""
	grid.selected.clear()
	grid.anchor_path = ""
	grid.active_key = "display_name"
	grid.anchor_key = "display_name"
	grid.vertical.value = 0
	grid.horizontal.value = 0
	preview_elite = false
	encounter_index = 0
	_refresh()
	_save_preferences()


func _run_dirty(path: String) -> bool:
	return store.is_dirty(path) or store.dependencies(path).any(func(p): return store.is_dirty(p))


func _refresh() -> void:
	refresh_queued = false
	if not is_node_ready():
		return
	var config := store.draft(selected_run) as RunConfig
	var rows: Array = []
	if config != null:
		report = config.validate_configuration()
		var columns := Model.columns(config.is_linear())
		if not columns.any(func(column): return column.key == grid.active_key):
			grid.active_key = "display_name"
			grid.anchor_key = "display_name"
		if not columns.any(func(column): return column.key == sort_key):
			sort_key = "display_name"
		for floor_number in range(1, config.combat_floor_count() + 1):
			var normal := Model.settings(config, floor_number)
			var elite := Model.settings(config, floor_number, true)
			var raw := {"display_name": floor_number, "stage": normal.stage}
			var cells := {"display_name": ("● " if _run_dirty(selected_run) else "") + "Floor %d" % floor_number, "stage": normal.stage}
			for kind in ["normal", "elite"]:
				var settings: Dictionary = normal if kind == "normal" else elite
				raw[kind + "_cr"] = settings.cr
				raw[kind + "_pool"] = ";".join(Model.pool_paths(settings.pool))
				cells[kind + "_cr"] = "%d [%s]" % [settings.cr, settings.cr_source]
				var names: Array[String] = []
				for scene in settings.pool:
					if scene != null:
						catalog.add_enemy(scene.resource_path)
						names.append(scene.resource_path.get_file().get_basename().capitalize())
					else:
						names.append("Missing scene")
				cells[kind + "_pool"] = "[%s] " % settings.pool_source + ", ".join(names)
			var issues: Array = report.errors.filter(func(message): return not str(message).begins_with("Floor ") or str(message).begins_with("Floor %d /" % floor_number))
			issues.append_array(report.warnings.filter(func(message): return str(message).begins_with("Floor %d /" % floor_number)))
			cells.validation = "Valid" if issues.is_empty() else "; ".join(issues)
			raw.validation = cells.validation
			if not search.text.is_empty() and search.text.to_lower() not in (str(cells.values()) + str(raw.values())).to_lower():
				continue
			rows.append({"path": row_id(floor_number), "cells": cells, "raw": raw, "floor": floor_number,
				"explanation": "Resolved floor settings; green fields are read-only. Pool copy uses scene paths."})
		rows.sort_custom(func(a, b):
			var left: Variant = a.raw.get(sort_key, a.floor)
			var right: Variant = b.raw.get(sort_key, b.floor)
			if left == right:
				return a.floor < b.floor
			if left is int and right is int:
				return left < right if sort_ascending else left > right
			return str(left).naturalnocasecmp_to(str(right)) < 0 if sort_ascending else str(left).naturalnocasecmp_to(str(right)) > 0
		)
		for column in columns:
			if column.key == sort_key:
				column.title += " ↑" if sort_ascending else " ↓"
		grid.set_data(columns, rows)
		floor_picker.max_value = config.combat_floor_count()
		type_picker.disabled = config.is_linear()
		if config.is_linear():
			preview_elite = false
	else:
		grid.set_data([], [])
		report = {"errors": ["The selected run resource is missing. Restore it or Revert All."], "warnings": []}
	grid.selected.assign(grid.selected.filter(func(path): return rows.any(func(row): return row.path == path)))
	if not rows.is_empty() and not rows.any(func(row): return row.path == grid.active_path):
		grid.select_cell(0, 0)
	summary.text = "%d floors • %d unsaved • %d errors • %d warnings" % [rows.size(), store.dirty_paths().size(), report.errors.size(), report.warnings.size()]
	for index in range(run_picker.item_count):
		var path: String = run_picker.get_item_metadata(index)
		var run := store.draft(path) as RunConfig
		if run != null:
			run_picker.set_item_text(index, ("● " if _run_dirty(path) else "") + run.display_name + " — " + path.get_file())
	save_button.disabled = store.dirty_paths().is_empty()
	undo_button.disabled = not store.history.has_undo()
	redo_button.disabled = not store.history.has_redo()
	_rebuild_details()


func _schedule_refresh() -> void:
	if not refresh_queued:
		refresh_queued = true
		_refresh.call_deferred()


func apply_values(paths: Array, column: Dictionary, text: String) -> bool:
	if column.kind == "result":
		_message("This column is read-only.", true)
		return false
	var parsed := Model.parse(column.key, text)
	if parsed.has("error"):
		_message(parsed.error, true)
		return false
	var edits: Array = []
	for path in paths:
		if not grid.rows.any(func(row): return row.path == path):
			return false
		edits.append({"floor": str(path).trim_prefix("floor:").to_int(), "key": column.key, "value": parsed.value})
	var success := store.edit_cells(selected_run, edits, "Set " + column.title)
	_message("Updated %d floor(s). Review, then Save All." % edits.size() if success else "Could not edit this run.", not success)
	return success


func paste_text(text: String) -> bool:
	if not grid.rows.any(func(row): return row.path == grid.active_path):
		_message("Select the first destination cell.", true)
		return false
	var lines := text.replace("\r\n", "\n").replace("\r", "\n").trim_suffix("\n").split("\n")
	var start_row := grid.row_index_for(grid.active_path)
	var start_column := grid.column_index_for(grid.active_key)
	var width := -1
	var edits: Array = []
	for offset in range(lines.size()):
		var values := lines[offset].split("\t")
		if width < 0:
			width = values.size()
		if values.size() != width or start_row + offset >= grid.rows.size() or start_column + width > grid.columns.size():
			_message("Paste must be a rectangle that fits the visible table. Nothing changed.", true)
			return false
		for index in range(values.size()):
			var column: Dictionary = grid.columns[start_column + index]
			var parsed := Model.parse(column.key, values[index]) if column.kind != "result" else {"error": "This column is read-only."}
			if parsed.has("error"):
				_message(parsed.error + " Nothing changed.", true)
				return false
			edits.append({"floor": grid.rows[start_row + offset].floor, "key": column.key, "value": parsed.value})
	return store.edit_cells(selected_run, edits, "Paste encounter cells")


func _edit_cell(path: String, column: Dictionary, targets: Array = []) -> void:
	if column.kind == "result":
		_message("This is a read-only field. Edit CR or a units pool.")
		return
	var paths: Array = targets if not targets.is_empty() else [path]
	var row: Dictionary = grid.rows[grid.row_index_for(path)]
	if column.kind == "pool":
		_pool_dialog(column.title, str(row.raw[column.key]), func(text): apply_values(paths, column, text))
	else:
		_text_dialog(column.title, str(row.raw[column.key]), func(text): apply_values(paths, column, text))


func _bulk_edit() -> void:
	var paths: Array = grid.rows.filter(func(row): return row.path in grid.selected).map(func(row): return row.path)
	if not paths.is_empty():
		_edit_cell(paths[0], grid.columns[grid.column_index_for(grid.active_key)], paths)


func _reset_selected() -> void:
	if grid.columns.is_empty() or grid.columns[grid.column_index_for(grid.active_key)].kind == "result":
		_message("Select a CR or pool column to reset.")
		return
	var edits: Array = []
	for row in grid.rows:
		if row.path in grid.selected:
			edits.append({"floor": row.floor, "key": grid.active_key, "reset": true})
	store.edit_cells(selected_run, edits, "Reset selected encounter fields")


func _rebuild_details() -> void:
	_clear(details)
	var config := store.draft(selected_run) as RunConfig
	if config == null or grid.active_path.is_empty() or not grid.rows.any(func(row): return row.path == grid.active_path):
		_label(details, "Select a floor to edit its settings and preview a generated roster.")
		return
	var floor_number := grid.active_path.trim_prefix("floor:").to_int()
	floor_picker.set_value_no_signal(floor_number)
	type_picker.select(1 if preview_elite else 0)
	layout_picker.clear()
	var encounters := config.elite_encounters if preview_elite else config.normal_encounters
	for encounter in encounters:
		layout_picker.add_item(encounter.display_name if encounter != null else "Missing encounter")
	encounter_index = clampi(encounter_index, 0, maxi(0, encounters.size() - 1))
	if layout_picker.item_count > 0:
		layout_picker.select(encounter_index)
	_label(details, "Floor %d — %s combat — %s" % [floor_number, "Elite" if preview_elite else "Normal", selected_run], 17)
	var actions := HFlowContainer.new()
	details.add_child(actions)
	_button(actions, "Inspect run / stages", func():
		if Engine.is_editor_hint():
			EditorInterface.edit_resource(load(selected_run))
	)
	for key in ["normal_cr", "normal_pool", "elite_cr", "elite_pool"]:
		if config.is_linear() and key.begins_with("elite_"):
			continue
		_button(actions, "Reset " + key.replace("_", " ").capitalize(), func():
			store.edit_cells(selected_run, [{"floor": floor_number, "key": key, "reset": true}], "Reset " + key)
		)
	for elite in [false, true]:
		var source := store.source_path(selected_run, floor_number, elite)
		if not source.is_empty():
			var owners: Array = catalog.runs.filter(func(path): return source in store.dependencies(path))
			_label(details, "%s shared override: %s — used by %d run(s)" % ["Elite" if elite else "Normal", source, owners.size()])
	var selected_row: Dictionary = grid.rows[grid.row_index_for(grid.active_path)]
	_label(details, "Validation: " + str(selected_row.cells.validation))
	if config.combat_stages.is_empty():
		_label(details, "This run uses legacy encounters. Add combat stages in the Inspector before authoring floor overrides.")
		return
	var preview := Model.preview(config, floor_number, preview_elite, encounter_index, int(seed_picker.value))
	if not preview.error.is_empty():
		_label(details, "Preview unavailable: " + preview.error)
		return
	_label(details, "Budget %d CR • Achievable %d CR • Unused %d CR • Enemy cells %d • Friendly cells %d • Stats %.1f×" % [preview.budget, preview.total_cr, preview.unused, preview.capacity, preview.friendly_capacity, preview.multiplier])
	_label(details, "Sample roster — seed %d (repeated enemy types are allowed)" % int(seed_picker.value))
	for path in preview.roster:
		var entry: Dictionary = preview.roster[path]
		var line := HBoxContainer.new()
		details.add_child(line)
		if entry.icon != null:
			var art := TextureRect.new()
			art.texture = entry.icon
			art.custom_minimum_size = Vector2(32, 32)
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			line.add_child(art)
		_label(line, "%d × %s — CR %d each, %d total — %s" % [entry.count, entry.name, entry.cr, entry.count * entry.cr, path])


func _pool_dialog(title: String, current: String, callback: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.ok_button_text = "Use selected units"
	var content := VBoxContainer.new()
	dialog.add_child(content)
	var filter := LineEdit.new()
	filter.placeholder_text = "Search enemy name, scene path, or CR…"
	content.add_child(filter)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(650, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var chosen := {}
	for path in current.split(";", false):
		chosen[path] = true
		catalog.add_enemy(path)
	var populate := func():
		_clear(list)
		var paths: Array = catalog.enemies.keys()
		for path in chosen:
			if path not in paths:
				paths.append(path)
		paths.sort()
		for path in paths:
			var entry: Dictionary = catalog.enemies.get(path, {"name": "Missing enemy", "cr": 0, "icon": null})
			var label := "%s — CR %d\n%s" % [entry.name, entry.cr, path]
			if not filter.text.is_empty() and filter.text.to_lower() not in label.to_lower():
				continue
			var check := CheckBox.new()
			check.text = label
			check.button_pressed = chosen.get(path, false)
			check.icon = entry.icon
			check.expand_icon = true
			check.add_theme_constant_override("icon_max_width", 40)
			check.set_meta("scene_path", path)
			list.add_child(check)
			check.toggled.connect(func(enabled): chosen[path] = enabled)
	filter.text_changed.connect(func(_text): populate.call())
	_button(content, "Browse enemy scene…", func():
		var browser := FileDialog.new()
		browser.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		browser.access = FileDialog.ACCESS_RESOURCES
		browser.filters = PackedStringArray(["*.tscn,*.scn ; Enemy scenes"])
		add_child(browser)
		browser.file_selected.connect(func(path):
			var entry := Catalog.inspect_enemy(path)
			if entry.error.is_empty():
				catalog.enemies[path] = entry
				chosen[path] = true
				populate.call()
			else:
				_message(entry.error, true)
		)
		_free_when_hidden(browser)
		browser.popup_centered_ratio(0.7)
	)
	populate.call()
	add_child(dialog)
	dialog.confirmed.connect(func():
		var paths: Array = chosen.keys().filter(func(path): return chosen[path])
		paths.sort()
		callback.call(";".join(paths))
	)
	_free_when_hidden(dialog)
	dialog.popup_centered_clamped(Vector2i(740, 470), 0.85)
	filter.grab_focus()


func _text_dialog(title: String, current: String, callback: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	var input := LineEdit.new()
	input.text = current
	input.custom_minimum_size.x = 360
	dialog.add_child(input)
	add_child(dialog)
	dialog.confirmed.connect(func(): callback.call(input.text))
	input.text_submitted.connect(func(_text):
		callback.call(input.text)
		dialog.hide()
	)
	_free_when_hidden(dialog)
	dialog.popup_centered(Vector2i(430, 130))
	input.grab_focus()
	input.select_all()


func save_changes(overwrite: Array[String] = []) -> Dictionary:
	var result := store.save_all(overwrite)
	_message("Saved %d resource(s). %s" % [result.saved.size(), "; ".join(result.failed)], not result.failed.is_empty())
	if not result.conflicts.is_empty():
		var dialog := ConfirmationDialog.new()
		dialog.title = "Resources changed outside Encounter Balance"
		dialog.dialog_text = "Changed resources:\n" + "\n".join(result.conflicts) + "\n\nOverwrite applies changed draft fields and preserves other disk fields. Reload discards these drafts."
		dialog.ok_button_text = "Overwrite these drafts"
		dialog.add_button("Reload these drafts", false, "reload")
		add_child(dialog)
		var conflicting: Array[String] = []
		conflicting.assign(result.conflicts)
		dialog.confirmed.connect(func(): save_changes(conflicting))
		dialog.custom_action.connect(func(action):
			if action == "reload":
				store.reload_paths(conflicting)
				dialog.hide()
		)
		_free_when_hidden(dialog)
		dialog.popup_centered_clamped(Vector2i(680, 300), 0.85)
		_message("External changes detected. Conflicting drafts remain unsaved.", true)
	if Engine.is_editor_hint() and not result.saved.is_empty():
		EditorInterface.get_resource_filesystem().scan()
	return result


func _confirm_revert() -> void:
	if store.dirty_paths().is_empty():
		return
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Discard all unsaved Encounter Balance edits and clear undo history?"
	dialog.ok_button_text = "Revert All"
	add_child(dialog)
	dialog.confirmed.connect(func(): store.reload_paths(store.dirty_paths()))
	_free_when_hidden(dialog)
	dialog.popup_centered(Vector2i(530, 150))


func _save_preferences() -> void:
	if not persist_preferences:
		return
	DirAccess.make_dir_recursive_absolute(preferences_path.get_base_dir())
	preferences.set_value("table", "run", selected_run)
	preferences.set_value("table", "sort_key", sort_key)
	preferences.set_value("table", "sort_ascending", sort_ascending)
	preferences.save(preferences_path)


func _message(text: String, error := false) -> void:
	status.text = text
	status.add_theme_color_override("font_color", Color("ffb095") if error else Color("a8c4dd"))


static func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


static func _label(parent: Node, text: String, font_size := 14) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_OFF if parent is HFlowContainer else TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if parent is HFlowContainer else Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


static func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


static func _free_when_hidden(dialog: Window) -> void:
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free()
	)


func _exit_tree() -> void:
	store.history.clear_history()
