@tool
extends EditorProperty

const StatusCatalog = preload("res://addons/tile_painter/status_effect_catalog.gd")

var _picker: OptionButton
var _statuses: Array = [null]
var _filesystem: EditorFileSystem


func _init() -> void:
	_picker = OptionButton.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.tooltip_text = "Status applied by this resource. Saved status resources are discovered automatically."
	_picker.item_selected.connect(_on_item_selected)
	add_child(_picker)
	_rebuild_options()


func setup(filesystem: EditorFileSystem) -> void:
	_filesystem = filesystem
	if (
		_filesystem != null
		and not _filesystem.filesystem_changed.is_connected(_on_filesystem_changed)
	):
		_filesystem.filesystem_changed.connect(_on_filesystem_changed)
	_rebuild_options()
	_update_property()


func _update_property() -> void:
	if _picker == null or get_edited_object() == null:
		return
	var current := get_edited_object().get(get_edited_property()) as StatusEffectDefinition
	var selected_index := _find_status(current)
	if current != null and selected_index < 0:
		_statuses.append(current)
		_picker.add_item("%s (external)" % current.display_name)
		_picker.set_item_tooltip(_picker.item_count - 1, current.resource_path)
		selected_index = _statuses.size() - 1
	_picker.select(maxi(0, selected_index))


func _rebuild_options() -> void:
	if _picker == null:
		return
	_picker.clear()
	_statuses = [null]
	_picker.add_item("None")
	_picker.set_item_tooltip(0, "This resource does not apply a direct status.")
	var discovered := StatusCatalog.get_statuses()
	var labels := StatusCatalog.get_labels(discovered)
	for index in range(discovered.size()):
		var status := discovered[index]
		_statuses.append(status)
		_picker.add_item(labels[index])
		_picker.set_item_tooltip(_picker.item_count - 1, status.resource_path)


func _find_status(status: StatusEffectDefinition) -> int:
	if status == null:
		return 0
	for index in range(1, _statuses.size()):
		var candidate := _statuses[index] as StatusEffectDefinition
		if candidate == status:
			return index
		if (
			candidate != null
			and not candidate.resource_path.is_empty()
			and candidate.resource_path == status.resource_path
		):
			return index
	return -1


func _on_item_selected(index: int) -> void:
	if index < 0 or index >= _statuses.size():
		return
	emit_changed(get_edited_property(), _statuses[index])


func _on_filesystem_changed() -> void:
	_rebuild_options()
	_update_property()
