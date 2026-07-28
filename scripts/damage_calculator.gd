@tool
class_name DamageCalculator
extends RefCounted

enum Type {
	PHYSICAL,
	MAGICAL,
}

## Legacy callers derive weapon usage from Physical/Magical damage type.
const USE_DAMAGE_TYPE_WEAPON_RULE := -2
## Magic abilities never receive weapon damage.
const NO_WEAPON_REQUIRED := -1


static func calculate_amount(
	caster: TacticalCharacter,
	damage_type: int,
	innate_damage: int,
	scaling_stat: UnitStat.Type,
	scaling_amount: float,
	required_weapon_type: int = USE_DAMAGE_TYPE_WEAPON_RULE
) -> int:
	# Keep all damage arithmetic here. Every runtime and preview path delegates to this function.
	var total := float(maxi(0, innate_damage))
	if is_instance_valid(caster):
		if required_weapon_type >= 0:
			total += float(caster.get_weapon_damage(required_weapon_type))
		elif (
			required_weapon_type == USE_DAMAGE_TYPE_WEAPON_RULE
			and damage_type == Type.PHYSICAL
		):
			total += float(caster.get_weapon_damage())
		if scaling_stat != UnitStat.Type.NONE:
			total += caster.get_effective_stat(scaling_stat) * maxf(0.0, scaling_amount) / 100.0
	return maxi(0, roundi(total))
