extends SceneTree

const DIRECTORY := "res://.godot/multiple_arrows_validation"
var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
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
		push_error("Run with --editor --script.")
		quit(1)
		return
	await create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
	var ability := AbilityDefinition.new()
	EditorInterface.edit_resource(ability)
	await _frames()
	check(_property("hit_count") != null and _property("hit_targeting") != null, "Inspector exposes Hit Count and Hit Targeting")
	check(_property("allow_repeated_targets") == null, "repeat toggle is hidden for legacy targeting")
	if _property("hit_targeting") != null:
		_property("hit_targeting").emit_changed("hit_targeting", AbilityDefinition.HitTargeting.SELECT_PER_HIT)
		await _frames()
	check(ability.selects_per_hit() and _property("allow_repeated_targets") != null, "Select Per Hit reveals repeated-target editing")
	if _property("allow_repeated_targets") != null:
		_property("allow_repeated_targets").emit_changed("allow_repeated_targets", false)
	if _property("hit_count") != null:
		_property("hit_count").emit_changed("hit_count", 4)
	await _frames()
	check(ability.hit_count == 4 and not ability.allow_repeated_targets, "Inspector edits count and repeat policy")
	check(ability.validate_targeting_button.is_valid() and ability.get_targeting_configuration_error().is_empty(), "targeting validation action is exposed and accepts valid settings")
	if _property("target_flags") != null:
		_property("target_flags").emit_changed("target_flags", 10)
	await _frames()
	check(not ability.get_targeting_configuration_error().is_empty(), "incompatible Inspector configuration reports the problem")
	if _property("target_flags") != null:
		_property("target_flags").emit_changed("target_flags", 2)
	await _frames()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	var path := DIRECTORY + "/editor_ability.tres"
	check(ResourceSaver.save(ability, path) == OK, "Inspector-authored ability saves")
	var restored := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as AbilityDefinition
	check(restored.selects_per_hit() and restored.hit_count == 4 and not restored.allow_repeated_targets and restored.target_flags == 2, "Inspector settings survive save and reload")
	EditorInterface.edit_resource(load("res://resources/abilities/multiple_arrows.tres"))
	await _frames()
	check(_property("hit_targeting") != null and _property("allow_repeated_targets") != null, "shipped ability opens in the Inspector with new controls")
	for failure in failures:
		push_error(failure)
	print("MULTIPLE_ARROWS_EDITOR_%s: %d failures" % ["OK" if failures.is_empty() else "FAILED", failures.size()])
	quit(0 if failures.is_empty() else 1)
