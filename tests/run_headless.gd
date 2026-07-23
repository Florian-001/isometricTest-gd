extends SceneTree

func _init() -> void:
	var failures: Array[String] = []
	var suite_paths := [
		"res://tests/test_tactical_foundation.gd",
		"res://tests/test_enemy_ai.gd",
		"res://tests/test_stats_system.gd",
		"res://tests/test_terrain_system.gd",
	]
	for suite_path in suite_paths:
		var suite_script: Script = load(suite_path)
		var suite = suite_script.new()
		for method_info in suite.get_method_list():
			var method_name: String = method_info.get("name", "")
			if not method_name.begins_with("test_"):
				continue
			suite._reset()
			suite.setup()
			suite.call(method_name)
			suite.teardown()
			suite._free_tracked()
			if suite._failed:
				failures.append("%s.%s: %s" % [suite.suite_name(), method_name, suite._message])

	if failures.is_empty():
		print("ALL_TACTICAL_TESTS_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
