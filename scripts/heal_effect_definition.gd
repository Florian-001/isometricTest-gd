@tool
class_name HealEffectDefinition
extends AbilityEffectDefinition

@export_category("Healing")
@export_range(0, 9999, 1, "or_greater") var amount: int = 10
@export var scaling_stat: UnitStat.Type = UnitStat.Type.NONE
@export_range(0.0, 100.0, 0.05, "or_greater") var scaling_ratio: float = 1.0


func _init() -> void:
	display_name = "Heal"


func calculate_amount(caster: TacticalCharacter) -> int:
	if scaling_stat == UnitStat.Type.NONE or not is_instance_valid(caster):
		return amount
	var stat_bonus := (caster.get_effective_stat(scaling_stat) - 10.0) * scaling_ratio
	return maxi(0, amount + roundi(stat_bonus))


func apply(
	caster: TacticalCharacter,
	target: TacticalCharacter,
	_source: Object = null
) -> void:
	if is_instance_valid(target) and target.current_health > 0:
		target.heal(calculate_amount(caster))


func estimate_for_ai(
	caster: TacticalCharacter,
	target: TacticalCharacter,
	simulated_health: int
) -> Dictionary:
	var maximum := target.get_max_health() if is_instance_valid(target) else simulated_health
	var calculated_amount := calculate_amount(caster)
	return {
		"health_delta": mini(calculated_amount, maxi(0, maximum - simulated_health)),
		"utility_hint": ai_utility_hint,
	}


func get_description(caster: TacticalCharacter = null) -> String:
	if scaling_stat == UnitStat.Type.NONE:
		return "%d healing" % amount
	if is_instance_valid(caster):
		return "%d healing (%d base, %s x%.2f)" % [
			calculate_amount(caster),
			amount,
			UnitStat.get_display_name(scaling_stat),
			scaling_ratio,
		]
	return "%d base healing + %s scaling x%.2f" % [
		amount,
		UnitStat.get_display_name(scaling_stat),
		scaling_ratio,
	]
