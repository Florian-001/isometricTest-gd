@tool
class_name TileDefinition
extends Resource

@export_category("Tile")
@export var display_name: String = "New Tile"
@export var tile_color: Color = Color(0.45, 0.45, 0.45, 1.0)

@export_category("Movement")
## Multiplies the cost of the step that enters this tile.
@export_range(0.0, 100.0, 0.05, "or_greater") var movement_cost_multiplier: float = 1.0

@export_category("Status Effect")
## Reusable status selected from the custom Inspector dropdown. Empty means None.
@export var status_effect: StatusEffectDefinition:
	set(value):
		status_effect = value
		if Engine.is_editor_hint():
			notify_property_list_changed()
@export_flags("Enter:1", "Turn Start:2") var status_triggers: int = (
	TileTriggeredEffectDefinition.Trigger.ENTER
	| TileTriggeredEffectDefinition.Trigger.TURN_START
)

@export_category("Additional Triggered Effects")
## Effects run in list order and stop once the occupant is defeated.
@export var effects: Array[TileTriggeredEffectDefinition] = []


func _validate_property(property: Dictionary) -> void:
	if property.name == &"status_triggers" and status_effect == null:
		property.usage = property.usage & ~PROPERTY_USAGE_EDITOR


func get_movement_cost_multiplier() -> float:
	return maxf(0.0, movement_cost_multiplier)


func status_applies_on(trigger: TileTriggeredEffectDefinition.Trigger) -> bool:
	return (
		status_effect != null
		and (status_triggers & int(trigger)) != 0
	)


func should_apply_additional_effect(
	triggered_effect: TileTriggeredEffectDefinition
) -> bool:
	if triggered_effect == null:
		return false
	if status_effect == null or not triggered_effect.effect is ApplyStatusEffectDefinition:
		return true
	var nested_status := (
		triggered_effect.effect as ApplyStatusEffectDefinition
	).status_effect
	return nested_status == null or nested_status.status_id != status_effect.status_id


func apply_trigger(unit: TacticalCharacter, trigger: TileTriggeredEffectDefinition.Trigger) -> void:
	if not is_instance_valid(unit) or unit.current_health <= 0 or PassiveAbilityResolver.ignores_tile_effects(unit):
		return
	if status_applies_on(trigger):
		unit.apply_status(status_effect, self)
	for triggered_effect in effects:
		if not should_apply_additional_effect(triggered_effect):
			continue
		triggered_effect.apply(unit, trigger, self)
		if unit.current_health <= 0:
			break


func estimate_trigger(
	unit: TacticalCharacter,
	trigger: TileTriggeredEffectDefinition.Trigger,
	simulated_health: int,
	simulated_armor: int = -1
) -> Dictionary:
	if PassiveAbilityResolver.ignores_tile_effects(unit):
		return {"health": simulated_health, "health_delta": 0, "utility_hint": 0.0}
	var initial_armor := simulated_armor if simulated_armor >= 0 else unit.current_armor
	var armor := initial_armor
	var health := clampi(simulated_health, 0, unit.get_max_health())
	var utility := 0.0
	if status_applies_on(trigger):
		var status_estimate := status_effect.estimate_for_ai(null, unit, health, -1, armor)
		health = clampi(
			health + int(status_estimate.get("health_delta", 0)),
			0,
			unit.get_max_health()
		)
		armor = maxi(0, armor + int(status_estimate.get("armor_delta", 0)))
		utility += float(status_estimate.get("utility_hint", 0.0))
	for triggered_effect in effects:
		if not should_apply_additional_effect(triggered_effect) or health <= 0:
			continue
		var estimate := triggered_effect.estimate_for_ai(unit, trigger, health, armor)
		health = clampi(
			health + int(estimate.get("health_delta", 0)),
			0,
			unit.get_max_health()
		)
		armor = maxi(0, armor + int(estimate.get("armor_delta", 0)))
		utility += float(estimate.get("utility_hint", 0.0))
	return {
		"health": health,
		"armor": armor,
		"armor_delta": armor - initial_armor,
		"health_delta": health - simulated_health,
		"utility_hint": utility,
	}


func get_description() -> String:
	var descriptions: Array[String] = []
	if status_effect != null:
		descriptions.append(status_effect.get_description())
	for triggered_effect in effects:
		if (
			should_apply_additional_effect(triggered_effect)
			and triggered_effect.effect != null
		):
			descriptions.append(triggered_effect.effect.get_description())
	return ", ".join(descriptions) if not descriptions.is_empty() else "No effects"
