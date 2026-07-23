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
## so stat-scaled effects use their unscaled base value.
@export var effect: AbilityEffectDefinition
## Signed utility from the occupant's perspective. Positive values attract AI;
## negative values discourage it. Health changes are scored automatically.
@export_range(-10000.0, 10000.0, 0.5) var occupant_ai_utility: float = 0.0


func applies_on(trigger: Trigger) -> bool:
	return (triggers & int(trigger)) != 0


func apply(unit: TacticalCharacter, trigger: Trigger) -> void:
	if applies_on(trigger) and effect != null and is_instance_valid(unit) and unit.current_health > 0:
		effect.apply(null, unit)


func estimate_for_ai(
	unit: TacticalCharacter,
	trigger: Trigger,
	simulated_health: int
) -> Dictionary:
	if not applies_on(trigger):
		return {"health_delta": 0, "utility_hint": 0.0}
	var estimate := (
		effect.estimate_for_ai(null, unit, simulated_health)
		if effect != null
		else {"health_delta": 0, "utility_hint": 0.0}
	)
	return {
		"health_delta": int(estimate.get("health_delta", 0)),
		"utility_hint": float(estimate.get("utility_hint", 0.0)) + occupant_ai_utility,
	}
