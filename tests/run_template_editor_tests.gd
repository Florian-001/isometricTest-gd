extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _run() -> void:
	if not Engine.is_editor_hint():
		push_error("Run this suite with --editor --script res://tests/run_template_editor_tests.gd")
		quit(1)
		return
	await create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
	EditorInterface.open_scene_from_path("res://scenes/maps/spawn_template_demo.tscn")
	await _frames(8)
	var map := EditorInterface.get_edited_scene_root() as BattleMap
	_check(map != null, "Editor opens the template map")
	if map == null:
		await _finish()
		return
	var spawns := map.get_node("SpawnTiles") as BattleSpawnTiles
	_check(spawns.visible, "Spawn overlay is visible in the actual editor")
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(spawns)
	var plugin: EditorPlugin
	for candidate in root.find_children("*", "EditorPlugin", true, false):
		if candidate.get_script() != null and candidate.get_script().resource_path == "res://addons/spawn_painter/spawn_painter_plugin.gd":
			plugin = candidate
			break
	_check(plugin != null, "Spawn Painter plugin is installed and active")
	if plugin == null:
		await _finish()
		return
	var before_friendly := spawns.friendly_cells.duplicate()
	var before_enemy := spawns.enemy_cells.duplicate()
	plugin._brush.select(0)
	plugin._paint_button.button_pressed = true
	var grid := map.get_grid()
	var position := EditorInterface.get_editor_viewport_2d().get_canvas_transform() * grid.grid_to_global(Vector2i(5, 5))
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	_check(plugin._forward_canvas_gui_input(event), "Spawn painter accepts mouse press")
	event.pressed = false
	_check(plugin._forward_canvas_gui_input(event), "Spawn painter commits mouse release")
	_check(spawns.friendly_cells.has(Vector2i(5, 5)), "Actual editor input paints the selected grid cell")
	var undo_manager := plugin.get_undo_redo()
	var history := undo_manager.get_history_undo_redo(undo_manager.get_object_history_id(spawns))
	history.undo()
	_check(spawns.friendly_cells == before_friendly and spawns.enemy_cells == before_enemy, "EditorUndoRedoManager restores the complete stroke")
	history.redo()
	_check(spawns.friendly_cells.has(Vector2i(5, 5)), "EditorUndoRedoManager redoes the complete stroke")
	history.undo()
	plugin._paint_button.button_pressed = false
	await _frames(4)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var screenshot := EditorInterface.get_editor_viewport_2d().get_texture().get_image()
		var path := "res://.godot/template_editor.png"
		_check(screenshot.save_png(path) == OK, "Editor spawn overlay screenshot saves")
		print("TEMPLATE_EDITOR_CAPTURE: ", ProjectSettings.globalize_path(path))
	await _finish()


func _finish() -> void:
	if _failures.is_empty():
		print("TEMPLATE_EDITOR_TESTS_OK")
	else:
		for failure in _failures:
			push_error(failure)
	# Quit through the active editor tree when running a custom editor MainLoop.
	EditorInterface.get_base_control().get_tree().quit(0 if _failures.is_empty() else 1)
