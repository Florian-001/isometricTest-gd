@tool
class_name DamageEffectDefinition
extends AbilityEffectDefinition

enum DamageType {
	PHYSICAL,
	MAGICAL,
}

@export_category("Damage Formula")
## Standalone legacy effects use this to decide weapon contribution. Ability-owned effects use
## their originating Ability Type instead.
@export var damage_type: DamageType = DamageType.PHYSICAL
## Innate damage contributes to both Physical and Magical damage.
@export_range(0, 9999, 1, "or_greater") var innate_damage: int = 0
## The effective stat includes equipment and status-effect buffs.
@export var scaling_stat: UnitStat.Type = UnitStat.Type.STRENGTH
## Percentage of the effective scaling stat added to damage. Values above 100% are supported.
@export_range(0.0, 10000.0, 5.0, "or_greater", "suffix:%") var scaling_percentage: float = 100.0


func _init() -> void:
	display_name = "Damage"


func calculate_amount(
	caster: TacticalCharacter,
	source_ability: AbilityDefinition = null,
	snapshot: AIBoardSnapshot = null
) -> int:
	var weapon_rule := DamageCalculator.USE_DAMAGE_TYPE_WEAPON_RULE
	if source_ability != null:
		weapon_rule = source_ability.get_required_weapon_type()
	return DamageCalculator.calculate_amount(
		caster,
		int(damage_type),
		innate_damage,
		scaling_stat,
		scaling_percentage,
		weapon_rule,
		snapshot.get_effective_stat(caster, scaling_stat) if snapshot != null and scaling_stat != UnitStat.Type.NONE else NAN
	)


func apply(
	caster: TacticalCharacter,
	target: TacticalCharacter,
	source: Object = null
) -> void:
	if is_instance_valid(target) and target.current_health > 0:
		target.apply_damage(calculate_amount(caster, source as AbilityDefinition))


func estimate_for_ai(
	caster: TacticalCharacter,
	target: TacticalCharacter,
	simulated_health: int
) -> Dictionary:
	return estimate_with_armor(caster, target, simulated_health, target.current_armor if is_instance_valid(target) else 0)


func estimate_with_armor(
	caster: TacticalCharacter,
	_target: TacticalCharacter,
	simulated_health: int,
	simulated_armor: int
) -> Dictionary:
	var result := DamageCalculator.resolve_damage(calculate_amount(caster), simulated_health, simulated_armor)
	result.utility_hint = ai_utility_hint
	return result


func estimate_for_ability(
	caster: TacticalCharacter,
	target: TacticalCharacter,
	simulated_health: int,
	source_ability: AbilityDefinition,
	passive_bonus: int = 0,
	simulated_armor: int = -1,
	snapshot: AIBoardSnapshot = null
) -> Dictionary:
	var armor := simulated_armor if simulated_armor >= 0 else (target.current_armor if is_instance_valid(target) else 0)
	var result := DamageCalculator.resolve_damage(calculate_amount(caster, source_ability, snapshot) + passive_bonus, simulated_health, armor)
	result.utility_hint = ai_utility_hint
	return result


func get_description(caster: TacticalCharacter = null) -> String:
	return _get_description(caster, null)


func get_description_for_ability(
	caster: TacticalCharacter,
	source_ability: AbilityDefinition
) -> String:
	return _get_description(caster, source_ability)


func _get_description(
	caster: TacticalCharacter,
	source_ability: AbilityDefinition
) -> String:
	var type_name := "Physical" if damage_type == DamageType.PHYSICAL else "Magical"
	if is_instance_valid(caster):
		return "%d %s damage (%s)" % [
			calculate_amount(caster, source_ability),
			type_name.to_lower(),
			_get_formula_description(source_ability),
		]
	return "%s damage: %s" % [type_name, _get_formula_description(source_ability)]


func _get_formula_description(source_ability: AbilityDefinition = null) -> String:
	var parts: Array[String] = []
	if (
		(source_ability == null and damage_type == DamageType.PHYSICAL)
		or (
			source_ability != null
			and source_ability.ability_type in [
				AbilityDefinition.AbilityType.MELEE,
				AbilityDefinition.AbilityType.RANGED,
			]
		)
	):
		parts.append("weapon damage")
	if innate_damage > 0:
		parts.append("%d innate" % innate_damage)
	if scaling_stat != UnitStat.Type.NONE and scaling_percentage > 0.0:
		parts.append("%s x%d%%" % [
			UnitStat.get_display_name(scaling_stat),
			roundi(scaling_percentage),
		])
	return " + ".join(parts) if not parts.is_empty() else "0"
