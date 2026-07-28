@tool
class_name ApplyStatusEffectDefinition
extends AbilityEffectDefinition

@export_category("Status")
@export var status_effect: StatusEffectDefinition


func _init() -> void:
	display_name = "Apply Status"


func apply(
	caster: TacticalCharacter,
	target: TacticalCharacter,
	source: Object = null
) -> void:
	if (
		status_effect != null
		and is_instance_valid(target)
		and target.current_health > 0
	):
		target.apply_status(status_effect, source if source != null else caster, caster)


func estimate_for_ai(
	caster: TacticalCharacter,
	target: TacticalCharacter,
	simulated_health: int
) -> Dictionary:
	if status_effect == null:
		return {"health_delta": 0, "utility_hint": ai_utility_hint}
	var estimate := status_effect.estimate_for_ai(caster, target, simulated_health)
	estimate["utility_hint"] = (
		float(estimate.get("utility_hint", 0.0)) + ai_utility_hint
	)
	return estimate


func get_description(_caster: TacticalCharacter = null) -> String:
	if status_effect == null:
		return "No status configured"
	return status_effect.get_description()
