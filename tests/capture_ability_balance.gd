extends SceneTree

const AbilityPanel = preload("res://addons/ability_balance/panel.gd")
const ROOT := "res://.godot/ability_balance_tests"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	var panel := AbilityPanel.new()
	panel.persist_preferences = false
	panel.store.recovery_path = ""
	root.add_child(panel)
	await process_frame
	for dimensions in [Vector2i(1440, 900), Vector2i(1000, 760)]:
		root.mode = Window.MODE_WINDOWED
		root.size = dimensions
		root.content_scale_size = dimensions
		panel.size = dimensions
		for tab in [0, 1]:
			panel.tabs.current_tab = tab
			var path := "res://resources/abilities/charge.tres" if tab == 0 else "res://resources/passives/pack_tactics.tres"
			panel.grid.select_cell(panel.grid.row_index_for(path), 0)
			await process_frame
			await process_frame
			RenderingServer.force_draw()
			root.get_texture().get_image().save_png(ROOT + "/%s_%d.png" % ["active" if tab == 0 else "passives", dimensions.x])
		panel._show_column_picker()
		await process_frame
		await process_frame
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png(ROOT + "/columns_%d.png" % dimensions.x)
		for child in panel.get_children():
			if child is AcceptDialog:
				child.hide()
		await process_frame
	panel.free()
	await process_frame
	print("ABILITY_BALANCE_CAPTURE_OK")
	quit()
