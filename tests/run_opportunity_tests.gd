extends SceneTree


func _init() -> void:
	var failures: Array[String] = []
	var tests := [
		{
			"suite": "res://tests/test_tactical_foundation.gd",
			"method": "test_opportunity_attack_selection_reach_reaction_and_round_reset",
		},
		{
			"suite": "res://tests/test_enemy_ai.gd",
			"method": "test_opportunity_forecast_consumes_reaction_applies_status_and_truncates_paths",
		},
	]
	for test in tests:
		var suite_script := load(String(test["suite"])) as Script
		var suite = suite_script.new()
		suite._reset()
		suite.setup()
		suite.call(StringName(test["method"]))
		suite.teardown()
		suite._free_tracked()
		if suite._failed:
			failures.append("%s.%s: %s" % [
				suite.suite_name(),
				test["method"],
				suite._message,
			])

	if failures.is_empty():
		print("OPPORTUNITY_UNIT_TESTS_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
