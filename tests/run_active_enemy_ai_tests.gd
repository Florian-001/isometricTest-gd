extends SceneTree

const ACTIVE_AI_TESTS := [
	"test_ai_log_summary_separates_ignored_diagnostics_from_the_total",
	"test_stun_forecast_suppresses_actions_movement_reactions_and_threat",
	"test_opportunity_forecast_consumes_reaction_applies_status_and_truncates_paths",
	"test_action_first_filters_non_action_plans_when_a_positive_cast_exists",
	"test_active_rule_forces_positive_healing_buffs_and_hostile_statuses",
	"test_action_first_requires_a_move_cast_even_when_counterplay_is_lethal",
	"test_post_cast_movement_does_not_retreat_for_safety",
	"test_post_cast_positioning_can_move_for_future_offense",
	"test_action_first_preserves_movement_when_the_action_is_spent",
	"test_spent_action_pursues_the_next_useful_support_position",
	"test_melee_enemy_pursues_attack_range_instead_of_retreating_from_ranged_threat",
	"test_terrain_showcase_melee_enemy_advances_until_it_can_strike",
	"test_active_rule_uses_best_effort_movement_when_no_attack_route_exists",
	"test_active_rule_holds_only_without_a_legal_action_or_cell_change",
	"test_snapshot_occupancy_ignores_defeated_enemies_only",
	"test_threat_diagnostics_do_not_choose_a_safer_destination",
	"test_threat_diagnostics_are_ignored_for_a_rewarding_melee_attack",
]

const TERRAIN_AI_TESTS := [
	"test_active_ai_prefers_closest_progress_without_a_future_action",
	"test_ai_accepts_fire_when_the_attack_reward_is_greater",
	"test_future_action_route_prefers_lower_damage_when_travel_time_ties",
	"test_active_ai_enters_lethal_fire_when_it_is_the_only_move",
]


func _init() -> void:
	var failures: Array[String] = []
	_run_selected(
		load("res://tests/test_enemy_ai.gd").new(),
		ACTIVE_AI_TESTS,
		failures
	)
	_run_selected(
		load("res://tests/test_terrain_system.gd").new(),
		TERRAIN_AI_TESTS,
		failures
	)
	if failures.is_empty():
		print("ACTIVE_ENEMY_AI_TESTS_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _run_selected(suite: McpTestSuite, methods: Array, failures: Array[String]) -> void:
	for method_name_value in methods:
		var method_name := str(method_name_value)
		suite._reset()
		suite.setup()
		suite.call(method_name)
		suite.teardown()
		suite._free_tracked()
		if suite._failed:
			failures.append("%s.%s: %s" % [
				suite.suite_name(),
				method_name,
				suite._message,
			])
