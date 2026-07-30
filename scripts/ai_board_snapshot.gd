class_name AIBoardSnapshot
extends RefCounted

var grid_size: Vector2i
var wall_cells: Dictionary = {}
var terrain_definitions: Dictionary = {}
var units: Array[TacticalCharacter] = []
var unit_cells: Dictionary = {}
var unit_health: Dictionary = {}
var unit_movement_ranges: Dictionary = {}
var unit_remaining_movement: Dictionary = {}
var unit_opportunity_reactions: Dictionary = {}
var unit_statuses: Dictionary = {}
var unit_stunned: Dictionary = {}


static func from_battle(
	battle_units: Array[TacticalCharacter],
	initial_grid_size: Vector2i,
	walls: Dictionary = {},
	terrain: Dictionary = {}
) -> AIBoardSnapshot:
	var snapshot := AIBoardSnapshot.new()
	snapshot.grid_size = initial_grid_size
	snapshot.wall_cells = walls.duplicate()
	snapshot.terrain_definitions = terrain.duplicate()
	for unit in battle_units:
		if not is_instance_valid(unit):
			continue
		snapshot.units.append(unit)
		snapshot.unit_cells[unit] = unit.grid_cell
		snapshot.unit_health[unit] = unit.current_health
		snapshot.unit_movement_ranges[unit] = unit.get_movement_range()
		snapshot.unit_remaining_movement[unit] = unit.remaining_movement
		snapshot.unit_opportunity_reactions[unit] = unit.opportunity_reaction_available
		var statuses: Dictionary = {}
		for active_status in unit.get_active_statuses():
			if active_status.definition == null or active_status.definition.status_id == &"":
				continue
			statuses[active_status.definition.status_id] = {
				"definition": active_status.definition,
				"remaining_turns": active_status.remaining_turns,
				"processed_this_turn": active_status.processed_this_turn,
			}
		snapshot.unit_statuses[unit] = statuses
		snapshot.unit_stunned[unit] = unit.is_stunned()
	return snapshot


func duplicate_state() -> AIBoardSnapshot:
	var result := AIBoardSnapshot.new()
	result.grid_size = grid_size
	result.wall_cells = wall_cells.duplicate()
	result.terrain_definitions = terrain_definitions.duplicate()
	result.units = units.duplicate()
	result.unit_cells = unit_cells.duplicate()
	result.unit_health = unit_health.duplicate()
	result.unit_movement_ranges = unit_movement_ranges.duplicate()
	result.unit_remaining_movement = unit_remaining_movement.duplicate()
	result.unit_opportunity_reactions = unit_opportunity_reactions.duplicate()
	result.unit_stunned = unit_stunned.duplicate()
	for unit in unit_statuses:
		var copied_statuses: Dictionary = {}
		var statuses := unit_statuses[unit] as Dictionary
		for status_id in statuses:
			copied_statuses[status_id] = (statuses[status_id] as Dictionary).duplicate()
		result.unit_statuses[unit] = copied_statuses
	return result


func is_living(unit: TacticalCharacter) -> bool:
	return is_instance_valid(unit) and int(unit_health.get(unit, 0)) > 0


func get_cell(unit: TacticalCharacter) -> Vector2i:
	return unit_cells.get(unit, Vector2i(-1, -1)) as Vector2i


func set_cell(unit: TacticalCharacter, cell: Vector2i) -> void:
	if unit_cells.has(unit):
		unit_cells[unit] = cell


func get_health(unit: TacticalCharacter) -> int:
	return int(unit_health.get(unit, 0))


func set_health(unit: TacticalCharacter, value: int) -> void:
	if unit_health.has(unit):
		unit_health[unit] = clampi(value, 0, unit.get_max_health())


func get_movement_range(unit: TacticalCharacter) -> float:
	return maxf(0.0, float(unit_movement_ranges.get(unit, 0.0)))


func get_remaining_movement(unit: TacticalCharacter) -> float:
	if is_stunned(unit):
		return 0.0
	return maxf(0.0, float(unit_remaining_movement.get(unit, 0.0)))


func reset_movement(unit: TacticalCharacter) -> void:
	if unit_movement_ranges.has(unit):
		unit_remaining_movement[unit] = (
			get_movement_range(unit)
			if is_living(unit) and not is_stunned(unit)
			else 0.0
		)


func spend_movement(unit: TacticalCharacter, cost: float) -> bool:
	if is_stunned(unit):
		return false
	var remaining := get_remaining_movement(unit)
	if cost < 0.0 or cost > remaining + GridPathfinder.COST_EPSILON:
		return false
	unit_remaining_movement[unit] = maxf(0.0, remaining - cost)
	return true


func can_use_opportunity_reaction(unit: TacticalCharacter) -> bool:
	return (
		is_living(unit)
		and not is_stunned(unit)
		and bool(unit_opportunity_reactions.get(unit, false))
	)


func spend_opportunity_reaction(unit: TacticalCharacter) -> bool:
	if not can_use_opportunity_reaction(unit):
		return false
	unit_opportunity_reactions[unit] = false
	return true


func get_status_remaining(unit: TacticalCharacter, status_id: StringName) -> int:
	var statuses := unit_statuses.get(unit, {}) as Dictionary
	if not statuses.has(status_id):
		return 0
	return maxi(0, int((statuses[status_id] as Dictionary).get("remaining_turns", 0)))


func get_status_state(unit: TacticalCharacter, status_id: StringName) -> Dictionary:
	var statuses := unit_statuses.get(unit, {}) as Dictionary
	return (statuses[status_id] as Dictionary).duplicate() if statuses.has(status_id) else {}


func get_status_ids(unit: TacticalCharacter) -> Array[StringName]:
	var result: Array[StringName] = []
	var statuses := unit_statuses.get(unit, {}) as Dictionary
	for status_id in statuses:
		result.append(status_id as StringName)
	result.sort()
	return result


func is_stunned(unit: TacticalCharacter) -> bool:
	return bool(unit_stunned.get(unit, false))


func forecast_status_application(
	caster: TacticalCharacter,
	target: TacticalCharacter,
	status_effect: StatusEffectDefinition,
	base_utility: float = 0.0
) -> Dictionary:
	if status_effect == null or not is_living(target):
		return {"health_delta": 0, "utility_hint": base_utility, "added_turns": 0}
	var duration := maxi(1, status_effect.duration_turns)
	var existing_turns := get_status_remaining(target, status_effect.status_id)
	var added_turns := maxi(0, duration - existing_turns)
	var duration_fraction := float(added_turns) / float(duration)
	var estimate := status_effect.estimate_for_ai(
		caster,
		target,
		get_health(target),
		added_turns
	)
	var statuses := unit_statuses.get(target, {}) as Dictionary
	if existing_turns <= 0:
		_apply_new_status_movement_modifiers(target, status_effect)
	statuses[status_effect.status_id] = {
		"definition": status_effect,
		"remaining_turns": duration,
		"processed_this_turn": false,
	}
	unit_statuses[target] = statuses
	if status_effect.blocks_actions():
		unit_stunned[target] = true
		unit_remaining_movement[target] = 0.0
	return {
		"health_delta": int(estimate.get("health_delta", 0)),
		"utility_hint": (
			float(estimate.get("utility_hint", 0.0)) + base_utility
		) * duration_fraction,
		"added_turns": added_turns,
	}


func _apply_new_status_movement_modifiers(
	unit: TacticalCharacter,
	status_effect: StatusEffectDefinition
) -> void:
	var movement := get_movement_range(unit)
	var flat_total := 0.0
	var percent_add_total := 0.0
	var percent_multiplier := 1.0
	for modifier in status_effect.get_stat_modifiers():
		if modifier == null or modifier.stat != UnitStat.Type.MOVEMENT_RANGE:
			continue
		match modifier.operation:
			StatModifierDefinition.Operation.FLAT:
				flat_total += modifier.value
			StatModifierDefinition.Operation.PERCENT_ADD:
				percent_add_total += modifier.value
			StatModifierDefinition.Operation.PERCENT_MULTIPLY:
				percent_multiplier *= maxf(0.0, 1.0 + modifier.value)
	var adjusted := (
		(movement + flat_total)
		* maxf(0.0, 1.0 + percent_add_total)
		* percent_multiplier
	)
	unit_movement_ranges[unit] = clampf(adjusted, 0.0, 10.0)
	unit_remaining_movement[unit] = minf(
		get_remaining_movement(unit),
		get_movement_range(unit)
	)


func get_terrain(cell: Vector2i) -> TileDefinition:
	return terrain_definitions.get(cell) as TileDefinition


func get_living_unit_at(cell: Vector2i) -> TacticalCharacter:
	for unit in units:
		if is_living(unit) and get_cell(unit) == cell:
			return unit
	return null


func get_blocked_cells(except_unit: TacticalCharacter = null) -> Dictionary:
	var blocked := wall_cells.duplicate()
	for unit in units:
		# Defeated units intentionally remain blockers until death removal exists.
		if is_instance_valid(unit) and unit != except_unit:
			blocked[get_cell(unit)] = true
	return blocked


func get_living_opponents(unit: TacticalCharacter) -> Array[TacticalCharacter]:
	var result: Array[TacticalCharacter] = []
	for candidate in units:
		if is_living(candidate) and candidate.is_friendly() != unit.is_friendly():
			result.append(candidate)
	return result


func get_living_allies(unit: TacticalCharacter, include_self: bool = true) -> Array[TacticalCharacter]:
	var result: Array[TacticalCharacter] = []
	for candidate in units:
		if (
			is_living(candidate)
			and candidate.is_friendly() == unit.is_friendly()
			and (include_self or candidate != unit)
		):
			result.append(candidate)
	return result
