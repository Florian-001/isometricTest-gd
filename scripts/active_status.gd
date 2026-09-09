class_name ActiveStatus
extends RefCounted

var definition: StatusEffectDefinition
var source: Object
var source_unit: TacticalCharacter
var remaining_turns: int
var stack_count: int = 1
var processed_this_turn: bool = false


func _init(
	status_definition: StatusEffectDefinition,
	status_source: Object = null,
	status_source_unit: TacticalCharacter = null
) -> void:
	definition = status_definition
	source = status_source
	source_unit = status_source_unit
	if source_unit == null and source is TacticalCharacter:
		source_unit = source as TacticalCharacter
	remaining_turns = status_definition.duration_turns if status_definition != null else 0
