@tool
class_name DevToolCatalog
extends Resource

@export_category("Unit Palette")
@export var unit_scenes: Array[PackedScene] = []

@export_category("Friendly Class Catalog")
@export var character_classes: Array[CharacterClassDefinition] = []

@export_category("Ability Catalog")
@export var abilities: Array[AbilityDefinition] = []

@export_category("Item Catalog")
@export var items: Array[ItemDefinition] = []

@export_category("Wall Catalog")
@export var wall_styles: Array[WallDefinition] = []
