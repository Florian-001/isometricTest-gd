extends SceneTree

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene := load("res://main.tscn") as PackedScene
	var manager := main_scene.instantiate() as MapManager
	root.add_child(manager)
	await process_frame

	_check(manager.current_battle == null, "startup should not create a battle")
	_check(manager.level_select.visible, "the level selector should remain the startup screen")
	_check(manager.show_map_button.visible, "startup should expose the Show Map button")
	_check(not manager.run_map_screen.visible, "the run map should begin hidden")

	manager.show_map_button.pressed.emit()
	await process_frame
	await process_frame
	_check(not manager.level_select.visible, "Show Map should hide level selection")
	_check(manager.run_map_screen.visible, "Show Map should reveal the run map")
	_check(manager.current_battle == null, "opening the run map should not create a battle")
	_check(manager.run_map_screen.graph.tier_count == 12, "the screen should render twelve tiers")
	_check(
		manager.run_map_screen.map_canvas.node_controls.size() == manager.run_map_screen.graph.nodes.size(),
		"the canvas should render one passive control per graph node"
	)
	_check(manager.run_map_screen.map_scroll.scroll_vertical > 0, "the map should initially scroll to Start")
	for node in manager.run_map_screen.graph.nodes:
		var control: Control = manager.run_map_screen.map_canvas.node_controls[node.id]
		_check(control.mouse_filter == Control.MOUSE_FILTER_IGNORE, "map nodes should remain non-interactive")
		var icon := control.get_node("Margin/Icon") as TextureRect
		_check(icon.texture != null, "every map node should have an imported icon texture")

	manager.run_map_screen.back_button.pressed.emit()
	await process_frame
	_check(manager.level_select.visible, "Back should return to level selection")
	_check(not manager.run_map_screen.visible, "Back should hide the run map")

	manager.queue_free()
	await process_frame
	if _failed:
		quit(1)
	else:
		print("RUN_MAP_INTEGRATION_OK")
		quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
