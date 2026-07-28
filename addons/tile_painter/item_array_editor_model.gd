@tool
class_name ItemArrayEditorModel
extends RefCounted


static func copy_items(value: Variant) -> Array[ItemDefinition]:
	var result: Array[ItemDefinition] = []
	if not value is Array:
		return result
	for entry in value:
		result.append(entry as ItemDefinition)
	return result


static func replace_entry(
	value: Variant,
	index: int,
	item: ItemDefinition
) -> Array[ItemDefinition]:
	var result := copy_items(value)
	if index >= 0 and index < result.size():
		result[index] = item
	return result


static func append_empty(value: Variant) -> Array[ItemDefinition]:
	var result := copy_items(value)
	result.append(null)
	return result


static func remove_entry(value: Variant, index: int) -> Array[ItemDefinition]:
	var result := copy_items(value)
	if index >= 0 and index < result.size():
		result.remove_at(index)
	return result


static func move_entry(
	value: Variant,
	index: int,
	direction: int
) -> Array[ItemDefinition]:
	var result := copy_items(value)
	var destination := index + direction
	if index < 0 or index >= result.size() or destination < 0 or destination >= result.size():
		return result
	var item := result[index]
	result.remove_at(index)
	result.insert(destination, item)
	return result
