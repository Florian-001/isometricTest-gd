@tool
extends EditorInspectorPlugin

const TileStatusEditorProperty = preload("res://addons/tile_painter/tile_status_editor_property.gd")

var _filesystem: EditorFileSystem


func setup(filesystem: EditorFileSystem) -> void:
	_filesystem = filesystem


func _can_handle(object: Object) -> bool:
	return object is TileDefinition or object is AbilityDefinition or object is ItemDefinition


func _parse_property(
	_object: Object,
	_type: Variant.Type,
	name: String,
	_hint_type: PropertyHint,
	_hint_string: String,
	_usage_flags: int,
	_wide: bool
) -> bool:
	if name != "status_effect":
		return false
	var editor_property := TileStatusEditorProperty.new()
	editor_property.setup(_filesystem)
	add_property_editor(name, editor_property)
	return true
