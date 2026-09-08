extends SceneTree


func _init() -> void:
	_capture.call_deferred()


func _capture() -> void:
	RenderingServer.set_default_clear_color(Color("25313a"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/boar_validation"))
	for resolution in [Vector2i(1280, 720), Vector2i(800, 600)]:
		root.size = resolution
		root.content_scale_size = resolution
		var field := Node2D.new()
		root.add_child(field)
		var entries := [
			["boar", TacticalCharacter.Facing.LEFT, "Boar Left"],
			["boar", TacticalCharacter.Facing.RIGHT, "Boar Right"],
			["wolf", TacticalCharacter.Facing.RIGHT, "Existing Wolf"],
		]
		var step: float = resolution.x / 3.0
		for index in range(entries.size()):
			var entry: Array = entries[index]
			var unit := (load("res://scenes/enemies/%s.tscn" % entry[0]) as PackedScene).instantiate() as TacticalCharacter
			unit.name = entry[2]
			unit.position = Vector2(step * (index + 0.5), 265)
			field.add_child(unit)
			unit.set_facing(entry[1])
			var caption := Label.new()
			caption.position = Vector2(unit.position.x - 65, 290)
			caption.text = entry[2]
			field.add_child(caption)
		var text := Label.new()
		text.position = Vector2(35, 50)
		text.add_theme_font_size_override("font_size", 22)
		text.text = "Boar - native gameplay size (112 px artwork frame)\n20 HP | Charge / Strike: 8 damage | CR 1"
		field.add_child(text)
		var icon := TextureRect.new()
		icon.texture = load("res://assets/item_icons/boar_tusks.svg")
		icon.position = Vector2(35, 365)
		icon.size = Vector2(48, 48)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		field.add_child(icon)
		var equipment := Label.new()
		equipment.position = Vector2(100, 369)
		equipment.text = "Boar Tusks\n6 weapon damage + 2 Strength"
		field.add_child(equipment)
		await process_frame
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png("res://.godot/boar_validation/boar_%dx%d.png" % [resolution.x, resolution.y])
		if result != OK:
			quit(result)
			return
		field.queue_free()
		await process_frame
	print("BOAR_PREVIEWS_SAVED")
	quit(0)
