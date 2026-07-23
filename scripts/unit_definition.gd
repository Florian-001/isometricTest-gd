@tool
class_name CharacterDefinition
extends Resource

enum Faction {
	FRIENDLY,
	ENEMY,
}

@export_category("Identity")
@export var display_name: String = "Adventurer"
@export var faction: Faction = Faction.FRIENDLY
@export var portrait: Texture2D

@export_category("Stats")
@export_range(1, 999, 1) var max_health: int = 100
@export_range(0.0, 100.0, 0.5) var movement_range: float = 6.0
@export_range(1, 999, 1, "or_greater") var strength: int = 10
@export_range(1, 999, 1, "or_greater") var dexterity: int = 10
@export_range(1, 999, 1, "or_greater") var intelligence: int = 10
@export_range(1, 999, 1, "or_greater") var speed: int = 10

@export_category("Starting Equipment")
## At most one item per slot. Duplicate slots use the last item in this list.
@export var starting_equipment: Array[ItemDefinition] = []

@export_category("Presentation")
@export var body_color: Color = Color("3c8cff")
@export var health_bar_color: Color = Color("42e66b")

@export_category("Ability Loadout")
## Resize this list in the Inspector, then choose New AbilityDefinition or load an existing .tres ability.
## Expand each ability to edit its targeting, shape, presentation, and effects inline.
@export var abilities: Array[AbilityDefinition] = []
