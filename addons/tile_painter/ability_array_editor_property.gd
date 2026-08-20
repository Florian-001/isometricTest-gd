@tool
extends EditorProperty

const AbilityCatalog = preload("res://addons/tile_painter/ability_definition_catalog.gd")
const AbilityArrayModel = preload("res://addons/tile_painter/ability_array_editor_model.gd")

var _content: VBoxContainer
var _filesystem: EditorFileSystem
var _catalog_abilities: Array[AbilityDefinition] = []


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
	_catalog_abilities = AbilityCatalog.get_abilities()
	var current_abilities := _get_current_abilities()
	if current_abilities.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No abilities granted"
		empty_label.add_theme_color_override("font_color", Color(0.58, 0.66, 0.74))
		_content.add_child(empty_label)
	for index in range(current_abilities.size()):
		_content.add_child(_make_ability_row(index, current_abilities[index], current_abilities.size()))
	var add_button := Button.new()
	add_button.text = "Add Ability"
	add_button.tooltip_text = "Add another ability granted while this item is equipped."
	add_button.pressed.connect(_on_add_pressed)
	_content.add_child(add_button)


func _make_ability_row(
	index: int,
	current: AbilityDefinition,
	ability_count: int
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.custom_minimum_size.x = 190.0
	var options: Array = [null]
	picker.add_item("None")
	picker.set_item_tooltip(0, AbilityCatalog.get_tooltip(null))
	var labels := AbilityCatalog.get_labels(_catalog_abilities)
	for catalog_index in range(_catalog_abilities.size()):
		var ability := _catalog_abilities[catalog_index]
		options.append(ability)
		picker.add_item(labels[catalog_index])
		picker.set_item_tooltip(picker.item_count - 1, AbilityCatalog.get_tooltip(ability))
	var selected_index := _find_option(current, options)
	if current != null and selected_index < 0:
		options.append(current)
		picker.add_item(AbilityCatalog.get_external_label(current))
		picker.set_item_tooltip(picker.item_count - 1, AbilityCatalog.get_tooltip(current))
		selected_index = options.size() - 1
	picker.select(maxi(0, selected_index))
	picker.item_selected.connect(_on_ability_selected.bind(index, options))
	row.add_child(picker)

	var edit_button := Button.new()
	edit_button.text = "Edit"
	edit_button.disabled = current == null
	edit_button.tooltip_text = "Open this ability in the Inspector"
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
	down_button.disabled = index >= ability_count - 1
	down_button.tooltip_text = "Move this entry down"
	down_button.pressed.connect(_on_move_pressed.bind(index, 1))
	row.add_child(down_button)

	var remove_button := Button.new()
	remove_button.text = "Remove"
	remove_button.tooltip_text = "Remove this granted ability"
	remove_button.pressed.connect(_on_remove_pressed.bind(index))
	row.add_child(remove_button)
	return row


func _get_current_abilities() -> Array[AbilityDefinition]:
	if get_edited_object() == null or get_edited_property().is_empty():
		return []
	return AbilityArrayModel.copy_abilities(get_edited_object().get(get_edited_property()))


func _find_option(ability: AbilityDefinition, options: Array) -> int:
	if ability == null:
		return 0
	for index in range(1, options.size()):
		var candidate := options[index] as AbilityDefinition
		if candidate == ability:
			return index
		if (
			candidate != null
			and not candidate.resource_path.is_empty()
			and candidate.resource_path == ability.resource_path
		):
			return index
	return -1


func _on_ability_selected(selected_index: int, entry_index: int, options: Array) -> void:
	if selected_index < 0 or selected_index >= options.size():
		return
	_commit(AbilityArrayModel.replace_entry(
		_get_current_abilities(),
		entry_index,
		options[selected_index] as AbilityDefinition
	))


func _on_edit_pressed(ability: AbilityDefinition) -> void:
	if ability != null:
		EditorInterface.edit_resource(ability)


func _on_move_pressed(index: int, direction: int) -> void:
	_commit(AbilityArrayModel.move_entry(_get_current_abilities(), index, direction))


func _on_remove_pressed(index: int) -> void:
	_commit(AbilityArrayModel.remove_entry(_get_current_abilities(), index))


func _on_add_pressed() -> void:
	_commit(AbilityArrayModel.append_empty(_get_current_abilities()))


func _commit(abilities: Array[AbilityDefinition]) -> void:
	emit_changed(get_edited_property(), abilities)
	call_deferred("_update_property")


func _on_filesystem_changed() -> void:
	call_deferred("_rebuild")
