class_name OpportunityAttackSystem
extends RefCounted

const MeleeDeliveryScript = preload("res://scripts/melee_delivery.gd")


static func get_opportunity_attack_ability(attacker: TacticalCharacter) -> AbilityDefinition:
	if not is_instance_valid(attacker) or attacker.current_health <= 0:
		return null
	for ability in attacker.get_abilities():
		if (
			ability != null
			and not ability.moves_caster()
			and ability.ability_type == AbilityDefinition.AbilityType.MELEE
			and ability.has_damage()
			and ability.get_effective_area_span() == 1
			and ability.has_target_flag(AbilityDefinition.TargetFlags.ENEMY)
			and ability.can_be_used_by(attacker)
		):
			return ability
	return null


static func is_leaving_reach(
	attacker_cell: Vector2i,
	current_cell: Vector2i,
	next_cell: Vector2i,
	wall_cells: Dictionary = {}
) -> bool:
	return (
		MeleeDeliveryScript.can_reach(attacker_cell, current_cell, wall_cells)
		and not MeleeDeliveryScript.can_reach(attacker_cell, next_cell, wall_cells)
	)


static func can_trigger(
	attacker: TacticalCharacter,
	mover: TacticalCharacter,
	current_cell: Vector2i,
	next_cell: Vector2i,
	wall_cells: Dictionary = {}
) -> bool:
	return (
		is_instance_valid(attacker)
		and is_instance_valid(mover)
		and attacker != mover
		and attacker.current_health > 0
		and mover.current_health > 0
		and attacker.is_friendly() != mover.is_friendly()
		and attacker.opportunity_reaction_available
		and get_opportunity_attack_ability(attacker) != null
		and is_leaving_reach(attacker.grid_cell, current_cell, next_cell, wall_cells)
	)


static func get_initiative_order(units: Array[TacticalCharacter]) -> Array[TacticalCharacter]:
	var result := units.duplicate()
	var scene_indices: Dictionary = {}
	for index in range(result.size()):
		scene_indices[result[index]] = index
	result.sort_custom(func(a: TacticalCharacter, b: TacticalCharacter) -> bool:
		var initiative_a := a.get_initiative()
		var initiative_b := b.get_initiative()
		if initiative_a != initiative_b:
			return initiative_a > initiative_b
		return int(scene_indices.get(a, 999999)) < int(scene_indices.get(b, 999999))
	)
	return result
