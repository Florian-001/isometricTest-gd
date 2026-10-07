@tool
class_name CharacterClassDefinition
extends Resource

@export var class_id: StringName
@export var display_name: String = "New Class"
## Entries are resolved in ascending required level; ties retain their authored order.
@export var ability_unlocks: Array[ClassAbilityUnlock] = []
@export_tool_button("Validate Class") var validate_button: Callable = _print_validation

@export_category("Default Stats")
## Base Strength before equipment and statuses. -1 inherits the character template.
@export_range(-1, 999, 1, "or_greater") var default_strength: int = -1:
	set(value):
		default_strength = maxi(-1, value)
		emit_changed()
## Base Dexterity before equipment and statuses. -1 inherits the character template.
@export_range(-1, 999, 1, "or_greater") var default_dexterity: int = -1:
	set(value):
		default_dexterity = maxi(-1, value)
		emit_changed()
## Base Intelligence before equipment and statuses. -1 inherits the character template.
@export_range(-1, 999, 1, "or_greater") var default_intelligence: int = -1:
	set(value):
		default_intelligence = maxi(-1, value)
		emit_changed()
## Base Constitution; HP uses the shared scaling rules. -1 inherits the character template.
@export_range(-1, 999, 1, "or_greater") var default_constitution: int = -1:
	set(value):
		default_constitution = maxi(-1, value)
		emit_changed()
## Base Speed; initiative and movement use the shared scaling rules. -1 inherits the character template.
@export_range(-1, 999, 1, "or_greater") var default_speed: int = -1:
	set(value):
		default_speed = maxi(-1, value)
		emit_changed()
## Base movement BEFORE Speed adjustment, equipment, and statuses. -1 inherits the character template.
@export_range(-1.0, 100.0, 0.5, "or_greater") var default_movement_range: float = -1.0:
	set(value):
		default_movement_range = maxf(-1.0, value)
		emit_changed()

@export_category("Auto Battle")
## Optional priorities for friendly Auto Battle. The first allocated class with a profile wins.
## A unit's Tactical AI override takes priority; an empty field allows later classes or General AI.
@export var ai_profile: EnemyAIProfile


## -1 means this stat is not authored on the class and should use the character template.
func get_default_stat(stat: UnitStat.Type) -> float:
	match stat:
		UnitStat.Type.STRENGTH:
			return float(default_strength)
		UnitStat.Type.DEXTERITY:
			return float(default_dexterity)
		UnitStat.Type.INTELLIGENCE:
			return float(default_intelligence)
		UnitStat.Type.CONSTITUTION:
			return float(default_constitution)
		UnitStat.Type.SPEED:
			return float(default_speed)
		UnitStat.Type.MOVEMENT_RANGE:
			return default_movement_range
	return -1.0


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
