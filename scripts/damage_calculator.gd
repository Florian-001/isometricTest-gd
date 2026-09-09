@tool
class_name DamageCalculator
extends RefCounted

enum Type {
	PHYSICAL,
	MAGICAL,
}

## Ability-facing scaling sources preserve UnitStat.Type's serialized values.
## Weapon keeps its legacy ability-only id 6; Constitution safely uses id 7.
enum ScalingSource {
	NONE = 0,
	STRENGTH = 1,
	DEXTERITY = 2,
	INTELLIGENCE = 3,
	CONSTITUTION = 7,
	SPEED = 4,
	MOVEMENT_RANGE = 5,
	WEAPON = 6,
}

const UNIT_STAT_SCALING_OPTIONS := (
	"None:0,Strength:1,Dexterity:2,Intelligence:3,Constitution:7,Speed:4,Movement Range:5"
)
const WEAPON_SCALING_OPTIONS := UNIT_STAT_SCALING_OPTIONS + ",Weapon:6"

## Legacy callers derive weapon usage from Physical/Magical damage type.
const USE_DAMAGE_TYPE_WEAPON_RULE := -2
## Magic abilities never receive weapon damage.
const NO_WEAPON_REQUIRED := -1


## Shared pool resolution for runtime damage and side-effect-free AI estimates.
## Damage is split before either pool is clamped, including on low-health targets.
static func resolve_damage(amount: int, health: int, armor: int) -> Dictionary:
	var absorbed := mini(maxi(0, armor), maxi(0, amount)) if health > 0 else 0
	return {
		"armor_delta": -absorbed,
		"health_delta": -mini(maxi(0, health), maxi(0, amount - absorbed)),
		"utility_hint": 0.0,
	}


## Forecasts may supply an effective stat value without coupling this calculator to AI state.
## NAN retains the ordinary live-caster calculation.
static func calculate_amount(
	caster: TacticalCharacter,
	damage_type: int,
	innate_damage: int,
	scaling_stat: int,
	scaling_amount: float,
	required_weapon_type: int = USE_DAMAGE_TYPE_WEAPON_RULE,
	stat_value_override: float = NAN
) -> int:
	# Keep all damage arithmetic here. Every runtime and preview path delegates to this function.
	return int(get_amount_breakdown(
		caster,
		damage_type,
		innate_damage,
		scaling_stat,
		scaling_amount,
		required_weapon_type,
		stat_value_override
	).total)


## Returns the exact terms used by calculate_amount without changing the caster.
static func get_amount_breakdown(
	caster: TacticalCharacter,
	damage_type: int,
	innate_damage: int,
	scaling_stat: int,
	scaling_amount: float,
	required_weapon_type: int = USE_DAMAGE_TYPE_WEAPON_RULE,
	stat_value_override: float = NAN
) -> Dictionary:
	var innate := float(maxi(0, innate_damage))
	var percentage := maxf(0.0, scaling_amount)
	var uses_weapon_term := (
		required_weapon_type >= 0
		or (
			required_weapon_type == USE_DAMAGE_TYPE_WEAPON_RULE
			and damage_type == Type.PHYSICAL
		)
		or scaling_stat == ScalingSource.WEAPON
	)
	var weapon_damage := 0.0
	if is_instance_valid(caster):
		if required_weapon_type >= 0:
			weapon_damage = float(caster.get_weapon_damage(required_weapon_type))
		elif (
			required_weapon_type == USE_DAMAGE_TYPE_WEAPON_RULE
			and damage_type == Type.PHYSICAL
		):
			weapon_damage = float(caster.get_weapon_damage())

	var weapon_scaled := scaling_stat == ScalingSource.WEAPON
	var weapon_contribution := (
		weapon_damage * percentage / 100.0
		if weapon_scaled
		else weapon_damage
	)
	var uses_stat_term := (
		is_unit_stat_scaling_source(scaling_stat)
		and scaling_stat != ScalingSource.NONE
	)
	var stat_value := 0.0
	if uses_stat_term and is_instance_valid(caster):
		stat_value = caster.get_effective_stat(scaling_stat) if is_nan(stat_value_override) else stat_value_override
	var stat_contribution := stat_value * percentage / 100.0 if uses_stat_term else 0.0
	var unrounded_total := innate + weapon_contribution + stat_contribution
	return {
		"total": maxi(0, roundi(unrounded_total)),
		"unrounded_total": unrounded_total,
		"innate": innate,
		"uses_weapon_term": uses_weapon_term,
		"weapon_damage": weapon_damage,
		"weapon_scaled": weapon_scaled,
		"weapon_contribution": weapon_contribution,
		"uses_stat_term": uses_stat_term,
		"stat_name": get_scaling_source_display_name(scaling_stat),
		"stat_value": stat_value,
		"scaling_percentage": percentage,
		"stat_contribution": stat_contribution,
	}


## Formats a user-facing equation from the same terms used by calculate_amount.
static func get_amount_calculation_description(
	caster: TacticalCharacter,
	damage_type: int,
	innate_damage: int,
	scaling_stat: int,
	scaling_amount: float,
	required_weapon_type: int = USE_DAMAGE_TYPE_WEAPON_RULE
) -> String:
	var breakdown := get_amount_breakdown(
		caster,
		damage_type,
		innate_damage,
		scaling_stat,
		scaling_amount,
		required_weapon_type
	)
	var parts: Array[String] = []
	var innate := float(breakdown.innate)
	if innate > 0.0:
		parts.append("%s innate" % _format_number(innate))
	if bool(breakdown.uses_weapon_term):
		if bool(breakdown.weapon_scaled):
			parts.append("%s weapon × %s%%" % [
				_format_number(float(breakdown.weapon_damage)),
				_format_number(float(breakdown.scaling_percentage)),
			])
		else:
			parts.append("%s weapon" % _format_number(float(breakdown.weapon_contribution)))
	if bool(breakdown.uses_stat_term):
		parts.append("%s effective %s × %s%%" % [
			_format_number(float(breakdown.stat_value)),
			str(breakdown.stat_name),
			_format_number(float(breakdown.scaling_percentage)),
		])
	if parts.is_empty():
		parts.append("0")
	var total := int(breakdown.total)
	var unrounded_total := float(breakdown.unrounded_total)
	var rounding_note := ""
	if not is_equal_approx(unrounded_total, float(total)):
		rounding_note = " (rounded from %s)" % _format_number(unrounded_total)
	return "%d = %s%s" % [total, " + ".join(parts), rounding_note]


static func is_unit_stat_scaling_source(scaling_stat: int) -> bool:
	return UnitStat.Type.values().has(scaling_stat)


static func get_scaling_source_display_name(scaling_stat: int) -> String:
	if scaling_stat == ScalingSource.WEAPON:
		return "Weapon"
	return UnitStat.get_display_name(scaling_stat) if is_unit_stat_scaling_source(scaling_stat) else "None"


static func _format_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return str(snappedf(value, 0.01))
