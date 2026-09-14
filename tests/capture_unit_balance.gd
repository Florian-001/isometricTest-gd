extends SceneTree

const BalancePanel = preload("res://addons/unit_balance/panel.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var panel := BalancePanel.new()
	panel.persist_preferences = false
	panel.store.recovery_path = ""
	root.add_child(panel)
	await process_frame
	for dimensions in [Vector2i(1440, 900), Vector2i(1000, 760)]:
		root.mode = Window.MODE_WINDOWED
		root.size = dimensions
		root.content_scale_size = dimensions
		panel.size = dimensions
		panel.tabs.current_tab = 0
		panel.grid.select_cell(0, 0)
		await process_frame
		await process_frame
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png("res://.godot/unit_balance_tests/enemies_%d.png" % dimensions.x)
	panel.tabs.current_tab = 1
	panel.grid.select_cell(2, 0)
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png("res://.godot/unit_balance_tests/items.png")
	panel.free()
	await process_frame
	print("UNIT_BALANCE_CAPTURE_OK")
	quit()
