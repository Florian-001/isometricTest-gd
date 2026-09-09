@tool
extends EditorPlugin

const Generator = preload("res://addons/class_ability_reference/reference_generator.gd")
const RUNNER := "res://addons/class_ability_reference/generate_reference.gd"
const MENU_NAME := "Regenerate Class Abilities"
const WORK_DIRECTORY := "res://.godot/class_ability_reference"

signal generation_finished(success: bool, changed: bool)

# Configurable by the isolated editor test; normal projects use the shared defaults.
var classes_directory := Generator.CLASSES_DIRECTORY
var output_path := Generator.OUTPUT_PATH
var _filesystem: EditorFileSystem
var _debounce: Timer
var _poll: Timer
var _worker_pid := -1
var _worker_started := 0
var _report_path := ""
var _log_path := ""
var _last_fingerprint := ""
var _last_output_hash := ""
var _pending := false
var _force := false
var _maintenance: Timer
var _replacement_path := ""
var _replacement_fingerprint := ""
var _exporter_hash := ""


func _enter_tree() -> void:
	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = 0.5
	_debounce.timeout.connect(_refresh)
	add_child(_debounce)
	_poll = Timer.new()
	_poll.wait_time = 0.1
	_poll.timeout.connect(_poll_worker)
	add_child(_poll)
	_maintenance = Timer.new()
	_maintenance.wait_time = 5.0
	_maintenance.timeout.connect(_maintain_workbook)
	add_child(_maintenance)
	_maintenance.start()
	_exporter_hash = FileAccess.get_sha256(Generator.Spreadsheet.EXPORTER)
	_filesystem = EditorInterface.get_resource_filesystem()
	_filesystem.filesystem_changed.connect(_queue_refresh)
	_filesystem.resources_reload.connect(_on_resources_changed)
	_filesystem.resources_reimported.connect(_on_resources_changed)
	_filesystem.script_classes_updated.connect(_queue_refresh)
	resource_saved.connect(_on_resource_saved)
	scene_saved.connect(_on_scene_saved)
	ProjectSettings.settings_changed.connect(_queue_refresh)
	add_tool_menu_item(MENU_NAME, regenerate)
	_queue_refresh()


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_NAME)
	for connection in [[_filesystem.filesystem_changed, _queue_refresh], [_filesystem.resources_reload, _on_resources_changed], [_filesystem.resources_reimported, _on_resources_changed], [_filesystem.script_classes_updated, _queue_refresh], [resource_saved, _on_resource_saved], [scene_saved, _on_scene_saved], [ProjectSettings.settings_changed, _queue_refresh]]:
		if connection[0].is_connected(connection[1]):
			connection[0].disconnect(connection[1])
	if _worker_pid > 0 and OS.is_process_running(_worker_pid):
		OS.kill(_worker_pid)
	_worker_pid = -1
	_debounce.queue_free()
	_poll.queue_free()
	_maintenance.queue_free()
	_discard_replacement()


func regenerate() -> void:
	_force = true
	_queue_refresh()


func _on_resource_saved(_resource: Resource) -> void:
	_queue_refresh()


func _on_scene_saved(_path: String) -> void:
	_queue_refresh()


func _on_resources_changed(_paths: PackedStringArray) -> void:
	_queue_refresh()


func _queue_refresh() -> void:
	_pending = true
	_debounce.start()


func _refresh() -> void:
	if _worker_pid > 0:
		return # Completion schedules any changes made during the current generation.
	if _filesystem.is_scanning() or _filesystem.is_importing():
		_debounce.start()
		return
	_pending = false
	var fingerprint := Generator.input_fingerprint(classes_directory)
	var output_hash := FileAccess.get_sha256(output_path) if FileAccess.file_exists(output_path) else "missing"
	if not _force and fingerprint == _last_fingerprint and output_hash == _last_output_hash:
		return
	_force = false
	_discard_replacement()
	_last_fingerprint = fingerprint
	var directory_error := DirAccess.make_dir_recursive_absolute(WORK_DIRECTORY)
	if directory_error != OK:
		_fail("Cannot create worker directory: %s" % error_string(directory_error))
		return
	var identifier := "%d_%d" % [OS.get_process_id(), get_instance_id()]
	_report_path = WORK_DIRECTORY.path_join("editor_%s.json" % identifier)
	_log_path = WORK_DIRECTORY.path_join("editor_%s.log" % identifier)
	if FileAccess.file_exists(_report_path):
		DirAccess.remove_absolute(_report_path)
	var arguments := PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", ProjectSettings.globalize_path(_log_path), "--script", RUNNER,
		"--", "--classes-dir=" + classes_directory, "--output=" + output_path, "--report=" + _report_path,
	])
	# A bounded, hidden worker exits after generation; there is no standalone watcher.
	_worker_pid = OS.create_process(OS.get_executable_path(), arguments, false)
	if _worker_pid <= 0:
		_fail("Could not start the reference generator.")
		return
	_worker_started = Time.get_ticks_msec()
	_poll.start()


func _poll_worker() -> void:
	if OS.is_process_running(_worker_pid):
		if Time.get_ticks_msec() - _worker_started > 30000:
			OS.kill(_worker_pid)
			_finish_worker()
			_fail("Reference generation timed out. See %s." % _log_path)
		return
	_finish_worker()
	var report = JSON.parse_string(FileAccess.get_file_as_string(_report_path)) if FileAccess.file_exists(_report_path) else null
	if report is Dictionary and report.get("locked", false):
		var candidate := str(report.get("pending_path", "")).replace("\\", "/").simplify_path()
		var directory := ProjectSettings.globalize_path(output_path.get_base_dir().path_join(".godot/class_ability_reference")).replace("\\", "/").simplify_path()
		if candidate.get_base_dir() != directory or not candidate.get_file().begins_with("workbook-pending-") or not FileAccess.file_exists(candidate):
			_fail("Invalid pending workbook path in exporter response.")
			return
		_replacement_path = candidate
		_replacement_fingerprint = _last_fingerprint
		_last_output_hash = FileAccess.get_sha256(output_path)
		print("Class abilities workbook is locked. Close it in Excel; the update will retry every five seconds.")
		return
	if not report is Dictionary or not report.get("ok", false):
		var details := "; ".join(report.get("errors", [])) if report is Dictionary else "Worker did not complete; check resource or script errors"
		_fail("%s. See %s." % [details.trim_suffix("."), _log_path])
		return
	_last_output_hash = FileAccess.get_sha256(output_path)
	if report.get("changed", false):
		print("Class abilities reference updated: %s" % output_path)
	generation_finished.emit(true, report.get("changed", false))


func _finish_worker() -> void:
	_poll.stop()
	_worker_pid = -1
	if _pending:
		_debounce.start()


func _fail(message: String) -> void:
	# Suppress repeated retries for unchanged invalid input, but retry after a fix.
	_last_output_hash = FileAccess.get_sha256(output_path) if FileAccess.file_exists(output_path) else "missing"
	push_error("Class Ability Reference: %s" % message)
	generation_finished.emit(false, false)


func _maintain_workbook() -> void:
	# .mjs files may not produce Godot resource notifications.
	var exporter_hash := FileAccess.get_sha256(Generator.Spreadsheet.EXPORTER)
	if exporter_hash != _exporter_hash:
		_exporter_hash = exporter_hash
		_queue_refresh()
	if _replacement_path.is_empty() or _worker_pid > 0:
		return
	if Generator.input_fingerprint(classes_directory) != _replacement_fingerprint:
		_discard_replacement()
		_queue_refresh()
		return
	var error := DirAccess.rename_absolute(_replacement_path, output_path)
	if error == OK:
		_replacement_path = ""
		_last_output_hash = FileAccess.get_sha256(output_path)
		print("Class abilities workbook updated: %s" % output_path)
		generation_finished.emit(true, true)
	# Windows reports a sharing violation as FAILED, rather than a permission code.
	elif error not in [FAILED, ERR_FILE_NO_PERMISSION, ERR_CANT_CREATE]:
		_discard_replacement()
		_fail("Cannot replace the pending workbook: %s" % error_string(error))


func _discard_replacement() -> void:
	if not _replacement_path.is_empty():
		DirAccess.remove_absolute(_replacement_path)
	_replacement_path = ""
	_replacement_fingerprint = ""
