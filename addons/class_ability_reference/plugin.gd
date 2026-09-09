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
	_filesystem = EditorInterface.get_resource_filesystem()
	_filesystem.filesystem_changed.connect(_queue_refresh)
	_filesystem.resources_reload.connect(_on_resources_changed)
	_filesystem.resources_reimported.connect(_on_resources_changed)
	_filesystem.script_classes_updated.connect(_queue_refresh)
	resource_saved.connect(_on_resource_saved)
	scene_saved.connect(_on_scene_saved)
	add_tool_menu_item(MENU_NAME, regenerate)
	_queue_refresh()


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_NAME)
	for connection in [[_filesystem.filesystem_changed, _queue_refresh], [_filesystem.resources_reload, _on_resources_changed], [_filesystem.resources_reimported, _on_resources_changed], [_filesystem.script_classes_updated, _queue_refresh], [resource_saved, _on_resource_saved], [scene_saved, _on_scene_saved]]:
		if connection[0].is_connected(connection[1]):
			connection[0].disconnect(connection[1])
	if _worker_pid > 0 and OS.is_process_running(_worker_pid):
		OS.kill(_worker_pid)
	_worker_pid = -1
	_debounce.queue_free()
	_poll.queue_free()


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
