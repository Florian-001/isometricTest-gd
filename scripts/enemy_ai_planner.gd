class_name EnemyAIPlanner
extends RefCounted

const COST_EPSILON := 0.0001
const MAX_TARGETS_PER_ABILITY := 3
const MAX_AREA_CENTERS_PER_ABILITY := 2
const MAX_CANDIDATES := 32
const MAX_CAST_CANDIDATES := 12
const MAX_SAFE_ORIGIN_PROBES := 8
const EXACT_REPLY_LIMIT := 3
const FUTURE_VALUE_WEIGHT := 0.25
const SHARED_PRESSURE_WEIGHT := 0.25
const IMMEDIATE_DEFEAT_RATIO := 0.25
const SETUP_DEFEAT_RATIO := 0.125
const FRIENDLY_DAMAGE_PENALTY := 2.0
const MeleeDeliveryScript = preload("res://scripts/melee_delivery.gd")
const OpportunityAttackSystemScript = preload("res://scripts/opportunity_attack_system.gd")

var ranked_candidates: Array[EnemyTurnPlan] = []
var last_planning_duration_ms := 0
var last_candidate_generation_duration_ms := 0
var last_threat_evaluation_duration_ms := 0
var last_candidate_count := 0
var last_threat_evaluation_count := 0
var last_exact_reply_count := 0
var last_reachability_search_count := 0
var last_cache_hit_count := 0

var _line_of_sight := GridLineOfSight.new()
var _static_geometry_key := ""
var _line_of_sight_cache: Dictionary = {}
var _decision_snapshot: AIBoardSnapshot
var _decision_pathfinder: GridPathfinder
var _decision_targeting: AbilityTargeting
var _decision_profile: EnemyAIProfile
var _initiative_order: Array[TacticalCharacter] = []
var _reachability_cache: Dictionary = {}
var _quick_danger_cache: Dictionary = {}
var _future_value_cache: Dictionary = {}
var _followup_cache: Dictionary = {}
var _threat_cache: Dictionary = {}
var _plan_state_cache: Dictionary = {}


func choose_plan(
	actor: TacticalCharacter,
	units: Array[TacticalCharacter],
	pathfinder: GridPathfinder,
	targeting: AbilityTargeting,
	wall_cells: Dictionary = {},
	terrain_definitions: Dictionary = {},
	initiative_order: Array[TacticalCharacter] = []
) -> EnemyTurnPlan:
	var planning_started := Time.get_ticks_msec()
	_reset_metrics()
	if (
		not is_instance_valid(actor)
		or actor.current_health <= 0
		or pathfinder == null
		or targeting == null
	):
		last_planning_duration_ms = Time.get_ticks_msec() - planning_started
		return EnemyTurnPlan.new()

	var profile := actor.get_enemy_ai_profile()
	if profile == null:
		profile = EnemyAIProfile.new()
	var snapshot := AIBoardSnapshot.from_battle(
		units,
		pathfinder.grid_size,
		wall_cells,
		terrain_definitions
	)
	_prepare_decision(actor, snapshot, pathfinder, targeting, profile, initiative_order)

	var generation_started := Time.get_ticks_msec()
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
	last_candidate_generation_duration_ms = Time.get_ticks_msec() - generation_started
	last_candidate_count = candidates.size()
	if candidates.is_empty():
		last_planning_duration_ms = Time.get_ticks_msec() - planning_started
		return EnemyTurnPlan.new()

	_apply_coordination_scores(actor, candidates, snapshot, pathfinder, targeting, profile)
	var threat_started := Time.get_ticks_msec()
	_apply_threat_scores(actor, candidates, snapshot, pathfinder, targeting, profile)
	last_threat_evaluation_duration_ms = Time.get_ticks_msec() - threat_started

	candidates.sort_custom(_compare_immediate_plans)
	var exact_count := mini(EXACT_REPLY_LIMIT, candidates.size())
	for index in range(exact_count):
		var plan := candidates[index]
		var resulting_state := _simulate_plan(
			actor,
			plan,
			snapshot,
			targeting,
			profile,
			pathfinder
		)
		var exact_reply := _get_best_opposing_reply(
			actor,
			resulting_state,
			pathfinder,
			targeting,
			profile
		)
		last_exact_reply_count += 1
		var score_before_danger := plan.immediate_score + plan.threat_penalty
		plan.counterplay_score = maxf(0.0, exact_reply) * profile.risk_aversion
		plan.total_score = score_before_danger - plan.counterplay_score
		plan.score_breakdown["exact_reply"] = exact_reply
		plan.score_breakdown["counterplay"] = plan.counterplay_score
		plan.score_breakdown["total"] = plan.total_score

	candidates.sort_custom(_compare_total_plans)
	ranked_candidates = candidates
	last_planning_duration_ms = Time.get_ticks_msec() - planning_started
	return candidates[0]


func _reset_metrics() -> void:
	ranked_candidates.clear()
	last_planning_duration_ms = 0
	last_candidate_generation_duration_ms = 0
	last_threat_evaluation_duration_ms = 0
	last_candidate_count = 0
	last_threat_evaluation_count = 0
	last_exact_reply_count = 0
	last_reachability_search_count = 0
	last_cache_hit_count = 0


func _prepare_decision(
	actor: TacticalCharacter,
	snapshot: AIBoardSnapshot,
	pathfinder: GridPathfinder,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile,
	initiative_order: Array[TacticalCharacter]
) -> void:
	_decision_snapshot = snapshot
	_decision_pathfinder = pathfinder
	_decision_targeting = targeting
	_decision_profile = profile
	_reachability_cache.clear()
	_quick_danger_cache.clear()
	_future_value_cache.clear()
	_followup_cache.clear()
	_threat_cache.clear()
	_plan_state_cache.clear()
	_initiative_order = _resolve_initiative_order(actor, initiative_order, snapshot)
	_ensure_static_geometry(snapshot)


func _ensure_static_geometry(snapshot: AIBoardSnapshot) -> void:
	var geometry_key := "%s|%s|%s" % [
		snapshot.grid_size,
		snapshot.wall_cells.hash(),
		snapshot.terrain_definitions.hash(),
	]
	if geometry_key != _static_geometry_key:
		_static_geometry_key = geometry_key
		_line_of_sight_cache.clear()


func _ensure_decision(
	actor: TacticalCharacter,
	snapshot: AIBoardSnapshot,
	pathfinder: GridPathfinder,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile
) -> void:
	if _decision_snapshot != snapshot:
		_prepare_decision(actor, snapshot, pathfinder, targeting, profile, [])


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
	_ensure_decision(actor, snapshot, pathfinder, targeting, profile)

	var seen: Dictionary = {}
	var start := snapshot.get_cell(actor)
	var reachable_result := _get_reachability(
		actor,
		start,
		maxf(0.0, movement_budget),
		snapshot,
		pathfinder,
		_get_terrain_path_penalties(actor, snapshot, profile)
	)
	var reachable := reachable_result["costs"] as Dictionary

	var hold := EnemyTurnPlan.new()
	_finalize_plan(hold, actor, start, snapshot, targeting, profile, include_position)
	_plan_state_cache[hold] = snapshot.duplicate_state()
	_append_unique(candidates, seen, hold, start)

	var descriptors: Array[Dictionary] = []
	if ability_ready:
		var abilities := actor.get_abilities()
		for ability_index in range(abilities.size()):
			var ability := abilities[ability_index]
			if ability == null or not ability.can_be_used_by(actor):
				continue
			var target_cells := _get_relevant_target_cells(
				actor,
				ability,
				snapshot,
				targeting
			)
			for target_cell in target_cells:
				var origins := _select_cast_origins(
					actor,
					ability,
					target_cell,
					reachable,
					snapshot,
					targeting
				)
				for origin in origins:
					descriptors.append({
						"ability": ability,
						"ability_index": ability_index,
						"target": target_cell,
						"origin": origin,
						"cost": float(reachable.get(origin, INF)),
						"rough": _rough_cast_value(
							actor,
							origin,
							ability,
							target_cell,
							snapshot,
							targeting
						),
					})

	descriptors.sort_custom(_descriptor_less)
	var descriptor_limit := mini(descriptors.size(), MAX_CAST_CANDIDATES)
	for descriptor_index in range(descriptor_limit):
		var plan := _build_cast_candidate(
			actor,
			start,
			descriptors[descriptor_index],
			reachable_result,
			snapshot,
			pathfinder,
			targeting,
			profile,
			include_position
		)
		if plan != null:
			_append_unique(candidates, seen, plan, start)

	if allow_post_cast_move and candidates.size() < MAX_CANDIDATES:
		var current_cast := _get_best_current_cast(candidates)
		if current_cast != null:
			var cast_move := _build_cast_move_candidate(
				actor,
				current_cast,
				snapshot,
				pathfinder,
				targeting,
				profile,
				include_position
			)
			if cast_move != null:
				_append_unique(candidates, seen, cast_move, start)

	var has_useful_cast := false
	for plan in candidates:
		if plan.ability != null:
			has_useful_cast = true
			break
	if not has_useful_cast and candidates.size() < MAX_CANDIDATES:
		var pursue := _build_pursuit_candidate(
			actor,
			start,
			reachable_result,
			snapshot,
			pathfinder,
			targeting,
			profile,
			include_position
		)
		if pursue != null:
			_append_unique(candidates, seen, pursue, start)

	if candidates.size() < MAX_CANDIDATES and _quick_cell_danger(
		actor,
		start,
		snapshot,
		pathfinder,
		targeting,
		profile
	) > COST_EPSILON:
		var disengage := _build_disengage_candidate(
			actor,
			start,
			reachable_result,
			snapshot,
			pathfinder,
			targeting,
			profile,
			include_position
		)
		if disengage != null:
			_append_unique(candidates, seen, disengage, start)

	return candidates


func _build_cast_candidate(
	actor: TacticalCharacter,
	start: Vector2i,
	descriptor: Dictionary,
	reachable_result: Dictionary,
	snapshot: AIBoardSnapshot,
	pathfinder: GridPathfinder,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile,
	include_position: bool
) -> EnemyTurnPlan:
	var origin := descriptor["origin"] as Vector2i
	var ability := descriptor["ability"] as AbilityDefinition
	var target_cell := descriptor["target"] as Vector2i
	var pre_path: Array[Vector2i] = []
	if origin != start:
		pre_path = pathfinder.reconstruct_reachable_path(reachable_result, origin)
		if pre_path.size() < 2:
			return null
	var state := snapshot.duplicate_state()
	var terrain_score := 0.0
	var actual_path: Array[Vector2i] = []
	if not pre_path.is_empty():
		var path_forecast := _forecast_terrain_path(
			actor,
			pre_path,
			state,
			profile,
			targeting,
			pathfinder
		)
		actual_path = path_forecast["path"] as Array[Vector2i]
		terrain_score = float(path_forecast["score"])
		if (
			not state.is_living(actor)
			or actual_path.is_empty()
			or actual_path[actual_path.size() - 1] != origin
		):
			return null
	var primary := state.get_living_unit_at(target_cell)
	var ability_score := _forecast_ability(
		actor,
		ability,
		target_cell,
		state,
		targeting,
		profile
	)
	if ability_score <= COST_EPSILON:
		return null

	var plan := EnemyTurnPlan.new()
	plan.sequence = (
		EnemyTurnPlan.Sequence.MOVE_CAST
		if origin != start
		else EnemyTurnPlan.Sequence.CAST_ONLY
	)
	plan.pre_cast_path = actual_path
	plan.ability = ability
	plan.ability_index = int(descriptor["ability_index"])
	plan.target_cell = target_cell
	plan.movement_cost = pathfinder.get_path_cost(actual_path)
	plan.effect_score = ability_score + terrain_score
	plan.terrain_score = terrain_score
	if primary != null:
		plan.scene_target_index = snapshot.units.find(primary)
		var target_order_index := _initiative_order.find(primary)
		if target_order_index >= 0:
			plan.target_turn_order_index = target_order_index
	_finalize_plan(plan, actor, start, state, targeting, profile, include_position)
	_plan_state_cache[plan] = state.duplicate_state()
	return plan


func _build_cast_move_candidate(
	actor: TacticalCharacter,
	base_plan: EnemyTurnPlan,
	snapshot: AIBoardSnapshot,
	pathfinder: GridPathfinder,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile,
	include_position: bool
) -> EnemyTurnPlan:
	var start := snapshot.get_cell(actor)
	if base_plan.sequence != EnemyTurnPlan.Sequence.CAST_ONLY:
		return null
	var cast_state := _simulate_plan(actor, base_plan, snapshot, targeting, profile, pathfinder)
	if not cast_state.is_living(actor):
		return null
	var remaining := maxf(0.0, snapshot.get_remaining_movement(actor))
	if remaining <= COST_EPSILON:
		return null
	var reachability := _get_reachability(
		actor,
		start,
		remaining,
		cast_state,
		pathfinder,
		_get_terrain_path_penalties(actor, cast_state, profile)
	)
	var destination := _select_safest_destination(
		actor,
		start,
		reachability["costs"] as Dictionary,
		cast_state,
		pathfinder,
		targeting,
		profile
	)
	if destination == start:
		return null
	var path := pathfinder.reconstruct_reachable_path(reachability, destination)
	if path.size() < 2:
		return null
	var post_state := cast_state.duplicate_state()
	var forecast := _forecast_terrain_path(
		actor,
		path,
		post_state,
		profile,
		targeting,
		pathfinder
	)
	var actual_path := forecast["path"] as Array[Vector2i]
	if actual_path.size() < 2 or actual_path[actual_path.size() - 1] != destination:
		return null
	var plan := _copy_plan(base_plan)
	plan.sequence = EnemyTurnPlan.Sequence.CAST_MOVE
	plan.post_cast_path = actual_path
	plan.movement_cost = pathfinder.get_path_cost(actual_path)
	plan.terrain_score += float(forecast["score"])
	plan.effect_score += float(forecast["score"])
	_finalize_plan(plan, actor, start, post_state, targeting, profile, include_position)
	_plan_state_cache[plan] = post_state.duplicate_state()
	return plan


func _build_pursuit_candidate(
	actor: TacticalCharacter,
	start: Vector2i,
	reachability: Dictionary,
	snapshot: AIBoardSnapshot,
	pathfinder: GridPathfinder,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile,
	include_position: bool
) -> EnemyTurnPlan:
	var reachable := reachability["costs"] as Dictionary
	var current_gap := _get_cast_gap(actor, start, snapshot, targeting)
	var best_cell := start
	var best_gap := current_gap
	var best_danger := INF
	var best_cost := INF
	for cell in _sorted_cells(reachable.keys()):
		if cell == start:
			continue
		var gap := _get_cast_gap(actor, cell, snapshot, targeting)
		if gap >= current_gap - COST_EPSILON:
			continue
		var danger := _quick_cell_danger(actor, cell, snapshot, pathfinder, targeting, profile)
		var cost := float(reachable[cell])
		if (
			gap < best_gap - COST_EPSILON
			or (
				is_equal_approx(gap, best_gap)
				and (
					danger < best_danger - COST_EPSILON
					or (
						is_equal_approx(danger, best_danger)
						and (
							cost < best_cost - COST_EPSILON
							or (is_equal_approx(cost, best_cost) and _cell_less(cell, best_cell))
						)
					)
				)
			)
		):
			best_cell = cell
			best_gap = gap
			best_danger = danger
			best_cost = cost
	return _build_move_candidate(
		actor,
		start,
		best_cell,
		reachability,
		snapshot,
		pathfinder,
		targeting,
		profile,
		include_position
	)


func _build_disengage_candidate(
	actor: TacticalCharacter,
	start: Vector2i,
	reachability: Dictionary,
	snapshot: AIBoardSnapshot,
	pathfinder: GridPathfinder,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile,
	include_position: bool
) -> EnemyTurnPlan:
	var destination := _select_safest_destination(
		actor,
		start,
		reachability["costs"] as Dictionary,
		snapshot,
		pathfinder,
		targeting,
		profile
	)
	return _build_move_candidate(
		actor,
		start,
		destination,
		reachability,
		snapshot,
		pathfinder,
		targeting,
		profile,
		include_position
	)


func _build_move_candidate(
	actor: TacticalCharacter,
	start: Vector2i,
	destination: Vector2i,
	reachability: Dictionary,
	snapshot: AIBoardSnapshot,
	pathfinder: GridPathfinder,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile,
	include_position: bool
) -> EnemyTurnPlan:
	if destination == start:
		return null
	var path := pathfinder.reconstruct_reachable_path(reachability, destination)
	if path.size() < 2:
		return null
	var state := snapshot.duplicate_state()
	var forecast := _forecast_terrain_path(
		actor,
		path,
		state,
		profile,
		targeting,
		pathfinder
	)
	var actual_path := forecast["path"] as Array[Vector2i]
	if actual_path.size() < 2 or actual_path[actual_path.size() - 1] != destination:
		return null
	var plan := EnemyTurnPlan.new()
	plan.sequence = EnemyTurnPlan.Sequence.MOVE_ONLY
	plan.pre_cast_path = actual_path
	plan.movement_cost = pathfinder.get_path_cost(actual_path)
	plan.terrain_score = float(forecast["score"])
	plan.effect_score = plan.terrain_score
	_finalize_plan(plan, actor, start, state, targeting, profile, include_position)
	_plan_state_cache[plan] = state.duplicate_state()
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
	var future_score := (
		_estimate_future_value(actor, end_cell, snapshot, targeting) * FUTURE_VALUE_WEIGHT
		if include_position and snapshot.is_living(actor)
		else 0.0
	)
	var safety_gain := 0.0
	if (
		include_position
		and snapshot.is_living(actor)
		and _decision_pathfinder != null
		and _decision_targeting != null
	):
		safety_gain = maxf(
			0.0,
			_quick_cell_danger(
				actor,
				start,
				snapshot,
				_decision_pathfinder,
				_decision_targeting,
				profile
			) - _quick_cell_danger(
				actor,
				end_cell,
				snapshot,
				_decision_pathfinder,
				_decision_targeting,
				profile
			)
		) * FUTURE_VALUE_WEIGHT * profile.risk_aversion
	plan.position_score = future_score + safety_gain
	plan.preferred_delivery_score = 0.0
	plan.immediate_score = plan.effect_score + plan.position_score + plan.coordination_score
	plan.total_score = plan.immediate_score
	plan.score_breakdown = {
		"effects": plan.effect_score,
		"terrain": plan.terrain_score,
		"future": plan.position_score,
		"coordination": plan.coordination_score,
		"threat": 0.0,
		"threat_score": 0.0,
		"threat_penalty": 0.0,
		"exact_reply": 0.0,
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
		for additional_effect in ability.effects:
			if ability.should_apply_additional_effect(additional_effect):
				score += additional_effect.ai_utility_hint
		return score

	for recipient in recipients:
		if ability.has_primary_effect() and snapshot.is_living(recipient):
			score += _score_effect_estimate(
				caster,
				recipient,
				ability.estimate_primary_effect_for_ai(
					caster,
					recipient,
					snapshot.get_health(recipient),
					false
				),
				profile,
				snapshot
			)
			if snapshot.is_living(recipient) and ability.status_effect != null:
				score += _score_effect_estimate(
					caster,
					recipient,
					snapshot.forecast_status_application(
						caster,
						recipient,
						ability.status_effect
					),
					profile,
					snapshot
				)
		for additional_effect in ability.effects:
			if (
				not snapshot.is_living(recipient)
				or not ability.should_apply_additional_effect(additional_effect)
			):
				continue
			var before := snapshot.get_health(recipient)
			var estimate: Dictionary
			if additional_effect is ApplyStatusEffectDefinition:
				var status_application := additional_effect as ApplyStatusEffectDefinition
				estimate = snapshot.forecast_status_application(
					caster,
					recipient,
					status_application.status_effect,
					status_application.ai_utility_hint
				)
			elif additional_effect is DamageEffectDefinition:
				estimate = (additional_effect as DamageEffectDefinition).estimate_for_ability(
					caster,
					recipient,
					before,
					ability
				)
			else:
				estimate = additional_effect.estimate_for_ai(caster, recipient, before)
			score += _score_effect_estimate(caster, recipient, estimate, profile, snapshot)
		var weapon_status := ability.get_weapon_status_effect(caster)
		if snapshot.is_living(recipient) and weapon_status != null:
			score += _score_effect_estimate(
				caster,
				recipient,
				snapshot.forecast_status_application(caster, recipient, weapon_status),
				profile,
				snapshot
			)
	return score


func _score_effect_estimate(
	caster: TacticalCharacter,
	recipient: TacticalCharacter,
	estimate: Dictionary,
	_profile: EnemyAIProfile,
	snapshot: AIBoardSnapshot
) -> float:
	var before := snapshot.get_health(recipient)
	var after := clampi(
		before + int(estimate.get("health_delta", 0)),
		0,
		recipient.get_max_health()
	)
	var actual_delta := after - before
	var is_opponent := recipient.is_friendly() != caster.is_friendly()
	var score := 0.0
	if actual_delta < 0:
		var damage := float(-actual_delta)
		if is_opponent:
			score += damage
			if after == 0 and before > 0:
				score += recipient.get_max_health() * IMMEDIATE_DEFEAT_RATIO
		else:
			score -= damage * FRIENDLY_DAMAGE_PENALTY
			if after == 0 and before > 0:
				score -= recipient.get_max_health() * IMMEDIATE_DEFEAT_RATIO
	elif actual_delta > 0:
		var healing := float(actual_delta)
		if is_opponent:
			score -= healing
		else:
			var missing_ratio := (
				float(recipient.get_max_health() - before)
				/ float(maxi(1, recipient.get_max_health()))
			)
			score += healing * missing_ratio
	score += float(estimate.get("utility_hint", 0.0))
	snapshot.set_health(recipient, after)
	return score


func _apply_coordination_scores(
	actor: TacticalCharacter,
	candidates: Array[EnemyTurnPlan],
	initial_state: AIBoardSnapshot,
	pathfinder: GridPathfinder,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile
) -> void:
	for plan in candidates:
		if plan.ability == null:
			continue
		var result := _simulate_plan(actor, plan, initial_state, targeting, profile, pathfinder)
		var coordination := 0.0
		for target in initial_state.get_living_opponents(actor):
			var before := initial_state.get_health(target)
			var remaining := result.get_health(target)
			var actor_damage := maxi(0, before - remaining)
			if actor_damage <= 0 or remaining <= 0:
				continue
			var followup := _get_allied_followup(
				actor,
				target,
				initial_state,
				pathfinder,
				targeting,
				profile
			)
			var followup_value := maxf(0.0, float(followup.get("value", 0.0)))
			var followup_damage := maxi(0, int(followup.get("damage", 0)))
			coordination += SHARED_PRESSURE_WEIGHT * minf(followup_value, float(remaining))
			if actor_damage < before and followup_damage >= remaining:
				coordination += target.get_max_health() * SETUP_DEFEAT_RATIO
		plan.coordination_score = coordination
		plan.immediate_score += coordination
		plan.total_score = plan.immediate_score
		plan.score_breakdown["coordination"] = coordination
		plan.score_breakdown["total"] = plan.total_score


func _get_allied_followup(
	actor: TacticalCharacter,
	target: TacticalCharacter,
	snapshot: AIBoardSnapshot,
	pathfinder: GridPathfinder,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile
) -> Dictionary:
	var key := "%s|%s" % [actor.get_instance_id(), target.get_instance_id()]
	if _followup_cache.has(key):
		last_cache_hit_count += 1
		return (_followup_cache[key] as Dictionary).duplicate()
	var total_damage := 0
	var total_value := 0.0
	for ally in _get_followup_allies_before_target(actor, target, snapshot):
		var estimate := _estimate_unit_action_against_target(
			ally,
			target,
			snapshot,
			pathfinder,
			targeting,
			profile,
			true
		)
		total_damage += maxi(0, int(estimate.get("damage", 0)))
		total_value += maxf(0.0, float(estimate.get("value", 0.0)))
	var result := {"damage": total_damage, "value": total_value}
	_followup_cache[key] = result
	return result.duplicate()


func _get_followup_allies_before_target(
	actor: TacticalCharacter,
	target: TacticalCharacter,
	snapshot: AIBoardSnapshot
) -> Array[TacticalCharacter]:
	var result: Array[TacticalCharacter] = []
	if _initiative_order.is_empty():
		return result
	var actor_index := _initiative_order.find(actor)
	if actor_index < 0:
		return result
	for offset in range(1, _initiative_order.size() + 1):
		var unit := _initiative_order[(actor_index + offset) % _initiative_order.size()]
		if unit == target:
			break
		if (
			unit != actor
			and snapshot.is_living(unit)
			and unit.is_friendly() == actor.is_friendly()
		):
			result.append(unit)
	return result


func _apply_threat_scores(
	actor: TacticalCharacter,
	candidates: Array[EnemyTurnPlan],
	initial_state: AIBoardSnapshot,
	pathfinder: GridPathfinder,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile
) -> void:
	for plan in candidates:
		var resulting_state := _simulate_plan(
			actor,
			plan,
			initial_state,
			targeting,
			profile,
			pathfinder
		)
		var state_key := _get_snapshot_key(resulting_state)
		var threat_score := 0.0
		if _threat_cache.has(state_key):
			last_cache_hit_count += 1
			threat_score = float(_threat_cache[state_key])
		else:
			threat_score = _estimate_incoming_threat(
				actor,
				resulting_state,
				pathfinder,
				targeting,
				profile
			)
			_threat_cache[state_key] = threat_score
			last_threat_evaluation_count += 1
		plan.threat_score = threat_score
		plan.threat_penalty = threat_score * profile.risk_aversion
		plan.immediate_score -= plan.threat_penalty
		plan.total_score = plan.immediate_score
		plan.score_breakdown["threat"] = plan.threat_penalty
		plan.score_breakdown["threat_score"] = plan.threat_score
		plan.score_breakdown["threat_penalty"] = plan.threat_penalty
		plan.score_breakdown["total"] = plan.total_score


func _estimate_incoming_threat(
	actor: TacticalCharacter,
	snapshot: AIBoardSnapshot,
	pathfinder: GridPathfinder,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile,
	_reachable_cache: Dictionary = {}
) -> float:
	if not snapshot.is_living(actor):
		return 0.0
	_ensure_static_geometry(snapshot)
	var best_threat := 0.0
	for responder in snapshot.get_living_opponents(actor):
		var estimate := _estimate_unit_action_against_target(
			responder,
			actor,
			snapshot,
			pathfinder,
			targeting,
			profile,
			false
		)
		best_threat = maxf(best_threat, float(estimate.get("score", 0.0)))
	return best_threat


func _estimate_unit_action_against_target(
	unit: TacticalCharacter,
	target: TacticalCharacter,
	snapshot: AIBoardSnapshot,
	pathfinder: GridPathfinder,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile,
	forecast_path: bool
) -> Dictionary:
	if not snapshot.is_living(unit) or not snapshot.is_living(target):
		return {"score": 0.0, "damage": 0, "value": 0.0}
	var usable_abilities: Array[AbilityDefinition] = []
	for ability in unit.get_abilities():
		if (
			ability != null
			and ability.can_be_used_by(unit)
			and (
				ability.has_target_flag(AbilityDefinition.TargetFlags.ENEMY)
				or ability.has_target_flag(AbilityDefinition.TargetFlags.CELL)
			)
		):
			usable_abilities.append(ability)
	if usable_abilities.is_empty():
		return {"score": 0.0, "damage": 0, "value": 0.0, "movement_cost": 0.0}
	var working_state := snapshot.duplicate_state()
	working_state.reset_movement(unit)
	var start := working_state.get_cell(unit)
	var reachability := _get_reachability(
		unit,
		start,
		working_state.get_movement_range(unit),
		working_state,
		pathfinder,
		_get_terrain_path_penalties(unit, working_state, profile),
		working_state.get_cell(target)
	)
	var reachable := reachability["costs"] as Dictionary
	var target_cell := working_state.get_cell(target)
	var best := {"score": 0.0, "damage": 0, "value": 0.0, "movement_cost": 0.0}
	for ability in usable_abilities:
		var origin := _get_cheapest_valid_origin(
			unit,
			ability,
			target_cell,
			reachable,
			working_state,
			targeting
		)
		if origin == Vector2i(-1, -1):
			continue
		var action_state := working_state.duplicate_state()
		if origin != start:
			if forecast_path:
				var path := pathfinder.reconstruct_reachable_path(reachability, origin)
				var path_result := _forecast_terrain_path(
					unit,
					path,
					action_state,
					profile,
					targeting,
					pathfinder
				)
				var actual_path := path_result["path"] as Array[Vector2i]
				if (
					not action_state.is_living(unit)
					or actual_path.is_empty()
					or actual_path[actual_path.size() - 1] != origin
				):
					continue
			else:
				action_state.set_cell(unit, origin)
		var before := action_state.get_health(target)
		var score := _forecast_ability(
			unit,
			ability,
			target_cell,
			action_state,
			targeting,
			profile
		)
		var after := action_state.get_health(target)
		var damage := maxi(0, before - after)
		var defeat_bonus := (
			target.get_max_health() * IMMEDIATE_DEFEAT_RATIO
			if after == 0 and before > 0
			else 0.0
		)
		var value := maxf(0.0, score - defeat_bonus)
		if score > float(best["score"]) + COST_EPSILON:
			best = {
				"score": score,
				"damage": damage,
				"value": value,
				"movement_cost": float(reachable.get(origin, 0.0)),
			}
	return best


func _get_best_opposing_reply(
	acting_unit: TacticalCharacter,
	snapshot: AIBoardSnapshot,
	pathfinder: GridPathfinder,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile
) -> float:
	var best_reply := 0.0
	for responder in snapshot.get_living_opponents(acting_unit):
		var turn_state := snapshot.duplicate_state()
		var turn_start_score := _forecast_terrain_trigger(
			responder,
			TileTriggeredEffectDefinition.Trigger.TURN_START,
			turn_state,
			profile
		)
		if not turn_state.is_living(responder):
			continue
		turn_state.reset_movement(responder)
		best_reply = maxf(
			best_reply,
			turn_start_score + _estimate_best_exact_action(
				responder,
				turn_state,
				pathfinder,
				targeting,
				profile
			)
		)
	return best_reply


func _estimate_best_exact_action(
	unit: TacticalCharacter,
	snapshot: AIBoardSnapshot,
	pathfinder: GridPathfinder,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile
) -> float:
	var abilities: Array[AbilityDefinition] = []
	for ability in unit.get_abilities():
		if ability != null and ability.can_be_used_by(unit):
			abilities.append(ability)
	if abilities.is_empty():
		return 0.0
	var start := snapshot.get_cell(unit)
	var reachability := _get_reachability(
		unit,
		start,
		snapshot.get_movement_range(unit),
		snapshot,
		pathfinder,
		_get_terrain_path_penalties(unit, snapshot, profile)
	)
	var reachable := reachability["costs"] as Dictionary
	var best := 0.0
	for ability in abilities:
		for target_cell in _get_relevant_target_cells(unit, ability, snapshot, targeting):
			var origin := _get_cheapest_valid_origin(
				unit,
				ability,
				target_cell,
				reachable,
				snapshot,
				targeting
			)
			if origin == Vector2i(-1, -1):
				continue
			var action_state := snapshot.duplicate_state()
			var path_score := 0.0
			if origin != start:
				var path := pathfinder.reconstruct_reachable_path(reachability, origin)
				var path_result := _forecast_terrain_path(
					unit,
					path,
					action_state,
					profile,
					targeting,
					pathfinder
				)
				var actual_path := path_result["path"] as Array[Vector2i]
				if (
					not action_state.is_living(unit)
					or actual_path.is_empty()
					or actual_path[actual_path.size() - 1] != origin
				):
					continue
				path_score = float(path_result["score"])
			best = maxf(
				best,
				path_score + _forecast_ability(
					unit,
					ability,
					target_cell,
					action_state,
					targeting,
					profile
				)
			)
	return best


## Compatibility alias retained for tests and developer tooling written against the old name.
func _get_best_friendly_reply(
	acting_enemy: TacticalCharacter,
	snapshot: AIBoardSnapshot,
	pathfinder: GridPathfinder,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile
) -> float:
	return _get_best_opposing_reply(acting_enemy, snapshot, pathfinder, targeting, profile)


func _simulate_plan(
	actor: TacticalCharacter,
	plan: EnemyTurnPlan,
	initial_state: AIBoardSnapshot,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile,
	pathfinder: GridPathfinder
) -> AIBoardSnapshot:
	if initial_state == _decision_snapshot and _plan_state_cache.has(plan):
		last_cache_hit_count += 1
		return (_plan_state_cache[plan] as AIBoardSnapshot).duplicate_state()
	var result := initial_state.duplicate_state()
	_forecast_terrain_path(actor, plan.pre_cast_path, result, profile, targeting, pathfinder)
	if plan.ability != null and result.is_living(actor):
		_forecast_ability(actor, plan.ability, plan.target_cell, result, targeting, profile)
	if result.is_living(actor):
		_forecast_terrain_path(actor, plan.post_cast_path, result, profile, targeting, pathfinder)
	return result


func _forecast_terrain_path(
	unit: TacticalCharacter,
	path: Array[Vector2i],
	snapshot: AIBoardSnapshot,
	profile: EnemyAIProfile,
	targeting: AbilityTargeting,
	pathfinder: GridPathfinder
) -> Dictionary:
	var traversed: Array[Vector2i] = []
	var score := 0.0
	if path.is_empty():
		return {"path": traversed, "score": score}
	traversed.append(path[0])
	for index in range(1, path.size()):
		if not snapshot.is_living(unit):
			break
		score += _forecast_opportunity_attacks(
			unit,
			path[index - 1],
			path[index],
			snapshot,
			targeting,
			profile
		)
		if not snapshot.is_living(unit):
			break
		if not snapshot.spend_movement(
			unit,
			pathfinder.get_step_cost(path[index - 1], path[index])
		):
			break
		snapshot.set_cell(unit, path[index])
		traversed.append(path[index])
		score += _forecast_terrain_trigger(
			unit,
			TileTriggeredEffectDefinition.Trigger.ENTER,
			snapshot,
			profile
		)
	return {"path": traversed, "score": score}


func _forecast_opportunity_attacks(
	mover: TacticalCharacter,
	current_cell: Vector2i,
	next_cell: Vector2i,
	snapshot: AIBoardSnapshot,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile
) -> float:
	var score := 0.0
	var ordered_units := OpportunityAttackSystemScript.get_initiative_order(snapshot.units)
	for attacker in ordered_units:
		if (
			attacker == mover
			or not snapshot.is_living(attacker)
			or not snapshot.is_living(mover)
			or attacker.is_friendly() == mover.is_friendly()
			or not snapshot.can_use_opportunity_reaction(attacker)
			or not OpportunityAttackSystemScript.is_leaving_reach(
				snapshot.get_cell(attacker),
				current_cell,
				next_cell,
				snapshot.wall_cells
			)
		):
			continue
		var ability := OpportunityAttackSystemScript.get_opportunity_attack_ability(attacker)
		if (
			ability == null
			or not _is_valid_primary_target(
				attacker,
				snapshot.get_cell(attacker),
				current_cell,
				ability,
				snapshot,
				targeting
			)
			or not snapshot.spend_opportunity_reaction(attacker)
		):
			continue
		score -= _forecast_ability(
			attacker,
			ability,
			current_cell,
			snapshot,
			targeting,
			profile
		)
	return score


func _forecast_terrain_trigger(
	unit: TacticalCharacter,
	trigger: TileTriggeredEffectDefinition.Trigger,
	snapshot: AIBoardSnapshot,
	profile: EnemyAIProfile
) -> float:
	if not snapshot.is_living(unit):
		return 0.0
	var definition := snapshot.get_terrain(snapshot.get_cell(unit))
	if definition == null:
		return 0.0
	var score := 0.0
	if definition.status_applies_on(trigger):
		score += _score_terrain_estimate(
			unit,
			snapshot.forecast_status_application(null, unit, definition.status_effect),
			snapshot,
			profile
		)
	for triggered_effect in definition.effects:
		if (
			not snapshot.is_living(unit)
			or not definition.should_apply_additional_effect(triggered_effect)
			or not triggered_effect.applies_on(trigger)
			or triggered_effect.effect == null
		):
			continue
		var effect := triggered_effect.effect
		var estimate: Dictionary
		if effect is ApplyStatusEffectDefinition:
			var status_application := effect as ApplyStatusEffectDefinition
			estimate = snapshot.forecast_status_application(
				null,
				unit,
				status_application.status_effect,
				status_application.ai_utility_hint
			)
		else:
			estimate = effect.estimate_for_ai(null, unit, snapshot.get_health(unit))
		estimate["utility_hint"] = (
			float(estimate.get("utility_hint", 0.0))
			+ triggered_effect.occupant_ai_utility
		)
		score += _score_terrain_estimate(unit, estimate, snapshot, profile)
	return score


func _score_terrain_estimate(
	unit: TacticalCharacter,
	estimate: Dictionary,
	snapshot: AIBoardSnapshot,
	_profile: EnemyAIProfile
) -> float:
	var before := snapshot.get_health(unit)
	var after := clampi(
		before + int(estimate.get("health_delta", 0)),
		0,
		unit.get_max_health()
	)
	snapshot.set_health(unit, after)
	var score := float(estimate.get("utility_hint", 0.0))
	if after < before:
		score -= float(before - after) * FRIENDLY_DAMAGE_PENALTY
		if after == 0:
			score -= unit.get_max_health() * IMMEDIATE_DEFEAT_RATIO
	elif after > before:
		var missing_ratio := (
			float(unit.get_max_health() - before)
			/ float(maxi(1, unit.get_max_health()))
		)
		score += float(after - before) * missing_ratio
	return score


func _get_terrain_path_penalties(
	unit: TacticalCharacter,
	snapshot: AIBoardSnapshot,
	profile: EnemyAIProfile
) -> Dictionary:
	var result: Dictionary = {}
	for cell: Vector2i in snapshot.terrain_definitions:
		var probe := snapshot.duplicate_state()
		probe.set_cell(unit, cell)
		var score := _forecast_terrain_trigger(
			unit,
			TileTriggeredEffectDefinition.Trigger.ENTER,
			probe,
			profile
		)
		if score < -COST_EPSILON:
			result[cell] = -score
	return result


func _get_relevant_target_cells(
	caster: TacticalCharacter,
	ability: AbilityDefinition,
	snapshot: AIBoardSnapshot,
	targeting: AbilityTargeting
) -> Array[Vector2i]:
	var ranked_units: Array[TacticalCharacter] = []
	for unit in snapshot.units:
		if not snapshot.is_living(unit) or not _is_relevant_candidate_unit(caster, unit, ability):
			continue
		ranked_units.append(unit)
	ranked_units.sort_custom(func(a: TacticalCharacter, b: TacticalCharacter) -> bool:
		var priority_a := _rough_unit_priority(caster, a, ability, snapshot)
		var priority_b := _rough_unit_priority(caster, b, ability, snapshot)
		if not is_equal_approx(priority_a, priority_b):
			return priority_a > priority_b
		return snapshot.units.find(a) < snapshot.units.find(b)
	)

	var result: Array[Vector2i] = []
	var unit_limit := mini(MAX_TARGETS_PER_ABILITY, ranked_units.size())
	for index in range(unit_limit):
		_append_cell_unique(result, snapshot.get_cell(ranked_units[index]), snapshot)

	if ability.has_target_flag(AbilityDefinition.TargetFlags.CELL) or ability.area_of_effect > 1:
		var centers: Array[Vector2i] = []
		for index in range(unit_limit):
			_append_cell_unique(centers, snapshot.get_cell(ranked_units[index]), snapshot)
		for first in range(unit_limit):
			for second in range(first + 1, unit_limit):
				var a := snapshot.get_cell(ranked_units[first])
				var b := snapshot.get_cell(ranked_units[second])
				_append_cell_unique(
					centers,
					Vector2i(roundi((a.x + b.x) * 0.5), roundi((a.y + b.y) * 0.5)),
					snapshot
				)
		centers.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var value_a := _rough_cast_value(caster, snapshot.get_cell(caster), ability, a, snapshot, targeting)
			var value_b := _rough_cast_value(caster, snapshot.get_cell(caster), ability, b, snapshot, targeting)
			if not is_equal_approx(value_a, value_b):
				return value_a > value_b
			return _cell_less(a, b)
		)
		var added_centers := 0
		for center in centers:
			if result.has(center):
				continue
			result.append(center)
			added_centers += 1
			if added_centers >= MAX_AREA_CENTERS_PER_ABILITY:
				break
	return result


func _is_relevant_candidate_unit(
	caster: TacticalCharacter,
	unit: TacticalCharacter,
	ability: AbilityDefinition
) -> bool:
	if _matches_unit_flag(caster, unit, ability):
		return true
	if not ability.has_target_flag(AbilityDefinition.TargetFlags.CELL):
		return false
	if ability.effect == AbilityDefinition.PrimaryEffect.HEAL:
		return unit.is_friendly() == caster.is_friendly()
	return unit.is_friendly() != caster.is_friendly()


func _rough_unit_priority(
	caster: TacticalCharacter,
	target: TacticalCharacter,
	ability: AbilityDefinition,
	snapshot: AIBoardSnapshot
) -> float:
	var health := snapshot.get_health(target)
	var score := 0.0
	if ability.effect == AbilityDefinition.PrimaryEffect.DAMAGE:
		var damage := mini(health, ability.calculate_primary_effect_amount(caster))
		score += damage
		if damage >= health:
			score += target.get_max_health() * IMMEDIATE_DEFEAT_RATIO
	elif ability.effect == AbilityDefinition.PrimaryEffect.HEAL:
		var healing := mini(
			target.get_max_health() - health,
			ability.calculate_primary_effect_amount(caster)
		)
		var missing_ratio := (
			float(target.get_max_health() - health)
			/ float(maxi(1, target.get_max_health()))
		)
		score += healing * missing_ratio
	if ability.status_effect != null:
		score += float(
			ability.status_effect.estimate_for_ai(caster, target, health).get("utility_hint", 0.0)
		)
	return score


func _rough_cast_value(
	caster: TacticalCharacter,
	caster_cell: Vector2i,
	ability: AbilityDefinition,
	target_cell: Vector2i,
	snapshot: AIBoardSnapshot,
	targeting: AbilityTargeting
) -> float:
	var affected_cells := targeting.get_affected_cells(
		caster_cell,
		target_cell,
		ability,
		snapshot.wall_cells
	)
	var score := 0.0
	var recipients := 0
	for unit in snapshot.units:
		if (
			not snapshot.is_living(unit)
			or not affected_cells.has(snapshot.get_cell(unit))
			or not _matches_unit_flag(caster, unit, ability)
		):
			continue
		recipients += 1
		var value := _rough_unit_priority(caster, unit, ability, snapshot)
		score += value if unit.is_friendly() != caster.is_friendly() or ability.effect != AbilityDefinition.PrimaryEffect.DAMAGE else -value * FRIENDLY_DAMAGE_PENALTY
		for effect in ability.effects:
			if ability.should_apply_additional_effect(effect):
				score += effect.ai_utility_hint
	if recipients == 0:
		for effect in ability.effects:
			if ability.should_apply_additional_effect(effect):
				score += effect.ai_utility_hint
	return score


func _select_cast_origins(
	caster: TacticalCharacter,
	ability: AbilityDefinition,
	target_cell: Vector2i,
	reachable: Dictionary,
	snapshot: AIBoardSnapshot,
	targeting: AbilityTargeting
) -> Array[Vector2i]:
	var valid: Array[Vector2i] = []
	for cell in _sorted_cells(reachable.keys()):
		if _is_valid_primary_target(caster, cell, target_cell, ability, snapshot, targeting):
			valid.append(cell)
	if valid.is_empty():
		return valid
	var cheapest := valid[0]
	for cell in valid:
		var cost := float(reachable[cell])
		var cheapest_cost := float(reachable[cheapest])
		if cost < cheapest_cost - COST_EPSILON or (is_equal_approx(cost, cheapest_cost) and _cell_less(cell, cheapest)):
			cheapest = cell
	var safest := cheapest
	var safest_danger := INF
	var danger_probes: Array[Vector2i] = []
	if _has_usable_hostile_ability(caster, snapshot):
		danger_probes = valid.duplicate()
		danger_probes.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var distance_a := _nearest_opponent_distance(caster, a, snapshot, targeting)
			var distance_b := _nearest_opponent_distance(caster, b, snapshot, targeting)
			if not is_equal_approx(distance_a, distance_b):
				return distance_a > distance_b
			var cost_a := float(reachable[a])
			var cost_b := float(reachable[b])
			if not is_equal_approx(cost_a, cost_b):
				return cost_a < cost_b
			return _cell_less(a, b)
		)
		if danger_probes.size() > MAX_SAFE_ORIGIN_PROBES:
			danger_probes.resize(MAX_SAFE_ORIGIN_PROBES)
		if not danger_probes.has(cheapest):
			danger_probes.append(cheapest)
		var current := snapshot.get_cell(caster)
		if valid.has(current) and not danger_probes.has(current):
			danger_probes.append(current)
	else:
		danger_probes.append(cheapest)
	for cell in danger_probes:
		var danger := _quick_cell_danger(
			caster,
			cell,
			snapshot,
			_decision_pathfinder,
			targeting,
			_decision_profile
		)
		if (
			danger < safest_danger - COST_EPSILON
			or (
				is_equal_approx(danger, safest_danger)
				and (
					float(reachable[cell]) < float(reachable[safest]) - COST_EPSILON
					or (
						is_equal_approx(float(reachable[cell]), float(reachable[safest]))
						and _cell_less(cell, safest)
					)
				)
			)
		):
			safest = cell
			safest_danger = danger
	var result: Array[Vector2i] = []
	var start := snapshot.get_cell(caster)
	if valid.has(start):
		result.append(start)
	if not result.has(cheapest):
		result.append(cheapest)
	if not result.has(safest):
		result.append(safest)
	return result


func _has_usable_hostile_ability(actor: TacticalCharacter, snapshot: AIBoardSnapshot) -> bool:
	for opponent in snapshot.get_living_opponents(actor):
		for ability in opponent.get_abilities():
			if (
				ability != null
				and ability.can_be_used_by(opponent)
				and (
					ability.has_target_flag(AbilityDefinition.TargetFlags.ENEMY)
					or ability.has_target_flag(AbilityDefinition.TargetFlags.CELL)
				)
			):
				return true
	return false


func _nearest_opponent_distance(
	actor: TacticalCharacter,
	cell: Vector2i,
	snapshot: AIBoardSnapshot,
	targeting: AbilityTargeting
) -> float:
	var nearest := INF
	for opponent in snapshot.get_living_opponents(actor):
		nearest = minf(
			nearest,
			targeting.get_weighted_distance(cell, snapshot.get_cell(opponent))
		)
	return nearest


func _get_cheapest_valid_origin(
	caster: TacticalCharacter,
	ability: AbilityDefinition,
	target_cell: Vector2i,
	reachable: Dictionary,
	snapshot: AIBoardSnapshot,
	targeting: AbilityTargeting
) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_cost := INF
	for cell in _sorted_cells(reachable.keys()):
		if cell == target_cell:
			continue
		if not _is_valid_primary_target(caster, cell, target_cell, ability, snapshot, targeting):
			continue
		var cost := float(reachable[cell])
		if cost < best_cost - COST_EPSILON:
			best = cell
			best_cost = cost
	return best


func _select_safest_destination(
	actor: TacticalCharacter,
	start: Vector2i,
	reachable: Dictionary,
	snapshot: AIBoardSnapshot,
	pathfinder: GridPathfinder,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile
) -> Vector2i:
	var best := start
	var best_score := _quick_position_value(actor, start, snapshot, pathfinder, targeting, profile)
	var best_cost := 0.0
	for cell in _sorted_cells(reachable.keys()):
		if cell == start:
			continue
		var score := _quick_position_value(actor, cell, snapshot, pathfinder, targeting, profile)
		var cost := float(reachable[cell])
		if (
			score > best_score + COST_EPSILON
			or (
				is_equal_approx(score, best_score)
				and (
					cost < best_cost - COST_EPSILON
					or (is_equal_approx(cost, best_cost) and _cell_less(cell, best))
				)
			)
		):
			best = cell
			best_score = score
			best_cost = cost
	return best


func _quick_position_value(
	actor: TacticalCharacter,
	cell: Vector2i,
	snapshot: AIBoardSnapshot,
	pathfinder: GridPathfinder,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile
) -> float:
	var future := _estimate_immediate_cast_value_from_cell(actor, cell, snapshot, targeting)
	var danger := _quick_cell_danger(actor, cell, snapshot, pathfinder, targeting, profile)
	return future * FUTURE_VALUE_WEIGHT - danger * profile.risk_aversion


func _quick_cell_danger(
	actor: TacticalCharacter,
	cell: Vector2i,
	snapshot: AIBoardSnapshot,
	pathfinder: GridPathfinder,
	targeting: AbilityTargeting,
	profile: EnemyAIProfile
) -> float:
	var key := "%s|%s|%s" % [_get_snapshot_key(snapshot), actor.get_instance_id(), cell]
	if _quick_danger_cache.has(key):
		last_cache_hit_count += 1
		return float(_quick_danger_cache[key])
	var probe := snapshot.duplicate_state()
	probe.set_cell(actor, cell)
	var danger := 0.0
	for opponent in probe.get_living_opponents(actor):
		var estimate := _estimate_unit_action_against_target(
			opponent,
			actor,
			probe,
			pathfinder,
			targeting,
			profile,
			false
		)
		var movement_pressure := float(estimate.get("movement_cost", 0.0)) * 0.5
		danger = maxf(danger, maxf(0.0, float(estimate.get("score", 0.0)) - movement_pressure))
	var terrain_probe := probe.duplicate_state()
	var terrain_score := _forecast_terrain_trigger(
		actor,
		TileTriggeredEffectDefinition.Trigger.ENTER,
		terrain_probe,
		profile
	)
	danger += maxf(0.0, -terrain_score)
	_quick_danger_cache[key] = danger
	return danger


func _estimate_immediate_cast_value_from_cell(
	actor: TacticalCharacter,
	cell: Vector2i,
	snapshot: AIBoardSnapshot,
	targeting: AbilityTargeting
) -> float:
	var best := 0.0
	for ability in actor.get_abilities():
		if ability == null or not ability.can_be_used_by(actor):
			continue
		for unit in snapshot.units:
			if not snapshot.is_living(unit) or not _is_relevant_candidate_unit(actor, unit, ability):
				continue
			var target_cell := snapshot.get_cell(unit)
			if _is_valid_primary_target(actor, cell, target_cell, ability, snapshot, targeting):
				best = maxf(
					best,
					_rough_unit_priority(actor, unit, ability, snapshot)
				)
	return best


func _estimate_future_value(
	actor: TacticalCharacter,
	cell: Vector2i,
	snapshot: AIBoardSnapshot,
	targeting: AbilityTargeting
) -> float:
	var key := "%s|%s|%s" % [_get_snapshot_key(snapshot), actor.get_instance_id(), cell]
	if _future_value_cache.has(key):
		last_cache_hit_count += 1
		return float(_future_value_cache[key])
	var best := _estimate_immediate_cast_value_from_cell(actor, cell, snapshot, targeting)
	var movement := snapshot.get_movement_range(actor)
	for ability in actor.get_abilities():
		if ability == null or not ability.can_be_used_by(actor):
			continue
		for unit in snapshot.units:
			if not snapshot.is_living(unit) or not _is_relevant_candidate_unit(actor, unit, ability):
				continue
			var target_cell := snapshot.get_cell(unit)
			var distance := targeting.get_weighted_distance(cell, target_cell)
			var gap := maxf(0.0, distance - ability.range)
			if gap > movement + COST_EPSILON:
				continue
			var access_ratio := 1.0 if gap <= COST_EPSILON else maxf(0.25, 1.0 - gap / maxf(1.0, movement))
			best = maxf(
				best,
				_rough_unit_priority(actor, unit, ability, snapshot) * access_ratio
			)
	_future_value_cache[key] = best
	return best


func _get_cast_gap(
	actor: TacticalCharacter,
	cell: Vector2i,
	snapshot: AIBoardSnapshot,
	targeting: AbilityTargeting
) -> float:
	var best := INF
	for ability in actor.get_abilities():
		if ability == null or not ability.can_be_used_by(actor):
			continue
		for target_cell in _get_relevant_target_cells(actor, ability, snapshot, targeting):
			best = minf(
				best,
				maxf(0.0, targeting.get_weighted_distance(cell, target_cell) - ability.range)
			)
	return best


func _get_reachability(
	unit: TacticalCharacter,
	start: Vector2i,
	budget: float,
	snapshot: AIBoardSnapshot,
	pathfinder: GridPathfinder,
	penalties: Dictionary = {},
	ignored_blocker: Vector2i = Vector2i(-1, -1)
) -> Dictionary:
	var blocked := snapshot.get_blocked_cells(unit)
	if ignored_blocker != Vector2i(-1, -1):
		blocked.erase(ignored_blocker)
	var key := "%s|%s|%.3f|%s|%s" % [
		unit.get_instance_id(),
		start,
		budget,
		blocked.hash(),
		penalties.hash(),
	]
	if _reachability_cache.has(key):
		last_cache_hit_count += 1
		return _reachability_cache[key] as Dictionary
	var result := pathfinder.build_reachability(
		start,
		budget,
		blocked,
		penalties
	)
	_reachability_cache[key] = result
	last_reachability_search_count += 1
	return result


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
		or not ability.can_be_used_by(caster)
	):
		return false
	if targeting.get_weighted_distance(caster_cell, target_cell) > ability.range + COST_EPSILON:
		return false
	if not _has_line_of_sight(caster_cell, target_cell, snapshot.wall_cells):
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


func _has_line_of_sight(from_cell: Vector2i, to_cell: Vector2i, walls: Dictionary) -> bool:
	var key := "%s>%s" % [from_cell, to_cell]
	if _line_of_sight_cache.has(key):
		last_cache_hit_count += 1
		return bool(_line_of_sight_cache[key])
	var result := _line_of_sight.has_line_of_sight(from_cell, to_cell, walls)
	_line_of_sight_cache[key] = result
	return result


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


func _resolve_initiative_order(
	actor: TacticalCharacter,
	provided: Array[TacticalCharacter],
	snapshot: AIBoardSnapshot
) -> Array[TacticalCharacter]:
	var result: Array[TacticalCharacter] = []
	for unit in provided:
		if snapshot.is_living(unit) and not result.has(unit):
			result.append(unit)
	if result.is_empty():
		result = snapshot.units.filter(func(unit: TacticalCharacter) -> bool:
			return snapshot.is_living(unit)
		)
		result.sort_custom(func(a: TacticalCharacter, b: TacticalCharacter) -> bool:
			if a.get_initiative() != b.get_initiative():
				return a.get_initiative() > b.get_initiative()
			return snapshot.units.find(a) < snapshot.units.find(b)
		)
	var actor_index := result.find(actor)
	if actor_index > 0:
		var rotated: Array[TacticalCharacter] = []
		for offset in range(result.size()):
			rotated.append(result[(actor_index + offset) % result.size()])
		result = rotated
	return result


func _get_snapshot_key(snapshot: AIBoardSnapshot) -> String:
	var parts: Array[String] = []
	for unit in snapshot.units:
		var status_parts: Array[String] = []
		for status_id in snapshot.get_status_ids(unit):
			var status_state := snapshot.get_status_state(unit, status_id)
			status_parts.append("%s:%d:%d" % [
				status_id,
				int(status_state.get("remaining_turns", 0)),
				int(bool(status_state.get("processed_this_turn", false))),
			])
		parts.append("%s:%s:%d:%.3f:%d:%s" % [
			unit.get_instance_id(),
			snapshot.get_cell(unit),
			snapshot.get_health(unit),
			snapshot.get_remaining_movement(unit),
			int(snapshot.can_use_opportunity_reaction(unit)),
			",".join(status_parts),
		])
	return "|".join(parts)


func _get_best_current_cast(candidates: Array[EnemyTurnPlan]) -> EnemyTurnPlan:
	var best: EnemyTurnPlan
	for plan in candidates:
		if plan.sequence != EnemyTurnPlan.Sequence.CAST_ONLY or plan.ability == null:
			continue
		if best == null or _plan_less(plan, best, false):
			best = plan
	return best


func _copy_plan(source: EnemyTurnPlan) -> EnemyTurnPlan:
	var result := EnemyTurnPlan.new()
	result.sequence = source.sequence
	result.pre_cast_path = source.pre_cast_path.duplicate()
	result.post_cast_path = source.post_cast_path.duplicate()
	result.ability = source.ability
	result.target_cell = source.target_cell
	result.cast_origin = source.cast_origin
	result.end_cell = source.end_cell
	result.ability_index = source.ability_index
	result.scene_target_index = source.scene_target_index
	result.target_turn_order_index = source.target_turn_order_index
	result.movement_cost = source.movement_cost
	result.effect_score = source.effect_score
	result.terrain_score = source.terrain_score
	result.position_score = source.position_score
	result.coordination_score = source.coordination_score
	result.preferred_delivery_score = source.preferred_delivery_score
	result.threat_score = source.threat_score
	result.threat_penalty = source.threat_penalty
	result.immediate_score = source.immediate_score
	result.counterplay_score = source.counterplay_score
	result.total_score = source.total_score
	result.score_breakdown = source.score_breakdown.duplicate()
	return result


func _append_unique(
	candidates: Array[EnemyTurnPlan],
	seen: Dictionary,
	plan: EnemyTurnPlan,
	start: Vector2i
) -> void:
	if candidates.size() >= MAX_CANDIDATES:
		return
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


func _append_cell_unique(
	cells: Array[Vector2i],
	cell: Vector2i,
	snapshot: AIBoardSnapshot
) -> void:
	if (
		cell.x >= 0
		and cell.y >= 0
		and cell.x < snapshot.grid_size.x
		and cell.y < snapshot.grid_size.y
		and not snapshot.wall_cells.has(cell)
		and not cells.has(cell)
	):
		cells.append(cell)


func _sorted_cells(values: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for value in values:
		cells.append(value as Vector2i)
	cells.sort_custom(_cell_less)
	return cells


func _descriptor_less(a: Dictionary, b: Dictionary) -> bool:
	var rough_a := float(a["rough"])
	var rough_b := float(b["rough"])
	if not is_equal_approx(rough_a, rough_b):
		return rough_a > rough_b
	var cost_a := float(a["cost"])
	var cost_b := float(b["cost"])
	if not is_equal_approx(cost_a, cost_b):
		return cost_a < cost_b
	if int(a["ability_index"]) != int(b["ability_index"]):
		return int(a["ability_index"]) < int(b["ability_index"])
	if a["target"] != b["target"]:
		return _cell_less(a["target"] as Vector2i, b["target"] as Vector2i)
	return _cell_less(a["origin"] as Vector2i, b["origin"] as Vector2i)


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
	if a.ability == null and b.ability != null:
		return false
	if a.ability != null and b.ability == null:
		return true
	if not is_equal_approx(a.movement_cost, b.movement_cost):
		return a.movement_cost < b.movement_cost
	if a.ability_index != b.ability_index:
		return a.ability_index < b.ability_index
	if a.target_turn_order_index != b.target_turn_order_index:
		return a.target_turn_order_index < b.target_turn_order_index
	if a.scene_target_index != b.scene_target_index:
		return a.scene_target_index < b.scene_target_index
	if a.target_cell != b.target_cell:
		return _cell_less(a.target_cell, b.target_cell)
	return a.sequence < b.sequence


func _cell_less(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
