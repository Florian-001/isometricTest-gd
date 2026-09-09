extends SceneTree

const DIRECTORY := "res://.godot/empower_validation"
var failures: Array[String] = []
var checks := 0


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _frames() -> void:
	for index in range(5):
		await process_frame


func _property(property_name: String) -> EditorProperty:
	for property in EditorInterface.get_inspector().find_children("*", "EditorProperty", true, false):
		if property.get_edited_property() == property_name:
			return property
	return null


func _run() -> void:
	if not Engine.is_editor_hint():
		push_error("Run this test with --editor --script.")
		quit(1)
		return
	await create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	var status := (load("res://resources/statuses/empowered.tres") as StatusEffectDefinition).duplicate(true) as StatusEffectDefinition
	EditorInterface.edit_resource(status)
	await _frames()
	for name in ["polarity", "duration_turns", "modifiers", "affected_unit_ai_utility"]:
		check(_property(name) != null, "Empowered Inspector exposes " + name)
	if _property("polarity") != null:
		_property("polarity").emit_changed("polarity", StatusEffectDefinition.Polarity.NEGATIVE)
		await _frames()
	check(status.is_negative(), "Inspector polarity change controls classification")
	var status_path := DIRECTORY + "/editor_status.tres"
	check(ResourceSaver.save(status, status_path) == OK, "edited status saves")
	var restored := ResourceLoader.load(status_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as StatusEffectDefinition
	check(restored != null and restored.is_negative() and restored.duration_turns == 3 and restored.modifiers.size() == 6, "polarity, duration, and modifiers survive reload")
	check(not (load("res://resources/statuses/empowered.tres") as StatusEffectDefinition).is_negative(), "editing a copy preserves the bundled status")
	var ability := (load("res://resources/abilities/cleanse.tres") as AbilityDefinition).duplicate() as AbilityDefinition
	EditorInterface.edit_resource(ability)
	await _frames()
	check(_property("effect") != null and ability.effect == AbilityDefinition.PrimaryEffect.CLEANSE, "Cleanse is available as a primary effect")
	check(_property("effect_amount") == null and _property("scaling_amount") == null, "Cleanse hides irrelevant numeric effect fields")
	check(_property("range") != null and _property("target_flags") != null, "support targeting remains editable")
	var ability_path := DIRECTORY + "/editor_cleanse.tres"
	check(ResourceSaver.save(ability, ability_path) == OK, "Cleanse definition saves")
	var restored_ability := ResourceLoader.load(ability_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as AbilityDefinition
	check(restored_ability.effect == AbilityDefinition.PrimaryEffect.CLEANSE and restored_ability.target_flags == 5, "Cleanse effect and targeting survive reload")
	EditorInterface.edit_resource(load("res://resources/abilities/empower.tres"))
	await _frames()
	check(_property("status_effect") != null, "Empower retains the reusable status picker")
	for failure in failures:
		push_error(failure)
	print("EMPOWER_CLEANSE_EDITOR_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	EditorInterface.get_base_control().get_tree().quit(0 if failures.is_empty() else 1)
