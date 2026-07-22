@tool
class_name HealEffectDefinition
extends AbilityEffectDefinition

@export_category("Healing")
@export_range(0, 9999, 1, "or_greater") var amount: int = 10


func _init() -> void:
	display_name = "Heal"


func apply(_caster: TacticalCharacter, target: TacticalCharacter) -> void:
	if is_instance_valid(target) and target.current_health > 0:
		target.heal(amount)


func estimate_for_ai(
	_caster: TacticalCharacter,
	target: TacticalCharacter,
	simulated_health: int
) -> Dictionary:
	var maximum := target.get_max_health() if is_instance_valid(target) else simulated_health
	return {
		"health_delta": mini(amount, maxi(0, maximum - simulated_health)),
		"utility_hint": ai_utility_hint,
	}


func get_description() -> String:
	return "%d healing" % amount
