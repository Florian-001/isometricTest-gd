@tool
extends EditorInspectorPlugin

const ItemArrayEditorProperty = preload("res://addons/tile_painter/item_array_editor_property.gd")

var _filesystem: EditorFileSystem


func setup(filesystem: EditorFileSystem) -> void:
	_filesystem = filesystem


func _can_handle(object: Object) -> bool:
	return (
		object is CharacterDefinition
		or object is TacticalCharacter
		or object is GeneralInventory
	)


func _parse_property(
	object: Object,
	type: Variant.Type,
	name: String,
	_hint_type: PropertyHint,
	hint_string: String,
	_usage_flags: int,
	_wide: bool
) -> bool:
	if type != TYPE_ARRAY or not hint_string.contains("ItemDefinition"):
		return false
	var supported := (
		(object is CharacterDefinition and name == "starting_equipment")
		or (object is TacticalCharacter and name == "starting_equipment_overrides")
		or (object is GeneralInventory and name == "starting_items")
	)
	if not supported:
		return false
	var editor_property := ItemArrayEditorProperty.new()
	editor_property.setup(_filesystem)
	add_property_editor(name, editor_property)
	return true
