@tool
class_name ClassAbilityUnlock
extends Resource

@export var ability: AbilityDefinition
@export_range(1, 99, 1, "or_greater") var required_level: int = 1
