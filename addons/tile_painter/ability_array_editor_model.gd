@tool
class_name AbilityArrayEditorModel
extends RefCounted


static func copy_abilities(value: Variant) -> Array[AbilityDefinition]:
	var result: Array[AbilityDefinition] = []
	if not value is Array:
		return result
	for entry in value:
		result.append(entry as AbilityDefinition)
	return result


static func replace_entry(
	value: Variant,
	index: int,
	ability: AbilityDefinition
) -> Array[AbilityDefinition]:
	var result := copy_abilities(value)
	if index >= 0 and index < result.size():
		result[index] = ability
	return result


static func append_empty(value: Variant) -> Array[AbilityDefinition]:
	var result := copy_abilities(value)
	result.append(null)
	return result


static func remove_entry(value: Variant, index: int) -> Array[AbilityDefinition]:
	var result := copy_abilities(value)
	if index >= 0 and index < result.size():
		result.remove_at(index)
	return result


static func move_entry(
	value: Variant,
	index: int,
	direction: int
) -> Array[AbilityDefinition]:
	var result := copy_abilities(value)
	var destination := index + direction
	if index < 0 or index >= result.size() or destination < 0 or destination >= result.size():
		return result
	var ability := result[index]
	result.remove_at(index)
	result.insert(destination, ability)
	return result
