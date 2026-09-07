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
		push_error("Run with --editor --script res://tests/run_skeleton_editor_tests.gd")
		quit(1)
		return
	await create_timer(3.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
	for entry in [{"id": "skeleton_warrior", "hp": 20}, {"id": "skeleton_archer", "hp": 12}]:
		var scene_path := "res://scenes/enemies/%s.tscn" % entry.id
		EditorInterface.open_scene_from_path(scene_path)
		await _frames(8)
		if EditorInterface.get_edited_scene_root().scene_file_path != scene_path:
			EditorInterface.open_scene_from_path(scene_path)
			await _frames(8)
		var actor := EditorInterface.get_edited_scene_root() as TacticalCharacter
		_check(actor != null and actor.max_health == entry.hp, "%s scene opens with correct Inspector health" % entry.id)
		var definition := load("res://resources/enemies/%s.tres" % entry.id) as EnemyDefinition
		EditorInterface.edit_resource(definition)
		await _frames(6)
		var inspector := EditorInterface.get_inspector()
		_check(inspector.get_edited_object() == definition, "Inspector displays %s definition" % entry.id)
		var fields := {}
		for field in inspector.find_children("*", "EditorProperty", true, false):
			fields[field.get_edited_property()] = field
		for property in ["max_health", "constitution", "combat_rating", "starting_equipment", "abilities"]:
			_check(fields.has(property), "%s Inspector exposes %s" % [entry.id, property])
		_check(definition.max_health == entry.hp and definition.combat_rating == 1, "%s Inspector shows expected HP and CR" % entry.id)
		var edited := definition.duplicate() as EnemyDefinition
		EditorInterface.edit_resource(edited)
		await _frames(6)
		for field in inspector.find_children("*", "EditorProperty", true, false):
			if field.get_edited_property() == "constitution":
				field.emit_changed("constitution", definition.constitution + 1)
		await _frames(4)
		_check(edited.max_health == entry.hp + 4, "Inspector Constitution editing refreshes derived health")
		var path := "res://.godot/%s_editor_test.tres" % entry.id
		_check(ResourceSaver.save(edited, path) == OK, "Inspector-edited definition saves")
		var reloaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as EnemyDefinition
		_check(reloaded.max_health == entry.hp + 4, "Edited Constitution survives resource reload")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		EditorInterface.edit_resource(definition)
		await _frames(4)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/%s_inspector.png" % entry.id)
	if _failures.is_empty():
		print("SKELETON_EDITOR_TESTS_OK")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)
