extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _frames(count: int = 5) -> void:
	for index in range(count):
		await process_frame


func _property(name: String) -> EditorProperty:
	for property in EditorInterface.get_inspector().find_children("*", "EditorProperty", true, false):
		if property.get_edited_property() == name:
			return property
	return null


func _run() -> void:
	if not Engine.is_editor_hint():
		push_error("Run this suite with --editor --script.")
		quit(1)
		return
	await create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
	var source := load("res://resources/run/default_run.tres") as RunConfig
	var config := source.duplicate() as RunConfig
	config.combat_stages = []
	for stage in source.combat_stages:
		config.combat_stages.append(stage.duplicate())
	EditorInterface.edit_resource(config)
	await _frames()
	_check(_property("combat_stages") != null and _property("floor_overrides") != null, "RunConfig exposes both editable lists in the real Inspector")
	_check(config.validate_progression_button.is_valid(), "Inspector validation action is callable in the editor")
	config.validate_progression_button.call()
	_check(config.validate_configuration().errors.is_empty(), "Validation can inspect the configured party, enemy scenes, and layouts in editor mode")
	EditorInterface.edit_resource(config.combat_stages[0])
	await _frames()
	for name in ["display_name", "first_floor", "last_floor", "starting_cr", "cr_per_floor", "enemy_pool"]:
		_check(_property(name) != null, "Stage Inspector exposes %s" % name)
	var starting_cr := _property("starting_cr")
	if starting_cr != null:
		starting_cr.emit_changed("starting_cr", 2)
		await _frames()
		_check(config.combat_stages[0].starting_cr == 2, "Editing an Inspector property changes the stage resource")
		starting_cr.emit_changed("starting_cr", 1)
		await _frames()
	var override := RunCombatFloorOverride.new()
	override.floor = 5
	config.floor_overrides = [override]
	EditorInterface.edit_resource(override)
	await _frames()
	for name in ["floor", "override_cr", "combat_rating", "override_enemy_pool", "enemy_pool"]:
		_check(_property(name) != null, "Floor Override Inspector exposes %s" % name)
	var toggle := _property("override_cr")
	var rating := _property("combat_rating")
	var pool_toggle := _property("override_enemy_pool")
	var pool := _property("enemy_pool")
	if toggle != null and rating != null and pool_toggle != null and pool != null:
		toggle.emit_changed("override_cr", true)
		rating.emit_changed("combat_rating", 7)
		pool_toggle.emit_changed("override_enemy_pool", true)
		var scenes: Array[PackedScene] = [load("res://scenes/enemies/skeleton_archer.tscn")]
		pool.emit_changed("enemy_pool", scenes)
		await _frames()
		var resolved := RunCombatProgression.resolve_floor(config, 5)
		_check(resolved.error.is_empty() and resolved.combat_rating == 7 and resolved.enemy_pool == scenes, "Manual Inspector edits drive both floor overrides")
	var directory := "res://.godot/progression_validation"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory + "/editor_%d.tres" % Time.get_ticks_usec()
	_check(ResourceSaver.save(config, path) == OK, "Inspector-edited settings serialize as a normal Godot resource")
	var restored := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as RunConfig
	_check(restored != null and restored.floor_overrides.size() == 1 and restored.floor_overrides[0].combat_rating == 7 and restored.floor_overrides[0].override_enemy_pool, "Saved stages and overrides survive resource reload")
	_check(source.floor_overrides.is_empty() and source.combat_stages[0].starting_cr == 1, "Editor checks leave the authored default configuration unchanged")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(directory + "/floor_override_inspector.png")
	EditorInterface.edit_resource(null)
	await _frames()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if _failures.is_empty():
		print("COMBAT_PROGRESSION_EDITOR_OK")
	for failure in _failures:
		push_error(failure)
	EditorInterface.get_base_control().get_tree().quit(0 if _failures.is_empty() else 1)
