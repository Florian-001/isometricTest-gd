extends SceneTree
## CLI and isolated editor worker. A fresh process also picks up saved script changes.

const Generator = preload("res://addons/class_ability_reference/reference_generator.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var output_path := Generator.OUTPUT_PATH
	var classes_directory := Generator.CLASSES_DIRECTORY
	var report_path := ""
	var check_only := false
	for argument in OS.get_cmdline_user_args():
		if argument == "--check":
			check_only = true
		elif argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--classes-dir="):
			classes_directory = argument.trim_prefix("--classes-dir=")
		elif argument.begins_with("--report="):
			report_path = argument.trim_prefix("--report=")
		else:
			printerr("Unknown argument: %s" % argument)
			quit(2)
			return
	if check_only and not report_path.is_empty():
		printerr("--check cannot be combined with --report; checks are read-only.")
		quit(2)
		return
	var result := Generator.update(output_path, classes_directory, check_only)
	if not report_path.is_empty():
		var report := FileAccess.open(report_path, FileAccess.WRITE)
		if report == null:
			printerr("Cannot write editor generation report: %s" % report_path)
			quit(1)
			return
		report.store_string(JSON.stringify({"ok": result.ok, "changed": result.changed, "errors": result.errors}))
		report.close()
	if result.ok:
		print("Class abilities reference: %s (%s)." % ["updated" if result.changed else "up to date", output_path])
	else:
		for error in result.errors:
			printerr(error)
	quit(0 if result.ok else 1)
