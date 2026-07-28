@tool
class_name DamageEffectDefinition
extends AbilityEffectDefinition

enum DamageType {
	PHYSICAL,
	MAGICAL,
}

@export_category("Damage Formula")
## Physical damage includes equipped weapon damage. Magical damage ignores the weapon.
@export var damage_type: DamageType = DamageType.PHYSICAL
## Innate damage contributes to both Physical and Magical damage.
@export_range(0, 9999, 1, "or_greater") var innate_damage: int = 0
## The effective stat includes equipment and status-effect buffs.
@export var scaling_stat: UnitStat.Type = UnitStat.Type.STRENGTH
## Percentage of the effective scaling stat added to damage. Values above 100% are supported.
@export_range(0.0, 10000.0, 5.0, "or_greater", "suffix:%") var scaling_percentage: float = 100.0


func _init() -> void:
	display_name = "Damage"


func calculate_amount(caster: TacticalCharacter) -> int:
	return DamageCalculator.calculate_amount(
		caster,
		int(damage_type),
		innate_damage,
		scaling_stat,
		scaling_percentage
	)


func apply(
	caster: TacticalCharacter,
	target: TacticalCharacter,
	_source: Object = null
) -> void:
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
	var type_name := "Physical" if damage_type == DamageType.PHYSICAL else "Magical"
	if is_instance_valid(caster):
		return "%d %s damage (%s)" % [
			calculate_amount(caster),
			type_name.to_lower(),
			_get_formula_description(),
		]
	return "%s damage: %s" % [type_name, _get_formula_description()]


func _get_formula_description() -> String:
	var parts: Array[String] = []
	if damage_type == DamageType.PHYSICAL:
		parts.append("weapon damage")
	elif innate_damage > 0:
		parts.append("%d innate" % innate_damage)
	if scaling_stat != UnitStat.Type.NONE and scaling_percentage > 0.0:
		parts.append("%s x%d%%" % [
			UnitStat.get_display_name(scaling_stat),
			roundi(scaling_percentage),
		])
	return " + ".join(parts) if not parts.is_empty() else "0"
