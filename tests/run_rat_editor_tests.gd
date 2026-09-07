extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _run() -> void:
	if not Engine.is_editor_hint():
		push_error("Run with --editor --script res://tests/run_rat_editor_tests.gd")
		quit(1)
		return
	await create_timer(3.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
	EditorInterface.open_scene_from_path("res://scenes/enemies/rat.tscn")
	await _frames(8)
	# Restoring the editor layout may briefly select a previously open scene.
	if EditorInterface.get_edited_scene_root().scene_file_path != "res://scenes/enemies/rat.tscn":
		EditorInterface.open_scene_from_path("res://scenes/enemies/rat.tscn")
		await _frames(8)
	var rat := EditorInterface.get_edited_scene_root() as TacticalCharacter
	_check(rat != null and rat.max_health == 5, "Rat scene loads with Inspector max health 5")
	var definition := load("res://resources/enemies/rat.tres") as EnemyDefinition
	EditorInterface.edit_resource(definition)
	await _frames(8)
	var inspector := EditorInterface.get_inspector()
	_check(inspector.get_edited_object() == definition, "Actual Inspector displays Rat definition")
	var fields := {}
	for field in inspector.find_children("*", "EditorProperty", true, false):
		fields[field.get_edited_property()] = field
	for property in ["base_health_override", "combat_rating", "max_health"]:
		_check(fields.has(property), "Inspector creates the %s field" % property)
	_check(definition.max_health == 5 and definition.combat_rating == 1, "Inspector starts with HP 5 and CR 1")
	var edited := definition.duplicate() as EnemyDefinition
	EditorInterface.edit_resource(edited)
	await _frames(8)
	for field in inspector.find_children("*", "EditorProperty", true, false):
		if field.get_edited_property() == "base_health_override":
			field.emit_changed("base_health_override", 7)
	await _frames(4)
	_check(edited.base_health_override == 7 and edited.max_health == 7, "Inspector edits refresh derived maximum health")
	var path := "res://.godot/rat_editor_test.tres"
	_check(ResourceSaver.save(edited, path) == OK, "Inspector-edited resource saves")
	var reloaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as EnemyDefinition
	_check(reloaded.max_health == 7, "Inspector-edited HP persists after reload")
	EditorInterface.edit_resource(definition)
	await _frames(4)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(definition.max_health == 5, "Original Rat remains at 5 HP")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/rat_inspector.png")
	if _failures.is_empty():
		print("RAT_EDITOR_TESTS_OK")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)
