@tool
extends EditorProperty

const ModifierModel = preload("res://addons/tile_painter/item_modifier_editor_model.gd")

var _content: VBoxContainer
var _undo_redo: EditorUndoRedoManager


func _init() -> void:
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_content)
	set_bottom_editor(_content)


func setup(undo_redo: EditorUndoRedoManager) -> void:
	_undo_redo = undo_redo
	_rebuild()


func _update_property() -> void:
	_rebuild()


func _rebuild() -> void:
	if _content == null:
		return
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

	var modifiers := _get_current_modifiers()
	if modifiers.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No stat modifiers"
		empty_label.add_theme_color_override("font_color", Color(0.58, 0.66, 0.74))
		_content.add_child(empty_label)
	else:
		_content.add_child(_make_header())
	for index in range(modifiers.size()):
		_content.add_child(_make_modifier_row(index, modifiers[index]))

	var add_button := Button.new()
	add_button.text = "Add Modifier"
	add_button.tooltip_text = "Add a Strength, Flat, 0 modifier"
	add_button.pressed.connect(_on_add_pressed)
	_content.add_child(add_button)


func _make_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	header.add_child(_make_header_label("Stat", 116.0))
	header.add_child(_make_header_label("Operation", 118.0))
	var value_label := _make_header_label("Value", 96.0)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(value_label)
	var remove_spacer := Control.new()
	remove_spacer.custom_minimum_size.x = 28.0
	header.add_child(remove_spacer)
	return header


func _make_header_label(text: String, minimum_width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = minimum_width
	label.add_theme_color_override("font_color", Color(0.66, 0.74, 0.82))
	label.add_theme_font_size_override("font_size", 12)
	return label


func _make_modifier_row(index: int, modifier: StatModifierDefinition) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	if modifier == null:
		var missing_label := Label.new()
		missing_label.text = "Missing modifier"
		missing_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		missing_label.add_theme_color_override("font_color", Color(0.9, 0.55, 0.35))
		row.add_child(missing_label)
		var create_button := Button.new()
		create_button.text = "Create"
		create_button.tooltip_text = "Replace this null entry with a default modifier"
		create_button.pressed.connect(_on_create_pressed.bind(index))
		row.add_child(create_button)
		row.add_child(_make_remove_button(index))
		return row

	var stat_picker := OptionButton.new()
	stat_picker.custom_minimum_size.x = 116.0
	for stat_value in UnitStat.Type.values():
		stat_picker.add_item(UnitStat.get_display_name(stat_value as UnitStat.Type), stat_value)
	stat_picker.select(_find_item_by_id(stat_picker, int(modifier.stat)))
	stat_picker.tooltip_text = "Stat modified by this item"
	stat_picker.item_selected.connect(_on_stat_selected.bind(index, stat_picker))
	row.add_child(stat_picker)

	var operation_picker := OptionButton.new()
	operation_picker.custom_minimum_size.x = 118.0
	for operation_value in StatModifierDefinition.Operation.values():
		operation_picker.add_item(
			ModifierModel.get_operation_label(operation_value as StatModifierDefinition.Operation),
			operation_value
		)
	operation_picker.select(_find_item_by_id(operation_picker, int(modifier.operation)))
	operation_picker.tooltip_text = "How this value combines with the base stat"
	operation_picker.item_selected.connect(
		_on_operation_selected.bind(index, operation_picker)
	)
	row.add_child(operation_picker)

	var value_editor := SpinBox.new()
	value_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_editor.custom_minimum_size.x = 96.0
	value_editor.allow_greater = true
	value_editor.allow_lesser = true
	if ModifierModel.is_percentage(modifier.operation):
		value_editor.min_value = -1000000.0
		value_editor.max_value = 1000000.0
		value_editor.step = 1.0
		value_editor.suffix = "%"
		value_editor.tooltip_text = "Displayed as a percentage; 25% is stored as 0.25"
	else:
		value_editor.min_value = -10000.0
		value_editor.max_value = 10000.0
		value_editor.step = 0.05
		value_editor.tooltip_text = "Flat stat points"
	value_editor.value = ModifierModel.to_display_value(modifier.value, modifier.operation)
	value_editor.value_changed.connect(
		_on_value_changed.bind(index, modifier.operation)
	)
	row.add_child(value_editor)
	row.add_child(_make_remove_button(index))
	return row


func _make_remove_button(index: int) -> Button:
	var remove_button := Button.new()
	remove_button.text = "×"
	remove_button.custom_minimum_size.x = 28.0
	remove_button.tooltip_text = "Remove this modifier"
	remove_button.pressed.connect(_on_remove_pressed.bind(index))
	return remove_button


func _get_current_modifiers() -> Array[StatModifierDefinition]:
	if get_edited_object() == null or get_edited_property().is_empty():
		return []
	return ModifierModel.copy_modifiers(get_edited_object().get(get_edited_property()))


func _get_modifier(index: int) -> StatModifierDefinition:
	var modifiers := _get_current_modifiers()
	if index < 0 or index >= modifiers.size():
		return null
	return modifiers[index]


func _find_item_by_id(picker: OptionButton, id: int) -> int:
	for item_index in range(picker.item_count):
		if picker.get_item_id(item_index) == id:
			return item_index
	return 0


func _on_stat_selected(
	selected_index: int,
	modifier_index: int,
	picker: OptionButton
) -> void:
	_set_modifier_property(
		modifier_index,
		&"stat",
		picker.get_item_id(selected_index),
		"Change Item Modifier Stat"
	)


func _on_operation_selected(
	selected_index: int,
	modifier_index: int,
	picker: OptionButton
) -> void:
	_set_modifier_property(
		modifier_index,
		&"operation",
		picker.get_item_id(selected_index),
		"Change Item Modifier Operation"
	)
	call_deferred("_rebuild")


func _on_value_changed(
	display_value: float,
	modifier_index: int,
	operation: StatModifierDefinition.Operation
) -> void:
	_set_modifier_property(
		modifier_index,
		&"value",
		ModifierModel.to_stored_value(display_value, operation),
		"Change Item Modifier Value"
	)


func _set_modifier_property(
	modifier_index: int,
	property_name: StringName,
	value: Variant,
	action_name: String
) -> void:
	var modifier := _get_modifier(modifier_index)
	if modifier == null:
		return
	var previous_value: Variant = modifier.get(property_name)
	if previous_value == value:
		return
	var item := get_edited_object() as ItemDefinition
	if _undo_redo == null:
		modifier.set(property_name, value)
		modifier.emit_changed()
		if item != null:
			item.emit_changed()
		return
	_undo_redo.create_action(action_name)
	_undo_redo.add_do_property(modifier, property_name, value)
	_undo_redo.add_undo_property(modifier, property_name, previous_value)
	_undo_redo.add_do_method(modifier, "emit_changed")
	_undo_redo.add_undo_method(modifier, "emit_changed")
	if item != null:
		_undo_redo.add_do_method(item, "emit_changed")
		_undo_redo.add_undo_method(item, "emit_changed")
	_undo_redo.commit_action()


func _on_add_pressed() -> void:
	_commit(ModifierModel.append_default(_get_current_modifiers()))


func _on_create_pressed(index: int) -> void:
	_commit(ModifierModel.replace_null(_get_current_modifiers(), index))


func _on_remove_pressed(index: int) -> void:
	_commit(ModifierModel.remove_entry(_get_current_modifiers(), index))


func _commit(modifiers: Array[StatModifierDefinition]) -> void:
	emit_changed(get_edited_property(), modifiers)
	call_deferred("_update_property")
