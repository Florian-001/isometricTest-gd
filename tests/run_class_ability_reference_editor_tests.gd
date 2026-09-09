extends SceneTree
## Exercises the enabled editor plugin with disposable, filesystem-visible resources.

const Xlsx = preload("res://tests/class_reference_xlsx_reader.gd")
const Generator = preload("res://addons/class_ability_reference/reference_generator.gd")
const PLUGIN_PATH := "res://addons/class_ability_reference/plugin.gd"
const RUNNER := "res://addons/class_ability_reference/generate_reference.gd"

var _failures: Array[String] = []
var _checks := 0
var _events: Array[Dictionary] = []
var _saved_paths: Array[String] = []
var _directory := "res://tests/class_ability_reference_validation_%d" % Time.get_ticks_usec()
var _classes := ""
var _output := ""
var _plugin: EditorPlugin
var _ability: AbilityDefinition
var _status: StatusEffectDefinition
var _class: CharacterClassDefinition


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _run() -> void:
	if not Engine.is_editor_hint():
		push_error("Run with --headless --editor --script.")
		quit(1)
		return
	await create_timer(1.0).timeout
	await _scan()
	for node in root.find_children("*", "EditorPlugin", true, false):
		if node.get_script() != null and node.get_script().resource_path == PLUGIN_PATH:
			_plugin = node
	_check(_plugin != null, "reference plugin is enabled by project settings")
	if _plugin == null:
		_finish()
		return
	await _wait_idle()
	_classes = _directory.path_join("classes")
	_output = _directory.path_join("reference.xlsx")
	_create_fixture()
	await _scan()
	_plugin.classes_directory = _classes
	_plugin.output_path = _output
	_plugin.generation_finished.connect(func(success: bool, changed: bool) -> void: _events.append({"ok": success, "changed": changed}))
	_plugin.resource_saved.connect(func(resource: Resource) -> void: _saved_paths.append(resource.resource_path))
	# Re-entering exercises the same startup path used on project opening/enabling.
	_plugin._exit_tree()
	_plugin._enter_tree()
	await _wait_for_event(1)
	_check(_events.size() == 1 and _events[0].ok and _events[0].changed, "editor startup creates the reference automatically")
	_check(_text().contains("Saved description v1"), "editor worker includes saved custom description scripts")
	await _test_inspector_save()
	await _test_external_changes()
	await _test_restart_and_failures()
	await _test_locked_file()
	_test_cli_check()
	await _wait_idle()
	_plugin.classes_directory = Generator.CLASSES_DIRECTORY
	_plugin.output_path = Generator.OUTPUT_PATH
	# Disable our plugin in this test process before removing fixtures; do not edit settings.
	_plugin.get_parent().remove_child(_plugin)
	_plugin.queue_free()
	EditorInterface.edit_resource(null)
	_remove_fixture(_directory)
	_finish()


func _create_fixture() -> void:
	DirAccess.make_dir_recursive_absolute(_classes)
	_status = StatusEffectDefinition.new()
	_status.status_id = &"editor_reference_status"
	_status.display_name = "Editor Status"
	_status.duration_turns = 2
	ResourceSaver.save(_status, _directory.path_join("status.tres"))
	_status = load(_directory.path_join("status.tres"))
	_write(_directory.path_join("description.gd"), _description_script("Saved description v1"))
	_ability = AbilityDefinition.new()
	_ability.display_name = "Editor Ability"
	_ability.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	_ability.innate_damage = 19
	_ability.status_effect = _status
	_ability.effects = [load(_directory.path_join("description.gd")).new()]
	ResourceSaver.save(_ability, _directory.path_join("ability.tres"))
	_ability = load(_directory.path_join("ability.tres"))
	_class = CharacterClassDefinition.new()
	_class.class_id = &"editor_reference"
	_class.display_name = "Editor Class"
	var unlock := ClassAbilityUnlock.new()
	unlock.ability = _ability
	_class.ability_unlocks = [unlock]
	ResourceSaver.save(_class, _classes.path_join("class.tres"))
	_class = load(_classes.path_join("class.tres"))


func _test_inspector_save() -> void:
	EditorInterface.edit_resource(_ability)
	await create_timer(0.3).timeout
	var property: EditorProperty
	for candidate in EditorInterface.get_inspector().find_children("*", "EditorProperty", true, false):
		if candidate.get_edited_property() == "innate_damage":
			property = candidate
	_check(property != null, "real Inspector exposes ability damage")
	if property == null:
		return
	property.emit_changed("innate_damage", 73)
	await create_timer(0.1).timeout
	var count := _events.size()
	_plugin.regenerate()
	await _wait_for_event(count + 1)
	_check(_text().contains("19 innate") and not _text().contains("73 innate"), "manual refresh excludes unsaved Inspector edits")
	_check(_ability.innate_damage == 73, "background generation preserves unfinished Inspector edits")
	count = _events.size()
	var saved := false
	# Invoke the actual Inspector Save action, without saving other project resources.
	for button in root.find_children("*", "MenuButton", true, false):
		if button.tooltip_text != "Save the currently edited resource.":
			continue
		var popup: PopupMenu = button.get_popup()
		for index in range(popup.item_count):
			if popup.get_item_text(index) == "Save":
				popup.id_pressed.emit(popup.get_item_id(index))
				saved = true
	_check(saved, "invoke the real Inspector Save action")
	await _wait_for_event(count + 1)
	_check(_saved_paths.has(_ability.resource_path), "Godot emitted the actual editor resource_saved signal")
	_check(_text().contains("73 innate"), "saving in the Inspector automatically refreshes ability details")


func _test_external_changes() -> void:
	await _wait_idle()
	var count := _events.size()
	_write(_status.resource_path, FileAccess.get_file_as_string(_status.resource_path).replace("duration_turns = 2", "duration_turns = 6"))
	_write(_class.resource_path, FileAccess.get_file_as_string(_class.resource_path).replace("ability = ExtResource", "required_level = 4\nability = ExtResource"))
	_write(_directory.path_join("description.gd"), _description_script("Saved description v2"))
	await _scan()
	await _wait_for_event(count + 1)
	_check(_text().contains("Editor Status for 6 turns"), "external nested status edit refreshes after the filesystem scan")
	_check(Xlsx.cells(_output).get("C8") == 4, "external unlock level edit refreshes")
	_check(_text().contains("Saved description v2") and not _text().contains("Saved description v1"), "fresh worker reads changed description code")
	await _wait_idle()
	_check(_events.size() == count + 1, "nearby saved changes are combined into one generation")
	var new_class := CharacterClassDefinition.new()
	new_class.class_id = &"added_reference_class"
	new_class.display_name = "Added Class"
	count = _events.size()
	ResourceSaver.save(new_class, _classes.path_join("added.tres"))
	await _scan()
	await _wait_for_event(count + 1)
	_check(_text().contains("Added Class"), "new class is automatically discovered")
	_check(Xlsx.sheet_names(_output) == ["Added Class", "Editor Class"], "added class gets a separate worksheet in alphabetical order")
	_check(Xlsx.cells(_output).get("A6") == 1 and Xlsx.cells(_output).get("A7") == 2 and Xlsx.cells(_output).get("A8") == null, "empty class numbers shared attacks and leaves its informational row unnumbered")
	count = _events.size()
	DirAccess.remove_absolute(_classes.path_join("added.tres"))
	await _scan()
	await _wait_for_event(count + 1)
	_check(not _text().contains("Added Class"), "deleted class automatically disappears")
	_check(Xlsx.sheet_names(_output) == ["Editor Class"], "removing a class removes its worksheet")
	await _wait_idle()
	count = _events.size()
	var modified := FileAccess.get_modified_time(_output)
	await create_timer(1.1).timeout
	await _scan()
	await create_timer(0.8).timeout
	_check(_events.size() == count and FileAccess.get_modified_time(_output) == modified, "unchanged filesystem events do not launch workers or rewrite output")


func _test_restart_and_failures() -> void:
	_plugin._exit_tree()
	_write(_ability.resource_path, FileAccess.get_file_as_string(_ability.resource_path).replace("innate_damage = 73", "innate_damage = 81"))
	var count := _events.size()
	_plugin._enter_tree()
	await _wait_for_event(count + 1)
	_check(_text().contains("81 innate"), "reopening/enabling catches edits made while the plugin was stopped")
	var previous := _text()
	var valid_class := FileAccess.get_file_as_string(_class.resource_path)
	_write(_class.resource_path, valid_class.replace("required_level = 4", "required_level = 0"))
	count = _events.size()
	print("Testing an intentional invalid unlock; the editor should report it without replacing the reference.")
	await _scan()
	await _wait_for_event(count + 1)
	_check(_events.size() > count and not _events[-1].ok, "editor reports invalid saved class data")
	_check(_text() == previous, "failed editor generation preserves the previous file")
	_write(_class.resource_path, valid_class)
	count = _events.size()
	await _scan()
	await _wait_for_event(count + 1)
	_check(_events.size() > count and _events[-1].ok, "saving a fix recovers automatically")


func _test_locked_file() -> void:
	if not OS.has_feature("windows"):
		return # Windows sharing locks reproduce Excel's destination-file behavior.
	await _wait_idle()
	var script := _directory.path_join("hold_workbook.ps1")
	var ready := _directory.path_join("lock-ready")
	var release := _directory.path_join("lock-release")
	_write(script, """param([string]$Workbook, [string]$Ready, [string]$Release)
$handle = [IO.File]::Open($Workbook, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
try {
    [IO.File]::WriteAllText($Ready, 'ready')
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    while (-not [IO.File]::Exists($Release) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
} finally { $handle.Dispose() }
""")
	var pid := OS.create_process("powershell.exe", PackedStringArray(["-NoProfile", "-WindowStyle", "Hidden", "-File", ProjectSettings.globalize_path(script), "-Workbook", ProjectSettings.globalize_path(_output), "-Ready", ProjectSettings.globalize_path(ready), "-Release", ProjectSettings.globalize_path(release)]), false)
	var deadline := Time.get_ticks_msec() + 10000
	while not FileAccess.file_exists(ready) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(pid > 0 and FileAccess.file_exists(ready), "hold a real Windows sharing lock on the disposable workbook")
	if not FileAccess.file_exists(ready):
		return
	var original_hash := FileAccess.get_sha256(_output)
	_write(_ability.resource_path, FileAccess.get_file_as_string(_ability.resource_path).replace("innate_damage = 81", "innate_damage = 91"))
	await _scan()
	await _wait_for_pending()
	var first_pending: String = _plugin._replacement_path
	_check(not first_pending.is_empty() and FileAccess.file_exists(first_pending), "locked output retains the fully generated pending workbook")
	_check(FileAccess.get_sha256(_output) == original_hash, "lock leaves the existing workbook intact")
	var retry_events := _events.size()
	await create_timer(5.2).timeout
	await _wait_idle()
	await _wait_for_pending()
	# Other development can update tracked scripts during this isolated fixture test.
	_check(not _plugin._replacement_path.is_empty() and FileAccess.file_exists(_plugin._replacement_path) and _events.size() == retry_events, "five-second retry retains pending data without reporting a failure while lock persists")
	_check(FileAccess.get_sha256(_output) == original_hash, "repeated locked replacements never remove the original workbook")
	_write(_ability.resource_path, FileAccess.get_file_as_string(_ability.resource_path).replace("innate_damage = 91", "innate_damage = 97"))
	await _scan()
	deadline = Time.get_ticks_msec() + 15000
	while (not FileAccess.file_exists(_plugin._replacement_path) or not Xlsx.text(_plugin._replacement_path).contains("97 innate")) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(_plugin._replacement_path != first_pending and not FileAccess.file_exists(first_pending), "new source changes replace the older pending workbook")
	_check(Xlsx.text(_plugin._replacement_path).contains("97 innate"), "new pending workbook contains the latest saved data")
	var count := _events.size()
	_write(release, "release")
	await _wait_for_event(count + 1)
	_check(_events.size() > count and _events[-1].ok and _text().contains("97 innate"), "closing the locked file automatically installs the latest pending update")
	_check(_plugin._replacement_path.is_empty(), "successful replacement clears pending state")
	while OS.is_process_running(pid):
		await process_frame


func _wait_for_pending() -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while _plugin._replacement_path.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame


func _test_cli_check() -> void:
	var output: Array = []
	var arguments := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", RUNNER, "--", "--classes-dir=" + _classes, "--output=" + _output, "--check"])
	var modified := FileAccess.get_modified_time(_output)
	_check(OS.execute(OS.get_executable_path(), arguments, output, true, false) == 0, "CLI --check exits zero for a current reference")
	_check(FileAccess.get_modified_time(_output) == modified, "CLI --check does not rewrite the current file")
	_write(_output, "Stale reference\n")
	output.clear()
	_check(OS.execute(OS.get_executable_path(), arguments, output, true, false) == 1, "CLI --check exits nonzero for stale content")
	_check(FileAccess.get_file_as_string(_output) == "Stale reference\n", "CLI --check leaves stale content untouched")


func _wait_for_event(count: int) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while _events.size() < count and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(_events.size() >= count, "generation completed before its deadline")


func _wait_idle() -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while (_plugin._worker_pid > 0 or _plugin._pending or not _plugin._debounce.is_stopped()) and Time.get_ticks_msec() < deadline:
		await process_frame


func _scan() -> void:
	var filesystem := EditorInterface.get_resource_filesystem()
	while filesystem.is_scanning() or filesystem.is_importing():
		await process_frame
	filesystem.scan()
	await process_frame
	while filesystem.is_scanning() or filesystem.is_importing():
		await process_frame


func _text() -> String:
	return Xlsx.text(_output) if FileAccess.file_exists(_output) else ""


func _description_script(description: String) -> String:
	return "@tool\nextends AbilityEffectDefinition\nfunc get_description(_caster: TacticalCharacter = null) -> String:\n\treturn \"%s\"\n" % description


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()


func _remove_fixture(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	var fixture_root := ProjectSettings.globalize_path(_directory).simplify_path()
	assert(absolute == fixture_root or absolute.begins_with(fixture_root + "/"))
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for child in dir.get_directories():
		_remove_fixture(path.path_join(child))
	for file_name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)


func _finish() -> void:
	for failure in _failures:
		push_error(failure)
	print("CLASS_ABILITY_REFERENCE_EDITOR_%s (%d checks)" % ["OK" if _failures.is_empty() else "FAILED", _checks])
	EditorInterface.get_base_control().get_tree().quit(0 if _failures.is_empty() else 1)
