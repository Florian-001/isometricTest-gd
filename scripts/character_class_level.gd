@tool
class_name CharacterClassLevel
extends Resource

@export var character_class: CharacterClassDefinition
@export_range(1, 99, 1, "or_greater") var level: int = 1


static func create(definition: CharacterClassDefinition, invested_level: int = 1) -> CharacterClassLevel:
	var entry := CharacterClassLevel.new()
	entry.character_class = definition
	entry.level = invested_level
	return entry
