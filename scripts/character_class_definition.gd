@tool
class_name CharacterClassDefinition
extends Resource

@export var class_id: StringName
@export var display_name: String = "New Class"
## Entries are resolved in ascending required level; ties retain their authored order.
@export var ability_unlocks: Array[ClassAbilityUnlock] = []
@export_tool_button("Validate Class") var validate_button: Callable = _print_validation


func get_sorted_unlocks() -> Array[ClassAbilityUnlock]:
	var result: Array[ClassAbilityUnlock] = []
	for entry in ability_unlocks:
		if entry == null:
			continue
		var index := 0
		while index < result.size() and result[index].required_level <= entry.required_level:
			index += 1
		result.insert(index, entry)
	return result


func validate() -> Array[String]:
	var errors: Array[String] = []
	if String(class_id).strip_edges().is_empty() or display_name.strip_edges().is_empty():
		errors.append("Class needs a unique ID and display name.")
	for entry in ability_unlocks:
		if entry == null or entry.ability == null or entry.required_level < 1:
			errors.append("%s: every unlock needs an ability and a positive level." % display_name)
	return errors


func _print_validation() -> void:
	var errors := validate()
	for message in errors:
		push_error(message)
	print("%s: %d class error(s)." % [display_name, errors.size()])
