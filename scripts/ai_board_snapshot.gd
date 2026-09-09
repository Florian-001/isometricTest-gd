class_name AIBoardSnapshot
extends RefCounted

var grid_size: Vector2i
var wall_cells: Dictionary = {}
var terrain_definitions: Dictionary = {}
var units: Array[TacticalCharacter] = []
var unit_cells: Dictionary = {}
var unit_health: Dictionary = {}
var unit_armor: Dictionary = {}
var unit_max_health: Dictionary = {}
var unit_constitutions: Dictionary = {}
var unit_movement_ranges: Dictionary = {}
var unit_remaining_movement: Dictionary = {}
var unit_opportunity_reactions: Dictionary = {}
var unit_statuses: Dictionary = {}
var unit_stunned: Dictionary = {}
var unit_bone_piles: Dictionary = {}
var unit_reassembly_effects: Dictionary = {}


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
		snapshot.unit_armor[unit] = unit.current_armor
		snapshot.unit_max_health[unit] = unit.get_max_health()
		snapshot.unit_constitutions[unit] = unit.get_effective_stat(UnitStat.Type.CONSTITUTION)
		snapshot.unit_movement_ranges[unit] = unit.get_movement_range()
		snapshot.unit_remaining_movement[unit] = unit._remaining_movement
		snapshot.unit_opportunity_reactions[unit] = unit._opportunity_reaction_available
		var statuses: Dictionary = {}
		for active_status in unit.get_active_statuses():
			if active_status.definition == null or active_status.definition.status_id == &"":
				continue
			statuses[active_status.definition.status_id] = {
				"definition": active_status.definition,
				"remaining_turns": active_status.remaining_turns,
				"processed_this_turn": active_status.processed_this_turn,
				"source_unit": active_status.source_unit,
			}
		snapshot.unit_statuses[unit] = statuses
		snapshot.unit_stunned[unit] = unit.is_stunned()
		snapshot.unit_bone_piles[unit] = unit.is_bone_pile
		snapshot.unit_reassembly_effects[unit] = unit.get_reassembly_effect()
	return snapshot


func duplicate_state() -> AIBoardSnapshot:
	var result := AIBoardSnapshot.new()
	result.grid_size = grid_size
	result.wall_cells = wall_cells.duplicate()
	result.terrain_definitions = terrain_definitions.duplicate()
	result.units = units.duplicate()
	result.unit_cells = unit_cells.duplicate()
	result.unit_health = unit_health.duplicate()
	result.unit_armor = unit_armor.duplicate()
	result.unit_max_health = unit_max_health.duplicate()
	result.unit_constitutions = unit_constitutions.duplicate()
	result.unit_movement_ranges = unit_movement_ranges.duplicate()
	result.unit_remaining_movement = unit_remaining_movement.duplicate()
	result.unit_opportunity_reactions = unit_opportunity_reactions.duplicate()
	result.unit_stunned = unit_stunned.duplicate()
	result.unit_bone_piles = unit_bone_piles.duplicate()
	result.unit_reassembly_effects = unit_reassembly_effects.duplicate()
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


func get_armor(unit: TacticalCharacter) -> int:
	return maxi(0, int(unit_armor.get(unit, 0)))


## Estimates already split armor from health. Never absorb their HP delta twice.
func apply_effect_estimate(unit: TacticalCharacter, estimate: Dictionary) -> Dictionary:
	if not is_living(unit):
		return {"health_delta": 0, "armor_delta": 0}
	var armor_before := get_armor(unit)
	unit_armor[unit] = maxi(0, armor_before + int(estimate.get("armor_delta", 0)))
	var health_delta := apply_health_delta(unit, int(estimate.get("health_delta", 0)))
	return {"health_delta": health_delta, "armor_delta": get_armor(unit) - armor_before}


func get_max_health(unit: TacticalCharacter) -> int:
	if unit_max_health.has(unit):
		return maxi(1, int(unit_max_health[unit]))
	return unit.get_max_health() if is_instance_valid(unit) else 1


func set_health(unit: TacticalCharacter, value: int) -> void:
	if unit_health.has(unit):
		unit_health[unit] = clampi(value, 0, get_max_health(unit))


## Forecast a single damage/healing event, preserving the same unit on collapse.
## Returns the actual HP delta of this event before a possible transformation.
func apply_health_delta(unit: TacticalCharacter, delta: int) -> int:
	if not is_living(unit):
		return 0
	var before := get_health(unit)
	var after := clampi(before + delta, 0, get_max_health(unit))
	var effect := unit_reassembly_effects.get(unit) as ReassemblePassiveEffect
	if after == 0 and not is_bone_pile(unit) and effect != null:
		unit_bone_piles[unit] = true
		unit_max_health[unit] = effect.pile_health
		unit_health[unit] = effect.pile_health
		unit_statuses[unit] = {}
		unit_stunned[unit] = false
		unit_constitutions[unit] = unit._calculate_effective_stat(UnitStat.Type.CONSTITUTION, true, false)
		unit_movement_ranges[unit] = unit._calculate_effective_stat(UnitStat.Type.MOVEMENT_RANGE, true, false)
		unit_remaining_movement[unit] = 0.0
		unit_opportunity_reactions[unit] = false
	else:
		set_health(unit, after)
	return after - before


func is_bone_pile(unit: TacticalCharacter) -> bool:
	return bool(unit_bone_piles.get(unit, false))


func is_incapacitated(unit: TacticalCharacter) -> bool:
	return is_bone_pile(unit) or is_stunned(unit)


func get_movement_range(unit: TacticalCharacter) -> float:
	return maxf(0.0, float(unit_movement_ranges.get(unit, 0.0)))


func get_remaining_movement(unit: TacticalCharacter) -> float:
	if is_incapacitated(unit):
		return 0.0
	return maxf(0.0, float(unit_remaining_movement.get(unit, 0.0)))


func reset_movement(unit: TacticalCharacter) -> void:
	if unit_movement_ranges.has(unit):
		unit_remaining_movement[unit] = (
			get_movement_range(unit)
			if is_living(unit) and not is_incapacitated(unit)
			else 0.0
		)


func spend_movement(unit: TacticalCharacter, cost: float) -> bool:
	if is_incapacitated(unit):
		return false
	var remaining := get_remaining_movement(unit)
	if cost < 0.0 or cost > remaining + GridPathfinder.COST_EPSILON:
		return false
	unit_remaining_movement[unit] = maxf(0.0, remaining - cost)
	return true


func can_use_opportunity_reaction(unit: TacticalCharacter) -> bool:
	return (
		is_living(unit)
		and not is_incapacitated(unit)
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


func get_passive_abilities(unit: TacticalCharacter) -> Array[PassiveAbilityDefinition]:
	var passives := unit.get_passive_abilities(false)
	var ids: Dictionary = {}
	for passive in passives:
		ids[passive.passive_id] = true
	for status_id in get_status_ids(unit):
		var status := get_status_state(unit, status_id)
		var definition := status.get("definition") as StatusEffectDefinition
		if definition == null or get_status_remaining(unit, status_id) <= 0 or definition.granted_passive == null:
			continue
		var passive := definition.granted_passive
		if not ids.has(passive.passive_id):
			passives.append(passive)
			ids[passive.passive_id] = true
	return passives


func expire_turn_start_statuses(unit: TacticalCharacter) -> void:
	var statuses := unit_statuses.get(unit, {}) as Dictionary
	var changed := false
	for status_id in get_status_ids(unit):
		var status := statuses[status_id] as Dictionary
		var definition := status.get("definition") as StatusEffectDefinition
		if definition == null or not definition.expires_at_turn_start:
			continue
		status.remaining_turns = int(status.remaining_turns) - 1
		changed = true
		if status.remaining_turns <= 0:
			statuses.erase(status_id)
	if changed:
		_recompute_status_stats(unit)


func get_effective_stat(unit: TacticalCharacter, stat: int) -> float:
	var definitions: Array[StatusEffectDefinition] = []
	for status_id in get_status_ids(unit):
		var definition := get_status_state(unit, status_id).get("definition") as StatusEffectDefinition
		if definition != null and get_status_remaining(unit, status_id) > 0:
			definitions.append(definition)
	return unit.calculate_stat_with_statuses(stat, definitions)


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


func get_taunt_target(unit: TacticalCharacter) -> TacticalCharacter:
	for status_id in get_status_ids(unit):
		var status := get_status_state(unit, status_id)
		var definition := status.get("definition") as StatusEffectDefinition
		var source = status.get("source_unit")
		if (
			definition != null and definition.effect == StatusEffectDefinition.Effect.TAUNT
			and int(status.get("remaining_turns", 0)) > 0
			and is_instance_valid(source) and is_living(source)
			and source.is_friendly() != unit.is_friendly()
		):
			return source
	return null


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
		added_turns,
		get_armor(target)
	)
	var statuses := unit_statuses.get(target, {}) as Dictionary
	var health_before_constitution_change := get_health(target)
	statuses[status_effect.status_id] = {
		"definition": status_effect,
		"remaining_turns": duration,
		"processed_this_turn": false,
		"source_unit": caster,
	}
	unit_statuses[target] = statuses
	_recompute_status_stats(target)
	return {
		"health_delta": (
			int(estimate.get("health_delta", 0))
			+ mini(0, get_max_health(target) - health_before_constitution_change)
		),
		"utility_hint": (
			float(estimate.get("utility_hint", 0.0)) + base_utility
		) * duration_fraction,
		"added_turns": added_turns,
		"armor_delta": int(estimate.get("armor_delta", 0)),
	}


## Evaluate the benefit of removing debuffs without restoring damage already taken.
func estimate_cleanse(caster: TacticalCharacter, target: TacticalCharacter) -> Dictionary:
	var utility := 0.0
	var removed := 0
	if is_living(target):
		for status_id in get_status_ids(target):
			var status := get_status_state(target, status_id)
			var definition := status.get("definition") as StatusEffectDefinition
			if definition == null or not definition.is_negative():
				continue
			removed += 1
			var turns := get_status_remaining(target, status_id)
			# A turn-start damage tick that already happened cannot be prevented by Cleanse.
			var pending_ticks := maxi(0, turns - (1 if bool(status.get("processed_this_turn", false)) else 0))
			var estimate := definition.estimate_for_ai(target, target, get_health(target), pending_ticks, get_armor(target))
			var fraction := float(turns) / float(maxi(1, definition.duration_turns))
			utility += maxf(0.0, -float(estimate.get("utility_hint", 0.0))) * fraction
			utility -= float(estimate.get("health_delta", 0)) + float(estimate.get("armor_delta", 0))
	if is_instance_valid(caster) and is_instance_valid(target) and caster.is_friendly() != target.is_friendly():
		utility = -utility
	return {"health_delta": 0, "armor_delta": 0, "utility_hint": utility, "removed_count": removed}


## Updates only this snapshot; callers apply the returned health delta as with other forecasts.
func forecast_cleanse(caster: TacticalCharacter, target: TacticalCharacter) -> Dictionary:
	var estimate := estimate_cleanse(caster, target)
	if int(estimate.removed_count) == 0:
		return estimate
	var statuses := unit_statuses.get(target, {}) as Dictionary
	for status_id in get_status_ids(target):
		var definition := (statuses[status_id] as Dictionary).get("definition") as StatusEffectDefinition
		if definition != null and definition.is_negative():
			statuses.erase(status_id)
	unit_statuses[target] = statuses
	_recompute_status_stats(target)
	estimate.health_delta = mini(0, get_max_health(target) - get_health(target))
	return estimate


func _recompute_status_stats(unit: TacticalCharacter) -> void:
	var definitions: Array[StatusEffectDefinition] = []
	var stunned := false
	for status_id in get_status_ids(unit):
		var definition := get_status_state(unit, status_id).get("definition") as StatusEffectDefinition
		if definition != null:
			definitions.append(definition)
			stunned = stunned or definition.blocks_actions()
	unit_stunned[unit] = stunned
	var constitution := unit.calculate_stat_with_statuses(UnitStat.Type.CONSTITUTION, definitions)
	unit_constitutions[unit] = constitution
	if not is_bone_pile(unit):
		unit_max_health[unit] = unit.calculate_max_health_for_constitution(constitution)
	unit_movement_ranges[unit] = UnitStat.get_scaling_rules().clamp_effective_movement_range(
		unit.calculate_stat_with_statuses(UnitStat.Type.MOVEMENT_RANGE, definitions)
	)
	# Stun suppresses access to movement/reactions; it does not spend the stored resources.
	unit_remaining_movement[unit] = minf(float(unit_remaining_movement.get(unit, 0.0)), get_movement_range(unit))


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
		# Defeated enemies are tactically absent; defeated friendlies retain their cells.
		if (
			is_instance_valid(unit)
			and unit != except_unit
			and (unit.is_friendly() or is_living(unit))
		):
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
