extends SceneTree

const EncounterPanel = preload("res://addons/encounter_balance/panel.gd")
const DIRECTORY := "res://.godot/encounter_balance_tests"


func _init() -> void:
	_run.call_deferred()


func capture(path: String) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(DIRECTORY + "/" + path)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	var panel := EncounterPanel.new()
	panel.persist_preferences = false
	panel.store.recovery_path = ""
	root.add_child(panel)
	await process_frame
	for dimensions in [Vector2i(1440, 900), Vector2i(1000, 760)]:
		root.mode = Window.MODE_WINDOWED
		root.size = dimensions
		root.content_scale_size = dimensions
		panel.size = dimensions
		panel.select_run("res://resources/run/default_run.tres")
		panel.grid.select_cell(4, panel.grid.column_index_for("elite_cr"))
		await capture("ascent_%d.png" % dimensions.x)
		panel._pool_dialog("Elite Units Pool — Floor 5", "res://scenes/enemies/skeleton_archer.tscn", func(_text): pass)
		await capture("picker_%d.png" % dimensions.x)
		for child in panel.get_children():
			if child is AcceptDialog:
				child.hide()
		await process_frame
		panel.select_run("res://resources/run/five_combats.tres")
		panel.grid.select_cell(2, panel.grid.column_index_for("normal_cr"))
		await capture("linear_%d.png" % dimensions.x)
	panel.free()
	await process_frame
	print("ENCOUNTER_BALANCE_CAPTURE_OK")
	quit()
