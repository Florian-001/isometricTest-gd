extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _run() -> void:
	if not Engine.is_editor_hint():
		push_error("Run with --editor --script res://tests/run_boar_editor_tests.gd")
		quit(1)
		return
	await create_timer(3.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/boar_validation"))
	var scene_path := "res://scenes/enemies/boar.tscn"
	EditorInterface.open_scene_from_path(scene_path)
	await _frames(8)
	if EditorInterface.get_edited_scene_root().scene_file_path != scene_path:
		EditorInterface.open_scene_from_path(scene_path)
		await _frames(8)
	var actor := EditorInterface.get_edited_scene_root() as TacticalCharacter
	check(actor != null and actor.max_health == 20, "Boar scene opens with 20 HP")
	var original := load("res://resources/enemies/boar.tres") as EnemyDefinition
	var edited := original.duplicate() as EnemyDefinition
	EditorInterface.edit_resource(edited)
	await _frames(6)
	var inspector := EditorInterface.get_inspector()
	var fields := {}
	for field in inspector.find_children("*", "EditorProperty", true, false):
		fields[field.get_edited_property()] = field
	for property in ["max_health", "constitution", "base_health_override", "strength", "dexterity", "intelligence", "speed", "movement_range", "combat_rating", "ai_profile", "starting_equipment", "abilities", "passive_abilities"]:
		check(fields.has(property), "Boar Inspector exposes %s" % property)
	if fields.has("constitution"):
		fields.constitution.emit_changed("constitution", 6)
	await _frames(4)
	check(edited.max_health == 24 and original.max_health == 20, "Inspector editing derives health without changing the original")
	var path := "res://.godot/boar_validation/boar_editor.tres"
	check(ResourceSaver.save(edited, path) == OK, "Inspector-edited definition saves")
	var reloaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as EnemyDefinition
	check(reloaded.max_health == 24 and reloaded.abilities == original.abilities and reloaded.starting_equipment == original.starting_equipment, "Inspector resource reload preserves stats and shared loadout references")
	var tusks := (load("res://resources/items/weapons/boar_tusks.tres") as ItemDefinition).duplicate() as ItemDefinition
	EditorInterface.edit_resource(tusks)
	await _frames(6)
	for field in inspector.find_children("*", "EditorProperty", true, false):
		if field.get_edited_property() == "weapon_damage":
			field.emit_changed("weapon_damage", 7)
	await _frames(4)
	path = "res://.godot/boar_validation/tusks_editor.tres"
	check(tusks.weapon_damage == 7 and ResourceSaver.save(tusks, path) == OK, "Tusks damage is editable in the Inspector")
	var reloaded_tusks := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ItemDefinition
	check(reloaded_tusks.weapon_damage == 7 and reloaded_tusks.icon != null, "Tusks damage and icon survive resource reload")
	EditorInterface.edit_resource(original)
	await _frames(4)
	for failure in failures:
		push_error(failure)
	print("BOAR_EDITOR_TESTS_%s" % ("OK" if failures.is_empty() else "FAILED"))
	quit(0 if failures.is_empty() else 1)
