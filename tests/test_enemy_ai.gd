@tool
extends McpTestSuite

const CharacterDefinitionScript = preload("res://scripts/unit_definition.gd")
const TacticalCharacterScript = preload("res://scripts/initiative_actor.gd")
const AbilityDefinitionScript = preload("res://scripts/ability_definition.gd")
const AbilityEffectScript = preload("res://scripts/ability_effect_definition.gd")
const DamageEffectScript = preload("res://scripts/damage_effect_definition.gd")
const HealEffectScript = preload("res://scripts/heal_effect_definition.gd")
const EnemyAIProfileScript = preload("res://scripts/enemy_ai_profile.gd")
const EnemyAIPlannerScript = preload("res://scripts/enemy_ai_planner.gd")
const GridPathfinderScript = preload("res://scripts/grid_pathfinder.gd")
const AbilityTargetingScript = preload("res://scripts/ability_targeting.gd")
const OpportunityAttackSystemScript = preload("res://scripts/opportunity_attack_system.gd")


func suite_name() -> String:
	return "enemy_ai"


func test_profile_defaults_resources_and_configuration_warnings() -> void:
	var profile := EnemyAIProfileScript.new() as EnemyAIProfile
	assert_eq(profile.display_name, "General AI", "new AI profiles should describe their general behavior")
	assert_true(is_equal_approx(profile.risk_aversion, 1.0), "general AI should default to balanced risk")

	var general_profile := ResourceLoader.load(
		"res://resources/ai/general_ai.tres",
		"",
		ResourceLoader.CACHE_MODE_REPLACE
	) as EnemyAIProfile
	assert_eq(general_profile.display_name, "General AI", "the reusable profile should be the single general template")
	assert_true(is_equal_approx(general_profile.risk_aversion, 1.0), "the reusable profile should use balanced risk")
	assert_false(FileAccess.file_exists("res://resources/ai/melee_ai.tres"), "the obsolete Melee profile should be removed")
	assert_false(FileAccess.file_exists("res://resources/ai/ranged_ai.tres"), "the obsolete Ranged profile should be removed")

	var enemy := _make_unit(false, Vector2i.ZERO, 4.0, [])
	assert_true(enemy._get_configuration_warnings().size() > 0, "an enemy without an AI profile should warn in the Inspector")
	enemy.enemy_ai_profile = general_profile
	assert_true(enemy._get_configuration_warnings().is_empty(), "attaching a profile should resolve the enemy warning")
	var friendly := _make_unit(true, Vector2i.ONE, 4.0, [])
	friendly.enemy_ai_profile = general_profile
	assert_true(friendly._get_configuration_warnings().size() > 0, "friendly units should warn that enemy AI is ignored")
	var bundled_definition := EnemyDefinition.new()
	bundled_definition.ai_profile = general_profile
	var bundled_enemy := track(TacticalCharacterScript.new()) as TacticalCharacter
	bundled_enemy.definition = bundled_definition
	assert_true(bundled_enemy._get_configuration_warnings().is_empty(), "a bundled archetype AI should satisfy enemy configuration")
	bundled_definition.faction = CharacterDefinition.Faction.FRIENDLY
	assert_true(bundled_enemy._get_configuration_warnings().size() > 0, "warnings should also recognize a bundled AI on an incorrectly friendly archetype")


func test_effect_forecasts_clamp_health_and_support_custom_utility() -> void:
	var caster := _make_unit(false, Vector2i.ZERO, 4.0, [])
	var target := _make_unit(true, Vector2i.ONE, 4.0, [])
	var damage := DamageEffectScript.new() as DamageEffectDefinition
	damage.damage_type = DamageEffectDefinition.DamageType.MAGICAL
	damage.innate_damage = 30
	damage.scaling_stat = UnitStat.Type.NONE
	var damage_estimate := damage.estimate_for_ai(caster, target, 20)
	assert_eq(damage_estimate["health_delta"], -20, "forecast damage should clamp overkill")

	var healing := HealEffectScript.new() as HealEffectDefinition
	healing.amount = 25
	var heal_estimate := healing.estimate_for_ai(caster, caster, 90)
	assert_eq(heal_estimate["health_delta"], 10, "forecast healing should clamp to maximum health")

	var custom := AbilityEffectScript.new() as AbilityEffectDefinition
	custom.ai_utility_hint = 7.5
	var custom_estimate := custom.estimate_for_ai(caster, target, 100)
	assert_true(is_equal_approx(custom_estimate["utility_hint"], 7.5), "custom effects should expose editable AI utility")
	assert_eq(custom_estimate["health_delta"], 0, "unknown effects should not invent health changes")


func test_planner_forecasts_primary_heal_and_slow_from_the_ability_api() -> void:
	var caster := _make_unit(false, Vector2i.ZERO, 4.0, [])
	var ally := _make_unit(false, Vector2i(1, 0), 4.0, [])
	var opponent := _make_unit(true, Vector2i(0, 1), 4.0, [])
	ally.current_health = 50
	var units: Array[TacticalCharacter] = [caster, ally, opponent]
	var targeting := AbilityTargetingScript.new(Vector2i(4, 4)) as AbilityTargeting
	var planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
	var profile := _profile(0.0)

	var heal := AbilityDefinitionScript.new() as AbilityDefinition
	heal.effect = AbilityDefinition.PrimaryEffect.HEAL
	heal.effect_amount = 25
	heal.scaling_stat = UnitStat.Type.NONE
	heal.target_flags = AbilityDefinition.TargetFlags.FRIEND
	var heal_snapshot := AIBoardSnapshot.from_battle(units, Vector2i(4, 4))
	var heal_score := planner._forecast_ability(
		caster,
		heal,
		ally.grid_cell,
		heal_snapshot,
		targeting,
		profile
	)
	assert_true(is_equal_approx(heal_score, 12.5), "planner healing should be weighted by the ally's missing-health percentage")
	assert_eq(heal_snapshot.get_health(ally), 75, "planner simulation should apply the forecasted primary healing")

	var slow := AbilityDefinitionScript.new() as AbilityDefinition
	slow.effect = AbilityDefinition.PrimaryEffect.STATUS
	slow.status_effect = load("res://resources/statuses/slow.tres") as StatusEffectDefinition
	slow.target_flags = AbilityDefinition.TargetFlags.ENEMY
	var slow_snapshot := AIBoardSnapshot.from_battle(units, Vector2i(4, 4))
	var slow_score := planner._forecast_ability(
		caster,
		slow,
		opponent.grid_cell,
		slow_snapshot,
		targeting,
		profile
	)
	assert_true(is_equal_approx(slow_score, 8.0), "planner utility should use the primary Slow forecast")
	assert_eq(slow_snapshot.get_health(opponent), 100, "Slow forecasting should leave simulated health unchanged")

	caster.intelligence_override = 12
	var ice_shard := load("res://resources/abilities/ice_shard.tres") as AbilityDefinition
	var ice_snapshot := AIBoardSnapshot.from_battle(units, Vector2i(4, 4))
	var ice_score := planner._forecast_ability(
		caster,
		ice_shard,
		opponent.grid_cell,
		ice_snapshot,
		targeting,
		profile
	)
	assert_true(is_equal_approx(ice_score, 35.0), "Ice Shard AI value should combine 27 damage with Slow's utility 8")
	assert_eq(ice_snapshot.get_health(opponent), 73, "Ice Shard forecasting should apply the exact centralized damage")
	var lethal_estimate := ice_shard.estimate_primary_effect_for_ai(caster, opponent, 27)
	assert_eq(lethal_estimate.health_delta, -27, "lethal Ice Shard forecasting should clamp damage to remaining health")
	assert_true(is_zero_approx(lethal_estimate.utility_hint), "lethal damage should not forecast applying Slow afterward")

	var frost_bow := load("res://resources/items/frost_bow.tres") as ItemDefinition
	caster.equip_item(frost_bow)
	var frost_arrow := AbilityDefinitionScript.new() as AbilityDefinition
	frost_arrow.ability_type = AbilityDefinition.AbilityType.RANGED
	frost_arrow.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	frost_arrow.scaling_stat = UnitStat.Type.NONE
	frost_arrow.target_flags = AbilityDefinition.TargetFlags.ENEMY
	var frost_snapshot := AIBoardSnapshot.from_battle(units, Vector2i(4, 4))
	var frost_score := planner._forecast_ability(
		caster,
		frost_arrow,
		opponent.grid_cell,
		frost_snapshot,
		targeting,
		profile
	)
	assert_true(is_equal_approx(frost_score, 18.0), "Frost Bow AI value should combine 10 weapon damage with Slow utility 8")
	assert_eq(frost_snapshot.get_health(opponent), 90, "weapon status forecasting should preserve the exact damage result")

	frost_arrow.status_effect = load("res://resources/statuses/slow.tres") as StatusEffectDefinition
	var duplicate_snapshot := AIBoardSnapshot.from_battle(units, Vector2i(4, 4))
	var duplicate_score := planner._forecast_ability(
		caster,
		frost_arrow,
		opponent.grid_cell,
		duplicate_snapshot,
		targeting,
		profile
	)
	assert_true(is_equal_approx(duplicate_score, 18.0), "matching ability and weapon statuses should contribute AI utility only once")

	var magic_damage := AbilityDefinitionScript.new() as AbilityDefinition
	magic_damage.ability_type = AbilityDefinition.AbilityType.MAGIC
	magic_damage.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	magic_damage.innate_damage = 10
	magic_damage.scaling_stat = UnitStat.Type.NONE
	magic_damage.target_flags = AbilityDefinition.TargetFlags.ENEMY
	var magic_snapshot := AIBoardSnapshot.from_battle(units, Vector2i(4, 4))
	var magic_score := planner._forecast_ability(
		caster,
		magic_damage,
		opponent.grid_cell,
		magic_snapshot,
		targeting,
		profile
	)
	assert_true(is_equal_approx(magic_score, 10.0), "Magic AI forecasts should ignore equipped weapon statuses")


func test_virtual_origin_targeting_does_not_move_live_unit() -> void:
	var caster := _make_unit(false, Vector2i.ZERO, 4.0, [])
	var target := _make_unit(true, Vector2i(3, 0), 4.0, [])
	var ability := _make_damage_ability("Short Shot", AbilityDefinition.DeliveryType.PROJECTILE, 1.0, 10)
	var units: Array[TacticalCharacter] = [caster, target]
	var targeting := AbilityTargetingScript.new(Vector2i(6, 6)) as AbilityTargeting
	assert_false(targeting.is_valid_primary_target(caster, target.grid_cell, ability, units), "the live origin should remain out of range")
	assert_true(targeting.is_valid_primary_target_from(caster, Vector2i(2, 0), target.grid_cell, ability, units), "a hypothetical origin should be evaluated without mutation")
	assert_eq(caster.grid_cell, Vector2i.ZERO, "virtual targeting must not move the live caster")


func test_cell_target_ai_prunes_zero_utility_empty_casts() -> void:
	var shot := _make_damage_ability("Cell Shot", AbilityDefinition.DeliveryType.PROJECTILE, 5.0, 10)
	shot.target_flags = AbilityDefinition.TargetFlags.ENEMY | AbilityDefinition.TargetFlags.CELL
	var profile := _profile(0.0)
	var enemy := _make_unit(false, Vector2i.ZERO, 0.0, [shot], profile)
	var target := _make_unit(true, Vector2i(3, 0), 0.0, [])
	var units: Array[TacticalCharacter] = [enemy, target]
	var grid_size := Vector2i(6, 6)
	var pathfinder := GridPathfinderScript.new(grid_size) as GridPathfinder
	var targeting := AbilityTargetingScript.new(grid_size) as AbilityTargeting
	var planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
	var snapshot := AIBoardSnapshot.from_battle(units, grid_size)
	var candidates := planner._generate_candidates(
		enemy,
		snapshot,
		pathfinder,
		targeting,
		profile,
		0.0,
		true,
		true,
		false
	)
	var cast_count := 0
	for candidate: EnemyTurnPlan in candidates:
		if candidate.ability == null:
			continue
		cast_count += 1
		assert_eq(candidate.target_cell, target.grid_cell, "zero-utility empty-cell casts should be pruned")
	assert_eq(cast_count, 1, "the planner should retain the one cell cast that damages an opponent")


func test_snapshot_scores_status_refreshes_by_added_duration_without_live_mutation() -> void:
	var caster := _make_unit(false, Vector2i.ZERO, 4.0, [])
	var target := _make_unit(true, Vector2i.ONE, 4.0, [])
	var slow := load("res://resources/statuses/slow.tres") as StatusEffectDefinition
	var focus := load("res://resources/statuses/focus.tres") as StatusEffectDefinition
	var burning := load("res://resources/statuses/burning.tres") as StatusEffectDefinition
	var units: Array[TacticalCharacter] = [caster, target]

	var new_snapshot := AIBoardSnapshot.from_battle(units, Vector2i(4, 4))
	var new_slow := new_snapshot.forecast_status_application(caster, target, slow)
	var new_focus := new_snapshot.forecast_status_application(caster, target, focus, 12.0)
	var new_burning := new_snapshot.forecast_status_application(caster, target, burning)
	assert_true(is_equal_approx(new_slow.utility_hint, 8.0), "a new Slow should receive its full configured utility")
	assert_true(is_equal_approx(new_focus.utility_hint, 12.0), "a new Focus should receive its full configured utility")
	assert_eq(new_burning.health_delta, -2, "a new Burning forecast should count its full future damage")
	assert_true(is_zero_approx(new_snapshot.forecast_status_application(caster, target, slow).utility_hint), "a full-duration Slow refresh should be redundant")
	assert_true(is_zero_approx(new_snapshot.forecast_status_application(caster, target, focus, 12.0).utility_hint), "a full-duration Focus refresh should be redundant")
	assert_eq(new_snapshot.forecast_status_application(caster, target, burning).health_delta, 0, "a full-duration Burning refresh should add no future damage")

	assert_true(target.apply_status(slow, caster, caster), "the live target should accept Slow")
	assert_true(target.apply_status(focus, caster, caster), "the live target should accept Focus")
	assert_true(target.apply_status(burning, caster, caster), "the live target should accept Burning")
	for active_status in target.get_active_statuses():
		active_status.remaining_turns = 1
		active_status.processed_this_turn = true
	var live_movement := target.get_movement_range()
	var refresh_snapshot := AIBoardSnapshot.from_battle(units, Vector2i(4, 4))
	var copied_slow := refresh_snapshot.get_status_state(target, slow.status_id)
	assert_eq(copied_slow.definition, slow, "snapshots should retain the active status definition")
	assert_eq(copied_slow.remaining_turns, 1, "snapshots should retain remaining status turns")
	assert_true(copied_slow.processed_this_turn, "snapshots should retain the processed state")
	assert_true(is_equal_approx(refresh_snapshot.get_movement_range(target), live_movement), "snapshots should retain status-adjusted movement")

	var refreshed_slow := refresh_snapshot.forecast_status_application(caster, target, slow)
	var refreshed_focus := refresh_snapshot.forecast_status_application(caster, target, focus, 12.0)
	var refreshed_burning := refresh_snapshot.forecast_status_application(caster, target, burning)
	assert_true(is_equal_approx(refreshed_slow.utility_hint, 4.0), "a one-turn Slow extension should receive half utility")
	assert_true(is_equal_approx(refreshed_focus.utility_hint, 6.0), "a one-turn Focus extension should receive half utility")
	assert_eq(refreshed_burning.health_delta, -1, "a one-turn Burning extension should count only one extra tick")
	assert_eq(refresh_snapshot.get_status_remaining(target, slow.status_id), 2, "a simulated refresh should record the new duration")
	assert_false(refresh_snapshot.get_status_state(target, slow.status_id).processed_this_turn, "a simulated refresh should reset the processed state")
	assert_eq(target.current_health, 100, "status forecasting must not mutate live health")
	for active_status in target.get_active_statuses():
		assert_eq(active_status.remaining_turns, 1, "status forecasting must not refresh live status duration")
		assert_true(active_status.processed_this_turn, "status forecasting must not change live processed state")


func test_opportunity_forecast_consumes_reaction_applies_status_and_truncates_paths() -> void:
	var strike := load("res://resources/abilities/strike.tres") as AbilityDefinition
	var slow := load("res://resources/statuses/slow.tres") as StatusEffectDefinition
	var attacker := _make_unit(true, Vector2i(1, 1), 6.0, [strike])
	var mover := _make_unit(
		false,
		Vector2i(2, 1),
		6.0,
		[],
		_profile(1.0)
	)
	var melee_weapon := ItemDefinition.new()
	melee_weapon.weapon_type = ItemDefinition.WeaponType.MELEE
	melee_weapon.weapon_damage = 10
	melee_weapon.status_effect = slow
	attacker.equip_item(melee_weapon)
	attacker.reset_opportunity_reaction()
	mover.reset_movement()

	var units := _typed_units([attacker, mover])
	var pathfinder := GridPathfinderScript.new(Vector2i(8, 3)) as GridPathfinder
	var targeting := AbilityTargetingScript.new(pathfinder.grid_size) as AbilityTargeting
	var planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
	var snapshot := AIBoardSnapshot.from_battle(units, pathfinder.grid_size)
	var path: Array[Vector2i] = [
		Vector2i(2, 1),
		Vector2i(3, 1),
		Vector2i(4, 1),
		Vector2i(5, 1),
		Vector2i(6, 1),
		Vector2i(7, 1),
	]
	var forecast := planner._forecast_terrain_path(
		mover,
		path,
		snapshot,
		mover.get_enemy_ai_profile(),
		targeting,
		pathfinder
	)
	var expected_damage := strike.calculate_damage(attacker)

	assert_true(float(forecast["score"]) < 0.0, "opportunity damage and Slow should penalize the moving unit's plan")
	assert_eq(snapshot.get_health(mover), 100 - expected_damage, "forecast damage should use the normal Strike calculation")
	assert_false(snapshot.can_use_opportunity_reaction(attacker), "the forecast should consume the attacker's reaction once")
	assert_true(attacker.opportunity_reaction_available, "forecasting must not mutate the live reaction")
	assert_eq(snapshot.get_status_remaining(mover, slow.status_id), 2, "weapon Slow should be included in the opportunity forecast")
	assert_true(is_equal_approx(snapshot.get_movement_range(mover), 4.2), "forecast Slow should update simulated movement range")
	assert_eq(
		forecast["path"],
		path.slice(0, 5),
		"Slow should stop the forecast before a fifth movement step exceeds the new range"
	)
	var guarded_plan := planner.choose_plan(mover, units, pathfinder, targeting)
	var guarded_disengages := false
	for index in range(1, guarded_plan.pre_cast_path.size()):
		guarded_disengages = guarded_disengages or OpportunityAttackSystemScript.is_leaving_reach(
			attacker.grid_cell,
			guarded_plan.pre_cast_path[index - 1],
			guarded_plan.pre_cast_path[index]
		)
	assert_false(guarded_disengages, "AI should avoid disengaging while the damaging reaction is available")
	attacker.spend_opportunity_reaction()
	var unguarded_plan := planner.choose_plan(mover, units, pathfinder, targeting)
	var unguarded_disengages := false
	for index in range(1, unguarded_plan.pre_cast_path.size()):
		unguarded_disengages = unguarded_disengages or OpportunityAttackSystemScript.is_leaving_reach(
			attacker.grid_cell,
			unguarded_plan.pre_cast_path[index - 1],
			unguarded_plan.pre_cast_path[index]
		)
	assert_true(unguarded_disengages, "AI should resume disengaging after the opposing reaction is spent; got %s" % unguarded_plan.get_debug_summary())

	mover.current_health = expected_damage
	attacker.reset_opportunity_reaction()
	mover.reset_movement()
	var lethal_snapshot := AIBoardSnapshot.from_battle(units, pathfinder.grid_size)
	var lethal_path: Array[Vector2i] = [Vector2i(2, 1), Vector2i(3, 1)]
	var lethal_forecast := planner._forecast_terrain_path(
		mover,
		lethal_path,
		lethal_snapshot,
		mover.get_enemy_ai_profile(),
		targeting,
		pathfinder
	)
	assert_eq(lethal_snapshot.get_health(mover), 0, "lethal opportunity damage should defeat the simulated mover")
	assert_eq(lethal_forecast["path"], [Vector2i(2, 1)], "a lethal reaction should stop movement before entering the next cell")


func test_general_ai_prioritizes_the_highest_value_usable_ability() -> void:
	var slash := load("res://resources/abilities/enemy_slash.tres") as AbilityDefinition
	var fallback := _make_damage_ability("Magic Fallback", AbilityDefinition.DeliveryType.PROJECTILE, 5.0, 10)
	var profile := _profile(0.0)
	var enemy := _make_unit(false, Vector2i(2, 2), 3.0, [slash, fallback], profile)
	var target := _make_unit(true, Vector2i(3, 2), 3.0, [])
	var plan := _choose(enemy, [enemy, target], Vector2i(7, 7))
	assert_eq(plan.ability, slash, "general AI should prefer the stronger legal result without a Melee style bonus")
	assert_true(plan.effect_score >= 30.0, "the chosen attack should forecast its centralized damage")


func test_general_ai_uses_an_available_fallback_from_its_loadout() -> void:
	var slash := load("res://resources/abilities/enemy_slash.tres") as AbilityDefinition
	var fallback := _make_damage_ability("Magic Fallback", AbilityDefinition.DeliveryType.PROJECTILE, 5.0, 10)
	var profile := _profile(0.0)
	var enemy := _make_unit(false, Vector2i(0, 2), 2.0, [slash, fallback], profile)
	var target := _make_unit(true, Vector2i(6, 2), 3.0, [])
	var plan := _choose(enemy, [enemy, target], Vector2i(8, 6))
	assert_eq(plan.ability, fallback, "general AI should use a legal fallback when its stronger attack cannot reach")
	assert_ne(plan.sequence, EnemyTurnPlan.Sequence.MOVE_CAST_MOVE, "general AI must never generate split movement")


func test_general_ai_uses_weapon_compatible_abilities_without_style_fields() -> void:
	var slash := load("res://resources/abilities/enemy_slash.tres") as AbilityDefinition
	var shot := load("res://resources/abilities/enemy_shot.tres") as AbilityDefinition
	var profile := _profile(1.0)
	var enemy := _make_unit(false, Vector2i(3, 3), 3.0, [slash, shot], profile, ItemDefinition.WeaponType.RANGED)
	var target := _make_unit(true, Vector2i(5, 3), 3.0, [])
	var plan := _choose(enemy, [enemy, target], Vector2i(10, 7))
	assert_eq(plan.ability, shot, "the planner should infer ranged behavior from the usable Ranged ability")
	assert_ne(plan.sequence, EnemyTurnPlan.Sequence.MOVE_CAST_MOVE, "the compatible shot may reposition but cannot split movement")


func test_candidate_search_is_capped_and_never_generates_split_movement() -> void:
	var shot := _make_damage_ability("Point Shot", AbilityDefinition.DeliveryType.PROJECTILE, 1.0, 20)
	shot.target_flags = AbilityDefinition.TargetFlags.ENEMY | AbilityDefinition.TargetFlags.CELL
	shot.area_of_effect = 3
	var profile := _profile(1.0)
	var enemy := _make_unit(false, Vector2i(0, 1), 2.0, [shot], profile)
	var targets: Array[TacticalCharacter] = []
	for index in range(8):
		targets.append(_make_unit(true, Vector2i(3 + index % 4, floori(index / 4.0)), 0.0, []))
	var pathfinder := GridPathfinderScript.new(Vector2i(8, 4)) as GridPathfinder
	var targeting := AbilityTargetingScript.new(Vector2i(8, 4)) as AbilityTargeting
	var planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
	var units: Array[TacticalCharacter] = [enemy]
	units.append_array(targets)
	planner.choose_plan(enemy, units, pathfinder, targeting)
	assert_true(planner.last_candidate_count <= 32, "the planner should score no more than 32 tactical candidates")
	assert_true(planner.last_exact_reply_count <= 3, "only the best three candidates should receive an exact reply")
	for candidate in planner.ranked_candidates:
		assert_ne(candidate.sequence, EnemyTurnPlan.Sequence.MOVE_CAST_MOVE, "split movement should remain serialized but never be generated")


func test_action_first_filters_non_action_plans_when_a_positive_cast_exists() -> void:
	var shot := _make_damage_ability("Committed Shot", AbilityDefinition.DeliveryType.PROJECTILE, 5.0, 12)
	var counter := _make_damage_ability("Long Counter", AbilityDefinition.DeliveryType.PROJECTILE, 5.0, 100)
	var enemy := _make_unit(false, Vector2i(0, 1), 3.0, [shot], _profile(2.0))
	var target := _make_unit(true, Vector2i(4, 1), 0.0, [counter])
	var units: Array[TacticalCharacter] = [enemy, target]
	var pathfinder := GridPathfinderScript.new(Vector2i(7, 4)) as GridPathfinder
	var targeting := AbilityTargetingScript.new(pathfinder.grid_size) as AbilityTargeting
	var planner := EnemyAIPlannerScript.new() as EnemyAIPlanner

	var plan := planner.choose_plan(enemy, units, pathfinder, targeting)

	assert_eq(plan.ability, shot, "maximum risk aversion should not suppress an available positive action")
	for candidate in planner.ranked_candidates:
		assert_ne(candidate.ability, null, "non-action plans should be filtered whenever an actionable plan exists")


func test_action_first_requires_a_move_cast_even_when_counterplay_is_lethal() -> void:
	var shot := _make_damage_ability("Committed Shot", AbilityDefinition.DeliveryType.PROJECTILE, 1.0, 40)
	var counter := _make_damage_ability("Counter Strike", AbilityDefinition.DeliveryType.MELEE, 1.0, 100)
	var enemy := _make_unit(false, Vector2i(0, 1), 3.0, [shot])
	var target := _make_unit(true, Vector2i(4, 1), 0.0, [counter])
	var units: Array[TacticalCharacter] = [enemy, target]

	enemy.enemy_ai_profile = _profile(2.0)
	var plan := _choose(enemy, units, Vector2i(6, 4))
	assert_eq(plan.ability, shot, "an action requiring movement should still beat Hold at maximum risk aversion")
	assert_eq(plan.sequence, EnemyTurnPlan.Sequence.MOVE_CAST, "the enemy should move into range and perform the action")
	assert_true(plan.counterplay_score > plan.effect_score, "the regression scenario should retain its punishing exact reply")
	assert_true(plan.score_breakdown.has("counterplay"), "counterplay should remain represented in the score breakdown")
	assert_eq(enemy.grid_cell, Vector2i(0, 1), "planning must not mutate the enemy position")
	assert_eq(enemy.current_health, 100, "planning must not mutate live health")
	assert_eq(target.current_health, 100, "forecast damage must remain side-effect-free")


func test_action_first_allows_cautious_post_cast_repositioning() -> void:
	var shot := _make_damage_ability("Point Shot", AbilityDefinition.DeliveryType.PROJECTILE, 1.0, 20)
	var counter := _make_damage_ability("Short Counter", AbilityDefinition.DeliveryType.PROJECTILE, 1.0, 20)
	var enemy := _make_unit(false, Vector2i(3, 2), 3.0, [shot], _profile(2.0))
	var target := _make_unit(true, Vector2i(3, 3), 0.0, [counter])
	var start_distance := AbilityTargetingScript.new(Vector2i(7, 6)).get_weighted_distance(enemy.grid_cell, target.grid_cell)
	var plan := _choose(enemy, [enemy, target], Vector2i(7, 6))
	var end_distance := AbilityTargetingScript.new(Vector2i(7, 6)).get_weighted_distance(plan.get_end_cell(enemy.grid_cell), target.grid_cell)

	assert_eq(plan.ability, shot, "the cautious enemy should perform its available action")
	assert_eq(plan.sequence, EnemyTurnPlan.Sequence.CAST_MOVE, "remaining movement should stay available after the action")
	assert_true(end_distance > start_distance, "risk aversion should still reward safer post-action positioning")


func test_action_first_preserves_movement_when_the_action_is_spent() -> void:
	var shot := _make_damage_ability("Spent Shot", AbilityDefinition.DeliveryType.PROJECTILE, 1.0, 20)
	var counter := _make_damage_ability("Short Counter", AbilityDefinition.DeliveryType.PROJECTILE, 1.0, 20)
	var enemy := _make_unit(false, Vector2i(3, 2), 3.0, [shot], _profile(2.0))
	var target := _make_unit(true, Vector2i(3, 3), 0.0, [counter])
	enemy.spend_ability_action()
	var plan := _choose(enemy, [enemy, target], Vector2i(7, 6))

	assert_eq(plan.ability, null, "a spent action should not fabricate an ability plan")
	assert_eq(plan.sequence, EnemyTurnPlan.Sequence.MOVE_ONLY, "movement-only behavior should remain available when no action can be taken")


func test_melee_enemy_pursues_attack_range_instead_of_retreating_from_ranged_threat() -> void:
	var slash := load("res://resources/abilities/enemy_slash.tres") as AbilityDefinition
	var counter := _make_damage_ability("Long Counter", AbilityDefinition.DeliveryType.PROJECTILE, 5.0, 35)
	var enemy := _make_unit(false, Vector2i(7, 11), 2.0, [slash], _profile(2.0))
	var target := _make_unit(true, Vector2i(4, 7), 6.0, [counter])
	var grid_size := Vector2i(12, 12)
	var targeting := AbilityTargetingScript.new(grid_size) as AbilityTargeting
	var start_distance := targeting.get_weighted_distance(enemy.grid_cell, target.grid_cell)
	var planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
	var plan := planner.choose_plan(
		enemy,
		_typed_units([enemy, target]),
		GridPathfinderScript.new(grid_size),
		targeting
	)
	var end_distance := targeting.get_weighted_distance(plan.get_end_cell(enemy.grid_cell), target.grid_cell)

	assert_eq(plan.ability, null, "the melee enemy should still be unable to attack this turn")
	assert_eq(plan.sequence, EnemyTurnPlan.Sequence.MOVE_ONLY, "the melee enemy should spend its turn pursuing")
	assert_true(end_distance < start_distance, "melee pursuit should reduce the distance to attack range")
	assert_eq(plan.get_end_cell(enemy.grid_cell), Vector2i(6, 10), "the sample melee enemy should take its best gap-closing step")
	assert_eq(planner.ranked_candidates.size(), 1, "retreat and Hold should not compete with a valid melee pursuit")


func test_threat_forecast_prefers_an_equally_effective_safe_destination() -> void:
	var counter := _make_damage_ability("Counter", AbilityDefinition.DeliveryType.MELEE, 1.0, 20)
	var profile := _profile(1.0)
	var enemy := _make_unit(false, Vector2i(3, 2), 3.0, [], profile)
	var target := _make_unit(true, Vector2i(3, 3), 0.0, [counter])
	var plan := _choose(enemy, [enemy, target], Vector2i(7, 6))
	var end_distance := AbilityTargetingScript.new(Vector2i(7, 6)).get_weighted_distance(plan.get_end_cell(enemy.grid_cell), target.grid_cell)
	assert_true(end_distance > 3.0, "threat scoring should select an equally effective cell outside movement-plus-counter range; got %s with %.2f threat" % [plan.get_end_cell(enemy.grid_cell), plan.threat_score])
	assert_true(is_zero_approx(plan.threat_score), "the selected safe destination should have no direct incoming threat")
	assert_true(plan.score_breakdown.has("threat"), "threat should be represented in the score breakdown")


func test_moderate_threat_still_allows_a_rewarding_melee_attack() -> void:
	var slash := _make_damage_ability("Slash", AbilityDefinition.DeliveryType.MELEE, 1.0, 30)
	var counter := _make_damage_ability("Counter", AbilityDefinition.DeliveryType.MELEE, 1.0, 10)
	var profile := _profile(0.35)
	var enemy := _make_unit(false, Vector2i(2, 2), 0.0, [slash], profile)
	var target := _make_unit(true, Vector2i(3, 2), 0.0, [counter])
	var plan := _choose(enemy, [enemy, target], Vector2i(6, 5))
	assert_eq(plan.ability, slash, "moderate threat should not outweigh a strong adjacent melee attack")
	assert_true(is_equal_approx(plan.threat_score, 10.0), "the plan should expose the opponent's strongest direct response")
	assert_true(is_equal_approx(plan.threat_penalty, 3.5), "the plan should expose the weighted threat penalty")
	assert_true(is_equal_approx(plan.score_breakdown.threat_score, 10.0), "the debug breakdown should expose raw threat")
	assert_true(is_equal_approx(plan.score_breakdown.threat_penalty, 3.5), "the debug breakdown should expose weighted threat")


func test_threat_forecast_respects_walls_line_of_sight_and_defeat() -> void:
	var shot := _make_damage_ability("Long Shot", AbilityDefinition.DeliveryType.PROJECTILE, 5.0, 20)
	var enemy := _make_unit(false, Vector2i(0, 1), 0.0, [])
	var target := _make_unit(true, Vector2i(4, 1), 0.0, [shot])
	var units: Array[TacticalCharacter] = [enemy, target]
	var grid_size := Vector2i(6, 3)
	var pathfinder := GridPathfinderScript.new(grid_size) as GridPathfinder
	var targeting := AbilityTargetingScript.new(grid_size) as AbilityTargeting
	var planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
	var profile := _profile(0.0)
	var open_snapshot := AIBoardSnapshot.from_battle(units, grid_size)
	assert_true(planner._estimate_incoming_threat(enemy, open_snapshot, pathfinder, targeting, profile) > 0.0, "a clear in-range projectile should contribute threat")

	var walls := {
		Vector2i(2, 0): true,
		Vector2i(2, 1): true,
		Vector2i(2, 2): true,
	}
	var blocked_snapshot := AIBoardSnapshot.from_battle(units, grid_size, walls)
	var blocked_threat := planner._estimate_incoming_threat(enemy, blocked_snapshot, pathfinder, targeting, profile)
	var direct_los := GridLineOfSight.new().has_line_of_sight(target.grid_cell, enemy.grid_cell, blocked_snapshot.wall_cells)
	assert_true(is_zero_approx(blocked_threat), "a wall blocking line of sight should remove projectile threat; got %.2f with movement %.2f and direct LOS %s" % [blocked_threat, blocked_snapshot.get_movement_range(target), direct_los])

	target.current_health = 0
	var defeated_snapshot := AIBoardSnapshot.from_battle(units, grid_size)
	assert_true(is_zero_approx(planner._estimate_incoming_threat(enemy, defeated_snapshot, pathfinder, targeting, profile)), "a defeated opponent should contribute no threat")


func test_walls_block_ai_ability_targeting() -> void:
	var shot := load("res://resources/abilities/enemy_shot.tres") as AbilityDefinition
	var profile := _profile(0.0)
	var enemy := _make_unit(false, Vector2i.ZERO, 0.0, [shot], profile, ItemDefinition.WeaponType.RANGED)
	var target := _make_unit(true, Vector2i(3, 0), 0.0, [])
	var pathfinder := GridPathfinderScript.new(Vector2i(5, 1)) as GridPathfinder
	var targeting := AbilityTargetingScript.new(Vector2i(5, 1)) as AbilityTargeting
	var planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
	var walls := {Vector2i(2, 0): true}
	var plan := planner.choose_plan(enemy, _typed_units([enemy, target]), pathfinder, targeting, walls)
	assert_eq(plan.ability, null, "AI should not select a projectile through a wall")


func test_ai_skips_incompatible_abilities_and_resumes_after_weapon_swap() -> void:
	var shot := load("res://resources/abilities/enemy_shot.tres") as AbilityDefinition
	var profile := _profile(0.0)
	var enemy := _make_unit(false, Vector2i.ZERO, 0.0, [shot], profile)
	var target := _make_unit(true, Vector2i(3, 0), 0.0, [])
	var melee_plan := _choose(enemy, [enemy, target], Vector2i(5, 2))
	assert_eq(melee_plan.ability, null, "AI should never plan a Ranged ability while holding a Melee weapon")

	var bow := ItemDefinition.new()
	bow.weapon_type = ItemDefinition.WeaponType.RANGED
	bow.weapon_damage = 10
	enemy.equip_item(bow)
	var ranged_plan := _choose(enemy, [enemy, target], Vector2i(5, 2))
	assert_eq(ranged_plan.ability, shot, "AI should resume using the ability after a compatible weapon is equipped")


func test_team_coordination_prefers_shared_and_setup_defeat_targets() -> void:
	var b1_attack := _make_damage_ability("B1 Attack", AbilityDefinition.DeliveryType.PROJECTILE, 3.0, 20)
	var b2_attack := _make_damage_ability("B2 Follow-up", AbilityDefinition.DeliveryType.PROJECTILE, 1.0, 20)
	var b1 := _make_unit(false, Vector2i(2, 1), 0.0, [b1_attack], _profile(0.0))
	var b2 := _make_unit(false, Vector2i(5, 2), 0.0, [b2_attack], _profile(0.0))
	var a1 := _make_unit(true, Vector2i(4, 0), 0.0, [])
	var a2 := _make_unit(true, Vector2i(4, 2), 0.0, [])
	var units := _typed_units([b1, b2, a1, a2])
	var grid_size := Vector2i(7, 4)
	var pathfinder := GridPathfinderScript.new(grid_size) as GridPathfinder
	var targeting := AbilityTargetingScript.new(grid_size) as AbilityTargeting
	var focus_walls := {Vector2i(4, 1): true, Vector2i(5, 1): true}

	var focus_planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
	var focus_plan := focus_planner.choose_plan(
		b1,
		units,
		pathfinder,
		targeting,
		focus_walls,
		{},
		_typed_units([b1, b2, a1, a2])
	)
	assert_eq(focus_plan.target_cell, a2.grid_cell, "B1 should focus A2 because B2 can follow up before A2 acts; got %s" % focus_plan.get_debug_summary())
	assert_true(focus_plan.coordination_score > 0.0, "shared pressure should be visible in the chosen score")
	assert_eq(a1.current_health, 100, "coordination forecasts must not mutate A1")
	assert_eq(a2.current_health, 100, "coordination forecasts must not mutate A2")

	var late_planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
	var late_plan := late_planner.choose_plan(
		b1,
		units,
		pathfinder,
		targeting,
		focus_walls,
		{},
		_typed_units([b1, a2, b2, a1])
	)
	assert_true(is_zero_approx(late_plan.coordination_score), "ineligible allied actions should add no focus-fire value")

	a1.current_health = 20
	var lethal_planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
	var lethal_plan := lethal_planner.choose_plan(
		b1,
		units,
		pathfinder,
		targeting,
		focus_walls,
		{},
		_typed_units([b1, b2, a2, a1])
	)
	assert_eq(lethal_plan.target_cell, a1.grid_cell, "an immediate defeat should beat nonlethal shared pressure")

	a1.current_health = 100
	a2.current_health = 35
	var setup_planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
	var setup_plan := setup_planner.choose_plan(
		b1,
		units,
		pathfinder,
		targeting,
		focus_walls,
		{},
		_typed_units([b1, b2, a2, a1])
	)
	assert_eq(setup_plan.target_cell, a2.grid_cell, "combined pre-activation damage should make A2 the setup-defeat target")
	assert_true(setup_plan.coordination_score >= 12.5, "setup defeat should include its maximum-health bonus")


func test_reachability_tree_reconstructs_cached_weighted_paths() -> void:
	var pathfinder := GridPathfinderScript.new(Vector2i(5, 3)) as GridPathfinder
	pathfinder.set_cell_cost_multipliers({Vector2i(1, 1): 2.0})
	var result := pathfinder.build_reachability(
		Vector2i(0, 1),
		5.0,
		{},
		{Vector2i(1, 1): 10.0}
	)
	var path := pathfinder.reconstruct_reachable_path(result, Vector2i(2, 1))
	assert_true(path.size() >= 3, "the shared reachability result should reconstruct a complete path")
	assert_false(path.has(Vector2i(1, 1)), "equal-cost reconstruction should retain safer path preferences")
	assert_true(pathfinder.get_path_cost(path) <= 5.0, "the reconstructed path should respect the original movement budget")


func test_representative_planning_meets_the_shallow_search_budget() -> void:
	var mage_scene := load("res://scenes/enemies/mage.tscn") as PackedScene
	var mage := track(mage_scene.instantiate()) as TacticalCharacter
	mage.starting_grid_cell = Vector2i(1, 3)
	mage._ready()
	mage.reset_movement()
	mage.reset_ability_action()
	var friendlies: Array[TacticalCharacter] = [
		_make_unit(true, Vector2i(6, 1), 4.0, []),
		_make_unit(true, Vector2i(7, 3), 4.0, []),
		_make_unit(true, Vector2i(6, 5), 4.0, []),
	]
	friendlies[1].current_health = 45
	var units: Array[TacticalCharacter] = [mage]
	units.append_array(friendlies)
	var pathfinder := GridPathfinderScript.new(Vector2i(10, 7)) as GridPathfinder
	var targeting := AbilityTargetingScript.new(pathfinder.grid_size) as AbilityTargeting
	var planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
	var durations: Array[int] = []
	for _iteration in range(7):
		planner.choose_plan(mage, units, pathfinder, targeting)
		durations.append(planner.last_planning_duration_ms)
		assert_true(planner.last_candidate_count <= 32, "representative turns should keep the hard candidate cap")
		assert_true(planner.last_exact_reply_count <= 3, "representative turns should keep shallow exact replies")
		assert_true(planner.last_cache_hit_count > 0, "a nontrivial decision should reuse cached battlefield queries")
	durations.sort()
	assert_true(durations[floori(durations.size() / 2.0)] <= 16, "median representative planning should stay within 16 ms; got %s (generation %d, threat %d, candidates %d, reachability %d)" % [durations, planner.last_candidate_generation_duration_ms, planner.last_threat_evaluation_duration_ms, planner.last_candidate_count, planner.last_reachability_search_count])
	assert_true(durations[durations.size() - 1] <= 32, "representative planning should stay within 32 ms; got %s" % [durations])


func test_reusable_enemy_archetypes_equipment_variants_and_scene_isolation() -> void:
	var ranger := _assert_enemy_definition(
		"res://resources/enemies/ranger.tres",
		"Ranger", 90, 6.0, [8, 14, 8, 12],
		["Ranger Bow", "Ranger Armor"],
		["Enemy Shot", "Focus"]
	)
	var warrior := _assert_enemy_definition(
		"res://resources/enemies/goblin_warrior.tres",
		"Goblin Warrior", 115, 5.0, [12, 8, 5, 9],
		["Goblin Sword"],
		["Enemy Slash"]
	)
	var archer := _assert_enemy_definition(
		"res://resources/enemies/goblin_archer.tres",
		"Goblin Archer", 75, 6.0, [7, 11, 6, 11],
		["Goblin Bow"],
		["Enemy Shot"]
	)
	var wolf := _assert_enemy_definition(
		"res://resources/enemies/wolf.tres",
		"Wolf", 85, 7.0, [14, 10, 4, 14],
		["Wolf Claws"],
		["Strike"]
	)
	var mage := _assert_enemy_definition(
		"res://resources/enemies/mage.tres",
		"Mage", 70, 5.0, [5, 8, 15, 9],
		["Mage Staff"],
		["Fireball", "Ice Shard", "Heal", "Slow"]
	)
	var body_colors := {
		ranger.body_color: true,
		warrior.body_color: true,
		archer.body_color: true,
		wolf.body_color: true,
		mage.body_color: true,
	}
	assert_eq(body_colors.size(), 5, "every starter archetype should have a distinct body color")
	for definition in [ranger, warrior, archer, wolf, mage]:
		assert_eq(definition.health_bar_color, Color(0.96, 0.62, 0.18, 1), "%s should use the standard enemy health-bar color" % definition.display_name)

	var scene_expectations := {
		"res://scenes/enemies/ranger.tscn": "Ranger",
		"res://scenes/enemies/goblin_warrior.tscn": "Goblin Warrior",
		"res://scenes/enemies/goblin_warrior_club.tscn": "Goblin Warrior",
		"res://scenes/enemies/goblin_archer.tscn": "Goblin Archer",
		"res://scenes/enemies/wolf.tscn": "Wolf",
		"res://scenes/enemies/mage.tscn": "Mage",
	}
	for scene_path in scene_expectations:
		var enemy_scene := load(scene_path) as PackedScene
		assert_true(enemy_scene != null, "%s should be a reusable enemy scene" % scene_path)
		var enemy := track(enemy_scene.instantiate()) as TacticalCharacter
		assert_eq(enemy.definition.display_name, scene_expectations[scene_path], "thin scenes should reference their shared archetype")
		assert_eq(enemy.enemy_ai_profile, null, "thin scenes should inherit AI instead of duplicating it")
		assert_true(enemy.get_enemy_ai_profile() != null, "thin scenes should resolve their bundled AI")

	var sword_scene := load("res://scenes/enemies/goblin_warrior.tscn") as PackedScene
	var sword_goblin := track(sword_scene.instantiate()) as TacticalCharacter
	var second_sword_goblin := track(sword_scene.instantiate()) as TacticalCharacter
	sword_goblin._ready()
	second_sword_goblin._ready()
	assert_eq(sword_goblin.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON).display_name, "Goblin Sword", "the base Goblin Warrior should inherit its Sword")
	assert_eq(sword_goblin.get_equipped_weapon_type(), ItemDefinition.WeaponType.MELEE, "Goblin Sword should be a Melee weapon")
	assert_eq(sword_goblin.get_weapon_damage(), 8, "Goblin Sword should provide 8 weapon damage")
	assert_true(is_equal_approx(sword_goblin.get_effective_stat(UnitStat.Type.STRENGTH), 13.0), "Goblin Sword should add one Strength")
	assert_eq(sword_goblin.get_abilities()[0].calculate_damage(sword_goblin), 34, "Sword Goblin Slash should deal 8 + 200% of Strength 13")
	assert_eq(sword_goblin.get_initiative(), 9, "Sword Goblin should keep Speed 9")
	sword_goblin.apply_damage(20)
	sword_goblin.unequip_item(ItemDefinition.EquipmentSlot.WEAPON)
	assert_eq(second_sword_goblin.current_health, 115, "repeated scene instances should have independent health")
	assert_eq(second_sword_goblin.get_weapon_damage(), 8, "runtime equipment changes should not affect another instance")
	assert_eq(sword_goblin.definition.starting_equipment[0].display_name, "Goblin Sword", "runtime changes should not mutate the shared definition")

	var club_scene := load("res://scenes/enemies/goblin_warrior_club.tscn") as PackedScene
	var club_goblin := track(club_scene.instantiate()) as TacticalCharacter
	club_goblin._ready()
	assert_eq(club_goblin.definition, second_sword_goblin.definition, "Sword and Club Goblins should share one archetype")
	assert_eq(club_goblin.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON).display_name, "Goblin Club", "the Club variant should replace only its inherited weapon")
	assert_eq(club_goblin.get_weapon_damage(), 12, "Goblin Club should provide 12 weapon damage")
	assert_eq(club_goblin.get_abilities()[0].calculate_damage(club_goblin), 36, "Club Goblin Slash should deal 12 + 200% of Strength 12")
	assert_eq(club_goblin.get_initiative(), 8, "Goblin Club should reduce Speed by one")

	var ranger_unit := track((load("res://scenes/enemies/ranger.tscn") as PackedScene).instantiate()) as TacticalCharacter
	ranger_unit._ready()
	assert_eq(ranger_unit.get_weapon_damage(), 10, "Ranger Bow should provide 10 weapon damage")
	assert_eq(ranger_unit.get_equipped_weapon_type(), ItemDefinition.WeaponType.RANGED, "Ranger Bow should be a Ranged weapon")
	assert_true(is_equal_approx(ranger_unit.get_effective_stat(UnitStat.Type.DEXTERITY), 16.0), "Ranger Armor should add two Dexterity")
	assert_eq(ranger_unit.get_abilities()[0].calculate_damage(ranger_unit), 26, "Ranger Shot should use Bow damage and equipped Dexterity")
	var archer_unit := track((load("res://scenes/enemies/goblin_archer.tscn") as PackedScene).instantiate()) as TacticalCharacter
	archer_unit._ready()
	assert_eq(archer_unit.get_weapon_damage(), 7, "Goblin Bow should provide 7 weapon damage")
	assert_eq(archer_unit.get_equipped_weapon_type(), ItemDefinition.WeaponType.RANGED, "Goblin Bow should be a Ranged weapon")
	assert_true(is_equal_approx(archer_unit.get_effective_stat(UnitStat.Type.DEXTERITY), 12.0), "Goblin Bow should add one Dexterity")
	assert_eq(archer_unit.get_abilities()[0].calculate_damage(archer_unit), 19, "Goblin Archer Shot should use Bow damage and equipped Dexterity")
	var wolf_unit := track((load("res://scenes/enemies/wolf.tscn") as PackedScene).instantiate()) as TacticalCharacter
	wolf_unit._ready()
	assert_eq(wolf_unit.get_equipped_items().size(), 1, "Wolf should start with its reusable Claws weapon")
	assert_eq(wolf_unit.get_equipped_weapon().display_name, "Wolf Claws", "Wolf should equip Wolf Claws")
	assert_eq(wolf_unit.get_equipped_weapon_type(), ItemDefinition.WeaponType.MELEE, "Wolf Claws should be Melee")
	assert_eq(wolf_unit.get_weapon_damage(), 0, "Wolf Claws should add no innate weapon damage")
	assert_true(wolf_unit.get_abilities()[0].can_be_used_by(wolf_unit), "Wolf Claws should keep Strike available")
	assert_eq(wolf_unit.get_abilities()[0].calculate_damage(wolf_unit), 14, "Wolf Strike should scale from Strength without weapon damage")
	var mage_unit := track((load("res://scenes/enemies/mage.tscn") as PackedScene).instantiate()) as TacticalCharacter
	mage_unit._ready()
	assert_true(is_equal_approx(mage_unit.get_effective_stat(UnitStat.Type.INTELLIGENCE), 17.0), "Mage Staff should add two Intelligence")
	assert_eq(mage_unit.get_abilities()[0].calculate_damage(mage_unit), 37, "Mage Fireball should deal 20 plus effective Intelligence")
	assert_eq(mage_unit.get_abilities()[1].calculate_damage(mage_unit), 32, "Mage Ice Shard should deal 15 plus effective Intelligence")
	assert_eq(mage_unit.get_abilities()[2].calculate_primary_effect_amount(mage_unit), 42, "Mage Heal should restore 25 plus effective Intelligence")
	for ability in mage_unit.get_abilities():
		assert_true(ability.can_be_used_by(mage_unit), "Mage abilities should remain usable despite the Staff being a Melee weapon")

	var ranger_variant := track(TacticalCharacterScript.new()) as TacticalCharacter
	ranger_variant.definition = ranger
	var club := load("res://resources/items/goblin_club.tres") as ItemDefinition
	var equipment_overrides: Array[ItemDefinition] = [club]
	ranger_variant.starting_equipment_overrides = equipment_overrides
	ranger_variant._ready()
	assert_eq(ranger_variant.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON), club, "an override should replace the inherited item in the same slot")
	assert_eq(ranger_variant.get_equipped_item(ItemDefinition.EquipmentSlot.ARMOR).display_name, "Ranger Armor", "an override should retain inherited items in other slots")
	assert_eq(ranger.starting_equipment[0].display_name, "Ranger Bow", "an instance override should leave the shared Ranger equipment unchanged")

	var explicit_ai := load("res://resources/ai/general_ai.tres") as EnemyAIProfile
	ranger_variant.enemy_ai_profile = explicit_ai
	assert_eq(ranger_variant.get_enemy_ai_profile(), explicit_ai, "an explicit per-instance AI profile should override the bundled profile")
	var legacy := load("res://resources/enemy_raider.tres") as CharacterDefinition
	assert_true(legacy != null, "the legacy Enemy Raider resource should remain loadable")
	var legacy_raider := track(TacticalCharacterScript.new()) as TacticalCharacter
	legacy_raider.definition = legacy
	legacy_raider._ready()
	assert_eq(legacy_raider.get_equipped_weapon_type(), ItemDefinition.WeaponType.MELEE, "Raider Weapon should remain Melee")
	assert_true(legacy_raider.get_abilities()[0].can_be_used_by(legacy_raider), "Enemy Slash should remain available to the Raider")
	assert_false(legacy_raider.get_abilities()[1].can_be_used_by(legacy_raider), "Enemy Shot should remain visible but unavailable to the Melee Raider")


func test_starter_enemy_archetype_plans_are_deterministic() -> void:
	var scene_paths: Array[String] = [
		"res://scenes/enemies/goblin_warrior.tscn",
		"res://scenes/enemies/goblin_archer.tscn",
		"res://scenes/enemies/mage.tscn",
		"res://scenes/enemies/ranger.tscn",
		"res://scenes/enemies/wolf.tscn",
	]
	var grid_size := Vector2i(8, 5)
	for scene_path in scene_paths:
		var enemy_scene := load(scene_path) as PackedScene
		var enemy := track(enemy_scene.instantiate()) as TacticalCharacter
		enemy.starting_grid_cell = Vector2i(1, 2)
		enemy._ready()
		enemy.reset_movement()
		enemy.reset_ability_action()
		var target := _make_unit(true, Vector2i(6, 2), 0.0, [])
		var units: Array[TacticalCharacter] = [enemy, target]
		var pathfinder := GridPathfinderScript.new(grid_size) as GridPathfinder
		var targeting := AbilityTargetingScript.new(grid_size) as AbilityTargeting
		var first_planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
		var second_planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
		var first := first_planner.choose_plan(enemy, units, pathfinder, targeting)
		var second := second_planner.choose_plan(enemy, units, pathfinder, targeting)
		assert_eq(second.sequence, first.sequence, "%s should choose a deterministic action sequence" % enemy.definition.display_name)
		assert_eq(second.ability, first.ability, "%s should choose a deterministic ability" % enemy.definition.display_name)
		assert_eq(second.target_cell, first.target_cell, "%s should choose a deterministic target" % enemy.definition.display_name)
		assert_eq(second.get_end_cell(enemy.grid_cell), first.get_end_cell(enemy.grid_cell), "%s should choose a deterministic destination" % enemy.definition.display_name)
		assert_true(is_equal_approx(second.total_score, first.total_score), "%s should produce a deterministic score" % enemy.definition.display_name)


func test_sample_scene_uses_goblin_archetypes_and_dev_history() -> void:
	var scene := ResourceLoader.load("res://main.tscn", "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var root: Node = track(scene.instantiate())
	var melee := root.get_node("Characters/MeleeEnemy") as TacticalCharacter
	var ranged := root.get_node("Characters/RangedEnemy") as TacticalCharacter
	assert_eq(melee.definition.display_name, "Goblin Warrior", "the sample melee enemy should use the Sword Goblin Warrior")
	assert_eq(ranged.definition.display_name, "Goblin Archer", "the sample ranged enemy should use the Goblin Archer")
	assert_eq(melee.enemy_ai_profile, null, "the sample melee enemy should inherit its bundled AI")
	assert_eq(ranged.enemy_ai_profile.display_name, "General AI", "the sample override should migrate to General AI")
	assert_eq(melee.get_enemy_ai_profile().display_name, "General AI", "the sample melee enemy should resolve the general profile")
	assert_eq(ranged.get_enemy_ai_profile().display_name, "General AI", "the sample ranged enemy should resolve the general profile")
	assert_eq(melee.get_abilities().size(), 1, "the Goblin Warrior should expose only Enemy Slash")
	assert_eq(ranged.get_abilities().size(), 1, "the sample Goblin Archer override should remain unchanged")
	assert_eq(melee.starting_grid_cell, Vector2i(7, 11), "sample melee placement should stay unchanged")
	assert_eq(ranged.starting_grid_cell, Vector2i(1, 10), "sample ranged placement should stay unchanged")
	assert_true(root.has_node("HUD/DevButton"), "the sample HUD should expose the Dev button")
	assert_eq(root.get_node("HUD/DevButton").text, "Dev", "the developer history button should have a clear compact label")
	assert_true(root.has_node("HUD/DevHistoryPanel"), "the sample HUD should contain an AI score history panel")
	assert_false(root.get_node("HUD/DevHistoryPanel").visible, "AI scores should stay off the battlefield until Dev is pressed")


func _assert_enemy_definition(
	path: String,
	expected_name: String,
	expected_health: int,
	expected_movement: float,
	expected_stats: Array,
	expected_items: Array,
	expected_abilities: Array
) -> EnemyDefinition:
	var definition := load(path) as EnemyDefinition
	assert_true(definition != null, "%s should load as an EnemyDefinition" % expected_name)
	assert_eq(definition.display_name, expected_name, "the archetype should keep its display name")
	assert_eq(definition.faction, CharacterDefinition.Faction.ENEMY, "%s should default to the Enemy faction" % expected_name)
	assert_eq(definition.max_health, expected_health, "%s should keep its configured HP" % expected_name)
	assert_true(is_equal_approx(definition.movement_range, expected_movement), "%s should keep its configured base movement" % expected_name)
	assert_eq([definition.strength, definition.dexterity, definition.intelligence, definition.speed], expected_stats, "%s should keep its configured core stats" % expected_name)
	assert_true(definition.ai_profile != null, "%s should bundle an AI profile" % expected_name)
	assert_eq(definition.ai_profile.display_name, "General AI", "%s should bundle the general ability-driven AI" % expected_name)
	var item_names: Array[String] = []
	for item in definition.starting_equipment:
		item_names.append(item.display_name)
	assert_eq(item_names, expected_items, "%s should bundle the expected equipment" % expected_name)
	var ability_names: Array[String] = []
	for ability in definition.abilities:
		ability_names.append(ability.display_name)
	assert_eq(ability_names, expected_abilities, "%s should bundle the expected abilities" % expected_name)
	return definition


func test_enemy_controller_has_no_planning_or_preview_delays() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/initiative_battle_controller.gd")
	assert_false(source.contains("is planning..."), "enemy turns should not expose a planning phase")
	assert_false(source.contains("enemy_path_preview_delay"), "enemy path previews should not add an artificial delay")
	assert_false(source.contains("enemy_ability_preview_delay"), "enemy ability previews should not add an artificial delay")
	assert_false(source.contains("_show_enemy_ability_preview"), "enemy abilities should execute without a preview overlay")
	assert_true(source.contains("call_deferred(\"_finish_enemy_turn\", unit)"), "instant enemy turns should advance through a guarded deferred callback")
	assert_true(source.contains("last_candidate_generation_duration_ms"), "Dev history should expose candidate-generation timing")
	assert_true(source.contains("last_threat_evaluation_duration_ms"), "Dev history should expose threat-evaluation timing")
	assert_true(source.contains("last_candidate_count"), "Dev history should expose the candidate count")


func _choose(
	actor: TacticalCharacter,
	units_value: Array,
	grid_size: Vector2i
) -> EnemyTurnPlan:
	var pathfinder := GridPathfinderScript.new(grid_size) as GridPathfinder
	var targeting := AbilityTargetingScript.new(grid_size) as AbilityTargeting
	var planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
	return planner.choose_plan(actor, _typed_units(units_value), pathfinder, targeting)


func _profile(risk_aversion: float = 1.0) -> EnemyAIProfile:
	var profile := EnemyAIProfileScript.new() as EnemyAIProfile
	profile.risk_aversion = risk_aversion
	return profile


func _make_unit(
	friendly: bool,
	cell: Vector2i,
	movement: float,
	abilities_value: Array,
	profile: EnemyAIProfile = null,
	weapon_type: ItemDefinition.WeaponType = ItemDefinition.WeaponType.MELEE
) -> TacticalCharacter:
	var definition := CharacterDefinitionScript.new() as CharacterDefinition
	definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	definition.max_health = 100
	definition.movement_range = movement
	var abilities: Array[AbilityDefinition] = []
	for ability in abilities_value:
		abilities.append(ability as AbilityDefinition)
	definition.abilities = abilities
	if not friendly:
		var weapon := ItemDefinition.new()
		weapon.weapon_type = weapon_type
		weapon.weapon_damage = 10
		var equipment: Array[ItemDefinition] = [weapon]
		definition.starting_equipment = equipment
	var unit := track(TacticalCharacterScript.new()) as TacticalCharacter
	unit.definition = definition
	unit.enemy_ai_profile = profile
	unit.movement_range_override = movement
	unit.starting_grid_cell = cell
	unit._ready()
	unit.reset_movement()
	unit.reset_ability_action()
	return unit


func _make_damage_ability(
	name_value: String,
	delivery: AbilityDefinition.DeliveryType,
	range_value: float,
	amount: int
) -> AbilityDefinition:
	var ability := AbilityDefinitionScript.new() as AbilityDefinition
	ability.display_name = name_value
	ability.delivery_type = delivery
	ability.range = range_value
	ability.target_flags = AbilityDefinition.TargetFlags.ENEMY
	ability.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	ability.damage_type = DamageCalculator.Type.MAGICAL
	ability.innate_damage = amount
	ability.scaling_stat = UnitStat.Type.NONE
	return ability


func _typed_units(values: Array) -> Array[TacticalCharacter]:
	var result: Array[TacticalCharacter] = []
	for value in values:
		result.append(value as TacticalCharacter)
	return result
