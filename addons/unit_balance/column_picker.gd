@tool
extends AcceptDialog

const Visibility = preload("res://addons/unit_balance/column_visibility.gd")
signal columns_changed(keys: Array)

var table := "enemies"
var visible_keys: Array = []
var search := LineEdit.new()
var checkboxes: Dictionary = {}
var group_checks: Dictionary = {}
var group_boxes: Dictionary = {}
var count_label := Label.new()
var no_results := Label.new()


func setup(table_name: String, keys: Array) -> void:
	table = table_name
	visible_keys = Visibility.normalize(table, keys)
	title = "Columns · " + table.capitalize()
	ok_button_text = "Done"
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	add_child(content)
	search.placeholder_text = "Search columns (name, stat, equipment…)"
	search.name = "ColumnSearch"
	content.add_child(search)
	var actions := HFlowContainer.new()
	content.add_child(actions)
	for entry in [["Show all", "all"], ["Hide optional columns", "none"], ["Reset defaults", "defaults"]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(func(): apply_preset(entry[1]))
		actions.add_child(button)
	content.add_child(count_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360, 260)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	for column in Visibility.definitions(table):
		if not group_boxes.has(column.group):
			var box := VBoxContainer.new()
			list.add_child(box)
			group_boxes[column.group] = box
			var group := CheckBox.new()
			group.tooltip_text = "Show/hide this entire group, including columns hidden by the search."
			group.toggled.connect(func(pressed): toggle_group(column.group, pressed))
			box.add_child(group)
			group_checks[column.group] = group
		var check := CheckBox.new()
		check.text = "    " + column.title + (" (always visible)" if column.key == "display_name" else "")
		check.disabled = column.key == "display_name"
		check.tooltip_text = column.key.replace("_", " ").capitalize()
		check.toggled.connect(func(pressed): toggle_column(column.key, pressed))
		group_boxes[column.group].add_child(check)
		checkboxes[column.key] = check
	no_results.text = "No columns match your search."
	list.add_child(no_results)
	search.text_changed.connect(filter_columns)
	_sync_checks()


func toggle_column(key: String, shown: bool) -> void:
	var keys := visible_keys.duplicate()
	if shown and key not in keys:
		keys.append(key)
	elif not shown:
		keys.erase(key)
	_commit(keys)


func toggle_group(group: String, shown: bool) -> void:
	var keys := visible_keys.duplicate()
	for column in Visibility.definitions(table):
		if column.group != group:
			continue
		if shown and column.key not in keys:
			keys.append(column.key)
		elif not shown:
			keys.erase(column.key)
	_commit(keys)


func apply_preset(preset: String) -> void:
	match preset:
		"all": _commit(Visibility.definitions(table).map(func(column): return column.key))
		"none": _commit([])
		"defaults": _commit(Visibility.defaults(table))


func _commit(keys: Array) -> void:
	visible_keys = Visibility.normalize(table, keys)
	_sync_checks()
	columns_changed.emit(visible_keys.duplicate())


func _sync_checks() -> void:
	var definitions := Visibility.definitions(table)
	for column in definitions:
		checkboxes[column.key].set_pressed_no_signal(column.key in visible_keys)
	for group in group_checks:
		var members: Array = definitions.filter(func(column): return column.group == group)
		var shown := members.filter(func(column): return column.key in visible_keys).size()
		group_checks[group].text = "%s · %d/%d shown" % [group, shown, members.size()]
		group_checks[group].set_pressed_no_signal(shown == members.size())
		group_checks[group].disabled = members.all(func(column): return column.key == "display_name")
	count_label.text = "%d of %d columns shown. Changes apply immediately." % [visible_keys.size(), definitions.size()]
	filter_columns(search.text)


func filter_columns(query: String) -> void:
	var matches := {}
	var normalized := query.strip_edges().to_lower()
	for column in Visibility.definitions(table):
		var matches_query: bool = normalized.is_empty() or normalized in (column.title + " " + column.key + " " + column.group).to_lower()
		checkboxes[column.key].visible = matches_query
		matches[column.group] = matches.get(column.group, false) or matches_query
	for group in group_boxes:
		group_boxes[group].visible = matches.get(group, false)
	no_results.visible = not matches.values().has(true)
