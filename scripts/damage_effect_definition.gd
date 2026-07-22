@tool
class_name DamageEffectDefinition
extends AbilityEffectDefinition

@export_category("Damage")
@export_range(0, 9999, 1, "or_greater") var amount: int = 10


func _init() -> void:
	display_name = "Damage"


func apply(_caster: TacticalCharacter, target: TacticalCharacter) -> void:
	if is_instance_valid(target) and target.current_health > 0:
		target.apply_damage(amount)


func estimate_for_ai(
	_caster: TacticalCharacter,
	_target: TacticalCharacter,
	simulated_health: int
) -> Dictionary:
	return {
		"health_delta": -mini(amount, maxi(0, simulated_health)),
		"utility_hint": ai_utility_hint,
	}


func get_description() -> String:
	return "%d damage" % amount
