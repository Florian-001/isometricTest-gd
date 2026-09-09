@tool
extends RefCounted
## The editor uses a fresh headless Godot worker; only that worker runs Node.

const EXPORTER := "res://addons/class_ability_reference/write_reference.mjs"
const NODE_SETTING := "class_ability_reference/node_executable"
const MODULES_SETTING := "class_ability_reference/node_modules"


static func runtime_paths() -> Dictionary:
	var user_directory := OS.get_environment("USERPROFILE") if OS.has_feature("windows") else OS.get_environment("HOME")
	var bundled := user_directory.path_join(".cache/codex-runtimes/codex-primary-runtime/dependencies/node")
	return {
		"node": OS.get_environment("CLASS_ABILITIES_NODE") if OS.has_environment("CLASS_ABILITIES_NODE") else str(ProjectSettings.get_setting(NODE_SETTING, bundled.path_join("bin/node.exe" if OS.has_feature("windows") else "bin/node"))),
		"modules": OS.get_environment("CLASS_ABILITIES_NODE_MODULES") if OS.has_environment("CLASS_ABILITIES_NODE_MODULES") else str(ProjectSettings.get_setting(MODULES_SETTING, bundled.path_join("node_modules"))),
	}


static func export_rows(rows: Array, output_path: String, check_only: bool = false) -> Dictionary:
	if output_path.get_extension().to_lower() != "xlsx":
		return _failure("The class reference output must use the .xlsx extension.")
	var runtime := runtime_paths()
	if not FileAccess.file_exists(runtime.node) or not FileAccess.file_exists(runtime.modules.path_join("@oai/artifact-tool/package.json")):
		return _failure("Spreadsheet runtime not found. Configure %s and %s, or CLASS_ABILITIES_NODE and CLASS_ABILITIES_NODE_MODULES." % [NODE_SETTING, MODULES_SETTING])
	var work_directory := "res://.godot/class_ability_reference"
	var directory_error := DirAccess.make_dir_recursive_absolute(work_directory)
	if directory_error != OK:
		return _failure("Cannot create spreadsheet work directory: %s" % error_string(directory_error))
	var input_path := work_directory.path_join("rows_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()])
	var input := FileAccess.open(input_path, FileAccess.WRITE)
	if input == null:
		return _failure("Cannot prepare spreadsheet input: %s" % error_string(FileAccess.get_open_error()))
	input.store_string(JSON.stringify({"rows": rows}))
	input.close()
	var arguments := PackedStringArray([ProjectSettings.globalize_path(EXPORTER), "--modules=" + runtime.modules, "--input=" + ProjectSettings.globalize_path(input_path), "--output=" + ProjectSettings.globalize_path(output_path)])
	if check_only:
		arguments.append("--check")
	var logs: Array = []
	var exit_code := OS.execute(runtime.node, arguments, logs, true, false)
	DirAccess.remove_absolute(input_path)
	# The exporter prints one tagged result; library diagnostics may precede it.
	for line in "\n".join(logs).split("\n"):
		if line.begins_with("CLASS_REFERENCE_RESULT="):
			var report = JSON.parse_string(line.trim_prefix("CLASS_REFERENCE_RESULT="))
			if report is Dictionary:
				return report
	return _failure("Spreadsheet exporter failed (exit %d): %s" % [exit_code, "\n".join(logs).right(3000)])


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "changed": false, "errors": [message]}
