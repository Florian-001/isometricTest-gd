@tool
class_name ItemModifierEditorModel
extends RefCounted

const PERCENT_DISPLAY_SCALE := 100.0


static func copy_modifiers(value: Variant) -> Array[StatModifierDefinition]:
	var result: Array[StatModifierDefinition] = []
	if not value is Array:
		return result
	for entry in value:
		result.append(entry as StatModifierDefinition)
	return result


static func append_default(value: Variant) -> Array[StatModifierDefinition]:
	var result := copy_modifiers(value)
	result.append(StatModifierDefinition.new())
	return result


static func replace_null(value: Variant, index: int) -> Array[StatModifierDefinition]:
	var result := copy_modifiers(value)
	if index >= 0 and index < result.size() and result[index] == null:
		result[index] = StatModifierDefinition.new()
	return result


static func remove_entry(value: Variant, index: int) -> Array[StatModifierDefinition]:
	var result := copy_modifiers(value)
	if index >= 0 and index < result.size():
		result.remove_at(index)
	return result


static func is_percentage(operation: StatModifierDefinition.Operation) -> bool:
	return operation in [
		StatModifierDefinition.Operation.PERCENT_ADD,
		StatModifierDefinition.Operation.PERCENT_MULTIPLY,
	]


static func to_display_value(
	stored_value: float,
	operation: StatModifierDefinition.Operation
) -> float:
	return stored_value * PERCENT_DISPLAY_SCALE if is_percentage(operation) else stored_value


static func to_stored_value(
	display_value: float,
	operation: StatModifierDefinition.Operation
) -> float:
	return display_value / PERCENT_DISPLAY_SCALE if is_percentage(operation) else display_value


static func get_operation_label(operation: StatModifierDefinition.Operation) -> String:
	match operation:
		StatModifierDefinition.Operation.PERCENT_ADD:
			return "Add %"
		StatModifierDefinition.Operation.PERCENT_MULTIPLY:
			return "Multiply %"
		_:
			return "Flat"
