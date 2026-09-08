class_name AbilityExecutor
extends Node

const MeleeDeliveryScript = preload("res://scripts/melee_delivery.gd")
const AbilityCasterMovementScript = preload("res://scripts/ability_caster_movement.gd")

signal ability_started(caster: TacticalCharacter, ability: AbilityDefinition, target_cell: Vector2i)
signal ability_finished(caster: TacticalCharacter, ability: AbilityDefinition, target_cell: Vector2i)

var projectile_delivery: ProjectileDelivery
var melee_delivery: Node
var _active_resolutions := 0


func is_resolving() -> bool:
	return _active_resolutions > 0


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


## Validate the complete ordered selection before consuming the single action.
func can_execute_targets(
	caster: TacticalCharacter,
	ability: AbilityDefinition,
	selected_targets: Array[TacticalCharacter],
	units: Array[TacticalCharacter],
	grid: IsometricGrid,
	targeting: AbilityTargeting,
	wall_cells: Dictionary = {}
) -> bool:
	if (not is_instance_valid(caster) or not caster.ability_available
		or ability == null or not ability.selects_per_hit()
		or selected_targets.size() != ability.get_hit_count()):
		return false
	var seen: Array[TacticalCharacter] = []
	for target in selected_targets:
		if not is_instance_valid(target) or not can_select_hit_target(caster, ability, target, units, grid, targeting, wall_cells):
			return false
		if not ability.allow_repeated_targets and seen.has(target):
			return false
		seen.append(target)
	return true


## Also used while filling the UI; action availability is checked when committing.
func can_select_hit_target(
	caster: TacticalCharacter,
	ability: AbilityDefinition,
	target: TacticalCharacter,
	units: Array[TacticalCharacter],
	grid: IsometricGrid,
	targeting: AbilityTargeting,
	wall_cells: Dictionary = {}
) -> bool:
	return (is_instance_valid(target) and target.current_health > 0
		and units.has(target) and units.has(caster)
		and ability != null and ability.selects_per_hit()
		and _can_execute_base(caster, ability, target.grid_cell, units, grid, targeting, wall_cells)
		and targeting.get_affected_units(caster, target.grid_cell, ability, units, wall_cells).has(target))


func execute_targets(
	caster: TacticalCharacter,
	ability: AbilityDefinition,
	selected_targets: Array[TacticalCharacter],
	units: Array[TacticalCharacter],
	grid: IsometricGrid,
	targeting: AbilityTargeting,
	wall_cells: Dictionary = {}
) -> bool:
	if not can_execute_targets(caster, ability, selected_targets, units, grid, targeting, wall_cells):
		return false
	# Spending the action emits signals that clear the controller's selection array.
	var locked_targets: Array[TacticalCharacter] = selected_targets.duplicate()
	var first_cell := locked_targets[0].grid_cell
	if not caster.spend_ability_action():
		return false
	_active_resolutions += 1
	ability_started.emit(caster, ability, first_cell)
	for target in locked_targets:
		if not is_instance_valid(caster) or not ability.can_be_used_by(caster) or not units.has(caster):
			break
		if not is_instance_valid(target) or not can_select_hit_target(caster, ability, target, units, grid, targeting, wall_cells):
			continue
		var recipients: Array[TacticalCharacter] = [target]
		await _deliver_hit(caster, ability, target.grid_cell, units, grid, targeting, wall_cells, recipients)
	_active_resolutions -= 1
	ability_finished.emit(caster if is_instance_valid(caster) else null, ability, first_cell)
	return true


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
	_active_resolutions += 1
	var succeeded := await _perform_resolved(caster, ability, selected_cell, units, grid, targeting, wall_cells, before_caster_step)
	_active_resolutions -= 1
	return succeeded


func _perform_resolved(
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
	# Lock recipients once so subsequent hits can never switch to another unit.
	var locked_recipients: Array[TacticalCharacter] = []
	if ability.get_hit_count() > 1:
		locked_recipients = targeting.get_affected_units(caster, selected_cell, ability, units, wall_cells)
	for hit_index in range(ability.get_hit_count()):
		if hit_index > 0:
			if not ability.can_be_used_by(caster):
				break
			var current_recipients := targeting.get_affected_units(caster, selected_cell, ability, units, wall_cells)
			var still_valid := false
			for recipient in locked_recipients:
				if is_instance_valid(recipient) and recipient.current_health > 0 and current_recipients.has(recipient):
					still_valid = true
					break
			if not still_valid or not _can_execute_base(caster, ability, selected_cell, units, grid, targeting, wall_cells):
				break
		if not await _deliver_hit(caster, ability, selected_cell, units, grid, targeting, wall_cells, locked_recipients):
			return false
	ability_finished.emit(caster, ability, selected_cell)
	return true


func _deliver_hit(
	caster: TacticalCharacter,
	ability: AbilityDefinition,
	selected_cell: Vector2i,
	units: Array[TacticalCharacter],
	grid: IsometricGrid,
	targeting: AbilityTargeting,
	wall_cells: Dictionary,
	locked_recipients: Array[TacticalCharacter]
) -> bool:
	caster.face_toward_world_position(grid.grid_to_global(selected_cell))
	var impact_callback := Callable(self, "_apply_delivered_effects").bind(
		caster, selected_cell, ability, units, grid, targeting, wall_cells, locked_recipients
	)
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
			impact_callback.call()
		AbilityDefinition.DeliveryType.MELEE:
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
			impact_callback.call()
	return true


func _apply_delivered_effects(
	caster: Variant,
	selected_cell: Vector2i,
	ability: AbilityDefinition,
	units: Array[TacticalCharacter],
	grid: IsometricGrid,
	targeting: AbilityTargeting,
	wall_cells: Dictionary,
	locked_recipients: Array[TacticalCharacter]
) -> void:
	if not is_instance_valid(caster):
		return
	if ability.selects_per_hit():
		if locked_recipients.size() != 1:
			return
		var target := locked_recipients[0]
		if (not is_instance_valid(target)
			or not can_select_hit_target(caster, ability, target, units, grid, targeting, wall_cells)
			or target.grid_cell != selected_cell):
			return
	_apply_effects(caster, selected_cell, ability, units, targeting, wall_cells, locked_recipients)


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
		and ability != null and not ability.selects_per_hit()
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
		and ability != null and not ability.selects_per_hit()
		and caster.opportunity_reaction_available
		and ability == OpportunityAttackSystem.get_opportunity_attack_ability(caster)
		# Weapon range bonuses apply only to normal casts, including direct API calls.
		and MeleeDeliveryScript.can_reach(caster.grid_cell, selected_cell, wall_cells)
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
		and not MeleeDeliveryScript.can_reach(delivery_origin, selected_cell, wall_cells, ability.get_effective_melee_reach(caster))
	):
		return false
	return true


func _apply_effects(
	caster: TacticalCharacter,
	selected_cell: Vector2i,
	ability: AbilityDefinition,
	units: Array[TacticalCharacter],
	targeting: AbilityTargeting,
	wall_cells: Dictionary,
	locked_recipients: Array[TacticalCharacter] = []
) -> void:
	var recipients := targeting.get_affected_units(
		caster,
		selected_cell,
		ability,
		units,
		wall_cells
	)
	for recipient in recipients:
		if not locked_recipients.is_empty() and not locked_recipients.has(recipient):
			continue
		var bonus_pending := ability.effect != AbilityDefinition.PrimaryEffect.DAMAGE
		if ability.has_primary_effect() and recipient.current_health > 0:
			ability.apply_primary_effect(caster, recipient)
		for additional_effect in ability.effects:
			if (
				recipient.current_health > 0
				and ability.should_apply_additional_effect(additional_effect)
			):
				if additional_effect is DamageEffectDefinition:
					var bonus := ability.get_passive_damage_bonus(caster) if bonus_pending else 0
					bonus_pending = false
					recipient.apply_damage(additional_effect.calculate_amount(caster, ability) + bonus)
				else:
					additional_effect.apply(caster, recipient, ability)
		if recipient.current_health > 0:
			ability.apply_weapon_status(caster, recipient)
