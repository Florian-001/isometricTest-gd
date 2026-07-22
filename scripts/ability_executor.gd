class_name AbilityExecutor
extends Node

const MeleeDeliveryScript = preload("res://scripts/melee_delivery.gd")

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
	wall_cells: Dictionary = {}
) -> bool:
	if not can_execute(caster, ability, selected_cell, units, grid, targeting, wall_cells):
		return false
	if not caster.spend_ability_action():
		return false

	ability_started.emit(caster, ability, selected_cell)
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
	if (
		not is_instance_valid(caster)
		or caster.current_health <= 0
		or not caster.ability_available
		or ability == null
		or grid == null
		or targeting == null
		or not targeting.is_valid_primary_target(caster, selected_cell, ability, units, wall_cells)
	):
		return false
	if (
		ability.delivery_type == AbilityDefinition.DeliveryType.PROJECTILE
		and not projectile_delivery.has_clear_trajectory(caster.grid_cell, selected_cell, wall_cells)
	):
		return false
	if (
		ability.delivery_type == AbilityDefinition.DeliveryType.MELEE
		and not MeleeDeliveryScript.can_reach(caster.grid_cell, selected_cell, wall_cells)
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
		for effect in ability.effects:
			if effect != null and recipient.current_health > 0:
				effect.apply(caster, recipient)
