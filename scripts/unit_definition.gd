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

@export_category("Friendly Class")
## Friendlies start at level one in this class unless their scene overrides the allocation.
@export var starting_class: CharacterClassDefinition

@export_category("Stats")
@export_range(0.0, 100.0, 0.5) var movement_range: float = 6.0
@export_range(1, 999, 1, "or_greater") var strength: int = 10
@export_range(1, 999, 1, "or_greater") var dexterity: int = 10
@export_range(1, 999, 1, "or_greater") var intelligence: int = 10
@export_range(1, 999, 1, "or_greater") var constitution: int = 25:
	set(value):
		constitution = maxi(1, value)
		if Engine.is_editor_hint():
			notify_property_list_changed()
@export_custom(
	PROPERTY_HINT_NONE,
	"",
	PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
) var max_health: int:
	get:
		return calculate_max_health(float(constitution))
@export_range(1, 999, 1, "or_greater") var speed: int = 10

@export_category("Starting Equipment")
## At most one item per slot. Duplicate slots use the last item in this list.
@export var starting_equipment: Array[ItemDefinition] = []

@export_category("Presentation")
@export var body_color: Color = Color("3c8cff")
@export var health_bar_color: Color = Color("42e66b")

@export_category("Passive Abilities")
## Always available, independently of active abilities and classes.
@export var passive_abilities: Array[PassiveAbilityDefinition] = []:
	set(value):
		passive_abilities = value.duplicate()
		emit_changed()

@export_category("Ability Loadout")
## Enemy loadout. Friendly characters resolve their abilities from class levels instead.
@export var abilities: Array[AbilityDefinition] = []


## Shared by the definition Inspector and runtime health, including stat modifiers.
func calculate_max_health(effective_constitution: float) -> int:
	return UnitStat.get_scaling_rules().calculate_max_health(effective_constitution)


func _validate_property(property: Dictionary) -> void:
	if (property.name == "starting_class" and faction != Faction.FRIENDLY) or (property.name == "abilities" and faction == Faction.FRIENDLY):
		property.usage = property.usage & ~PROPERTY_USAGE_EDITOR
