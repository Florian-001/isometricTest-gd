class_name ActiveStatus
extends RefCounted

var definition: StatusEffectDefinition
var source: TacticalCharacter
var remaining_turns: int


func _init(
	status_definition: StatusEffectDefinition,
	status_source: TacticalCharacter = null
) -> void:
	definition = status_definition
	source = status_source
	remaining_turns = status_definition.duration_turns if status_definition != null else 0
