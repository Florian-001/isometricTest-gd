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
	var default_fields := ["default_strength", "default_dexterity", "default_intelligence", "default_constitution", "default_speed", "default_movement_range"]
	var default_values := [7, 8, 9, 11, 12, 7.0]
	for index in default_fields.size():
		var field := _property(default_fields[index])
		_check(field != null, "Class Inspector exposes %s" % default_fields[index])
		if field != null:
			field.emit_changed(default_fields[index], default_values[index])
			await _frames()
			_check(float(definition.get(default_fields[index])) == float(default_values[index]), "Inspector edits %s" % default_fields[index])
	var preview := TacticalCharacter.new()
	preview.definition = CharacterDefinition.new()
	preview.definition.starting_class = definition
	root.add_child(preview)
	_check(preview.get_max_health() == 44 and preview.get_initiative() == 12 and preview.get_movement_range() == 7.5, "Inspector class edits drive unit HP, initiative, and movement previews")
	if _property("default_constitution") != null:
		_property("default_constitution").emit_changed("default_constitution", 6)
		await _frames()
		_check(preview.current_health == 24 and preview.max_health == 24, "class Inspector edit refreshes existing unit and clamps HP")
		_property("default_constitution").emit_changed("default_constitution", 11)
		await _frames()
		_check(preview.current_health == 24, "class Inspector edit never grants healing")
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
	var strike := load("res://resources/abilities/strike.tres") as AbilityDefinition
	EditorInterface.edit_resource(strike)
	await _frames()
	_check(_property("allow_unarmed_for_friendlies") != null and strike.allow_unarmed_for_friendlies, "Strike Inspector exposes its opt-in unarmed friendly setting")
	var bloodlust := (load("res://resources/abilities/bloodlust.tres") as AbilityDefinition).duplicate() as AbilityDefinition
	EditorInterface.edit_resource(bloodlust)
	await _frames()
	_check(_property("on_kill_status") != null and _property("on_kill_status_stacks") != null, "Ability Inspector exposes reusable on-kill reward fields")
	if _property("on_kill_status_stacks") != null:
		_property("on_kill_status_stacks").emit_changed("on_kill_status_stacks", 3)
		await _frames()
		_check(bloodlust.on_kill_status_stacks == 3, "Inspector edits reward stack count")
	var ability_path := "res://.godot/class_validation/editor_bloodlust_%d.tres" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ability_path.get_base_dir())
	_check(ResourceSaver.save(bloodlust, ability_path) == OK, "Inspector reward configuration saves")
	var restored_ability := ResourceLoader.load(ability_path, "", ResourceLoader.CACHE_MODE_IGNORE) as AbilityDefinition
	_check(restored_ability.on_kill_status_stacks == 3 and restored_ability.on_kill_status == load("res://resources/statuses/strength_up.tres"), "Inspector reward resource and count survive reload")
	var path := "res://.godot/class_validation/editor_allocation_%d.tres" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	_check(ResourceSaver.save(allocation, path) == OK, "Allocation and inline class save")
	var restored := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as CharacterClassLevel
	_check(restored != null and restored.level == 3 and restored.character_class.ability_unlocks[0].required_level == 3, "Inspector allocation and unlock edits survive resource reload")
	for index in default_fields.size():
		_check(float(restored.character_class.get(default_fields[index])) == float(default_values[index]), "%s survives Inspector resource save and reload" % default_fields[index])
	EditorInterface.edit_node(preview)
	await _frames()
	_check(_property("max_health") != null and preview.max_health == 44, "unit Inspector shows health derived from class defaults")
	preview.class_level_overrides = [allocation]
	EditorInterface.edit_resource(preview.class_level_overrides[0])
	await _frames()
	var alternate := definition.duplicate() as CharacterClassDefinition
	alternate.default_constitution = 13
	if _property("character_class") != null:
		_property("character_class").emit_changed("character_class", alternate)
		await _frames()
		_check(preview.get_max_health() == 52 and preview.current_health == 24, "nested allocation Inspector changes the stat class without healing")
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		EditorInterface.edit_resource(restored.character_class)
		await _frames()
		await RenderingServer.frame_post_draw
		var capture_path := "res://.godot/class_validation/default_stats_inspector.png"
		_check(EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(capture_path) == OK, "class defaults Inspector screenshot saves")
	EditorInterface.get_inspector().edit(null)
	preview.free()
	if _failures.is_empty():
		print("CHARACTER_CLASS_EDITOR_OK")
	for failure in _failures:
		push_error(failure)
	EditorInterface.get_base_control().get_tree().quit(0 if _failures.is_empty() else 1)
