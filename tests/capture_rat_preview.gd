extends SceneTree


func _init() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(900, 520)
	RenderingServer.set_default_clear_color(Color("25313a"))
	var field := Node2D.new()
	root.add_child(field)
	var grid := IsometricGrid.new()
	grid.grid_size = Vector2i(5, 5)
	grid.position = Vector2(450, 110)
	field.add_child(grid)
	var units: Array[TacticalCharacter] = []
	for entry in [
		["res://scenes/enemies/rat.tscn", Vector2i(1, 3), TacticalCharacter.Facing.LEFT],
		["res://scenes/enemies/rat.tscn", Vector2i(3, 1), TacticalCharacter.Facing.RIGHT],
		["res://scenes/enemies/wolf.tscn", Vector2i(1, 1), TacticalCharacter.Facing.RIGHT],
	]:
		var unit := (load(entry[0]) as PackedScene).instantiate() as TacticalCharacter
		unit.starting_grid_cell = entry[1]
		field.add_child(unit, true)
		unit.initialize(grid)
		unit.set_facing(entry[2])
		print("RAT_FRAME %s: %s" % [unit.name, unit._get_facing_texture().get_size()])
		units.append(unit)
	var label := Label.new()
	label.position = Vector2(30, 410)
	label.text = "Rat: 5 HP / Bite: 5 damage / CR 1\nLeft and right facings beside the existing Wolf, at the standard artwork size."
	field.add_child(label)
	await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://.godot/rat_preview.png"
	var error := root.get_texture().get_image().save_png(path)
	print("RAT_PREVIEW: %s (error %d)" % [path, error])
	field.queue_free()
	await process_frame
	quit(error)
