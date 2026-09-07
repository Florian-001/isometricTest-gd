class_name AbilityExecutor
extends Node

const MeleeDeliveryScript = preload("res://scripts/melee_delivery.gd")
const AbilityCasterMovementScript = preload("res://scripts/ability_caster_movement.gd")

signal ability_started(caster: TacticalCharacter, ability: AbilityDefinition, target_cell: Vector2i)
signal ability_finished(caster: TacticalCharacter, ability: AbilityDefinition, target_cell: Vector2i)

var projectile_delivery: ProjectileDelivery
var melee_delivery: Node


func _init() -> void:
	projectile_delivery = ProjectileDelivery.new()
	projectile_delivery.name = "ProjectileDelivery"
	add_child(projectile_delivery)
	melee_delivery = MeleeDeliveryScript.new()
	melee_delivery.name = "MeleeDelivery"
	add_child(melee_delivery)


func execute(
	caster: TacticalCharacter,
	ability: AbilityDefinition,
	selected_cell: Vector2i,
	units: Array[TacticalCharacter],
	grid: IsometricGrid,
	targeting: AbilityTargeting,
	wall_cells: Dictionary = {},
	before_caster_step: Callable = Callable()
) -> bool:
	if not can_execute(caster, ability, selected_cell, units, grid, targeting, wall_cells):
		return false
	if not caster.spend_ability_action():
		return false
	return await _perform(
		caster,
		ability,
		selected_cell,
		units,
		grid,
		targeting,
		wall_cells,
		before_caster_step
	)


func execute_opportunity_attack(
	caster: TacticalCharacter,
	ability: AbilityDefinition,
	selected_cell: Vector2i,
	units: Array[TacticalCharacter],
	grid: IsometricGrid,
	targeting: AbilityTargeting,
	wall_cells: Dictionary = {}
) -> bool:
	if not can_execute_opportunity_attack(
		caster,
		ability,
		selected_cell,
		units,
		grid,
		targeting,
		wall_cells
	):
		return false
	if not caster.spend_opportunity_reaction():
		return false
	return await _perform(caster, ability, selected_cell, units, grid, targeting, wall_cells)


func _perform(
	caster: TacticalCharacter,
	ability: AbilityDefinition,
	selected_cell: Vector2i,
	units: Array[TacticalCharacter],
	grid: IsometricGrid,
	targeting: AbilityTargeting,
	wall_cells: Dictionary,
	before_caster_step: Callable = Callable()
) -> bool:

	ability_started.emit(caster, ability, selected_cell)
	if ability.moves_caster():
		var movement_path := targeting.get_caster_movement_path(
			caster,
			selected_cell,
			ability,
			units,
			wall_cells
		)
		if movement_path.is_empty():
			return false
		var landing_cell := AbilityCasterMovementScript.get_landing_cell(movement_path)
		if movement_path.size() > 1:
			await caster.move_along(movement_path, before_caster_step)
		if (
			not is_instance_valid(caster)
			or caster.current_health <= 0
			or caster.grid_cell != landing_cell
			or not _can_execute_base(
				caster,
				ability,
				selected_cell,
				units,
				grid,
				targeting,
				wall_cells
			)
		):
			return false
	caster.face_toward_world_position(grid.grid_to_global(selected_cell))
	match ability.delivery_type:
		AbilityDefinition.DeliveryType.PROJECTILE:
			var projectile_arrived := await projectile_delivery.launch(
				caster,
				ability,
				selected_cell,
				grid,
				wall_cells
			)
			if not projectile_arrived:
				return false
			_apply_effects(caster, selected_cell, ability, units, targeting, wall_cells)
		AbilityDefinition.DeliveryType.MELEE:
			var impact_callback := Callable(self, "_apply_effects").bind(
				caster,
				selected_cell,
				ability,
				units,
				targeting,
				wall_cells
			)
			var melee_finished: bool = await melee_delivery.perform(
				caster,
				ability,
				selected_cell,
				grid,
				impact_callback,
				wall_cells
			)
			if not melee_finished:
				return false
		_:
			_apply_effects(caster, selected_cell, ability, units, targeting, wall_cells)

	ability_finished.emit(caster, ability, selected_cell)
	return true


func can_execute(
	caster: TacticalCharacter,
	ability: AbilityDefinition,
	selected_cell: Vector2i,
	units: Array[TacticalCharacter],
	grid: IsometricGrid,
	targeting: AbilityTargeting,
	wall_cells: Dictionary = {}
) -> bool:
	return (
		is_instance_valid(caster)
		and caster.ability_available
		and _can_execute_base(
			caster,
			ability,
			selected_cell,
			units,
			grid,
			targeting,
			wall_cells
		)
	)


func can_execute_opportunity_attack(
	caster: TacticalCharacter,
	ability: AbilityDefinition,
	selected_cell: Vector2i,
	units: Array[TacticalCharacter],
	grid: IsometricGrid,
	targeting: AbilityTargeting,
	wall_cells: Dictionary = {}
) -> bool:
	return (
		is_instance_valid(caster)
		and caster.opportunity_reaction_available
		and ability == OpportunityAttackSystem.get_opportunity_attack_ability(caster)
		and _can_execute_base(
			caster,
			ability,
			selected_cell,
			units,
			grid,
			targeting,
			wall_cells
		)
	)


func _can_execute_base(
	caster: TacticalCharacter,
	ability: AbilityDefinition,
	selected_cell: Vector2i,
	units: Array[TacticalCharacter],
	grid: IsometricGrid,
	targeting: AbilityTargeting,
	wall_cells: Dictionary
) -> bool:
	if (
		not is_instance_valid(caster)
		or caster.current_health <= 0
		or ability == null
		or (caster.is_friendly() and not caster.get_abilities().has(ability))
		or not ability.can_be_used_by(caster)
		or grid == null
		or targeting == null
		or not targeting.is_valid_primary_target(caster, selected_cell, ability, units, wall_cells)
	):
		return false
	var delivery_origin := caster.grid_cell
	if ability.moves_caster():
		var movement_path := targeting.get_caster_movement_path(
			caster,
			selected_cell,
			ability,
			units,
			wall_cells
		)
		if movement_path.is_empty():
			return false
		delivery_origin = AbilityCasterMovementScript.get_landing_cell(movement_path)
	if (
		ability.delivery_type == AbilityDefinition.DeliveryType.PROJECTILE
		and not projectile_delivery.has_clear_trajectory(delivery_origin, selected_cell, wall_cells)
	):
		return false
	if (
		ability.delivery_type == AbilityDefinition.DeliveryType.MELEE
		and not MeleeDeliveryScript.can_reach(delivery_origin, selected_cell, wall_cells)
	):
		return false
	return true


func _apply_effects(
	caster: TacticalCharacter,
	selected_cell: Vector2i,
	ability: AbilityDefinition,
	units: Array[TacticalCharacter],
	targeting: AbilityTargeting,
	wall_cells: Dictionary
) -> void:
	var recipients := targeting.get_affected_units(
		caster,
		selected_cell,
		ability,
		units,
		wall_cells
	)
	for recipient in recipients:
		if ability.has_primary_effect() and recipient.current_health > 0:
			ability.apply_primary_effect(caster, recipient)
		for additional_effect in ability.effects:
			if (
				recipient.current_health > 0
				and ability.should_apply_additional_effect(additional_effect)
			):
				additional_effect.apply(caster, recipient, ability)
		if recipient.current_health > 0:
			ability.apply_weapon_status(caster, recipient)
