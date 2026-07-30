@tool
class_name DamageCalculator
extends RefCounted

enum Type {
	PHYSICAL,
	MAGICAL,
}

## Ability-facing scaling sources preserve UnitStat.Type's serialized values and
## append Weapon without exposing it to item or status stat-modifier Inspectors.
enum ScalingSource {
	NONE,
	STRENGTH,
	DEXTERITY,
	INTELLIGENCE,
	SPEED,
	MOVEMENT_RANGE,
	WEAPON,
}

const UNIT_STAT_SCALING_OPTIONS := "None,Strength,Dexterity,Intelligence,Speed,Movement Range"
const WEAPON_SCALING_OPTIONS := UNIT_STAT_SCALING_OPTIONS + ",Weapon"

## Legacy callers derive weapon usage from Physical/Magical damage type.
const USE_DAMAGE_TYPE_WEAPON_RULE := -2
## Magic abilities never receive weapon damage.
const NO_WEAPON_REQUIRED := -1


static func calculate_amount(
	caster: TacticalCharacter,
	damage_type: int,
	innate_damage: int,
	scaling_stat: int,
	scaling_amount: float,
	required_weapon_type: int = USE_DAMAGE_TYPE_WEAPON_RULE
) -> int:
	# Keep all damage arithmetic here. Every runtime and preview path delegates to this function.
	var total := float(maxi(0, innate_damage))
	if is_instance_valid(caster):
		var weapon_damage := 0.0
		if required_weapon_type >= 0:
			weapon_damage = float(caster.get_weapon_damage(required_weapon_type))
		elif (
			required_weapon_type == USE_DAMAGE_TYPE_WEAPON_RULE
			and damage_type == Type.PHYSICAL
		):
			weapon_damage = float(caster.get_weapon_damage())
		if scaling_stat == ScalingSource.WEAPON:
			total += weapon_damage * maxf(0.0, scaling_amount) / 100.0
		else:
			total += weapon_damage
		if is_unit_stat_scaling_source(scaling_stat) and scaling_stat != ScalingSource.NONE:
			total += caster.get_effective_stat(scaling_stat) * maxf(0.0, scaling_amount) / 100.0
	return maxi(0, roundi(total))


static func is_unit_stat_scaling_source(scaling_stat: int) -> bool:
	return scaling_stat >= ScalingSource.NONE and scaling_stat <= ScalingSource.MOVEMENT_RANGE


static func get_scaling_source_display_name(scaling_stat: int) -> String:
	if scaling_stat == ScalingSource.WEAPON:
		return "Weapon"
	return UnitStat.get_display_name(scaling_stat) if is_unit_stat_scaling_source(scaling_stat) else "None"
