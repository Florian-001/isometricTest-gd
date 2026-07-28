@tool
extends EditorProperty

const ItemCatalog = preload("res://addons/tile_painter/item_definition_catalog.gd")
const ItemArrayModel = preload("res://addons/tile_painter/item_array_editor_model.gd")

var _content: VBoxContainer
var _filesystem: EditorFileSystem
var _catalog_items: Array[ItemDefinition] = []


func _init() -> void:
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_content)
	set_bottom_editor(_content)


func setup(filesystem: EditorFileSystem) -> void:
	_filesystem = filesystem
	if (
		_filesystem != null
		and not _filesystem.filesystem_changed.is_connected(_on_filesystem_changed)
	):
		_filesystem.filesystem_changed.connect(_on_filesystem_changed)
	_rebuild()


func _update_property() -> void:
	_rebuild()


func _rebuild() -> void:
	if _content == null:
		return
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_catalog_items = ItemCatalog.get_items()
	var current_items := _get_current_items()
	if current_items.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No items configured"
		empty_label.add_theme_color_override("font_color", Color(0.58, 0.66, 0.74))
		_content.add_child(empty_label)
	for index in range(current_items.size()):
		_content.add_child(_make_item_row(index, current_items[index], current_items.size()))
	var add_button := Button.new()
	add_button.text = "Add Item"
	add_button.tooltip_text = "Add another item entry. Repeating an item creates another logical copy."
	add_button.pressed.connect(_on_add_pressed)
	_content.add_child(add_button)


func _make_item_row(index: int, current: ItemDefinition, item_count: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.custom_minimum_size.x = 190.0
	var options: Array = [null]
	picker.add_item("None")
	picker.set_item_tooltip(0, ItemCatalog.get_tooltip(null))
	var labels := ItemCatalog.get_labels(_catalog_items)
	for catalog_index in range(_catalog_items.size()):
		var item := _catalog_items[catalog_index]
		options.append(item)
		picker.add_item(labels[catalog_index])
		picker.set_item_tooltip(picker.item_count - 1, ItemCatalog.get_tooltip(item))
	var selected_index := _find_option(current, options)
	if current != null and selected_index < 0:
		options.append(current)
		picker.add_item(ItemCatalog.get_external_label(current))
		picker.set_item_tooltip(picker.item_count - 1, ItemCatalog.get_tooltip(current))
		selected_index = options.size() - 1
	picker.select(maxi(0, selected_index))
	picker.item_selected.connect(_on_item_selected.bind(index, options))
	row.add_child(picker)

	var edit_button := Button.new()
	edit_button.text = "Edit"
	edit_button.disabled = current == null
	edit_button.tooltip_text = "Open this item in the Inspector"
	if current != null:
		edit_button.pressed.connect(_on_edit_pressed.bind(current))
	row.add_child(edit_button)

	var up_button := Button.new()
	up_button.text = "↑"
	up_button.disabled = index == 0
	up_button.tooltip_text = "Move this entry up"
	up_button.pressed.connect(_on_move_pressed.bind(index, -1))
	row.add_child(up_button)

	var down_button := Button.new()
	down_button.text = "↓"
	down_button.disabled = index >= item_count - 1
	down_button.tooltip_text = "Move this entry down"
	down_button.pressed.connect(_on_move_pressed.bind(index, 1))
	row.add_child(down_button)

	var remove_button := Button.new()
	remove_button.text = "Remove"
	remove_button.tooltip_text = "Remove this item entry"
	remove_button.pressed.connect(_on_remove_pressed.bind(index))
	row.add_child(remove_button)
	return row


func _get_current_items() -> Array[ItemDefinition]:
	if get_edited_object() == null or get_edited_property().is_empty():
		return []
	return ItemArrayModel.copy_items(get_edited_object().get(get_edited_property()))


func _find_option(item: ItemDefinition, options: Array) -> int:
	if item == null:
		return 0
	for index in range(1, options.size()):
		var candidate := options[index] as ItemDefinition
		if candidate == item:
			return index
		if (
			candidate != null
			and not candidate.resource_path.is_empty()
			and candidate.resource_path == item.resource_path
		):
			return index
	return -1


func _on_item_selected(selected_index: int, entry_index: int, options: Array) -> void:
	if selected_index < 0 or selected_index >= options.size():
		return
	_commit(ItemArrayModel.replace_entry(
		_get_current_items(),
		entry_index,
		options[selected_index] as ItemDefinition
	))


func _on_edit_pressed(item: ItemDefinition) -> void:
	if item != null:
		EditorInterface.edit_resource(item)


func _on_move_pressed(index: int, direction: int) -> void:
	_commit(ItemArrayModel.move_entry(_get_current_items(), index, direction))


func _on_remove_pressed(index: int) -> void:
	_commit(ItemArrayModel.remove_entry(_get_current_items(), index))


func _on_add_pressed() -> void:
	_commit(ItemArrayModel.append_empty(_get_current_items()))


func _commit(items: Array[ItemDefinition]) -> void:
	emit_changed(get_edited_property(), items)
	call_deferred("_update_property")


func _on_filesystem_changed() -> void:
	call_deferred("_rebuild")
