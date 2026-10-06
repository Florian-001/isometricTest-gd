extends SceneTree

const VALUES := {
	"damage_weight": 2.0,
	"healing_weight": 3.0,
	"utility_weight": 4.0,
	"friendly_damage_penalty": 5.0,
	"immediate_defeat_ratio": 0.5,
	"future_value_weight": 0.75,
	"shared_pressure_weight": 0.5,
	"setup_defeat_ratio": 0.25,
}
var checks := 0
var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	if not Engine.is_editor_hint():
		push_error("Run with --editor --script res://tests/run_ai_profile_editor_tests.gd")
		quit(1)
		return
	await create_timer(3.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
	var original := EnemyAIProfile.get_default()
	var edited := original.duplicate() as EnemyAIProfile
	EditorInterface.edit_resource(edited)
	for _frame in range(8):
		await process_frame
	var fields := {}
	for field in EditorInterface.get_inspector().find_children("*", "EditorProperty", true, false):
		fields[field.get_edited_property()] = field
	for key in VALUES:
		check(fields.has(key), "Inspector shows %s" % key)
		if fields.has(key):
			fields[key].emit_changed(key, VALUES[key])
	for _frame in range(4):
		await process_frame
	for key in VALUES:
		check(is_equal_approx(edited.get(key), VALUES[key]), "Inspector edits %s" % key)
	var path := "res://.godot/ai_profile_validation/inspector_profile.tres"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	check(ResourceSaver.save(edited, path) == OK, "Inspector-edited profile saves")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as EnemyAIProfile
	check(loaded != null, "Inspector-edited profile reloads")
	if loaded != null:
		for key in VALUES:
			check(is_equal_approx(loaded.get(key), VALUES[key]), "Inspector edit persists for %s" % key)
	check(original.damage_weight == 1.0 and original.healing_weight == 1.0,
		"editing a duplicate preserves the shared profile")
	print("AI_PROFILE_EDITOR_TESTS_%s: %d checks, %d failures" % [
		"OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
