@tool
class_name TileTriggeredEffectDefinition
extends Resource

enum Trigger {
	ENTER = 1,
	TURN_START = 2,
}

@export_category("Trigger")
@export_flags("Enter", "Turn Start") var triggers: int = Trigger.ENTER

@export_category("Effect")
## Reuses the same editable effect resources as abilities. Terrain has no caster,
## so magical damage uses only Innate Damage and physical damage has no weapon/stat contribution.
@export var effect: AbilityEffectDefinition
## Signed utility from the occupant's perspective. Positive values attract AI;
## negative values discourage it. Health changes are scored automatically.
@export_range(-10000.0, 10000.0, 0.5) var occupant_ai_utility: float = 0.0


func applies_on(trigger: Trigger) -> bool:
	return (triggers & int(trigger)) != 0


func apply(
	unit: TacticalCharacter,
	trigger: Trigger,
	source: Object = null
) -> void:
	if applies_on(trigger) and effect != null and is_instance_valid(unit) and unit.current_health > 0 and not PassiveAbilityResolver.ignores_tile_effects(unit):
		effect.apply(null, unit, source)


func estimate_for_ai(
	unit: TacticalCharacter,
	trigger: Trigger,
	simulated_health: int,
	simulated_armor: int = -1
) -> Dictionary:
	if not applies_on(trigger) or PassiveAbilityResolver.ignores_tile_effects(unit):
		return {"health_delta": 0, "utility_hint": 0.0}
	var armor := simulated_armor if simulated_armor >= 0 else unit.current_armor
	var estimate := (
		effect.estimate_with_armor(null, unit, simulated_health, armor)
		if effect != null
		else {"health_delta": 0, "utility_hint": 0.0}
	)
	return {
		"health_delta": int(estimate.get("health_delta", 0)),
		"armor_delta": int(estimate.get("armor_delta", 0)),
		"utility_hint": float(estimate.get("utility_hint", 0.0)) + occupant_ai_utility,
	}
