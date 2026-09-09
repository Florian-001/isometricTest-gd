class_name CounterAttackSystem
extends RefCounted


## Enemy loadouts do not expose a basic slot; use the same equipment-granted attack.
static func get_ability(unit: TacticalCharacter) -> AbilityDefinition:
	if not is_instance_valid(unit):
		return null
	var basic := unit.get_basic_attack_ability()
	if basic != null:
		return basic
	var weapon := unit.get_equipped_weapon()
	var grants: Array[AbilityDefinition] = weapon.get_granted_abilities() if weapon != null else []
	return grants[0] if not grants.is_empty() else null


## Pure eligibility shared with AI. Reactions do not obey turn-action taunt restrictions.
static func can_counter(
	defender: TacticalCharacter,
	attacker: TacticalCharacter,
	units: Array[TacticalCharacter],
	targeting: AbilityTargeting,
	wall_cells: Dictionary = {},
	snapshot: AIBoardSnapshot = null
) -> bool:
	if (not is_instance_valid(defender) or not is_instance_valid(attacker)
		or defender == attacker or not units.has(defender) or not units.has(attacker)
		or targeting == null or not PassiveAbilityResolver.has_counter(defender, snapshot)):
		return false
	if snapshot != null:
		if not snapshot.is_living(defender) or not snapshot.is_living(attacker) or snapshot.is_incapacitated(defender):
			return false
	elif not defender.can_use_abilities() or attacker.current_health <= 0:
		return false
	var basic := get_ability(defender)
	if basic == null or not basic.has_damage() or not basic.has_compatible_equipment(defender):
		return false
	var friendly := defender.is_friendly() == attacker.is_friendly()
	if not basic.has_target_flag(AbilityDefinition.TargetFlags.FRIEND if friendly else AbilityDefinition.TargetFlags.ENEMY):
		return false
	var origin := snapshot.get_cell(defender) if snapshot != null else defender.grid_cell
	var destination := snapshot.get_cell(attacker) if snapshot != null else attacker.grid_cell
	if (not targeting._is_in_bounds(origin) or not targeting._is_in_bounds(destination)
		or targeting.get_weighted_distance(origin, destination) > basic.get_effective_range(defender) + AbilityTargeting.COST_EPSILON
		or wall_cells.has(destination)
		or not GridLineOfSight.new().has_line_of_sight(origin, destination, wall_cells)):
		return false
	return basic.delivery_type != AbilityDefinition.DeliveryType.MELEE or MeleeDelivery.can_reach(
		origin, destination, wall_cells, basic.get_effective_melee_reach(defender))
