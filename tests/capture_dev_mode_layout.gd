extends SceneTree


func _init() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var output_path := "user://dev_mode_layout.png"
	var user_args := OS.get_cmdline_user_args()
	if not user_args.is_empty():
		output_path = str(user_args[0])
	if user_args.size() >= 2:
		var dimensions := str(user_args[1]).split("x")
		if dimensions.size() == 2:
			root.size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres") as BattleMapDefinition
	root.add_child(battle)
	battle._on_dev_button_pressed()
	if user_args.size() >= 3:
		var requested_tab := str(user_args[2]).to_lower()
		if requested_tab == "terrain":
			battle.dev_mode_panel.tabs.current_tab = DevModePanel.TERRAIN_TAB
		elif requested_tab == "ai" or requested_tab == "ai_log":
			battle.dev_mode_panel.tabs.current_tab = DevModePanel.AI_LOG_TAB
			var entries: Array[String] = [
				(
					"Round 2 | Goblin Warrior | Defensive\n"
					+ "Planning: 5.1 ms | Cache: 2 hits, 0 misses\n"
					+ "1. Guard — 62.0"
				),
				(
					"Round 3 | Goblin Scout | Aggressive\n"
					+ "Planning: 8.2 ms | Cache: 4 hits, 1 miss\n"
					+ "1. Arrow Shot — 83.5\n2. Move — 41.0"
				),
			]
			battle.dev_mode_panel.set_ai_history(entries)
	print("DEV_MODE_CAPTURE_STATE: visible=%s in_tree=%s size=%s drawer=%s paused=%s" % [
		battle.dev_mode_panel.visible,
		battle.dev_mode_panel.is_visible_in_tree(),
		battle.dev_mode_panel.size,
		battle.dev_mode_panel.drawer.get_global_rect(),
		paused,
	])
	# The live integration test verifies pause semantics. Unpause only while the
	# off-screen capture settles so the standalone --script viewport redraws.
	paused = false
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	var error := image.save_png(output_path)
	paused = false
	root.remove_child(battle)
	battle.free()
	if error == OK:
		print("DEV_MODE_LAYOUT_CAPTURED: %s" % output_path)
		quit(0)
	else:
		push_error("Could not save Dev Mode layout capture (error %d)." % error)
		quit(1)
