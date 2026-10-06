extends SceneTree

const DEFAULTS := {
	"damage_weight": 1.0,
	"healing_weight": 1.0,
	"utility_weight": 1.0,
	"friendly_damage_penalty": 2.0,
	"kill_weight": 0.0,
	"immediate_defeat_ratio": 0.25,
	"future_value_weight": 0.25,
	"shared_pressure_weight": 0.25,
	"setup_defeat_ratio": 0.125,
}
const GRID_SIZE := Vector2i(8, 8)
var checks := 0
var failures: Array[String] = []
var fixture: McpTestSuite


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	fixture = load("res://tests/test_enemy_ai.gd").new()
	_test_resource()
	_test_effect_weights()
	_test_decisions_and_inheritance()
	_test_target_shortlist()
	_test_position_and_team()
	_test_per_hit_damage_over_time()
	fixture._free_tracked()
	print("AI_PROFILE_TESTS_%s: %d checks, %d failures" % [
		"OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func profile() -> EnemyAIProfile:
	var result := EnemyAIProfile.new()
	result.future_value_weight = 0.0
	result.shared_pressure_weight = 0.0
	result.setup_defeat_ratio = 0.0
	result.immediate_defeat_ratio = 0.0
	return result


func unit(friendly: bool, cell: Vector2i, abilities: Array = [], ai: EnemyAIProfile = null) -> TacticalCharacter:
	var actor := fixture._make_unit(friendly, cell, 0.0, abilities, ai) as TacticalCharacter
	actor._remaining_movement = 0.0
	return actor


func damage(amount: int) -> AbilityDefinition:
	return fixture._make_damage_ability("Damage %d" % amount,
		AbilityDefinition.DeliveryType.CAST_ON_TARGET, 10.0, amount)


func heal(amount: int) -> AbilityDefinition:
	var result := AbilityDefinition.new()
	result.display_name = "Heal"
	result.effect = AbilityDefinition.PrimaryEffect.HEAL
	result.effect_amount = amount
	result.scaling_stat = UnitStat.Type.NONE
	result.target_flags = AbilityDefinition.TargetFlags.FRIEND
	result.range = 10.0
	return result


func plan(actor: TacticalCharacter, units: Array[TacticalCharacter]) -> EnemyTurnPlan:
	return EnemyAIPlanner.new().choose_plan(actor, units, GridPathfinder.new(GRID_SIZE),
		AbilityTargeting.new(GRID_SIZE), {}, {}, units)


func score(caster: TacticalCharacter, target: TacticalCharacter, estimate: Dictionary,
	ai: EnemyAIProfile, units: Array[TacticalCharacter]) -> float:
	return EnemyAIPlanner.new()._score_effect_estimate(caster, target, estimate, ai,
		AIBoardSnapshot.from_battle(units, GRID_SIZE))


func _test_resource() -> void:
	var fresh := EnemyAIProfile.new()
	var shared := EnemyAIProfile.get_default()
	var properties := {}
	for property in fresh.get_property_list():
		properties[property.name] = property
	for key in DEFAULTS:
		check(is_equal_approx(fresh.get(key), DEFAULTS[key]), "%s preserves the original default" % key)
		check(is_equal_approx(shared.get(key), DEFAULTS[key]), "shared profile inherits %s" % key)
		check((int(properties[key].usage) & PROPERTY_USAGE_EDITOR) != 0,
			"%s is exposed in the Inspector" % key)
		check(properties[key].hint == PROPERTY_HINT_RANGE, "%s has an Inspector numeric range" % key)
		fresh.set(key, DEFAULTS[key] + 0.75)
	var path := "res://.godot/ai_profile_validation/edited_profile.tres"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	check(ResourceSaver.save(fresh, path) == OK, "edited profile saves")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as EnemyAIProfile
	check(loaded != null, "edited profile reloads")
	if loaded != null:
		for key in DEFAULTS:
			check(is_equal_approx(loaded.get(key), fresh.get(key)), "%s survives resource reload" % key)


func _test_effect_weights() -> void:
	var ai := profile()
	var caster := unit(false, Vector2i(1, 1))
	var opponent := unit(true, Vector2i(2, 1))
	var ally := unit(false, Vector2i(1, 2))
	var units: Array[TacticalCharacter] = [caster, opponent, ally]
	check(score(caster, opponent, {"health_delta": -10}, null, units) == 10.0,
		"legacy forecasts without a profile use shared defaults")
	ai.damage_weight = 3.0
	check(score(caster, opponent, {"health_delta": -10}, ai, units) == 30.0,
		"damage weight scales opponent HP damage")
	check(score(caster, ally, {"health_delta": -10}, ai, units) == -60.0,
		"damage and allied penalty combine")
	ai.friendly_damage_penalty = 0.5
	check(score(caster, ally, {"health_delta": -10}, ai, units) == -15.0,
		"allied damage penalty is editable")
	opponent.current_health = 5
	ai.immediate_defeat_ratio = 0.5
	check(score(caster, opponent, {"health_delta": -10}, ai, units)
		== 15.0 + opponent.get_max_health() * 0.5, "defeat reward uses maximum HP and the edited ratio")
	check(opponent.current_health == 5, "scoring leaves live health unchanged")
	ally.current_health = ally.get_max_health() / 2
	ai.healing_weight = 3.0
	check(score(caster, ally, {"health_delta": 10}, ai, units) == 15.0,
		"healing weight retains missing-health urgency")
	ai.utility_weight = 4.0
	check(score(caster, ally, {"utility_hint": 7.0}, ai, units) == 28.0,
		"positive effect utility is editable")
	check(score(caster, ally, {"utility_hint": -7.0}, ai, units) == -28.0,
		"negative effect utility keeps its sign")
	var terrain_state := AIBoardSnapshot.from_battle(units, GRID_SIZE)
	check(EnemyAIPlanner.new()._score_terrain_estimate(caster,
		{"health_delta": -4, "utility_hint": -2.0}, terrain_state, ai) == -14.0,
		"terrain uses edited damage, allied penalty, and utility weights")


func _test_decisions_and_inheritance() -> void:
	for friendly in [true, false]:
		var ai := profile()
		var strike := damage(10)
		var healing := heal(10)
		var actor := unit(friendly, Vector2i(1, 1), [strike, healing], ai)
		var opponent := unit(not friendly, Vector2i(3, 1))
		var ally := unit(friendly, Vector2i(1, 3))
		ally.current_health = ally.get_max_health() / 2
		var units: Array[TacticalCharacter] = [actor, opponent, ally]
		check(plan(actor, units).ability == strike, "default scoring prefers damage for faction %s" % friendly)
		ai.healing_weight = 3.0
		check(plan(actor, units).ability == healing, "higher healing value changes faction %s's decision" % friendly)
		ai.damage_weight = 4.0
		check(plan(actor, units).ability == strike, "higher damage value changes faction %s's decision" % friendly)
		ai.damage_weight = 0.0
		ai.healing_weight = 0.0
		check(plan(actor, units).sequence == EnemyTurnPlan.Sequence.HOLD,
			"zero-value casts are discarded for faction %s" % friendly)
	var ai := profile()
	var strike := damage(10)
	var buff := AbilityDefinition.new()
	buff.display_name = "Buff"
	buff.range = 10.0
	buff.target_flags = AbilityDefinition.TargetFlags.SELF
	var utility := AbilityEffectDefinition.new()
	utility.ai_utility_hint = 6.0
	buff.effects = [utility]
	var actor := unit(false, Vector2i(1, 1), [strike, buff], ai)
	var opponent := unit(true, Vector2i(3, 1))
	var units: Array[TacticalCharacter] = [actor, opponent]
	check(plan(actor, units).ability == strike, "default utility loses to the stronger attack")
	ai.utility_weight = 3.0
	check(plan(actor, units).ability == buff, "edited utility changes ability selection")
	var inherited := EnemyDefinition.new()
	inherited.ai_profile = ai
	var archetype_actor := fixture.track(TacticalCharacter.new()) as TacticalCharacter
	archetype_actor.definition = inherited
	check(EnemyAIPlanner.new()._resolve_profile(archetype_actor) == ai, "enemy archetype supplies its profile")
	var override := EnemyAIProfile.new()
	archetype_actor.enemy_ai_profile = override
	check(EnemyAIPlanner.new()._resolve_profile(archetype_actor) == override, "per-unit profile overrides the archetype")
	actor.enemy_ai_profile = null
	var shared := EnemyAIProfile.get_default()
	var original_utility := shared.utility_weight
	shared.utility_weight = 4.0
	check(plan(actor, units).ability == buff, "unassigned enemy uses edited shared profile")
	shared.utility_weight = original_utility
	var friendly_actor := unit(true, Vector2i(1, 1), [strike, buff])
	var enemy := unit(false, Vector2i(3, 1))
	shared.utility_weight = 4.0
	check(plan(friendly_actor, [friendly_actor, enemy]).ability == buff,
		"friendly Auto Battle uses edited shared profile")
	shared.utility_weight = original_utility


func _test_target_shortlist() -> void:
	var ai := profile()
	var strike := damage(10)
	var actor := unit(false, Vector2i(1, 1), [strike], ai)
	var units: Array[TacticalCharacter] = [actor]
	for cell in [Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3), Vector2i(2, 3)]:
		units.append(unit(true, cell))
	var weak := units[4]
	weak.current_health = 5
	check(plan(actor, units).target_cell != weak.grid_cell, "without defeat value the weaker target loses the shortlist")
	ai.immediate_defeat_ratio = 1.0
	var chosen := plan(actor, units)
	check(chosen.target_cell == weak.grid_cell, "edited defeat ratio changes the shortlist and chosen target")
	check(chosen.effect_score == 5.0 + weak.get_max_health(), "edited defeat bonus reaches the final score")


func _test_position_and_team() -> void:
	var ai := profile()
	var actor := unit(false, Vector2i(1, 1), [damage(5)], ai)
	var ally := unit(false, Vector2i(1, 2), [damage(20)])
	var target := unit(true, Vector2i(3, 1))
	target.current_health = 14
	var units: Array[TacticalCharacter] = [actor, ally, target]
	var base := plan(actor, units)
	check(base.position_score == 0.0 and base.coordination_score == 0.0,
		"zero position and team weights disable their bonuses")
	ai.future_value_weight = 0.5
	check(plan(actor, units).position_score == 2.5, "future position weight scales the next-turn action")
	ai.future_value_weight = 0.0
	ai.shared_pressure_weight = 1.0
	check(plan(actor, units).coordination_score == 9.0, "shared pressure weight scales allied follow-up")
	ai.shared_pressure_weight = 0.0
	ai.setup_defeat_ratio = 0.5
	check(plan(actor, units).coordination_score == target.get_max_health() * 0.5,
		"setup defeat ratio scales finishing bonuses")
	check(plan(actor, [actor, target, ally]).coordination_score == 0.0,
		"team rewards still require allies to act before the target")


func _test_per_hit_damage_over_time() -> void:
	var ai := profile()
	ai.damage_weight = 3.0
	ai.utility_weight = 0.0
	var strike := damage(2)
	strike.hit_targeting = AbilityDefinition.HitTargeting.SELECT_PER_HIT
	strike.hit_count = 2
	var burning := StatusEffectDefinition.new()
	burning.status_id = &"profile_test_burning"
	burning.effect = StatusEffectDefinition.Effect.DAMAGE_EACH_TURN
	burning.damage_type = DamageCalculator.Type.MAGICAL
	burning.damage_per_turn = 4
	burning.duration_turns = 2
	strike.status_effect = burning
	var actor := unit(false, Vector2i(1, 1), [strike], ai)
	var target := unit(true, Vector2i(3, 1))
	var units: Array[TacticalCharacter] = [actor, target]
	var chosen := plan(actor, units)
	check(chosen.selected_targets.size() == 2, "edited weights preserve per-hit recipients")
	check(chosen.effect_score == 36.0, "per-hit damage over time uses damage weight independently of utility weight")
	check(target.current_health == target.get_max_health() and target.get_active_statuses().is_empty(),
		"per-hit forecasts leave live health and statuses unchanged")
