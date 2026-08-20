@tool
extends EditorInspectorPlugin

const AbilityArrayEditorProperty = preload("res://addons/tile_painter/ability_array_editor_property.gd")

var _filesystem: EditorFileSystem


func setup(filesystem: EditorFileSystem) -> void:
	_filesystem = filesystem


func _can_handle(object: Object) -> bool:
	return object is ItemDefinition


func _parse_property(
	object: Object,
	type: Variant.Type,
	name: String,
	_hint_type: PropertyHint,
	hint_string: String,
	_usage_flags: int,
	_wide: bool
) -> bool:
	if (
		not object is ItemDefinition
		or name != "granted_abilities"
		or type != TYPE_ARRAY
		or not hint_string.contains("AbilityDefinition")
	):
		return false
	var editor_property := AbilityArrayEditorProperty.new()
	editor_property.setup(_filesystem)
	add_property_editor(name, editor_property)
	return true
