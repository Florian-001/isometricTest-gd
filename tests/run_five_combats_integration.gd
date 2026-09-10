extends SceneTree

const DIRECTORY := "res://.godot/five_combats_validation"
var failures: Array[String] = []
var checks := 0
var manager: MapManager
var run: RunController
var ascent_path: String
var short_path: String
var ascent_checkpoint: String


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count := 4) -> void:
	for index in range(count):
		await process_frame


func _open_manager() -> void:
	manager = load("res://main.tscn").instantiate() as MapManager
	manager.get_node("RunController").save_path = ascent_path
	manager.get_node("FiveCombatsController").save_path = short_path
	root.add_child(manager)
	current_scene = manager
	run = manager.five_combats_controller
	await frames()


func _close_manager() -> void:
	manager.return_to_level_select()
	manager.queue_free()
	paused = false
	await frames()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	var stamp := Time.get_ticks_usec()
	ascent_path = DIRECTORY + "/ascent_%d.json" % stamp
	short_path = DIRECTORY + "/five_%d.json" % stamp
	await _open_manager()
	_test_configuration()
	check(manager.ascent_run_controller.new_run(37), "full run saves independently")
	ascent_checkpoint = FileAccess.get_file_as_string(ascent_path)
	manager.five_combats_button.pressed.emit()
	manager.starting_hub.toggle_character("vanguard")
	manager.starting_hub.toggle_character("archer")
	manager.starting_hub.start_button.pressed.emit()
	await frames()
	check(not manager.replace_run_dialog.visible and run.state != null, "new short run needs no replacement of the active full run")
	if run.state == null:
		await _finish()
		return
	check(manager.run_controller == run and manager.run_map_screen.controller == run, "hub selects the short controller")
	check(run.state.party.size() == 2 and run.state.gold == 50, "same party selection and starting gold")
	await _test_switching_and_layout()
	# Keep fixtures at a player boundary while testing real battle lifecycles.
	run.state.party[0].setup.stat_overrides.speed = 1000
	run.state.inventory.append("res://resources/items/weapons/wooden_sword.tres")
	var carried_health := run.state.party[0].health - 7
	for index in range(5):
		check(run.state.available_rooms() == [index], "only combat %d is available" % (index + 1))
		check(not run.select_room(index + 1), "future room cannot be skipped to")
		manager.run_map_screen.map_canvas.node_controls[index].pressed.emit()
		await frames()
		var battle := manager.current_battle
		check(battle != null and battle.initialization_succeeded, "combat %d initializes" % (index + 1))
		if battle == null:
			break
		check(int(run.state.pending.combat_progression.combat_rating) == index + 1 and int(run.state.pending.template_setup.total_cr) == index + 1, "actual roster spends the expected CR")
		check(battle.run_encounter.enemy_multiplier == 1.0 and battle.run_encounter.chief_node_name.is_empty(), "no elite or chief scaling")
		for enemy in battle._characters:
			if not enemy.is_friendly():
				check(enemy.scene_file_path.contains("goblin" if index < 3 else "skeleton"), "correct enemy family for combat %d" % (index + 1))
		if index == 0:
			_friendly(battle).apply_damage(7)
		if index == 1:
			check(_friendly(battle).current_health == carried_health, "health carries to the next fight")
			var pending_text := JSON.stringify(run.state.pending)
			var payload := battle.capture_save_payload(true)
			check(ScenarioSaveStore.validate_payload(payload).ok, "restart payload validates: " + str(ScenarioSaveStore.validate_payload(payload).errors))
			check(manager.reload_battle_from_payload(payload, battle), "developer restart uses short run context")
			await frames()
			check(manager.current_battle.run_node_id == index and JSON.stringify(run.state.pending) == pending_text, "developer restart preserves committed room")
			battle = manager.current_battle
			battle.dev_button.pressed.emit()
			await frames()
			var snapshot := battle.capture_save_payload(false)
			check(manager.reload_battle_from_payload(snapshot, battle), "exact scenario reload retains short progression context")
			await frames()
			await _close_manager()
			await _open_manager()
			check(run.state != null and _normalized(run.state.pending) == _normalized(JSON.parse_string(pending_text)), "fresh application restores committed short encounter")
			manager.continue_five_combats_button.pressed.emit()
			await frames()
			battle = manager.current_battle
			check(battle != null and battle.run_node_id == index, "short Continue resumes its own battle")
			if battle == null:
				break
		if index == 2:
			for member in battle._characters:
				if member.is_friendly() and member.scenario_unit_id == "archer":
					member.apply_damage(100000)
		if index >= 3:
			check(run.state.party[1].lost and battle._characters.filter(func(unit: TacticalCharacter) -> bool: return unit.is_friendly()).size() == 1, "fallen member remains lost")
		if index == 4:
			var blocker := DIRECTORY + "/blocker_%d" % stamp
			var file := FileAccess.open(blocker, FileAccess.WRITE)
			file.store_string("file")
			file.close()
			run.save_store.path = blocker + "/cannot_write.json"
		await _win_battle()
		if index == 4:
			check(manager.current_battle != null and run.state.status == RunState.Status.ACTIVE and not run.state.pending.resolved, "failed final save keeps battle and rolls back victory")
			check(run.state.gold == 110, "failed final save does not award gold")
			run.save_store.path = short_path
			manager._retry_run_result()
			await frames()
		check(manager.current_battle == null and run.state.pending.resolved, "combat result saved and battle closed")
		check(run.state.gold == 50 + (index + 1) * 15, "normal reward awarded once")
		check(not run.finish_battle(index, true, [], []), "duplicate result rejected")
		check(run.state.party[0].health == carried_health and run.state.inventory.has("res://resources/items/weapons/wooden_sword.tres"), "health and pack persist")
		if index < 4:
			check(run.state.status == RunState.Status.ACTIVE, "early victories do not finish run")
			manager.run_map_screen.room_action.pressed.emit()
			await frames()
	check(run.state.status == RunState.Status.WON, "fifth normal combat wins run")
	check(run.save_store.load_run().status == RunState.Status.WON, "unacknowledged victory reloads")
	check(manager.run_map_screen.room_title.text == "RUN COMPLETE" and manager.run_map_screen.get_node("%MapLength").text == "5 OF 5 COMBATS", "completion labels count final result")
	await _capture("victory")
	manager.run_map_screen.room_action.pressed.emit()
	await frames()
	check(run.state.route.size() == 5 and run.state.pending.is_empty() and run.state.available_rooms().is_empty(), "final acknowledgement ends route")
	check(run.save_store.load_run().status == RunState.Status.WON, "acknowledged victory reloads")
	check(manager.continue_five_combats_button.text == "View Last: Five Combats", "completed short run has View Last")
	var invalid := run.state.to_data()
	invalid.status = RunState.Status.ACTIVE
	check(RunState.from_data(invalid) == null, "completed route cannot claim active status")
	await _test_replacement_and_defeat()
	check(FileAccess.get_file_as_string(ascent_path) == ascent_checkpoint, "short lifecycle never changes full run save")
	await _finish()


func _test_configuration() -> void:
	check(run.config.validate_configuration(4).errors.is_empty(), "short configuration supports four party members without elites or boss")
	var baseline := manager.ascent_run_controller.config
	for floor_number in range(1, 6):
		var short_settings := RunCombatProgression.resolve_floor(run.config, floor_number)
		check(short_settings.error.is_empty() and int(short_settings.combat_rating) == floor_number, "short floor CR %d" % floor_number)
		check(int(RunCombatProgression.resolve_floor(baseline, floor_number).combat_rating) == [8, 9, 10, 12, 13][floor_number - 1], "original difficulty unchanged")
	var invalid := run.config.duplicate() as RunConfig
	invalid.combat_stages = [invalid.combat_stages[0]]
	check(not invalid.validate_configuration(2).errors.is_empty(), "missing short floor progression rejected")
	invalid = run.config.duplicate()
	var elite := run.config.normal_encounters[0].duplicate() as RunEncounterDefinition
	elite.enemy_multiplier = 1.5
	invalid.normal_encounters = [elite]
	check(not invalid.validate_configuration(2).errors.is_empty(), "linear configuration rejects elite scaling")
	invalid = run.config.duplicate()
	invalid.map_settings = run.config.map_settings.duplicate()
	invalid.map_settings.combat_count = 1000000
	check(not invalid.validate_configuration(2).errors.is_empty(), "invalid linear floor counts fail before progression iteration")


func _test_switching_and_layout() -> void:
	for index in range(3):
		manager.hide_run_map()
		manager.continue_run_button.pressed.emit()
		check(manager.run_controller == manager.ascent_run_controller, "full Continue selects full controller")
		manager.hide_run_map()
		manager.continue_five_combats_button.pressed.emit()
	check(run.state_changed.get_connections().size() == 2 and manager.ascent_run_controller.state_changed.get_connections().size() == 1, "map refresh subscribes only once to active controller")
	check(run.battle_requested.get_connections().size() == 1 and manager.ascent_run_controller.battle_requested.get_connections().is_empty(), "battle requests subscribe only to active controller")
	for size_value in [Vector2i(1024, 720), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = size_value
		manager.hide_run_map()
		await frames()
		for button in [manager.show_map_button, manager.continue_run_button, manager.five_combats_button, manager.continue_five_combats_button]:
			check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(button.get_global_rect()), "menu button fits at %d" % size_value.x)
		await _capture("menu_%d" % size_value.x)
		manager.continue_five_combats_button.pressed.emit()
		await frames()
		var canvas := manager.run_map_screen.map_canvas
		check(manager.run_map_screen.get_node("%MapTitle").text == "FIVE COMBATS", "short title shown")
		for entry in manager.run_map_screen.get_node("Margin/VBox/Legend").get_children():
			check(entry.visible == (entry.name == "Combat"), "only combat legend visible")
		for position_value: Vector2 in canvas.node_positions.values():
			check(is_equal_approx(position_value.x, canvas.size.x * 0.5), "linear nodes centered")
		check(canvas.node_controls.size() == 5, "five combat buttons drawn")
		for button: Button in canvas.node_controls.values():
			check(manager.run_map_screen.map_scroll.get_global_rect().encloses(button.get_global_rect()), "all five combats fit the map viewport at %d" % size_value.x)
		await _capture("map_%d" % size_value.x)
	root.size = Vector2i(1280, 720)
	await frames()


func _test_replacement_and_defeat() -> void:
	manager.five_combats_button.pressed.emit()
	manager.starting_hub.toggle_character("vanguard")
	manager.starting_hub.start_button.pressed.emit()
	await frames()
	check(not manager.replace_run_dialog.visible and run.state.status == RunState.Status.ACTIVE, "finished short run can be replaced directly")
	var checkpoint := FileAccess.get_file_as_string(short_path)
	manager.hide_run_map()
	manager.five_combats_button.pressed.emit()
	manager.starting_hub.toggle_character("archer")
	manager.starting_hub.start_button.pressed.emit()
	check(manager.replace_run_dialog.visible and manager.replace_run_dialog.dialog_text.contains("Five Combats"), "replacement names only short save")
	manager.replace_run_dialog.canceled.emit()
	manager.replace_run_dialog.hide()
	check(FileAccess.get_file_as_string(short_path) == checkpoint, "cancel preserves short checkpoint")
	manager.continue_five_combats_button.pressed.emit()
	run.state.party[0].setup.stat_overrides.speed = 1000
	check(run.select_room(0), "defeat fixture opens")
	await frames()
	for actor in manager.current_battle._characters:
		if actor.is_friendly():
			actor.apply_damage(100000)
	await frames()
	check(run.state.status == RunState.Status.LOST and run.state.available_rooms().is_empty(), "defeat ends short run")
	check(run.save_store.load_run().status == RunState.Status.LOST, "defeat survives reload")
	await _capture("defeat")
	var file := FileAccess.open(short_path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	var backup := run.save_store.load_run()
	check(backup != null and run.save_store.recovered_backup and backup.pending.get("node_id", -1) == 0, "short backup recovers battle entry")


func _friendly(battle: TacticalBattle) -> TacticalCharacter:
	for actor in battle._characters:
		if actor.is_friendly() and actor.scenario_unit_id == "vanguard":
			return actor
	return null


func _win_battle() -> void:
	for actor in manager.current_battle._characters:
		if not actor.is_friendly():
			actor.apply_damage(100000)
			if actor.is_bone_pile:
				actor.apply_damage(1)
	await frames(6)


func _normalized(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(DIRECTORY + "/" + label + ".png") == OK, "capture " + label)


func _finish() -> void:
	await _close_manager()
	print("FIVE_COMBATS_INTEGRATION_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
