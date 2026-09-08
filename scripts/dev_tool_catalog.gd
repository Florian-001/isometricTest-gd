@tool
class_name DevToolCatalog
extends Resource

@export_category("Unit Palette")
@export var unit_scenes: Array[PackedScene] = []

@export_category("Friendly Class Catalog")
@export var character_classes: Array[CharacterClassDefinition] = []

@export_category("Passive Catalog")
@export var passive_abilities: Array[PassiveAbilityDefinition] = []
@export_tool_button("Validate Passive Catalog") var validate_passives_button: Callable = _validate_passives

@export_category("Ability Catalog")
@export var abilities: Array[AbilityDefinition] = []

@export_category("Item Catalog")
@export var items: Array[ItemDefinition] = []

@export_category("Wall Catalog")
@export var wall_styles: Array[WallDefinition] = []


func _validate_passives() -> void:
	var errors := PassiveLoadout.validate(passive_abilities)
	if errors.is_empty():
		print("Passive catalog is valid.")
	for error in errors:
		push_warning(error)
