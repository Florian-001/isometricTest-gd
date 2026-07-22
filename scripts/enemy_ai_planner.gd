class_name EnemyAIPlanner
extends RefCounted

const COST_EPSILON := 0.0001
const DEFAULT_RANGED_DISTANCE := 4.0
const MeleeDeliveryScript = preload("res://scripts/melee_delivery.gd")

var ranked_candidates: Array[EnemyTurnPlan] = []
var last_planning_duration_ms := 0
var _line_of_sight := GridLineOfSight.new()


func choose_plan(
	actor: TacticalCharacter,
	units: Array[TacticalCharacter],
	pathfinder: GridPathfinder,
	targeting: AbilityTargeting,
	wall_cells: Dictionary = {}
) -> EnemyTurnPlan:
	var planning_started := Time.get_ticks_msec()
	ranked_candidates.clear()
	if (
		not is_instance_valid(actor)
		or actor.current_health <= 0
		or pathfinder == null
		or targeting == null
	):
		last_planning_duration_ms = Time.get_ticks_msec() - planning_started
		return EnemyTurnPlan.new()

	var profile := actor.enemy_ai_profile
	if profile == null:
		profile = EnemyAIProfile.new()
	var snapshot := AIBoardSnapshot.from_battle(units, pathfinder.grid_size, wall_cells)
	var candidates := _generate_candidates(
		actor,
		snapshot,
		pathfinder,
		targeting,
		profile,
		actor.remaining_movement,
		actor.ability_available,
		true,
		true
	)
	if candidates.is_empty():
		last_planning_duration_ms = Time.get_ticks_msec() - planning_started
		return EnemyTurnPlan.new()

	candidates.sort_custom(_compare_immediate_plans)
	var beam: Array[EnemyTurnPlan] = []
	var beam_size := mini(profile.lookahead_candidate_limit, candidates.size())
	for index in range(beam_size):
		beam.append(candidates[index])

	var reply_cache: Dictionary = {}
	for plan in beam:
		var best_reply := 0.0
		if profile.counterplay_discount > COST_EPSILON:
			var resulting_state := _simulate_plan(actor, plan, snapshot, targeting, profile)
			var state_key := _get_snapshot_key(resulting_state)
			if reply_cache.has(state_key):
				best_reply = float(reply_cache[state_key])
			else:
				best_reply = _get_best_friendly_reply(
					actor,
					resulting_state,
					pathfinder,
					targeting,
					profile
				)
				reply_cache[state_key] = best_reply
		plan.counterplay_score = maxf(0.0, best_reply) * profile.counterplay_discount
		plan.total_score = plan.immediate_score - plan.counterplay_score
		plan.score_breakdown["counterplay"] = plan.counterplay_score
		plan.score_breakdown["total"] = plan.total_score

	beam.sort_custom(_compare_total_plans)
	ranked_candidates = beam
	last_planning_duration_ms = Time.get_ticks_msec() - planning_started
	return beam[0] if not beam.is_empty() else EnemyTurnPlan.new()


func _generate_candidates(
	actor: TacticalCharacter,
	snapshot: AIBoardSnapshot,
	pathfinder: GridPathfinder,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile,
	movement_budget: float,
	ability_ready: bool,
	include_position: bool,
	allow_post_cast_move: bool
) -> Array[EnemyTurnPlan]:
	var candidates: Array[EnemyTurnPlan] = []
	if not snapshot.is_living(actor):
		return candidates
	var seen: Dictionary = {}
	var start := snapshot.get_cell(actor)
	var blocked := snapshot.get_blocked_cells(actor)
	var reachable := pathfinder.get_reachable(start, maxf(0.0, movement_budget), blocked)
	var reachable_cells := _sorted_cells(reachable.keys())

	var hold := EnemyTurnPlan.new()
	_finalize_plan(hold, actor, start, snapshot, targeting, profile, include_position)
	_append_unique(candidates, seen, hold, start)

	for destination in reachable_cells:
		if destination == start:
			continue
		var move_path := pathfinder.find_path(start, destination, movement_budget, blocked)
		if move_path.size() < 2:
			continue
		var move_plan := EnemyTurnPlan.new()
		move_plan.sequence = EnemyTurnPlan.Sequence.MOVE_ONLY
		move_plan.pre_cast_path = move_path
		move_plan.movement_cost = pathfinder.get_path_cost(move_path)
		_finalize_plan(move_plan, actor, start, snapshot, targeting, profile, include_position)
		_append_unique(candidates, seen, move_plan, start)

	if not ability_ready:
		return candidates

	var abilities := actor.get_abilities()
	for pre_cell in reachable_cells:
		var pre_cost: float = float(reachable.get(pre_cell, INF))
		if pre_cost > movement_budget + COST_EPSILON:
			continue
		var pre_path: Array[Vector2i] = []
		if pre_cell != start:
			pre_path = pathfinder.find_path(start, pre_cell, movement_budget, blocked)
			if pre_path.size() < 2:
				continue

		for ability_index in range(abilities.size()):
			var ability := abilities[ability_index]
			if ability == null:
				continue
			for y in range(snapshot.grid_size.y):
				for x in range(snapshot.grid_size.x):
					var target_cell := Vector2i(x, y)
					if not _is_valid_primary_target(
						actor,
						pre_cell,
						target_cell,
						ability,
						snapshot,
						targeting
					):
						continue

					var cast_state := snapshot.duplicate_state()
					cast_state.set_cell(actor, pre_cell)
					var effect_score := _forecast_ability(
						actor,
						ability,
						target_cell,
						cast_state,
						targeting,
						profile
					)
					var base_plan := _make_cast_plan(
						actor,
						start,
						pre_cell,
						pre_path,
						pre_cost,
						ability,
						ability_index,
						target_cell,
						effect_score,
						cast_state,
						targeting,
						profile,
						include_position
					)
					_append_unique(candidates, seen, base_plan, start)

					var remaining := movement_budget - pre_cost
					if (
						not allow_post_cast_move
						or remaining <= COST_EPSILON
						or not cast_state.is_living(actor)
					):
						continue
					var post_blocked := cast_state.get_blocked_cells(actor)
					var post_reachable := pathfinder.get_reachable(pre_cell, remaining, post_blocked)
					var post_cells := _get_best_post_cells(
						actor,
						start,
						pre_cell,
						post_reachable,
						cast_state,
						targeting,
						profile
					)
					var post_limit := mini(profile.post_cast_position_limit, post_cells.size())
					for post_index in range(post_limit):
						var post_cell := post_cells[post_index]
						if post_cell == pre_cell:
							continue
						var post_path := pathfinder.find_path(
							pre_cell,
							post_cell,
							remaining,
							post_blocked
						)
						if post_path.size() < 2:
							continue
						var repositioned := _make_cast_plan(
							actor,
							start,
							pre_cell,
							pre_path,
							pre_cost,
							ability,
							ability_index,
							target_cell,
							effect_score,
							cast_state,
							targeting,
							profile,
							include_position
						)
						repositioned.post_cast_path = post_path
						repositioned.movement_cost += pathfinder.get_path_cost(post_path)
						repositioned.sequence = (
							EnemyTurnPlan.Sequence.MOVE_CAST_MOVE
							if pre_cell != start
							else EnemyTurnPlan.Sequence.CAST_MOVE
						)
						_finalize_plan(
							repositioned,
							actor,
							start,
							cast_state,
							targeting,
							profile,
							include_position
						)
						_append_unique(candidates, seen, repositioned, start)

	return candidates


func _make_cast_plan(
	actor: TacticalCharacter,
	start: Vector2i,
	pre_cell: Vector2i,
	pre_path: Array[Vector2i],
	pre_cost: float,
	ability: AbilityDefinition,
	ability_index: int,
	target_cell: Vector2i,
	effect_score: float,
	cast_state: AIBoardSnapshot,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile,
	include_position: bool
) -> EnemyTurnPlan:
	var plan := EnemyTurnPlan.new()
	plan.sequence = (
		EnemyTurnPlan.Sequence.MOVE_CAST
		if pre_cell != start
		else EnemyTurnPlan.Sequence.CAST_ONLY
	)
	plan.pre_cast_path = pre_path.duplicate()
	plan.ability = ability
	plan.ability_index = ability_index
	plan.target_cell = target_cell
	plan.movement_cost = pre_cost
	plan.effect_score = effect_score
	var primary := cast_state.get_living_unit_at(target_cell)
	if primary != null:
		plan.scene_target_index = cast_state.units.find(primary)
	_finalize_plan(plan, actor, start, cast_state, targeting, profile, include_position)
	return plan


func _finalize_plan(
	plan: EnemyTurnPlan,
	actor: TacticalCharacter,
	start: Vector2i,
	snapshot: AIBoardSnapshot,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile,
	include_position: bool
) -> void:
	var end_cell := plan.get_end_cell(start)
	plan.cast_origin = plan.get_cast_cell(start)
	plan.end_cell = end_cell
	plan.position_score = (
		_score_position(actor, start, end_cell, snapshot, targeting, profile)
		if include_position
		else 0.0
	)
	plan.preferred_delivery_score = _score_preferred_delivery(plan, profile)
	plan.immediate_score = plan.effect_score + plan.position_score + plan.preferred_delivery_score
	plan.total_score = plan.immediate_score
	plan.score_breakdown = {
		"effects": plan.effect_score,
		"position": plan.position_score,
		"preferred_delivery": plan.preferred_delivery_score,
		"counterplay": 0.0,
		"total": plan.total_score,
	}


func _forecast_ability(
	caster: TacticalCharacter,
	ability: AbilityDefinition,
	target_cell: Vector2i,
	snapshot: AIBoardSnapshot,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile
) -> float:
	var caster_cell := snapshot.get_cell(caster)
	var affected_cells := targeting.get_affected_cells(
		caster_cell,
		target_cell,
		ability,
		snapshot.wall_cells
	)
	var recipients: Array[TacticalCharacter] = []
	for unit in snapshot.units:
		if (
			snapshot.is_living(unit)
			and affected_cells.has(snapshot.get_cell(unit))
			and _matches_unit_flag(caster, unit, ability)
		):
			recipients.append(unit)

	var score := 0.0
	if recipients.is_empty():
		for effect in ability.effects:
			if effect != null:
				score += effect.ai_utility_hint * profile.custom_effect_weight
		return score

	for recipient in recipients:
		for effect in ability.effects:
			if effect == null or not snapshot.is_living(recipient):
				continue
			var before := snapshot.get_health(recipient)
			var estimate := effect.estimate_for_ai(caster, recipient, before)
			var requested_delta := int(estimate.get("health_delta", 0))
			var after := clampi(before + requested_delta, 0, recipient.get_max_health())
			var actual_delta := after - before
			var is_opponent := recipient.is_friendly() != caster.is_friendly()
			if actual_delta < 0:
				var damage := float(-actual_delta)
				if is_opponent:
					score += damage * profile.damage_reward
					if after == 0 and before > 0:
						score += profile.defeat_reward
				else:
					score -= damage * profile.friendly_damage_penalty
					if after == 0 and before > 0:
						score -= profile.defeat_reward
			elif actual_delta > 0:
				var healing := float(actual_delta)
				if is_opponent:
					score -= healing * profile.enemy_healing_penalty
				else:
					score += healing * profile.healing_reward
			score += float(estimate.get("utility_hint", 0.0)) * profile.custom_effect_weight
			snapshot.set_health(recipient, after)
	return score


func _simulate_plan(
	actor: TacticalCharacter,
	plan: EnemyTurnPlan,
	initial_state: AIBoardSnapshot,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile
) -> AIBoardSnapshot:
	var result := initial_state.duplicate_state()
	var start := result.get_cell(actor)
	var cast_cell := plan.get_cast_cell(start)
	result.set_cell(actor, cast_cell)
	if plan.ability != null and result.is_living(actor):
		_forecast_ability(actor, plan.ability, plan.target_cell, result, targeting, profile)
	if result.is_living(actor):
		result.set_cell(actor, plan.get_end_cell(start))
	return result


func _get_best_friendly_reply(
	acting_enemy: TacticalCharacter,
	snapshot: AIBoardSnapshot,
	pathfinder: GridPathfinder,
	targeting: AbilityTargeting,
	enemy_profile: EnemyAIProfile
) -> float:
	var response_profile := EnemyAIProfile.new()
	response_profile.damage_reward = enemy_profile.damage_reward
	response_profile.healing_reward = enemy_profile.healing_reward
	response_profile.defeat_reward = enemy_profile.defeat_reward
	response_profile.friendly_damage_penalty = enemy_profile.friendly_damage_penalty
	response_profile.enemy_healing_penalty = enemy_profile.enemy_healing_penalty
	response_profile.custom_effect_weight = enemy_profile.custom_effect_weight
	response_profile.melee_delivery_reward = 0.0
	response_profile.ranged_delivery_reward = 0.0
	response_profile.approach_reward = 0.0
	response_profile.adjacent_reward = 0.0
	response_profile.ranged_clear_shot_reward = 0.0

	var best_reply := 0.0
	for responder in snapshot.units:
		if (
			not snapshot.is_living(responder)
			or responder.is_friendly() == acting_enemy.is_friendly()
		):
			continue
		# A reply is the terminal depth of the search, so paths and post-cast
		# destinations cannot affect its reward. Scan reachable cast origins directly
		# instead of allocating thousands of throwaway EnemyTurnPlan objects.
		var start := snapshot.get_cell(responder)
		var reachable := pathfinder.get_reachable(
			start,
			responder.get_movement_range(),
			snapshot.get_blocked_cells(responder)
		)
		var reachable_cells := _sorted_cells(reachable.keys())
		for ability in responder.get_abilities():
			if ability == null:
				continue
			var origin_sensitive := (
				ability.shape == AbilityDefinition.Shape.LINE_FROM_CASTER
				or ability.has_target_flag(AbilityDefinition.TargetFlags.SELF)
			)
			for y in range(snapshot.grid_size.y):
				for x in range(snapshot.grid_size.x):
					var target_cell := Vector2i(x, y)
					for caster_cell in reachable_cells:
						if not _is_valid_primary_target(
							responder,
							caster_cell,
							target_cell,
							ability,
							snapshot,
							targeting
						):
							continue
						var reply_state := snapshot.duplicate_state()
						reply_state.set_cell(responder, caster_cell)
						best_reply = maxf(
							best_reply,
							_forecast_ability(
								responder,
								ability,
								target_cell,
								reply_state,
								targeting,
								response_profile
							)
						)
						# Centered areas affect the same non-self recipients from every valid
						# origin. One successful origin therefore proves and scores the action.
						if not origin_sensitive:
							break
	return best_reply


func _get_snapshot_key(snapshot: AIBoardSnapshot) -> String:
	var parts: Array[String] = []
	for unit in snapshot.units:
		parts.append("%s:%s:%d" % [unit.get_instance_id(), snapshot.get_cell(unit), snapshot.get_health(unit)])
	return "|".join(parts)


func _is_valid_primary_target(
	caster: TacticalCharacter,
	caster_cell: Vector2i,
	target_cell: Vector2i,
	ability: AbilityDefinition,
	snapshot: AIBoardSnapshot,
	targeting: AbilityTargeting
) -> bool:
	if (
		target_cell.x < 0
		or target_cell.y < 0
		or target_cell.x >= snapshot.grid_size.x
		or target_cell.y >= snapshot.grid_size.y
		or snapshot.wall_cells.has(target_cell)
	):
		return false
	if targeting.get_weighted_distance(caster_cell, target_cell) > ability.range + COST_EPSILON:
		return false
	if not _line_of_sight.has_line_of_sight(caster_cell, target_cell, snapshot.wall_cells):
		return false
	if (
		ability.delivery_type == AbilityDefinition.DeliveryType.MELEE
		and not MeleeDeliveryScript.can_reach(caster_cell, target_cell, snapshot.wall_cells)
	):
		return false
	if ability.has_target_flag(AbilityDefinition.TargetFlags.CELL):
		return true
	var occupant := snapshot.get_living_unit_at(target_cell)
	return occupant != null and _matches_unit_flag(caster, occupant, ability)


func _matches_unit_flag(
	caster: TacticalCharacter,
	target: TacticalCharacter,
	ability: AbilityDefinition
) -> bool:
	if target == caster:
		return ability.has_target_flag(AbilityDefinition.TargetFlags.SELF)
	if target.is_friendly() == caster.is_friendly():
		return ability.has_target_flag(AbilityDefinition.TargetFlags.FRIEND)
	return ability.has_target_flag(AbilityDefinition.TargetFlags.ENEMY)


func _score_preferred_delivery(plan: EnemyTurnPlan, profile: EnemyAIProfile) -> float:
	if plan.ability == null or plan.effect_score <= COST_EPSILON:
		return 0.0
	if profile.behavior_style == EnemyAIProfile.BehaviorStyle.MELEE:
		return profile.melee_delivery_reward if plan.ability.delivery_type == AbilityDefinition.DeliveryType.MELEE else 0.0
	return profile.ranged_delivery_reward if plan.ability.delivery_type != AbilityDefinition.DeliveryType.MELEE else 0.0


func _score_position(
	actor: TacticalCharacter,
	start_cell: Vector2i,
	end_cell: Vector2i,
	snapshot: AIBoardSnapshot,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile
) -> float:
	var opponents := snapshot.get_living_opponents(actor)
	if opponents.is_empty():
		return 0.0
	var start_distance := _nearest_distance(start_cell, opponents, snapshot, targeting)
	var end_distance := _nearest_distance(end_cell, opponents, snapshot, targeting)
	if profile.behavior_style == EnemyAIProfile.BehaviorStyle.MELEE:
		var score := (start_distance - end_distance) * profile.approach_reward
		if end_distance <= GridPathfinder.DIAGONAL_COST + COST_EPSILON:
			score += profile.adjacent_reward
		return score

	var maximum_range := _get_maximum_ranged_range(actor)
	var preferred_distance := clampf(
		maximum_range * profile.ranged_standoff_ratio,
		minf(profile.ranged_minimum_distance, maximum_range),
		maximum_range
	)
	var ranged_score := -absf(end_distance - preferred_distance) * profile.ranged_distance_penalty
	if end_distance < profile.ranged_minimum_distance:
		ranged_score -= (profile.ranged_minimum_distance - end_distance) * profile.ranged_too_close_penalty
	if end_distance > maximum_range:
		ranged_score -= (end_distance - maximum_range) * profile.ranged_out_of_range_penalty
	if _has_clear_ranged_target(end_cell, opponents, maximum_range, snapshot, targeting):
		ranged_score += profile.ranged_clear_shot_reward
	return ranged_score


func _get_maximum_ranged_range(actor: TacticalCharacter) -> float:
	var result := 0.0
	for ability in actor.get_abilities():
		if (
			ability != null
			and ability.delivery_type != AbilityDefinition.DeliveryType.MELEE
			and (
				ability.has_target_flag(AbilityDefinition.TargetFlags.ENEMY)
				or ability.has_target_flag(AbilityDefinition.TargetFlags.CELL)
			)
		):
			result = maxf(result, ability.range)
	return result if result > COST_EPSILON else DEFAULT_RANGED_DISTANCE


func _has_clear_ranged_target(
	cell: Vector2i,
	opponents: Array[TacticalCharacter],
	maximum_range: float,
	snapshot: AIBoardSnapshot,
	targeting: AbilityTargeting
) -> bool:
	for opponent in opponents:
		var opponent_cell := snapshot.get_cell(opponent)
		if (
			targeting.get_weighted_distance(cell, opponent_cell) <= maximum_range + COST_EPSILON
			and _line_of_sight.has_line_of_sight(cell, opponent_cell, snapshot.wall_cells)
		):
			return true
	return false


func _nearest_distance(
	cell: Vector2i,
	opponents: Array[TacticalCharacter],
	snapshot: AIBoardSnapshot,
	targeting: AbilityTargeting
) -> float:
	var nearest := INF
	for opponent in opponents:
		nearest = minf(nearest, targeting.get_weighted_distance(cell, snapshot.get_cell(opponent)))
	return nearest


func _get_best_post_cells(
	actor: TacticalCharacter,
	start_cell: Vector2i,
	pre_cell: Vector2i,
	reachable: Dictionary,
	snapshot: AIBoardSnapshot,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile
) -> Array[Vector2i]:
	var ranked: Array[Dictionary] = []
	for cell: Vector2i in reachable.keys():
		if cell == pre_cell:
			continue
		ranked.append({
			"cell": cell,
			"score": _score_position(actor, start_cell, cell, snapshot, targeting, profile),
			"cost": float(reachable[cell]),
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var score_a := float(a["score"])
		var score_b := float(b["score"])
		if not is_equal_approx(score_a, score_b):
			return score_a > score_b
		var cost_a := float(a["cost"])
		var cost_b := float(b["cost"])
		if not is_equal_approx(cost_a, cost_b):
			return cost_a < cost_b
		return _cell_less(a["cell"], b["cell"])
	)
	var result: Array[Vector2i] = []
	for entry in ranked:
		result.append(entry["cell"] as Vector2i)
	return result


func _append_unique(
	candidates: Array[EnemyTurnPlan],
	seen: Dictionary,
	plan: EnemyTurnPlan,
	start: Vector2i
) -> void:
	var key := "%d|%s|%s|%d|%s" % [
		plan.sequence,
		plan.get_cast_cell(start),
		plan.get_end_cell(start),
		plan.ability_index,
		plan.target_cell,
	]
	if seen.has(key):
		return
	seen[key] = true
	candidates.append(plan)


func _sorted_cells(values: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for value in values:
		cells.append(value as Vector2i)
	cells.sort_custom(_cell_less)
	return cells


func _compare_immediate_plans(a: EnemyTurnPlan, b: EnemyTurnPlan) -> bool:
	return _plan_less(a, b, false)


func _compare_total_plans(a: EnemyTurnPlan, b: EnemyTurnPlan) -> bool:
	return _plan_less(a, b, true)


func _plan_less(a: EnemyTurnPlan, b: EnemyTurnPlan, use_total: bool) -> bool:
	var score_a := a.total_score if use_total else a.immediate_score
	var score_b := b.total_score if use_total else b.immediate_score
	if not is_equal_approx(score_a, score_b):
		return score_a > score_b
	if not is_equal_approx(a.effect_score, b.effect_score):
		return a.effect_score > b.effect_score
	if not is_equal_approx(a.preferred_delivery_score, b.preferred_delivery_score):
		return a.preferred_delivery_score > b.preferred_delivery_score
	if not is_equal_approx(a.movement_cost, b.movement_cost):
		return a.movement_cost < b.movement_cost
	if a.ability_index != b.ability_index:
		return a.ability_index < b.ability_index
	if a.scene_target_index != b.scene_target_index:
		return a.scene_target_index < b.scene_target_index
	if a.target_cell != b.target_cell:
		return _cell_less(a.target_cell, b.target_cell)
	return a.sequence < b.sequence


func _cell_less(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
