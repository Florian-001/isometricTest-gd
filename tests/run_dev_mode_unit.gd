extends SceneTree


func _init() -> void:
	var suite_script: Script = load("res://tests/test_dev_mode.gd")
	var suite = suite_script.new()
	var failures: Array[String] = []
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
			failures.append("%s: %s" % [method_name, suite._message])
	if failures.is_empty():
		print("ALL_DEV_MODE_UNIT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
