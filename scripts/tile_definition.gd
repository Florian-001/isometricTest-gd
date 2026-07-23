@tool
class_name TileDefinition
extends Resource

@export_category("Tile")
@export var display_name: String = "New Tile"
@export var tile_color: Color = Color(0.45, 0.45, 0.45, 1.0)

@export_category("Movement")
## Multiplies the cost of the step that enters this tile.
@export_range(0.0, 100.0, 0.05, "or_greater") var movement_cost_multiplier: float = 1.0

@export_category("Triggered Effects")
## Effects run in list order and stop once the occupant is defeated.
@export var effects: Array[TileTriggeredEffectDefinition] = []


func get_movement_cost_multiplier() -> float:
	return maxf(0.0, movement_cost_multiplier)


func apply_trigger(unit: TacticalCharacter, trigger: TileTriggeredEffectDefinition.Trigger) -> void:
	if not is_instance_valid(unit) or unit.current_health <= 0:
		return
	for triggered_effect in effects:
		if triggered_effect == null:
			continue
		triggered_effect.apply(unit, trigger)
		if unit.current_health <= 0:
			break


func estimate_trigger(
	unit: TacticalCharacter,
	trigger: TileTriggeredEffectDefinition.Trigger,
	simulated_health: int
) -> Dictionary:
	var health := clampi(simulated_health, 0, unit.get_max_health())
	var utility := 0.0
	for triggered_effect in effects:
		if triggered_effect == null or health <= 0:
			continue
		var estimate := triggered_effect.estimate_for_ai(unit, trigger, health)
		health = clampi(
			health + int(estimate.get("health_delta", 0)),
			0,
			unit.get_max_health()
		)
		utility += float(estimate.get("utility_hint", 0.0))
	return {
		"health": health,
		"health_delta": health - simulated_health,
		"utility_hint": utility,
	}
