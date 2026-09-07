@tool
extends EditorInspectorPlugin

const ItemModifierEditorProperty = preload("res://addons/tile_painter/item_modifier_editor_property.gd")

var _undo_redo: EditorUndoRedoManager


func setup(undo_redo: EditorUndoRedoManager) -> void:
	_undo_redo = undo_redo


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
		or name != "modifiers"
		or type != TYPE_ARRAY
		or not hint_string.contains("StatModifierDefinition")
	):
		return false
	var editor_property := ItemModifierEditorProperty.new()
	editor_property.setup(_undo_redo)
	add_property_editor(name, editor_property)
	return true
