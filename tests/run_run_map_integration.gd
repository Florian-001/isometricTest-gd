extends SceneTree

var failed := false
var manager: MapManager
var run: RunController
var rendered := false
var artifact_directory := "res://.godot/run_validation"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	rendered = DisplayServer.get_name() != "headless"
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(artifact_directory))
	manager = load("res://main.tscn").instantiate() as MapManager
	run = manager.get_node("RunController") as RunController
	run.save_path = artifact_directory + "/integration_%d.json" % Time.get_ticks_usec()
	run.use_fixed_seed = true
	run.fixed_seed = 37
	root.add_child(manager)
	current_scene = manager
	await process_frame
	check(manager.current_battle == null and manager.level_select.visible, "standalone menu remains startup")
	manager.show_map_button.pressed.emit()
	await frames(4)
	check(run.state != null, "New Run creates and saves party state: " + run.error_message)
	if run.state == null:
		finish()
		return
	check(run.state.party.size() == 2 and run.state.gold == 50 and run.state.inventory.is_empty(), "initial party and resources")
	check(run.state.party[0].health == 48 and run.state.party[1].health == 100, "party uses friendly scene health defaults")
	check(manager.run_map_screen.visible, "new run opens map")
	check(manager.run_map_screen.map_scroll.scroll_vertical > 0, "map opens at the starts")
	check(manager.run_map_screen.map_canvas.node_controls.size() == run.state.graph.nodes.size(), "one scene-authored button per generated room")
	await capture("map_start_1280")
	var scroll_before := manager.run_map_screen.map_scroll.scroll_vertical
	var map_center := manager.run_map_screen.map_scroll.get_global_rect().get_center()
	for tick in range(3):
		var wheel := InputEventMouseButton.new()
		wheel.position = map_center
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		root.push_input(wheel, true)
		wheel.pressed = false
		root.push_input(wheel, true)
	await frames(3)
	check(manager.run_map_screen.map_scroll.scroll_vertical < scroll_before, "mouse wheel scrolls map")
	manager.run_map_screen.map_scroll.scroll_vertical = 0
	await frames(3)
	await capture("map_boss_1280")
	manager.run_map_screen._reset_scroll()
	await frames(5)
	for width in [1024, 1920]:
		root.size = Vector2i(width, 720 if width == 1024 else 1080)
		await frames(4)
		var screen := manager.run_map_screen
		check(screen.map_canvas.size.x <= screen.map_scroll.size.x, "map fits viewport width %d" % width)
		for id: int in screen.map_canvas.node_controls:
			var button: Button = screen.map_canvas.node_controls[id]
			check(button.position.x >= 0 and button.position.x + button.size.x <= screen.map_canvas.size.x, "room stays inside map")
		await capture("map_start_%d" % width)
	root.size = Vector2i(1280, 720)
	await frames(4)
	# Exercise real GUI input on a reachable room.
	var first_id := run.state.available_rooms()[0]
	var button: Button = manager.run_map_screen.map_canvas.node_controls[first_id]
	var click := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = click
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = click
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await frames(5)
	if manager.current_battle == null:
		print("Input diagnostic ", click, " scroll ", manager.run_map_screen.map_scroll.scroll_vertical, " state ", run.error_message, " pending ", run.state.pending, " focus ", root.gui_get_focus_owner(), " hover ", root.gui_get_hovered_control())
	check(manager.current_battle != null, "mouse selection enters tactical encounter")
	if manager.current_battle == null:
		finish()
		return
	check(not run.select_room(first_id), "double selection rejected")
	check(run.state.route.is_empty(), "entry is not completion")
	var battle := manager.current_battle
	check(not battle.restart_button.visible and not battle.dev_button.visible, "run disables restart and developer tools")
	var original_pending := JSON.stringify(run.state.pending)
	var entry := run.save_store.load_run()
	check(entry != null and entry.party[0].health == 48, "entry checkpoint contains original party")
	# Quit before resolution and continue the exact committed encounter.
	battle._characters.filter(func(unit: TacticalCharacter) -> bool: return unit.is_friendly())[0].apply_damage(5)
	var checkpoint_path := run.save_path
	manager.return_to_level_select()
	manager.queue_free()
	await frames(3)
	manager = load("res://main.tscn").instantiate() as MapManager
	run = manager.get_node("RunController") as RunController
	run.save_path = checkpoint_path
	root.add_child(manager)
	current_scene = manager
	await frames(3)
	check(manager.continue_run_button.visible, "fresh application session offers Continue Run")
	manager.continue_run_button.pressed.emit()
	await frames(4)
	check(JSON.stringify(run.state.pending) == original_pending, "interruption does not reroll room content")
	battle = manager.current_battle
	var friendly := battle._characters.filter(func(unit: TacticalCharacter) -> bool: return unit.is_friendly())[0] as TacticalCharacter
	check(friendly.current_health == 48, "interrupted battle restores entry health")
	friendly.apply_damage(7)
	# Equip a reward through the existing inventory API, then keep it across rooms.
	var armor := load("res://resources/items/ranger_armor.tres") as ItemDefinition
	battle.general_inventory.add_item(armor)
	battle.inventory_button.button_pressed = true
	await frames(2)
	check(battle.inventory_screen.visible, "run opens existing inventory screen")
	for entry_control in battle.inventory_screen.general_entries.get_children():
		if entry_control.get_meta("item", null) == armor:
			battle.inventory_screen.quick_transfer(entry_control as InventoryItemSlot)
			break
	check(friendly.get_equipped_items().has(armor), "inventory quick action equips loot on the run party")
	await capture("run_inventory")
	battle.inventory_screen.close_button.pressed.emit()
	await frames(2)
	var carried_health := friendly.current_health
	var temporary := StatusEffectDefinition.new()
	temporary.status_id = &"run_test_constitution"
	var temporary_modifier := StatModifierDefinition.new()
	temporary_modifier.stat = UnitStat.Type.CONSTITUTION
	temporary_modifier.value = 10
	temporary.modifiers = [temporary_modifier]
	friendly.apply_status(temporary)
	check(friendly.get_max_health() > 48, "fixture applies temporary health modifier")
	await capture("run_battle")
	await win_battle()
	check(run.state.pending.get("resolved", false), "victory resolves room")
	check(manager.current_battle == null and manager.run_map_screen.visible, "victory returns to map result panel")
	check(run.state.gold == 65, "normal battle reward paid once")
	check(run.state.party[0].health == carried_health and run.state.party[0].equipment.has(armor.resource_path), "health and equipment carry forward")
	check(run.state.party[0].max_health == 48, "temporary maximum health does not persist")
	check(not run.finish_battle(first_id, true, [], []), "duplicate result rejected")
	await capture("room_result")
	manager.run_map_screen.room_action.pressed.emit()
	await frames(3)
	check(run.state.route.size() == 1 and not run.state.available_rooms().has(first_id), "completed room cannot be revisited")
	var before_replace := run.state.graph.get_signature()
	manager.hide_run_map()
	manager.show_map_button.pressed.emit()
	await frames(2)
	check(manager.replace_run_dialog.visible, "replacing unfinished run asks for confirmation")
	manager.replace_run_dialog.canceled.emit()
	manager.replace_run_dialog.hide()
	check(run.state.graph.get_signature() == before_replace, "cancelled replacement preserves the run")
	manager.continue_run()
	await frames(4)
	# Follow the entire generated route with actual battle lifecycles.
	var battles := 1
	while run.state.status == RunState.Status.ACTIVE and not failed:
		var choices := run.state.available_rooms()
		check(not choices.is_empty(), "completed room has a next choice")
		if choices.is_empty():
			break
		check(run.select_room(choices[0]), "next connected room is selectable")
		await frames(3)
		if manager.current_battle != null:
			for enemy in manager.current_battle._characters:
				if not enemy.is_friendly():
					check(enemy.current_health == enemy.get_max_health(), "scaled encounter enemies start at full health")
			battles += 1
			await win_battle()
		elif int(run.state.pending.type) == RunMapGraph.NodeType.SHOP:
			await capture("merchant")
			if run.state.gold >= int(run.state.pending.price):
				check(run.buy_offer(0), "merchant purchase works")
				check(not run.buy_offer(0), "merchant cannot sell offer twice")
		if run.state.status == RunState.Status.ACTIVE:
			check(run.complete_room(), "room acknowledgement advances route")
		await frames(2)
	check(run.state.status == RunState.Status.WON, "full act reaches boss victory")
	await capture("run_victory")
	check(run.complete_room(), "boss result can be acknowledged")
	check(run.state.route.size() == 16, "fifteen floors and boss completed")
	var loaded := run.save_store.load_run()
	check(loaded != null and loaded.status == RunState.Status.WON, "completed run survives reload")
	# Exercise the actual merchant panel independently of the chosen full-act route.
	check(run.new_run(55), "merchant UI fixture starts")
	var merchant_id := run.state.available_rooms()[0]
	run.state.graph.get_node_by_id(merchant_id).type = RunMapGraph.NodeType.SHOP
	run.select_room(merchant_id)
	await frames(4)
	check(manager.run_map_screen.offers.get_child_count() == 3, "merchant panel renders three offers")
	await capture("merchant")
	(manager.run_map_screen.offers.get_child(0) as Button).pressed.emit()
	await frames(2)
	check(run.state.gold == 10 and (manager.run_map_screen.offers.get_child(0) as Button).disabled, "merchant UI updates after purchase")
	manager.run_map_screen.room_action.pressed.emit()
	check(run.state.pending.is_empty(), "leave merchant returns to route")
	# New run: a fallen party member never reappears; total defeat is terminal.
	check(run.new_run(71), "new run can replace finished run")
	await frames(5)
	var keyboard_room: Button = manager.run_map_screen.map_canvas.node_controls[run.state.available_rooms()[0]]
	keyboard_room.grab_focus()
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ENTER
		key.pressed = pressed
		root.push_input(key, true)
	await frames(3)
	check(manager.current_battle != null, "keyboard activation enters focused room")
	battle = manager.current_battle
	friendly = battle._characters.filter(func(unit: TacticalCharacter) -> bool: return unit.is_friendly())[0]
	friendly.apply_damage(100000)
	friendly.heal(100000)
	check(friendly.current_health == 0, "run members cannot be revived during battle")
	await win_battle()
	check(run.state.party[0].lost and run.state.party[0].equipment.is_empty(), "fallen member and equipped items are lost")
	run.complete_room()
	while run.state.status == RunState.Status.ACTIVE and manager.current_battle == null:
		run.select_room(run.state.available_rooms()[0])
		await frames(3)
		if manager.current_battle == null:
			run.complete_room()
	battle = manager.current_battle
	check(battle._characters.filter(func(unit: TacticalCharacter) -> bool: return unit.is_friendly()).size() == 1, "lost member is not spawned again")
	for unit in battle._characters:
		if unit.is_friendly():
			unit.apply_damage(100000)
	await frames(4)
	check(run.state.status == RunState.Status.LOST and run.state.available_rooms().is_empty(), "full party defeat ends run")
	await capture("run_defeat")
	check(run.save_store.load_run().status == RunState.Status.LOST, "defeat persists")
	print("Run integration exercised %d battles in a full act." % battles)
	manager.queue_free()
	await frames(3)
	finish()

func win_battle() -> void:
	var battle := manager.current_battle
	check(battle != null and battle.initialization_succeeded, "battle initialized")
	if battle == null:
		return
	for unit in battle._characters:
		if not unit.is_friendly():
			unit.apply_damage(100000)
	await frames(5)

func frames(count: int) -> void:
	for index in range(count):
		await process_frame

func capture(file_name: String) -> void:
	if rendered:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(artifact_directory + "/" + file_name + ".png")

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func finish() -> void:
	if not failed:
		print("RUN_MAP_INTEGRATION_OK")
	quit(1 if failed else 0)
