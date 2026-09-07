extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


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
	var definition := (load("res://resources/classes/warrior.tres") as CharacterClassDefinition).duplicate() as CharacterClassDefinition
	definition.class_id = &"editor_test_warrior"
	definition.ability_unlocks = []
	var unlock := ClassAbilityUnlock.new()
	unlock.ability = load("res://resources/abilities/strike.tres")
	definition.ability_unlocks.append(unlock)
	EditorInterface.edit_resource(definition)
	await _frames()
	for property_name in ["class_id", "display_name", "ability_unlocks"]:
		_check(_property(property_name) != null, "Class Inspector exposes %s" % property_name)
	_check(definition.validate_button.is_valid(), "Class validation action is callable")
	EditorInterface.edit_resource(unlock)
	await _frames()
	_check(_property("ability") != null and _property("required_level") != null, "Unlock Inspector exposes ability and level")
	var level_property := _property("required_level")
	if level_property != null:
		level_property.emit_changed("required_level", 3)
		await _frames()
		_check(unlock.required_level == 3, "Inspector edits the unlock level")
	var allocation := CharacterClassLevel.create(definition)
	EditorInterface.edit_resource(allocation)
	await _frames()
	_check(_property("character_class") != null and _property("level") != null, "Allocation Inspector exposes class and level")
	if _property("level") != null:
		_property("level").emit_changed("level", 3)
		await _frames()
	var character := CharacterDefinition.new()
	character.starting_class = definition
	EditorInterface.edit_resource(character)
	await _frames()
	_check(_property("starting_class") != null and _property("abilities") == null, "Friendly template exposes classes instead of legacy abilities")
	var path := "res://.godot/class_validation/editor_allocation_%d.tres" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	_check(ResourceSaver.save(allocation, path) == OK, "Allocation and inline class save")
	var restored := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as CharacterClassLevel
	_check(restored != null and restored.level == 3 and restored.character_class.ability_unlocks[0].required_level == 3, "Inspector allocation and unlock edits survive resource reload")
	if _failures.is_empty():
		print("CHARACTER_CLASS_EDITOR_OK")
	for failure in _failures:
		push_error(failure)
	EditorInterface.get_base_control().get_tree().quit(0 if _failures.is_empty() else 1)
