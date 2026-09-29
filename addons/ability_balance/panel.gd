@tool
extends VBoxContainer

const Catalog = preload("res://addons/ability_balance/catalog.gd")
const Store = preload("res://addons/ability_balance/draft_store.gd")
const Columns = preload("res://addons/ability_balance/columns.gd")
const Grid = preload("res://addons/unit_balance/balance_grid.gd")
const ColumnPicker = preload("res://addons/unit_balance/column_picker.gd")
const PREFS := "res://.godot/ability_balance/preferences.cfg"

var catalog := Catalog.new()
var store := Store.new()
var grid := Grid.new()
var search := LineEdit.new()
var status := Label.new()
var summary := Label.new()
var details := VBoxContainer.new()
var tabs := TabBar.new()
var preferences := ConfigFile.new()
var column_visibility: Dictionary = {}
var sort_key := "display_name"
var sort_ascending := true
var refresh_queued := false
var save_button: Button
var undo_button: Button
var redo_button: Button
var catalog_root := "res://resources"
var persist_preferences := true
var preferences_path := PREFS


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	if persist_preferences and preferences.load(preferences_path) == OK:
		sort_key = preferences.get_value("table", "sort_key", sort_key)
		sort_ascending = preferences.get_value("table", "sort_ascending", true)
	for table in ["active", "passives"]:
		column_visibility[table] = _normalize_columns(table, preferences.get_value("table", table + "_columns", Columns.defaults(table)))
	var heading := HBoxContainer.new()
	add_child(heading)
	var title := Label.new()
	title.text = "ABILITY BALANCE"
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
	_button(toolbar, "Copy", func(): DisplayServer.clipboard_set(grid.copy_text()))
	_button(toolbar, "Paste", func(): paste_text(DisplayServer.clipboard_get()))
	var filter_bar := HBoxContainer.new()
	add_child(filter_bar)
	tabs.add_tab("Active Abilities")
	tabs.add_tab("Passives")
	tabs.custom_minimum_size.x = 270
	filter_bar.add_child(tabs)
	_button(filter_bar, "Columns…", _show_column_picker)
	search.placeholder_text = "Search name, path, effects, or values…"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_bar.add_child(search)
	search.text_changed.connect(func(_text): _refresh())
	tabs.tab_changed.connect(func(_tab):
		grid.selected.clear()
		grid.active_path = ""
		grid.anchor_path = ""
		grid.active_key = "display_name"
		grid.anchor_key = "display_name"
		grid.horizontal.value = 0
		_refresh()
	)
	var conditions := Label.new()
	conditions.text = "Edit shared ability definitions • Changes stay in drafts until Save All • Formulas use no selected caster."
	conditions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	conditions.add_theme_color_override("font_color", Color("9eb7d1"))
	add_child(conditions)
	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	split.add_child(grid)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 260
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
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
	grid.selection_changed.connect(_rebuild_details)
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
	_save_preferences()
	_message("Recovered %d unsaved resources. Review and Save All, or Revert All." % recovered if recovered > 0 else "Double-click / Enter to edit • Shift-click: rectangle • Ctrl-click: rows • Ctrl+C/V: copy/paste • Green values are read-only summaries")


func refresh_catalog() -> void:
	catalog.scan(catalog_root)
	for path in catalog.active + catalog.passives:
		store.add_resource(path)
	store.refresh_clean()
	_refresh()


func _table_key() -> String:
	return "active" if tabs.current_tab == 0 else "passives"


func _normalize_columns(table: String, keys: Array) -> Array:
	return Columns.definitions(table).filter(func(column): return column.key == "display_name" or column.key in keys).map(func(column): return column.key)


func set_visible_columns(table: String, keys: Array) -> void:
	column_visibility[table] = _normalize_columns(table, keys)
	_refresh()
	_save_preferences()


func _show_column_picker() -> void:
	var picker := ColumnPicker.new()
	var table := _table_key()
	picker.setup(table, column_visibility[table], Columns.definitions(table), Columns.defaults(table))
	picker.search.placeholder_text = "Search columns (name, effect, targeting…)"
	add_child(picker)
	picker.columns_changed.connect(func(keys): set_visible_columns(table, keys))
	picker.visibility_changed.connect(func():
		if not picker.visible:
			picker.queue_free()
	)
	picker.popup_centered_clamped(Vector2i(520, 600), 0.85)
	picker.search.grab_focus()


func _refresh() -> void:
	refresh_queued = false
	if not is_node_ready():
		return
	var all_columns := Columns.definitions(_table_key())
	var keys: Array = column_visibility[_table_key()]
	_reconcile_visible_columns(keys)
	var visible_columns := all_columns.filter(func(column): return column.key in keys)
	var rows: Array = []
	var paths: Array = catalog.active if tabs.current_tab == 0 else catalog.passives
	for path in paths:
		if not store.states.has(path):
			continue
		var resource := store.draft(path)
		if resource == null:
			continue
		var cells := {}
		var raw := {}
		for column in all_columns:
			if column.kind == "result":
				continue
			var value: Variant = resource.get(column.key)
			# Dynamic enum choices (Weapon scaling) depend on this row's type/effect.
			var actual := Columns.property_column(resource, column.key)
			cells[column.key] = Columns.format_value(actual, value)
			if column.kind == "resource":
				raw[column.key] = value.resource_path if value is Resource else ""
			else:
				raw[column.key] = cells[column.key] if value is String or value is StringName or value is Color else value
		cells.effect_summary = _effect_summary(resource)
		var errors := store.validation(path)
		cells.validation = "Valid" if errors.is_empty() else "; ".join(errors)
		raw.effect_summary = cells.effect_summary
		raw.validation = cells.validation
		cells.display_name = ("● " if store.is_dirty(path) or store.dependencies(path).any(func(p): return store.is_dirty(p)) else "") + str(resource.display_name)
		var query := search.text.strip_edges().to_lower()
		if not query.is_empty() and query not in (path + " " + str(cells.values())).to_lower():
			continue
		rows.append({"path": path, "cells": cells, "raw": raw, "explanation": "Shared ability definition"})
	rows.sort_custom(func(a, b):
		var left: Variant = a.raw.get(sort_key, a.raw.display_name)
		var right: Variant = b.raw.get(sort_key, b.raw.display_name)
		if left == right:
			return a.path < b.path
		if (left is int or left is float) and (right is int or right is float):
			return left < right if sort_ascending else left > right
		var comparison := str(left).naturalnocasecmp_to(str(right))
		return comparison < 0 if sort_ascending else comparison > 0
	)
	for column in visible_columns:
		if column.key == sort_key:
			column.title += " ↑" if sort_ascending else " ↓"
	grid.set_data(visible_columns, rows)
	summary.text = "%d / %d rows  •  %d unsaved" % [rows.size(), paths.size(), store.dirty_paths().size()]
	save_button.disabled = store.dirty_paths().is_empty()
	undo_button.disabled = not store.history.has_undo()
	redo_button.disabled = not store.history.has_redo()
	_rebuild_details()


func _effect_summary(resource: Resource) -> String:
	var parts: Array[String] = []
	for effect in resource.effects:
		parts.append(effect.get_description() if effect != null else "Empty effect")
	return "; ".join(parts) if not parts.is_empty() else "None"


func _edit_cell(path: String, column: Dictionary, targets: Array = []) -> void:
	if column.kind == "result":
		_message("This is a read-only summary. Edit the definition or its effects below.")
		return
	var paths: Array = targets if not targets.is_empty() else [path]
	var resource := store.draft(path)
	if resource == null or not grid.rows.any(func(row): return row.path == path):
		_message("Select a visible resource before editing.", true)
		return
	var actual := Columns.property_column(resource, column.key)
	_edit_value(actual, resource.get(column.key), func(text): apply_values(paths, column, text))


func _edit_value(column: Dictionary, value: Variant, callback: Callable) -> void:
	match str(column.kind):
		"enum": _pick_values(column.title, column.choices, callback)
		"bool": _pick_values(column.title, ["Yes", "No"], callback)
		"resource": _pick_resource(column, callback)
		"flags": _flags_dialog(column, int(value), callback)
		"multiline": _multiline_dialog(column.title, str(value), callback)
		_: _text_dialog(column.title, Columns.format_value(column, value), callback)


func _parse_for_state(path: String, state: Dictionary, key: String, text: String) -> Dictionary:
	var resource: Resource = load(path).duplicate(false)
	store.apply_state(resource, state, false)
	var column := Columns.property_column(resource, key)
	if column.is_empty():
		return {"error": "This is a read-only summary."}
	return Columns.parse(column, text)


func apply_values(paths: Array, column: Dictionary, text: String) -> bool:
	if column.kind == "result":
		_message("This column is read-only.", true)
		return false
	var replacements := {}
	for path in paths:
		var parsed := _parse_for_state(path, store.states[path], column.key, text)
		if parsed.has("error"):
			_message(parsed.error, true)
			return false
		var state: Dictionary = store.states[path].duplicate(true)
		state[column.key] = parsed.value
		replacements[path] = state
	store.change("Set " + column.title, replacements)
	_message("Updated %d row(s). Review, then Save All." % paths.size())
	return true


func paste_text(text: String) -> bool:
	if grid.active_path.is_empty() or not grid.rows.any(func(row): return row.path == grid.active_path):
		_message("Select the first destination cell before pasting.", true)
		return false
	var lines := text.replace("\r\n", "\n").replace("\r", "\n").trim_suffix("\n").split("\n")
	var start_row := grid.row_index_for(grid.active_path)
	var start_column := grid.column_index_for(grid.active_key)
	var width := -1
	var replacements := {}
	for offset in range(lines.size()):
		var values := lines[offset].split("\t")
		if width == -1:
			width = values.size()
		if values.size() != width or start_row + offset >= grid.rows.size() or start_column + width > grid.columns.size():
			_message("Paste must be a rectangle that fits the visible table. Nothing changed.", true)
			return false
		var path: String = grid.rows[start_row + offset].path
		var state: Dictionary = store.states[path].duplicate(true)
		for index in range(values.size()):
			var column: Dictionary = grid.columns[start_column + index]
			var parsed := _parse_for_state(path, state, column.key, values[index])
			if column.kind == "result" or parsed.has("error"):
				_message(str(parsed.get("error", "Read-only summary.")) + " Nothing changed.", true)
				return false
			state[column.key] = parsed.value
		replacements[path] = state
	store.change("Paste ability cells", replacements)
	_message("Pasted %d × %d cells. Undo restores the entire edit." % [lines.size(), width])
	return true


func _rebuild_details() -> void:
	_clear(details)
	var path: String = grid.active_path
	if path.is_empty() or not store.states.has(path):
		_detail_text("Select an ability or passive to edit effects and presentation settings.")
		return
	var resource := store.draft(path)
	if resource == null:
		_detail_text("Resource is missing: " + path + ". Draft retained; restore the file or Revert All.")
		return
	_detail_text(str(resource.display_name) + "  •  " + path, 17)
	_detail_text(resource.get_description())
	var errors := store.validation(path)
	_detail_text("Validation: " + ("Valid" if errors.is_empty() else "; ".join(errors)))
	var references: Array = catalog.references.get(path, [])
	_detail_text("Used by: " + ("; ".join(references) if not references.is_empty() else "No class, unit, or status references found"))
	var bar := HFlowContainer.new()
	details.add_child(bar)
	_button(bar, "Inspect saved resource", func():
		if Engine.is_editor_hint():
			EditorInterface.edit_resource(load(path))
	)
	_button(bar, "Add effect…", func(): _add_effect_dialog(path))
	for index in range(resource.effects.size()):
		_effect_editor(path, index, resource.effects[index])
	var presentation := VBoxContainer.new()
	var toggle := CheckButton.new()
	toggle.text = "Presentation settings"
	details.add_child(toggle)
	details.add_child(presentation)
	presentation.visible = false
	toggle.toggled.connect(func(shown): presentation.visible = shown)
	for property in resource.get_property_list():
		if property.name in Columns.PRESENTATION:
			_property_button(presentation, path, -1, resource, Columns.from_property(property))


func _effect_editor(path: String, index: int, effect: Resource) -> void:
	var box := VBoxContainer.new()
	details.add_child(box)
	var bar := HFlowContainer.new()
	box.add_child(bar)
	var title := Label.new()
	title.text = "%d. %s" % [index + 1, effect.get_script().resource_path.get_file().get_basename().capitalize() if effect != null else "Empty effect"]
	bar.add_child(title)
	var up := _button(bar, "↑", func(): _move_effect(path, index, -1))
	up.disabled = index == 0
	var down := _button(bar, "↓", func(): _move_effect(path, index, 1))
	down.disabled = index == store.states[path].effects.size() - 1
	_button(bar, "Remove", func():
		var entries: Array = store.states[path].effects.duplicate(true)
		entries.remove_at(index)
		store.set_field(path, "effects", entries)
	)
	if effect == null:
		return
	var location := store.effect_location(path, index)
	if location.index < 0:
		var shared := Label.new()
		shared.text = "Shared effect: " + location.path
		box.add_child(shared)
	var script_path: String = effect.get_script().resource_path
	if script_path not in Columns.ACTIVE_EFFECTS + Columns.PASSIVE_EFFECTS:
		var snapshot: Variant = store.states[path].effects[index]
		_button(bar, "Inspect custom effect", func():
			if Engine.is_editor_hint():
				# Locate the saved custom type even after draft reordering/removal.
				var saved: Resource = load(path)
				for original in saved.effects:
					if original != null and Store.encode(original) == snapshot:
						EditorInterface.edit_resource(original)
						break
		)
		return
	var properties := HFlowContainer.new()
	box.add_child(properties)
	for property in effect.get_property_list():
		if Columns.editable_property(property):
			_property_button(properties, path, index, effect, Columns.from_property(property))


func _property_button(parent: Control, path: String, index: int, resource: Resource, column: Dictionary) -> void:
	var value: Variant = resource.get(column.key)
	var button := _button(parent, column.title + ": " + Columns.format_value(column, value), func():
		_edit_value(column, value, func(text):
			var parsed := Columns.parse(column, text)
			if parsed.has("error"):
				_message(parsed.error, true)
				return
			if index < 0:
				store.set_field(path, column.key, parsed.value)
			else:
				store.set_effect_field(path, index, column.key, parsed.value)
		)
	)
	if value is Texture2D:
		button.icon = value
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 28)
	elif value is StatusEffectDefinition and value.icon != null:
		button.icon = value.icon
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 28)


func _add_effect_dialog(path: String) -> void:
	var scripts: Array = Columns.ACTIVE_EFFECTS if store.draft(path) is AbilityDefinition else Columns.PASSIVE_EFFECTS
	var options: Array = []
	for script in scripts:
		options.append({"label": script.get_file().get_basename().capitalize(), "value": script})
	_choice_dialog("Add effect", options, func(script):
		var effects: Array = store.states[path].effects.duplicate(true)
		effects.append(Store.encode(load(script).new()))
		store.set_field(path, "effects", effects)
	)


func _move_effect(path: String, index: int, offset: int) -> void:
	var effects: Array = store.states[path].effects.duplicate(true)
	var entry: Variant = effects[index]
	effects.remove_at(index)
	effects.insert(index + offset, entry)
	store.set_field(path, "effects", effects)


func _pick_resource(column: Dictionary, callback: Callable) -> void:
	if column.resource_type == "StatusEffectDefinition":
		var options: Array = [{"label": "None", "value": ""}]
		for path in catalog.statuses:
			var status_resource: StatusEffectDefinition = load(path)
			options.append({"label": Catalog.label(path) + " · " + path, "value": path, "icon": status_resource.icon})
		_choice_dialog(column.title, options, callback)
	else:
		var dialog := FileDialog.new()
		dialog.title = "Choose texture (Cancel to keep current)"
		dialog.access = FileDialog.ACCESS_RESOURCES
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dialog.filters = PackedStringArray(["*.png,*.svg,*.jpg,*.jpeg,*.webp,*.tres,*.res ; Texture resources"])
		dialog.add_button("Clear", false, "clear")
		dialog.custom_action.connect(func(_action):
			callback.call("")
			dialog.hide()
		)
		dialog.file_selected.connect(callback)
		add_child(dialog)
		dialog.visibility_changed.connect(func():
			if not dialog.visible:
				dialog.queue_free()
		)
		dialog.popup_centered_clamped(Vector2i(800, 600), 0.85)


func _flags_dialog(column: Dictionary, value: int, callback: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = column.title
	var box := VBoxContainer.new()
	dialog.add_child(box)
	var checks: Array[CheckBox] = []
	for index in range(column.choices.size()):
		var check := CheckBox.new()
		check.text = column.choices[index]
		check.button_pressed = bool(value & int(column.values[index]))
		box.add_child(check)
		checks.append(check)
	dialog.confirmed.connect(func():
		var flags := 0
		for index in range(checks.size()):
			if checks[index].button_pressed:
				flags |= int(column.values[index])
		callback.call(str(flags))
	)
	add_child(dialog)
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free()
	)
	dialog.popup_centered(Vector2i(350, 250))


func _multiline_dialog(title: String, current: String, callback: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	var input := TextEdit.new()
	input.text = current
	input.custom_minimum_size = Vector2(550, 240)
	dialog.add_child(input)
	add_child(dialog)
	dialog.confirmed.connect(func(): callback.call(input.text))
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free()
	)
	dialog.popup_centered_clamped(Vector2i(610, 320), 0.85)
	input.grab_focus()


func _save_preferences() -> void:
	if not persist_preferences:
		return
	for table in ["active", "passives"]:
		preferences.set_value("table", table + "_columns", column_visibility[table])
	preferences.set_value("table", "sort_key", sort_key)
	preferences.set_value("table", "sort_ascending", sort_ascending)
	DirAccess.make_dir_recursive_absolute(preferences_path.get_base_dir())
	preferences.save(preferences_path)


func _schedule_refresh() -> void:
	if not refresh_queued:
		refresh_queued = true
		_refresh.call_deferred()


func _reconcile_visible_columns(keys: Array) -> void:
	if grid.active_key not in keys or grid.anchor_key not in keys:
		grid.active_key = "display_name"
		grid.anchor_key = "display_name"
	if sort_key not in keys:
		sort_key = "display_name"
		sort_ascending = true


func _bulk_edit() -> void:
	var paths: Array = grid.rows.filter(func(row): return row.path in grid.selected).map(func(row): return row.path)
	if paths.is_empty():
		_message("Select rows and the column to change first.")
		return
	_edit_cell(paths[0], grid.columns[grid.column_index_for(grid.active_key)], paths)


func save_changes(overwrite: Array[String] = []) -> Dictionary:
	var result := store.save_all(overwrite)
	var messages: Array[String] = ["Saved %d resource(s)." % result.saved.size()]
	if not result.failed.is_empty():
		messages.append("Save failed: " + "; ".join(result.failed))
	if not result.conflicts.is_empty():
		messages.append("External changes detected. Conflicting drafts remain unsaved.")
		var dialog := ConfirmationDialog.new()
		dialog.title = "Resources changed outside Ability Balance"
		dialog.dialog_text = "These resources changed since your draft began:\n" + "\n".join(result.conflicts) + "\n\nOverwrite applies this draft's editable fields. Reload discards these drafts."
		dialog.ok_button_text = "Overwrite these drafts"
		dialog.add_button("Reload these drafts", false, "reload")
		add_child(dialog)
		var conflicts_to_replace: Array[String] = []
		conflicts_to_replace.assign(result.conflicts)
		dialog.confirmed.connect(func(): save_changes(conflicts_to_replace))
		dialog.custom_action.connect(func(action):
			if action == "reload":
				store.reload_paths(result.conflicts)
				dialog.hide()
		)
		dialog.visibility_changed.connect(func():
			if not dialog.visible:
				dialog.queue_free()
		)
		dialog.popup_centered(Vector2i(680, 300))
	_message(" ".join(messages), not result.failed.is_empty() or not result.conflicts.is_empty())
	if Engine.is_editor_hint() and not result.saved.is_empty():
		EditorInterface.get_resource_filesystem().scan()
	return result


func _confirm_revert() -> void:
	if store.dirty_paths().is_empty():
		return
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Discard all unsaved Ability Balance edits and reload the resources? This clears table undo history."
	dialog.ok_button_text = "Revert All"
	add_child(dialog)
	dialog.confirmed.connect(func(): store.reload_paths(store.dirty_paths()))
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free()
	)
	dialog.popup_centered(Vector2i(530, 150))


func _pick_values(title: String, values: Array, callback: Callable) -> void:
	var options: Array = []
	for value in values:
		options.append({"label": str(value), "value": str(value)})
	_choice_dialog(title, options, callback)


func _choice_dialog(title: String, options: Array, callback: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.ok_button_text = "Choose"
	var content := VBoxContainer.new()
	dialog.add_child(content)
	var filter := LineEdit.new()
	filter.placeholder_text = "Type to filter…"
	content.add_child(filter)
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(550, 260)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(list)
	var populate := func(text: String):
		list.clear()
		for option in options:
			if text.to_lower() in str(option.label).to_lower():
				var index := list.add_item(option.label, option.get("icon", null))
				list.set_item_metadata(index, option.value)
		if list.item_count > 0:
			list.select(0)
		dialog.get_ok_button().disabled = list.item_count == 0
	filter.text_changed.connect(populate)
	populate.call("")
	var choose := func():
		if not list.get_selected_items().is_empty():
			callback.call(str(list.get_item_metadata(list.get_selected_items()[0])))
			dialog.hide()
	dialog.confirmed.connect(choose)
	list.item_activated.connect(func(_index): choose.call())
	filter.text_submitted.connect(func(_text): choose.call())
	add_child(dialog)
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free()
	)
	dialog.popup_centered(Vector2i(650, 380))
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
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free()
	)
	dialog.popup_centered(Vector2i(430, 130))
	input.grab_focus()
	input.select_all()


func _detail_text(text: String, font_size := 14) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	details.add_child(label)


func _message(text: String, error := false) -> void:
	status.text = text
	status.add_theme_color_override("font_color", Color("ffb095") if error else Color("a8c4dd"))


static func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


static func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _exit_tree() -> void:
	# UndoRedo actions hold bound references back to the store.
	store.history.clear_history()
