extends "res://tests/run_ai_profile_tests.gd"


func _run() -> void:
	fixture = load("res://tests/test_enemy_ai.gd").new()
	_test_fixed_bonus()
	_test_decisions_and_shortlist()
	_test_multiple_kills()
	_test_reassembly()
	_test_followup_and_reactions()
	fixture._free_tracked()
	print("KILL_WEIGHT_TESTS_%s: %d checks, %d failures" % [
		"OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_fixed_bonus() -> void:
	var ai := profile()
	check(ai.kill_weight == 0.0 and EnemyAIProfile.get_default().kill_weight == 0.0,
		"new and existing profiles default to zero Kill Weight")
	ai.kill_weight = 20.0
	var actor := unit(true, Vector2i(1, 1))
	var small := unit(false, Vector2i(3, 1))
	var large := unit(false, Vector2i(3, 2))
	large.constitution_override = 50
	small.current_health = 4
	large.current_health = 4
	var participants: Array[TacticalCharacter] = [actor, small, large]
	check(large.get_max_health() > small.get_max_health(), "flat bonus fixture has different maximum HP")
	for target in [small, large]:
		check(score(actor, target, {"health_delta": -40}, ai, participants) == 24.0,
			"kill grants 20 fixed points plus actual damage regardless of maximum HP")
	ai.immediate_defeat_ratio = 0.25
	check(score(actor, small, {"health_delta": -40}, ai, participants)
		== 24.0 + small.get_max_health() * 0.25, "flat and maximum-HP defeat bonuses add together")
	ai.damage_weight = 0.0
	check(score(actor, small, {"health_delta": -40}, ai, participants)
		== 20.0 + small.get_max_health() * 0.25, "Kill Weight is independent of Damage Weight")
	ai.damage_weight = 1.0
	large.current_health = 30
	check(score(actor, large, {"health_delta": -4}, ai, participants) == 4.0, "nonlethal damage earns no kill bonus")
	var ally := unit(true, Vector2i(1, 2))
	ally.current_health = 4
	participants.append(ally)
	var planner := EnemyAIPlanner.new()
	var strike := damage(40)
	var allied_score := score(actor, ally, {"health_delta": -40}, ai, participants)
	var allied_priority := planner._rough_unit_priority(actor, ally, strike,
		AIBoardSnapshot.from_battle(participants, GRID_SIZE), actor.grid_cell, ai)
	var terrain_score := planner._score_terrain_estimate(ally, {"health_delta": -40},
		AIBoardSnapshot.from_battle(participants, GRID_SIZE), ai)
	ai.kill_weight = 0.0
	check(score(actor, ally, {"health_delta": -40}, ai, participants) == allied_score,
		"Kill Weight does not alter allied defeat penalty")
	check(planner._rough_unit_priority(actor, ally, strike,
		AIBoardSnapshot.from_battle(participants, GRID_SIZE), actor.grid_cell, ai) == allied_priority,
		"Kill Weight does not alter allied target priority")
	check(planner._score_terrain_estimate(ally, {"health_delta": -40},
		AIBoardSnapshot.from_battle(participants, GRID_SIZE), ai) == terrain_score,
		"Kill Weight does not alter lethal terrain penalty")
	ai.kill_weight = 20.0
	var state := AIBoardSnapshot.from_battle(participants, GRID_SIZE)
	check(planner._score_effect_estimate(actor, small, {"health_delta": -40}, ai, state) == 24.0 + small.get_max_health() * 0.25,
		"first lethal event grants bonus")
	check(planner._score_effect_estimate(actor, small, {"health_delta": -40}, ai, state) == 0.0,
		"already defeated target grants neither damage nor another kill bonus")
	check(small.current_health == 4 and ally.current_health == 4, "forecasts preserve live HP")


func _test_decisions_and_shortlist() -> void:
	for friendly in [true, false]:
		var ai := profile()
		var strike := damage(10)
		var actor := unit(friendly, Vector2i(1, 1), [strike], ai)
		var participants: Array[TacticalCharacter] = [actor]
		for cell in [Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3), Vector2i(2, 3)]:
			participants.append(unit(not friendly, cell))
		var weak := participants[4]
		weak.current_health = 5
		check(plan(actor, participants).target_cell != weak.grid_cell,
			"zero Kill Weight preserves nonlethal target preference for faction %s" % friendly)
		ai.kill_weight = 20.0
		var chosen := plan(actor, participants)
		check(chosen.target_cell == weak.grid_cell, "Kill Weight brings finishing target into shortlist for faction %s" % friendly)
		check(chosen.effect_score == 25.0, "chosen finishing action includes exactly one flat bonus")
		var healing := heal(10)
		actor.set_dev_ability_loadout([strike, healing])
		var ally := unit(friendly, Vector2i(1, 3))
		ally.current_health = ally.get_max_health() / 2
		participants = [actor, weak, ally]
		ai.kill_weight = 0.0
		ai.healing_weight = 3.0
		check(plan(actor, participants).ability == healing, "without flat bonus support beats low remaining damage")
		ai.kill_weight = 20.0
		check(plan(actor, participants).ability == strike, "Kill Weight changes faction %s's choice to a finishing attack" % friendly)


func _test_multiple_kills() -> void:
	var ai := profile()
	ai.kill_weight = 20.0
	var strike := damage(10)
	strike.hit_count = 3
	var actor := unit(true, Vector2i(1, 1), [strike], ai)
	var first := unit(false, Vector2i(3, 1))
	first.current_health = 5
	var chosen := plan(actor, [actor, first])
	check(chosen.effect_score == 25.0, "three same-target hits reward one early kill only")
	strike.hit_targeting = AbilityDefinition.HitTargeting.SELECT_PER_HIT
	chosen = plan(actor, [actor, first])
	check(chosen.selected_targets == [first, first, first], "repeated selections preserve complete per-hit plan")
	check(chosen.effect_score == 25.0, "repeated per-hit selections reward one early kill only")
	var second := unit(false, Vector2i(3, 2))
	second.current_health = 8
	strike.hit_count = 2
	strike.allow_repeated_targets = false
	chosen = plan(actor, [actor, first, second])
	check(chosen.selected_targets.size() == 2 and chosen.selected_targets.has(first) and chosen.selected_targets.has(second),
		"distinct per-hit selection defeats two opponents")
	check(chosen.effect_score == 53.0, "distinct per-hit kills each earn one bonus")
	strike.hit_targeting = AbilityDefinition.HitTargeting.SAME_TARGET
	strike.hit_count = 3
	strike.area_of_effect = 3
	chosen = plan(actor, [actor, first, second])
	check(chosen.effect_score == 53.0, "multi-hit area action rewards each opponent once")
	strike.area_of_effect = 0
	strike.innate_damage = 4
	first.current_health = 10
	chosen = plan(actor, [actor, first])
	check(chosen.effect_score == 30.0, "kill on final hit earns one bonus after accumulated damage")
	check(first.current_health == 10 and second.current_health == 8, "multi-hit planning leaves live opponents intact")


func _test_reassembly() -> void:
	var ai := profile()
	ai.kill_weight = 20.0
	var strike := damage(10)
	var actor := unit(true, Vector2i(1, 1), [strike], ai)
	var skeleton := unit(false, Vector2i(3, 1))
	skeleton.override_template_passives = true
	skeleton.passive_overrides = [load("res://resources/passives/reassemble.tres") as PassiveAbilityDefinition]
	skeleton.current_health = 4
	var planner := EnemyAIPlanner.new()
	var state := AIBoardSnapshot.from_battle([actor, skeleton], GRID_SIZE)
	check(planner._rough_unit_priority(actor, skeleton, strike, state, actor.grid_cell, ai) == 4.0,
		"shortlist does not reward collapsing skeleton as a kill")
	check(planner._score_effect_estimate(actor, skeleton, {"health_delta": -10}, ai, state) == 4.0,
		"detailed forecast does not reward collapsing skeleton as a kill")
	check(state.is_living(skeleton) and state.is_bone_pile(skeleton), "collapsed skeleton remains alive as pile")
	check(planner._rough_unit_priority(actor, skeleton, strike, state, actor.grid_cell, ai) == 21.0,
		"shortlist rewards destroying the living pile")
	check(planner._score_effect_estimate(actor, skeleton, {"health_delta": -10}, ai, state) == 21.0,
		"destroying pile grants one flat bonus")
	check(planner._score_effect_estimate(actor, skeleton, {"health_delta": -10}, ai, state) == 0.0,
		"destroyed pile grants no repeated bonus")
	strike.hit_count = 3
	check(plan(actor, [actor, skeleton]).effect_score == 25.0, "multi-hit collapse and permanent defeat earn only one kill bonus")
	check(skeleton.current_health == 4 and not skeleton.is_bone_pile, "pile forecasts do not transform live skeleton")


func _test_followup_and_reactions() -> void:
	var ai := profile()
	ai.kill_weight = 20.0
	ai.immediate_defeat_ratio = 0.25
	var actor := unit(false, Vector2i(1, 1), [damage(5)], ai)
	var ally := unit(false, Vector2i(1, 2), [damage(20)])
	var target := unit(true, Vector2i(3, 1))
	target.current_health = 14
	var participants: Array[TacticalCharacter] = [actor, ally, target]
	var planner := EnemyAIPlanner.new()
	var estimate := planner._estimate_unit_action_against_target(ally, target,
		AIBoardSnapshot.from_battle(participants, GRID_SIZE), GridPathfinder.new(GRID_SIZE),
		AbilityTargeting.new(GRID_SIZE), ai, true)
	check(estimate.score == 34.0 + target.get_max_health() * 0.25, "ally forecast includes both defeat bonuses")
	check(estimate.value == 14.0 and estimate.damage == 14, "allied follow-up value excludes both defeat bonuses")
	ai.shared_pressure_weight = 1.0
	check(plan(actor, participants).coordination_score == 9.0, "shared pressure does not duplicate Kill Weight")
	ai.shared_pressure_weight = 0.0
	ai.setup_defeat_ratio = 0.5
	check(plan(actor, participants).coordination_score == target.get_max_health() * 0.5,
		"Kill Weight does not change Setup Defeat Ratio reward")
	ally.override_template_passives = true
	ally.passive_overrides = [load("res://resources/passives/counter.tres") as PassiveAbilityDefinition]
	# Counter/opportunity forecasts score the responder's attack, then invert opposing value.
	target.current_health = 1
	target.grid_cell = Vector2i(2, 2)
	var counter_state := AIBoardSnapshot.from_battle([target, ally], GRID_SIZE)
	ai.kill_weight = 0.0
	var counter_before := planner._forecast_counters(target, [ally], counter_state.duplicate_state(), AbilityTargeting.new(GRID_SIZE), ai)
	ai.kill_weight = 20.0
	var counter_after := planner._forecast_counters(target, [ally], counter_state.duplicate_state(), AbilityTargeting.new(GRID_SIZE), ai)
	check(counter_after == counter_before - 20.0, "opposing counter kill retains forecast sign inversion")
	ally.set_dev_ability_loadout([load("res://resources/abilities/strike.tres") as AbilityDefinition])
	ally.reset_opportunity_reaction()
	check(OpportunityAttackSystem.get_opportunity_attack_ability(ally) != null, "opportunity fixture has usable melee attack")
	var opportunity_state := AIBoardSnapshot.from_battle([target, ally], GRID_SIZE)
	ai.kill_weight = 0.0
	var opportunity_before := planner._forecast_opportunity_attacks(target, Vector2i(2, 2), Vector2i(3, 2),
		opportunity_state.duplicate_state(), AbilityTargeting.new(GRID_SIZE), ai)
	check(opportunity_before < 0.0, "opportunity fixture forecasts an opposing lethal reaction")
	ai.kill_weight = 20.0
	var opportunity_after := planner._forecast_opportunity_attacks(target, Vector2i(2, 2), Vector2i(3, 2),
		opportunity_state.duplicate_state(), AbilityTargeting.new(GRID_SIZE), ai)
	check(opportunity_after == opportunity_before - 20.0, "opposing opportunity kill retains forecast sign inversion")
