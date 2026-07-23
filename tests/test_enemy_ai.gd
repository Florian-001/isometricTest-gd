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


func suite_name() -> String:
	return "enemy_ai"


func test_profile_defaults_resources_and_configuration_warnings() -> void:
	var profile := EnemyAIProfileScript.new() as EnemyAIProfile
	assert_eq(profile.lookahead_candidate_limit, 32, "AI profiles should default to a 32-plan beam")
	assert_true(is_equal_approx(profile.counterplay_discount, 0.75), "counterplay should be discounted by 0.75")
	assert_true(is_equal_approx(profile.damage_reward, 1.0), "damage should reward effective HP loss")
	assert_true(is_equal_approx(profile.healing_reward, 0.75), "healing should use its planned default weight")

	var melee_profile := load("res://resources/ai/melee_ai.tres") as EnemyAIProfile
	var ranged_profile := load("res://resources/ai/ranged_ai.tres") as EnemyAIProfile
	assert_eq(melee_profile.behavior_style, EnemyAIProfile.BehaviorStyle.MELEE, "melee template should be editable and typed")
	assert_eq(ranged_profile.behavior_style, EnemyAIProfile.BehaviorStyle.RANGED, "ranged template should be editable and typed")

	var enemy := _make_unit(false, Vector2i.ZERO, 4.0, [])
	assert_true(enemy._get_configuration_warnings().size() > 0, "an enemy without an AI profile should warn in the Inspector")
	enemy.enemy_ai_profile = melee_profile
	assert_true(enemy._get_configuration_warnings().is_empty(), "attaching a profile should resolve the enemy warning")
	var friendly := _make_unit(true, Vector2i.ONE, 4.0, [])
	friendly.enemy_ai_profile = melee_profile
	assert_true(friendly._get_configuration_warnings().size() > 0, "friendly units should warn that enemy AI is ignored")


func test_effect_forecasts_clamp_health_and_support_custom_utility() -> void:
	var caster := _make_unit(false, Vector2i.ZERO, 4.0, [])
	var target := _make_unit(true, Vector2i.ONE, 4.0, [])
	var damage := DamageEffectScript.new() as DamageEffectDefinition
	damage.amount = 30
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


func test_virtual_origin_targeting_does_not_move_live_unit() -> void:
	var caster := _make_unit(false, Vector2i.ZERO, 4.0, [])
	var target := _make_unit(true, Vector2i(3, 0), 4.0, [])
	var ability := _make_damage_ability("Short Shot", AbilityDefinition.DeliveryType.PROJECTILE, 1.0, 10)
	var units: Array[TacticalCharacter] = [caster, target]
	var targeting := AbilityTargetingScript.new(Vector2i(6, 6)) as AbilityTargeting
	assert_false(targeting.is_valid_primary_target(caster, target.grid_cell, ability, units), "the live origin should remain out of range")
	assert_true(targeting.is_valid_primary_target_from(caster, Vector2i(2, 0), target.grid_cell, ability, units), "a hypothetical origin should be evaluated without mutation")
	assert_eq(caster.grid_cell, Vector2i.ZERO, "virtual targeting must not move the live caster")


func test_melee_profile_prioritizes_melee_when_adjacent() -> void:
	var slash := load("res://resources/abilities/enemy_slash.tres") as AbilityDefinition
	var shot := load("res://resources/abilities/enemy_shot.tres") as AbilityDefinition
	var profile := _profile(EnemyAIProfile.BehaviorStyle.MELEE, 0.0)
	var enemy := _make_unit(false, Vector2i(2, 2), 3.0, [slash, shot], profile)
	var target := _make_unit(true, Vector2i(3, 2), 3.0, [])
	var plan := _choose(enemy, [enemy, target], Vector2i(7, 7))
	assert_eq(plan.ability, slash, "adjacent melee AI should prefer its melee delivery")
	assert_true(plan.effect_score >= 30.0, "the chosen melee attack should forecast its damage")


func test_melee_profile_closes_and_uses_ranged_fallback() -> void:
	var slash := load("res://resources/abilities/enemy_slash.tres") as AbilityDefinition
	var shot := load("res://resources/abilities/enemy_shot.tres") as AbilityDefinition
	var profile := _profile(EnemyAIProfile.BehaviorStyle.MELEE, 0.0)
	var enemy := _make_unit(false, Vector2i(0, 2), 2.0, [slash, shot], profile)
	var target := _make_unit(true, Vector2i(6, 2), 3.0, [])
	var plan := _choose(enemy, [enemy, target], Vector2i(8, 6))
	assert_eq(plan.ability, shot, "melee AI should use a ranged ability when melee cannot be reached")
	assert_true(plan.get_end_cell(enemy.grid_cell).x > enemy.grid_cell.x, "the fallback shot should still end closer to the opponent")


func test_ranged_profile_shoots_and_retreats_to_standoff() -> void:
	var slash := load("res://resources/abilities/enemy_slash.tres") as AbilityDefinition
	var shot := load("res://resources/abilities/enemy_shot.tres") as AbilityDefinition
	var profile := _profile(EnemyAIProfile.BehaviorStyle.RANGED, 0.0)
	var enemy := _make_unit(false, Vector2i(3, 3), 3.0, [slash, shot], profile)
	var target := _make_unit(true, Vector2i(5, 3), 3.0, [])
	var plan := _choose(enemy, [enemy, target], Vector2i(10, 7))
	assert_eq(plan.ability, shot, "a ranged unit outside melee reach should use its ranged attack")
	assert_true(plan.sequence in [EnemyTurnPlan.Sequence.MOVE_CAST, EnemyTurnPlan.Sequence.CAST_MOVE, EnemyTurnPlan.Sequence.MOVE_CAST_MOVE], "a threatened ranged unit should combine its attack with repositioning")
	var final_distance := AbilityTargetingScript.new(Vector2i(10, 7)).get_weighted_distance(plan.get_end_cell(enemy.grid_cell), target.grid_cell)
	assert_true(final_distance >= 3.0, "the ranged profile should increase separation while retaining a shot")


func test_move_cast_move_candidates_respect_the_shared_budget() -> void:
	var shot := _make_damage_ability("Point Shot", AbilityDefinition.DeliveryType.PROJECTILE, 1.0, 20)
	var profile := _profile(EnemyAIProfile.BehaviorStyle.MELEE, 0.0)
	profile.lookahead_candidate_limit = 256
	profile.post_cast_position_limit = 8
	var enemy := _make_unit(false, Vector2i(0, 1), 2.0, [shot], profile)
	var target := _make_unit(true, Vector2i(2, 1), 0.0, [])
	var pathfinder := GridPathfinderScript.new(Vector2i(4, 3)) as GridPathfinder
	var targeting := AbilityTargetingScript.new(Vector2i(4, 3)) as AbilityTargeting
	var planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
	planner.choose_plan(enemy, _typed_units([enemy, target]), pathfinder, targeting)
	var found_split := false
	for candidate in planner.ranked_candidates:
		if candidate.sequence == EnemyTurnPlan.Sequence.MOVE_CAST_MOVE:
			found_split = true
			assert_true(candidate.movement_cost <= enemy.remaining_movement + GridPathfinder.COST_EPSILON, "split movement must share one exact budget")
	assert_true(found_split, "the tactical search should retain legal move-cast-move candidates")


func test_counterplay_forecast_chooses_safer_plan_without_mutation() -> void:
	var shot := _make_damage_ability("Long Shot", AbilityDefinition.DeliveryType.PROJECTILE, 4.0, 40)
	var counter := _make_damage_ability("Counter Strike", AbilityDefinition.DeliveryType.MELEE, 1.0, 100)
	var enemy := _make_unit(false, Vector2i(0, 1), 3.0, [shot])
	var target := _make_unit(true, Vector2i(4, 1), 0.0, [counter])
	var units: Array[TacticalCharacter] = [enemy, target]

	enemy.enemy_ai_profile = _profile(EnemyAIProfile.BehaviorStyle.MELEE, 0.0)
	var aggressive := _choose(enemy, units, Vector2i(6, 4))
	var aggressive_distance := AbilityTargetingScript.new(Vector2i(6, 4)).get_weighted_distance(aggressive.get_end_cell(enemy.grid_cell), target.grid_cell)

	enemy.enemy_ai_profile = _profile(EnemyAIProfile.BehaviorStyle.MELEE, 1.0)
	var cautious := _choose(enemy, units, Vector2i(6, 4))
	var cautious_distance := AbilityTargetingScript.new(Vector2i(6, 4)).get_weighted_distance(cautious.get_end_cell(enemy.grid_cell), target.grid_cell)
	assert_true(cautious_distance > aggressive_distance, "two-ply scoring should avoid an otherwise lethal adjacent counterattack")
	assert_true(cautious.score_breakdown.has("counterplay"), "counterplay should be represented in the score breakdown")
	assert_eq(enemy.grid_cell, Vector2i(0, 1), "planning must not mutate the enemy position")
	assert_eq(enemy.current_health, 100, "planning must not mutate live health")
	assert_eq(target.current_health, 100, "forecast damage must remain side-effect-free")


func test_walls_block_ai_ability_targeting() -> void:
	var shot := load("res://resources/abilities/enemy_shot.tres") as AbilityDefinition
	var profile := _profile(EnemyAIProfile.BehaviorStyle.RANGED, 0.0)
	var enemy := _make_unit(false, Vector2i.ZERO, 0.0, [shot], profile)
	var target := _make_unit(true, Vector2i(3, 0), 0.0, [])
	var pathfinder := GridPathfinderScript.new(Vector2i(5, 1)) as GridPathfinder
	var targeting := AbilityTargetingScript.new(Vector2i(5, 1)) as AbilityTargeting
	var planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
	var walls := {Vector2i(2, 0): true}
	var plan := planner.choose_plan(enemy, _typed_units([enemy, target]), pathfinder, targeting, walls)
	assert_eq(plan.ability, null, "AI should not select a projectile through a wall")


func test_sample_scene_has_two_profiles_shared_loadout_and_dev_history() -> void:
	ResourceLoader.load("res://resources/enemy_raider.tres", "", ResourceLoader.CACHE_MODE_REPLACE)
	var scene := ResourceLoader.load("res://main.tscn", "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var root: Node = track(scene.instantiate())
	var melee := root.get_node("Characters/MeleeEnemy") as TacticalCharacter
	var ranged := root.get_node("Characters/RangedEnemy") as TacticalCharacter
	assert_eq(melee.enemy_ai_profile.behavior_style, EnemyAIProfile.BehaviorStyle.MELEE, "sample melee enemy should use the melee template")
	assert_eq(ranged.enemy_ai_profile.behavior_style, EnemyAIProfile.BehaviorStyle.RANGED, "sample ranged enemy should use the ranged template")
	assert_eq(melee.definition, ranged.definition, "both samples should share the same mixed character loadout")
	assert_eq(melee.get_abilities().size(), 2, "the enemy template should expose slash and shot in the Inspector")
	assert_eq(melee.speed_override, 10, "sample melee Speed should remain 10")
	assert_eq(ranged.speed_override, 9, "sample ranged Speed should be 9")
	assert_eq(ranged.starting_grid_cell, Vector2i(9, 3), "sample ranged placement should match the design")
	assert_true(root.has_node("HUD/DevButton"), "the sample HUD should expose the Dev button")
	assert_eq(root.get_node("HUD/DevButton").text, "Dev", "the developer history button should have a clear compact label")
	assert_true(root.has_node("HUD/DevHistoryPanel"), "the sample HUD should contain an AI score history panel")
	assert_false(root.get_node("HUD/DevHistoryPanel").visible, "AI scores should stay off the battlefield until Dev is pressed")


func test_enemy_controller_has_no_planning_or_preview_delays() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/initiative_battle_controller.gd")
	assert_false(source.contains("is planning..."), "enemy turns should not expose a planning phase")
	assert_false(source.contains("enemy_path_preview_delay"), "enemy path previews should not add an artificial delay")
	assert_false(source.contains("enemy_ability_preview_delay"), "enemy ability previews should not add an artificial delay")
	assert_false(source.contains("_show_enemy_ability_preview"), "enemy abilities should execute without a preview overlay")
	assert_true(source.contains("call_deferred(\"_finish_enemy_turn\", unit)"), "instant enemy turns should advance through a guarded deferred callback")


func _choose(
	actor: TacticalCharacter,
	units_value: Array,
	grid_size: Vector2i
) -> EnemyTurnPlan:
	var pathfinder := GridPathfinderScript.new(grid_size) as GridPathfinder
	var targeting := AbilityTargetingScript.new(grid_size) as AbilityTargeting
	var planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
	return planner.choose_plan(actor, _typed_units(units_value), pathfinder, targeting)


func _profile(style: EnemyAIProfile.BehaviorStyle, counter_discount: float) -> EnemyAIProfile:
	var profile := EnemyAIProfileScript.new() as EnemyAIProfile
	profile.behavior_style = style
	profile.counterplay_discount = counter_discount
	return profile


func _make_unit(
	friendly: bool,
	cell: Vector2i,
	movement: float,
	abilities_value: Array,
	profile: EnemyAIProfile = null
) -> TacticalCharacter:
	var definition := CharacterDefinitionScript.new() as CharacterDefinition
	definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	definition.max_health = 100
	definition.movement_range = movement
	var abilities: Array[AbilityDefinition] = []
	for ability in abilities_value:
		abilities.append(ability as AbilityDefinition)
	definition.abilities = abilities
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
	var damage := DamageEffectScript.new() as DamageEffectDefinition
	damage.amount = amount
	var effects: Array[AbilityEffectDefinition] = [damage]
	ability.effects = effects
	return ability


func _typed_units(values: Array) -> Array[TacticalCharacter]:
	var result: Array[TacticalCharacter] = []
	for value in values:
		result.append(value as TacticalCharacter)
	return result
