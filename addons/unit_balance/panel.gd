@tool
extends VBoxContainer

const Catalog = preload("res://addons/unit_balance/catalog.gd")
const Store = preload("res://addons/unit_balance/draft_store.gd")
const Preview = preload("res://addons/unit_balance/preview.gd")
const Columns = preload("res://addons/unit_balance/columns.gd")
const Grid = preload("res://addons/unit_balance/balance_grid.gd")
const ColumnVisibility = preload("res://addons/unit_balance/column_visibility.gd")
const ColumnPicker = preload("res://addons/unit_balance/column_picker.gd")
const PREFS := "res://.godot/unit_balance/preferences.cfg"

var catalog := Catalog.new()
var store := Store.new()
var grid := Grid.new()
var search := LineEdit.new()
var status := Label.new()
var summary := Label.new()
var details := VBoxContainer.new()
var tabs := TabBar.new()
var preferences := ConfigFile.new()
var attacks: Dictionary = {}
var previews: Dictionary = {}
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
		attacks = preferences.get_value("table", "attacks", {})
		sort_key = preferences.get_value("table", "sort_key", sort_key)
		sort_ascending = preferences.get_value("table", "sort_ascending", true)
	column_visibility = ColumnVisibility.read_preferences(preferences)
	var heading := HBoxContainer.new()
	add_child(heading)
	var title := Label.new()
	title.text = "UNIT BALANCE"
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
	tabs.add_tab("Enemies")
	tabs.add_tab("Items")
	tabs.custom_minimum_size.x = 190
	filter_bar.add_child(tabs)
	_button(filter_bar, "Columns…", _show_column_picker)
	search.placeholder_text = "Search name, path, equipment, or values…"
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
	conditions.text = "Preview: starting equipment, no temporary statuses, no nearby allies. Damage before target armor."
	conditions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	conditions.add_theme_color_override("font_color", Color("9eb7d1"))
	add_child(conditions)
	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	split.add_child(grid)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 150
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 8)
	scroll.add_child(details)
	split.split_offset = int(preferences.get_value("table", "split", 330))
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
	_message("Recovered %d unsaved resources. Review and Save All, or Revert All." % recovered if recovered > 0 else "Double-click / Enter to edit • Shift-click: rectangle • Ctrl-click: rows • Ctrl+C/V: copy/paste • Green values are calculated")


func refresh_catalog() -> void:
	catalog.scan(catalog_root)
	for path in catalog.enemies + catalog.items:
		store.add_resource(path)
	# Refresh clean drafts only. Dirty drafts retain their baseline for conflict checks.
	for path in store.states:
		if not store.is_dirty(path) and (FileAccess.get_sha256(path) != store.hashes[path] or Store.capture(load(path)) != store.baselines[path]):
			var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) if FileAccess.get_sha256(path) != store.hashes[path] else load(path)
			if resource != null:
				store.states[path] = Store.capture(resource)
				store.baselines[path] = store.states[path].duplicate(true)
				store.hashes[path] = FileAccess.get_sha256(path)
	_refresh()


func _schedule_refresh() -> void:
	if not refresh_queued:
		refresh_queued = true
		_refresh.call_deferred()


func _table_key() -> String:
	return "enemies" if tabs.current_tab == 0 else "items"


func _show_column_picker() -> void:
	var picker := ColumnPicker.new()
	var table := _table_key()
	picker.setup(table, column_visibility[table])
	add_child(picker)
	picker.columns_changed.connect(func(keys): set_visible_columns(table, keys))
	picker.visibility_changed.connect(func():
		if not picker.visible:
			picker.queue_free()
	)
	picker.popup_centered_clamped(Vector2i(520, 600), 0.85)
	picker.search.grab_focus()


func set_visible_columns(table: String, keys: Array) -> void:
	column_visibility[table] = ColumnVisibility.normalize(table, keys)
	_refresh()
	_save_preferences()


func _reconcile_visible_columns(keys: Array) -> void:
	if grid.active_key not in keys or grid.anchor_key not in keys:
		grid.active_key = "display_name"
		grid.anchor_key = "display_name"
	if sort_key not in keys:
		sort_key = "display_name"
		sort_ascending = true


func _refresh() -> void:
	refresh_queued = false
	if not is_node_ready():
		return
	previews.clear()
	var all_columns := Columns.enemies() if tabs.current_tab == 0 else Columns.items()
	var keys: Array = column_visibility[_table_key()]
	_reconcile_visible_columns(keys)
	var visible_columns: Array = all_columns.filter(func(column): return column.key in keys)
	var rows: Array = []
	var paths: Array = catalog.enemies if tabs.current_tab == 0 else catalog.items
	for path in paths:
		var state: Dictionary = store.states[path]
		var cells := state.duplicate(true)
		var raw := cells.duplicate(true)
		if tabs.current_tab == 0:
			var preview: Dictionary = Preview.calculate(store, path, attacks.get(path, ""))
			previews[path] = preview
			cells.merge(preview, true)
			raw.merge(preview, true)
			for slot in preview.equipment:
				var item_path: String = preview.equipment[slot]
				var reserved := not item_path.is_empty() and int((store.draft(item_path) if store.states.has(item_path) else load(item_path)).slot) != int(slot)
				cells["slot_" + str(slot)] = ("2H: " if reserved else "") + _label(item_path)
				raw["slot_" + str(slot)] = "" if reserved else item_path
			raw.attack = preview.attack_path
		else:
			for column in all_columns:
				if column.kind == "enum":
					cells[column.key] = column.choices[int(state[column.key])]
		cells.display_name = ("● " if store.is_dirty(path) else "") + str(state.display_name)
		var query := search.text.strip_edges().to_lower()
		if not query.is_empty() and query not in (path + " " + str(cells.values())).to_lower():
			continue
		rows.append({"path": path, "cells": cells, "raw": raw, "explanation": previews.get(path, {}).get("explanation", "")})
	rows.sort_custom(func(a: Dictionary, b: Dictionary):
		var left: Variant = a.raw.get(sort_key, a.raw.display_name)
		var right: Variant = b.raw.get(sort_key, b.raw.display_name)
		if left == right:
			return a.path < b.path
		if left is float or left is int:
			if right is float or right is int:
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


func _label(path: String) -> String:
	return str(store.states[path].display_name) if store.states.has(path) else Catalog.label(path)


func _edit_cell(path: String, column: Dictionary, targets: Array = []) -> void:
	if column.kind == "result":
		_message("%s is calculated. Edit its base stats, equipment, or ability assignment." % column.title)
		return
	var paths: Array = targets if not targets.is_empty() else [path]
	if column.kind in ["item", "attack"]:
		var candidates: Array = []
		if column.kind == "item":
			candidates = catalog.items.filter(func(p): return int(store.states[p].slot) == int(column.slot))
		else:
			candidates = previews.get(path, {}).get("abilities", [])
		_pick("Choose " + column.title, candidates, func(value): apply_values(paths, column, value), column.kind == "item")
	elif column.kind == "enum":
		_pick_values(column.title, column.choices, func(value): apply_values(paths, column, value))
	else:
		var current := str(store.states[path].get(column.key, ""))
		_text_dialog("Set %s · %d row(s)" % [column.title, paths.size()], current, func(value): apply_values(paths, column, value))


func _bulk_edit() -> void:
	var paths: Array = grid.rows.filter(func(row): return row.path in grid.selected).map(func(row): return row.path)
	if paths.is_empty():
		_message("Select rows and the column to change first.")
		return
	_edit_cell(paths[0], grid.columns[grid.column_index_for(grid.active_key)], paths)


func apply_values(paths: Array, column: Dictionary, text: String) -> bool:
	var replacements := {}
	var parsed := Columns.parse(column, text)
	if parsed.has("error"):
		_message(parsed.error, true)
		return false
	for path in paths:
		var result := _changed_state(path, store.states[path], column, parsed.value)
		if result.has("error"):
			_message(result.error, true)
			return false
		replacements[path] = result.state
	if column.kind == "attack":
		for path in paths:
			attacks[path] = parsed.value
		_save_preferences()
		_refresh()
	else:
		store.change("Set " + column.title, replacements)
	_message("Updated %d row(s). Review results, then Save All." % paths.size())
	return true


func _changed_state(path: String, state: Dictionary, column: Dictionary, value: Variant) -> Dictionary:
	if column.kind == "item":
		var item_path := str(value)
		if not item_path.is_empty() and (item_path not in catalog.items or int(store.states[item_path].slot) != int(column.slot)):
			return {"error": "Choose a compatible item resource path for " + column.title + "."}
		return {"state": store.equipment_state(state, column.slot, item_path)}
	if column.kind == "attack":
		if value not in previews.get(path, {}).get("abilities", []):
			return {"error": "Preview attack must be a damaging ability in this enemy's loadout."}
		return {"state": state}
	var result := state.duplicate(true)
	result[column.key] = value
	return {"state": result}


func paste_text(text: String) -> bool:
	if grid.active_path.is_empty() or grid.rows.is_empty():
		_message("Select the first destination cell before pasting.", true)
		return false
	var lines := text.replace("\r\n", "\n").replace("\r", "\n").trim_suffix("\n").split("\n")
	var start_row := grid.row_index_for(grid.active_path)
	var start_column := grid.column_index_for(grid.active_key)
	var replacements := {}
	var width := -1
	var attack_updates := {}
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
			var parsed := Columns.parse(column, values[index])
			if parsed.has("error"):
				_message(parsed.error + " Nothing changed.", true)
				return false
			var result := _changed_state(path, state, column, parsed.value)
			if result.has("error"):
				_message(result.error + " Nothing changed.", true)
				return false
			state = result.state
			if column.kind == "attack":
				attack_updates[path] = parsed.value
		replacements[path] = state
	store.change("Paste balance cells", replacements)
	attacks.merge(attack_updates, true)
	_save_preferences()
	_refresh()
	_message("Pasted %d × %d cells. Undo restores the entire edit." % [lines.size(), width])
	return true


func _rebuild_details() -> void:
	_clear(details)
	var path: String = grid.active_path
	if path.is_empty() or not store.states.has(path):
		_detail_text("Select an enemy or item to inspect its loadout and calculations.")
		return
	_detail_text(_label(path) + "  •  " + path, 17)
	var state: Dictionary = store.states[path]
	if state.has("combat_rating"):
		_detail_text("Template defaults only. Scene overrides remain in the Inspector.")
		var preview: Dictionary = previews.get(path, {})
		_detail_text(str(preview.get("explanation", "")))
		_detail_text("Potential total assumes all hits resolve; it is not guaranteed damage to one target.")
		if not str(preview.get("passives", "")).is_empty():
			_detail_text("Passives (conditional effects excluded from baseline): " + str(preview.passives))
		var equipment_descriptions: Array[String] = []
		for item_path in state.starting_equipment:
			if str(item_path).is_empty():
				continue
			var item := (store.draft(item_path) if store.states.has(item_path) else load(item_path)) as ItemDefinition
			var parts: Array[String] = ["%s: weapon %d, armor %d" % [_label(item_path), item.weapon_damage, item.armor]]
			for modifier in item.modifiers:
				if modifier != null:
					parts.append("%s %s %s" % [UnitStat.get_display_name(modifier.stat), ["flat", "add %", "multiply %"][modifier.operation], str(modifier.value * (1 if modifier.operation == 0 else 100))])
			equipment_descriptions.append(" · ".join(parts))
		_detail_text("Equipment: " + ("; ".join(equipment_descriptions) if not equipment_descriptions.is_empty() else "None"))
		var ai := HBoxContainer.new()
		details.add_child(ai)
		_button(ai, "AI: " + _label(state.ai_profile), func(): _pick("AI profile", catalog.profiles, func(value): store.set_field(path, "ai_profile", value)))
		_loadout(path, "abilities", "Abilities", catalog.abilities)
		_loadout(path, "passive_abilities", "Passives", catalog.passives)
	else:
		var affected: Array[String] = []
		for enemy in catalog.enemies:
			if path in store.states[enemy].starting_equipment:
				affected.append(_label(enemy))
		_detail_text("Shared item · Affects: " + (", ".join(affected) if not affected.is_empty() else "No enemy templates") + ". Other game resources may also use this item.")
		var bar := HBoxContainer.new()
		details.add_child(bar)
		_button(bar, "Weapon status: " + _label(state.status_effect), func(): _pick("Weapon status", catalog.statuses, func(value): store.set_field(path, "status_effect", value)))
		_button(bar, "Add modifier", func():
			var modifiers: Array = store.states[path].modifiers.duplicate(true)
			modifiers.append({"stat": 1, "operation": 0, "value": 0.0})
			store.set_field(path, "modifiers", modifiers)
		)
		for index in range(state.modifiers.size()):
			_modifier_row(path, index, state.modifiers[index])


func _loadout(path: String, field: String, title: String, candidates: Array) -> void:
	var header := HBoxContainer.new()
	details.add_child(header)
	var label := Label.new()
	label.text = title
	header.add_child(label)
	_button(header, "Add…", func(): _pick("Add " + title, candidates, func(value):
		var entries: Array = store.states[path][field].duplicate()
		entries.append(value)
		store.set_field(path, field, entries)
	, false))
	var entries: Array = store.states[path][field]
	for index in range(entries.size()):
		var bar := HBoxContainer.new()
		details.add_child(bar)
		var entry_path: String = entries[index]
		var entry := Label.new()
		entry.text = "%d. %s" % [index + 1, _label(entry_path)]
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(entry)
		_button(bar, "Inspect", func():
			if Engine.is_editor_hint() and not entry_path.is_empty():
				EditorInterface.edit_resource(load(entry_path))
		)
		var up := _button(bar, "↑", func(): _move_entry(path, field, index, -1))
		up.disabled = index == 0
		var down := _button(bar, "↓", func(): _move_entry(path, field, index, 1))
		down.disabled = index == entries.size() - 1
		_button(bar, "Remove", func():
			var updated: Array = store.states[path][field].duplicate()
			updated.remove_at(index)
			store.set_field(path, field, updated)
		)


func _move_entry(path: String, field: String, index: int, offset: int) -> void:
	var entries: Array = store.states[path][field].duplicate()
	var value: Variant = entries[index]
	entries.remove_at(index)
	entries.insert(index + offset, value)
	store.set_field(path, field, entries)


func _modifier_row(path: String, index: int, data: Variant) -> void:
	var bar := HFlowContainer.new()
	details.add_child(bar)
	if data == null:
		_button(bar, "Replace empty modifier", func(): _update_modifier(path, index, {"stat": 1, "operation": 0, "value": 0.0}))
	else:
		var stat := OptionButton.new()
		for id in UnitStat.Type.values():
			stat.add_item(UnitStat.get_display_name(id), id)
		stat.select(stat.get_item_index(data.stat))
		bar.add_child(stat)
		var operation := OptionButton.new()
		for text in ["Flat", "Add %", "Multiply %"]:
			operation.add_item(text)
		operation.select(data.operation)
		bar.add_child(operation)
		var value := LineEdit.new()
		value.custom_minimum_size.x = 120
		value.text = str(float(data.value) * (1.0 if data.operation == 0 else 100.0))
		value.tooltip_text = "Percent operations use 25 for 25%. Flat uses stat points."
		bar.add_child(value)
		_button(bar, "Apply modifier", func():
			if not value.text.is_valid_float() or not is_finite(value.text.to_float()):
				_message("Modifier needs a finite number.", true)
				return
			_update_modifier(path, index, {"stat": stat.get_selected_id(), "operation": operation.selected, "value": value.text.to_float() / (1.0 if operation.selected == 0 else 100.0)})
		)
	_button(bar, "Remove", func():
		var modifiers: Array = store.states[path].modifiers.duplicate(true)
		modifiers.remove_at(index)
		store.set_field(path, "modifiers", modifiers)
	)


func _update_modifier(path: String, index: int, value: Dictionary) -> void:
	var modifiers: Array = store.states[path].modifiers.duplicate(true)
	modifiers[index] = value
	store.set_field(path, "modifiers", modifiers)


func save_changes(overwrite: Array[String] = []) -> Dictionary:
	var result := store.save_all(overwrite)
	var messages: Array[String] = ["Saved %d resource(s)." % result.saved.size()]
	if not result.failed.is_empty():
		messages.append("Save failed: " + "; ".join(result.failed))
	if not result.conflicts.is_empty():
		messages.append("External changes detected. Conflicting drafts remain unsaved.")
		var dialog := ConfirmationDialog.new()
		dialog.title = "Resources changed outside Unit Balance"
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
	dialog.dialog_text = "Discard all unsaved Unit Balance edits and reload the resources? This clears table undo history."
	dialog.ok_button_text = "Revert All"
	add_child(dialog)
	dialog.confirmed.connect(func(): store.reload_paths(store.dirty_paths()))
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free()
	)
	dialog.popup_centered(Vector2i(530, 150))


func _pick(title: String, paths: Array, callback: Callable, allow_empty := true) -> void:
	var options: Array = []
	if allow_empty:
		options.append({"label": "None", "value": ""})
	for path in paths:
		options.append({"label": _label(path) + "  ·  " + str(path), "value": path})
	_choice_dialog(title, options, callback)


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
				var index := list.add_item(option.label)
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


func _save_preferences() -> void:
	if not persist_preferences:
		return
	ColumnVisibility.write_preferences(preferences, column_visibility)
	preferences.set_value("table", "attacks", attacks)
	preferences.set_value("table", "sort_key", sort_key)
	preferences.set_value("table", "sort_ascending", sort_ascending)
	DirAccess.make_dir_recursive_absolute(preferences_path.get_base_dir())
	preferences.save(preferences_path)


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
