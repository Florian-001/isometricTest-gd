@tool
class_name DamageEffectDefinition
extends AbilityEffectDefinition

@export_category("Damage")
@export_range(0, 9999, 1, "or_greater") var amount: int = 10
@export var scaling_stat: UnitStat.Type = UnitStat.Type.NONE
@export_range(0.0, 100.0, 0.05, "or_greater") var scaling_ratio: float = 1.0


func _init() -> void:
	display_name = "Damage"


func calculate_amount(caster: TacticalCharacter) -> int:
	if scaling_stat == UnitStat.Type.NONE or not is_instance_valid(caster):
		return amount
	var stat_bonus := (caster.get_effective_stat(scaling_stat) - 10.0) * scaling_ratio
	return maxi(0, amount + roundi(stat_bonus))


func apply(caster: TacticalCharacter, target: TacticalCharacter) -> void:
	if is_instance_valid(target) and target.current_health > 0:
		target.apply_damage(calculate_amount(caster))


func estimate_for_ai(
	caster: TacticalCharacter,
	_target: TacticalCharacter,
	simulated_health: int
) -> Dictionary:
	var calculated_amount := calculate_amount(caster)
	return {
		"health_delta": -mini(calculated_amount, maxi(0, simulated_health)),
		"utility_hint": ai_utility_hint,
	}


func get_description(caster: TacticalCharacter = null) -> String:
	if scaling_stat == UnitStat.Type.NONE:
		return "%d damage" % amount
	if is_instance_valid(caster):
		return "%d damage (%d base, %s x%.2f)" % [
			calculate_amount(caster),
			amount,
			UnitStat.get_display_name(scaling_stat),
			scaling_ratio,
		]
	return "%d base damage + %s scaling x%.2f" % [
		amount,
		UnitStat.get_display_name(scaling_stat),
		scaling_ratio,
	]
