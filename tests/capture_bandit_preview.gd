extends SceneTree


func _init() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(1200, 620)
	root.content_scale_size = root.size
	RenderingServer.set_default_clear_color(Color("25313a"))
	var field := Node2D.new()
	root.add_child(field)
	var entries := [
		["bandit_warrior", TacticalCharacter.Facing.LEFT, "Warrior Left"],
		["bandit_warrior", TacticalCharacter.Facing.RIGHT, "Warrior Right"],
		["goblin_warrior", TacticalCharacter.Facing.RIGHT, "Existing Goblin"],
		["bandit_ranger", TacticalCharacter.Facing.LEFT, "Ranger Left"],
		["bandit_ranger", TacticalCharacter.Facing.RIGHT, "Ranger Right"],
	]
	var baseline := Line2D.new()
	baseline.points = PackedVector2Array([Vector2(20, 340), Vector2(1180, 340)])
	baseline.width = 1
	baseline.default_color = Color("49616d")
	field.add_child(baseline)
	for index in range(entries.size()):
		var entry: Array = entries[index]
		var unit := (load("res://scenes/enemies/%s.tscn" % entry[0]) as PackedScene).instantiate() as TacticalCharacter
		unit.name = entry[2]
		unit.position = Vector2(120 + index * 240, 340)
		unit.scale = Vector2(1.8, 1.8)
		field.add_child(unit)
		unit.set_facing(entry[1])
	var label := Label.new()
	label.position = Vector2(40, 430)
	label.add_theme_font_size_override("font_size", 22)
	label.text = "Bandit Warrior: 20 HP / Strike: 6 damage / CR 1\nBandit Ranger: 12 HP / Enemy Shot: 5 damage / CR 1\nBoth facings shown beside the existing Goblin Warrior at equal artwork scale."
	field.add_child(label)
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("res://.godot/bandit_preview.png")
	print("BANDIT_PREVIEW_SAVED (error %d)" % error)
	field.queue_free()
	await process_frame
	quit(error)
