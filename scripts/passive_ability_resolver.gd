class_name PassiveAbilityResolver
extends RefCounted


static func has_counter(unit: TacticalCharacter, snapshot: AIBoardSnapshot = null) -> bool:
	if not is_instance_valid(unit):
		return false
	var passives := snapshot.get_passive_abilities(unit) if snapshot != null else unit.get_passive_abilities()
	for passive in passives:
		for effect in passive.effects:
			if effect is CounterPassiveEffect:
				return true
	return false


static func reassemble_effect(unit: TacticalCharacter) -> ReassemblePassiveEffect:
	for passive in unit.get_passive_abilities():
		for effect in passive.effects:
			if effect is ReassemblePassiveEffect and effect.validate().is_empty():
				return effect
	return null


static func ignores_tile_effects(unit: TacticalCharacter) -> bool:
	for passive in unit.get_passive_abilities():
		for effect in passive.effects:
			if effect is GroundImmunityPassiveEffect and effect.ignore_tile_effects:
				return true
	return false


static func ignores_movement_modifiers(unit: TacticalCharacter) -> bool:
	for passive in unit.get_passive_abilities():
		for effect in passive.effects:
			if effect is GroundImmunityPassiveEffect and effect.ignore_movement_modifiers:
				return true
	return false


## AI provides an immutable board view; ordinary combat and UI use the unit's battle roster.
## origin overrides only the evaluated caster's cell, e.g. a Charge landing-cell preview.
static func weapon_damage_bonus(unit: TacticalCharacter, snapshot: AIBoardSnapshot = null, origin := Vector2i(-1, -1)) -> int:
	if not is_instance_valid(unit):
		return 0
	if (snapshot != null and not snapshot.is_living(unit)) or (snapshot == null and unit.current_health <= 0):
		return 0
	var center := origin
	if center == Vector2i(-1, -1):
		center = snapshot.get_cell(unit) if snapshot != null else unit.grid_cell
	var units := snapshot.units if snapshot != null else unit.get_passive_battle_units()
	var bonus := 0
	var passives := snapshot.get_passive_abilities(unit) if snapshot != null else unit.get_passive_abilities()
	for passive in passives:
		for effect in passive.effects:
			if not effect is NearbyAlliesWeaponDamagePassiveEffect or not effect.validate().is_empty():
				continue
			for ally in units:
				if not is_instance_valid(ally) or ally == unit or ally.is_friendly() != unit.is_friendly():
					continue
				if (snapshot != null and not snapshot.is_living(ally)) or (snapshot == null and ally.current_health <= 0):
					continue
				var cell := snapshot.get_cell(ally) if snapshot != null else ally.grid_cell
				if Vector2(center).distance_to(Vector2(cell)) > effect.radius + 0.0001:
					continue
				var ally_passives := snapshot.get_passive_abilities(ally) if snapshot != null else ally.get_passive_abilities()
				for ally_passive in ally_passives:
					if ally_passive.passive_id == passive.passive_id:
						bonus += effect.damage_per_ally
						break
	return bonus
