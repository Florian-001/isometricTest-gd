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
	await _test_class_and_unit_assignment(loaded)
	print("AI_PROFILE_EDITOR_TESTS_%s: %d checks, %d failures" % [
		"OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _inspector_fields(object: Object) -> Dictionary:
	EditorInterface.inspect_object(object)
	for _frame in range(8):
		await process_frame
	var fields := {}
	for field in EditorInterface.get_inspector().find_children("*", "EditorProperty", true, false):
		fields[field.get_edited_property()] = field
	return fields


func _test_class_and_unit_assignment(ai: EnemyAIProfile) -> void:
	var definition := (load("res://resources/classes/warrior.tres") as CharacterClassDefinition).duplicate() as CharacterClassDefinition
	var fields: Dictionary = await _inspector_fields(definition)
	check(fields.has("ai_profile"), "class Inspector exposes Auto Battle AI Profile")
	if fields.has("ai_profile"):
		fields.ai_profile.emit_changed("ai_profile", ai)
		for _frame in range(4):
			await process_frame
	check(definition.ai_profile == ai, "class profile assigns through Inspector")
	var class_path := "res://.godot/ai_profile_validation/inspector_class.tres"
	check(ResourceSaver.save(definition, class_path) == OK, "Inspector-edited class profile saves")
	var restored_class := ResourceLoader.load(class_path, "", ResourceLoader.CACHE_MODE_IGNORE) as CharacterClassDefinition
	check(restored_class != null and restored_class.ai_profile.healing_weight == 3.0,
		"class profile assignment survives resource reload")
	var actor := (load("res://scenes/friendlies/cleric.tscn") as PackedScene).instantiate() as TacticalCharacter
	root.add_child(actor)
	fields = await _inspector_fields(actor)
	check(fields.has("ai_profile_override"), "unit Inspector exposes Tactical AI AI Profile Override")
	check(not fields.has("enemy_ai_profile"), "legacy alias is hidden in Inspector")
	if fields.has("ai_profile_override"):
		fields.ai_profile_override.emit_changed("ai_profile_override", ai)
		for _frame in range(4):
			await process_frame
	check(actor.ai_profile_override == ai and actor.enemy_ai_profile == ai, "unit Inspector assignment updates compatibility alias")
	var scene := PackedScene.new()
	check(scene.pack(actor) == OK, "Inspector-edited unit packs")
	var scene_path := "res://.godot/ai_profile_validation/inspector_unit.tscn"
	check(ResourceSaver.save(scene, scene_path) == OK, "Inspector-edited unit saves")
	var restored_scene := ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var restored := restored_scene.instantiate() as TacticalCharacter
	check(restored.ai_profile_override != null and restored.ai_profile_override.healing_weight == 3.0,
		"unit override assignment survives scene reload")
	fields = await _inspector_fields(actor)
	if fields.has("ai_profile_override"):
		fields.ai_profile_override.emit_changed("ai_profile_override", null)
		for _frame in range(4):
			await process_frame
	check(actor.ai_profile_override == null, "Inspector can clear the unit override for inheritance")
	EditorInterface.inspect_object(null)
	actor.free()
	restored.free()
