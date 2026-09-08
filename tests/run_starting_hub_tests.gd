extends SceneTree

const IDS: Array[String] = ["vanguard", "archer", "wizard", "cleric"]
const CELLS: Array[Vector2i] = [Vector2i(4, 9), Vector2i(7, 9), Vector2i(4, 10), Vector2i(7, 10)]
var failures: Array[String] = []
var directory := "res://.godot/hub_validation"
var manager: MapManager
var run: RunController
var hub: StartingHub


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count := 3) -> void:
	for index in range(count):
		await process_frame


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	manager = load("res://main.tscn").instantiate() as MapManager
	run = manager.get_node("RunController") as RunController
	run.save_path = directory + "/hub_%d.json" % Time.get_ticks_usec()
	run.use_fixed_seed = true
	run.fixed_seed = 37
	root.add_child(manager)
	current_scene = manager
	hub = manager.starting_hub
	await frames()
	_test_roster_and_creation()
	await _test_hub()
	await _test_cleric_combat()
	await _test_four_character_battles()
	manager.return_to_level_select()
	manager.queue_free()
	await frames()
	for failure in failures:
		print("HUB_FAILURE: ", failure)
	if failures.is_empty():
		print("STARTING_HUB_TESTS_OK")
	quit(0 if failures.is_empty() else 1)


func _test_roster_and_creation() -> void:
	var report := run.config.inspect_starting_roster()
	check(report.errors.is_empty() and report.entries.size() == 4, "four valid roster scenes: " + " ".join(report.errors))
	if not report.errors.is_empty():
		return
	var config_path := directory + "/roster_config.tres"
	check(ResourceSaver.save(run.config.duplicate(), config_path) == OK, "Inspector-editable roster configuration saves as a resource")
	var reloaded := ResourceLoader.load(config_path, "", ResourceLoader.CACHE_MODE_IGNORE) as RunConfig
	check(reloaded != null and reloaded.inspect_starting_roster().errors.is_empty() and reloaded.starting_character_roster.size() == 4, "roster resource reload preserves scenes and classes")
	var expected := {"vanguard": ["Strike"], "archer": ["Shoot"], "wizard": ["Strike", "Ice Shard"], "cleric": ["Strike", "Heal", "Beam"]}
	for entry in report.entries:
		var character := (entry.scene as PackedScene).instantiate() as TacticalCharacter
		var names: Array[String] = []
		for ability in character.get_abilities():
			names.append(ability.display_name)
		check(names == expected[entry.id], "%s level-one loadout" % entry.id)
		check(character.get_character_level() == 1 and not character.override_template_abilities, "level one without developer bypass")
		if entry.id in ["wizard", "cleric"]:
			check(character.get_equipped_items().is_empty() and character.get_max_health() == 24, "casters inherit spellcaster stats without equipment")
		else:
			var weapon := "iron_sword.tres" if entry.id == "vanguard" else "goblin_bow.tres"
			check(character.get_equipped_items()[0].resource_path.ends_with(weapon), "original run weapon preserved")
		for texture in [character.facing_left_texture, character.facing_right_texture]:
			check(texture != null and texture.get_image().detect_alpha() != Image.ALPHA_NONE, "%s has transparent art in both directions" % entry.id)
		character.free()
	# Every nonempty subset covers each solo and all party sizes.
	for mask in range(1, 16):
		var chosen: Array[String] = []
		for index in range(4):
			if mask & (1 << index):
				chosen.append(IDS[index])
		check(run.new_run_with_party(chosen, 37), "valid party creates: " + str(chosen) + " " + run.error_message)
		if run.state == null:
			return
		check(_party_ids() == chosen, "saved party follows selection order")
		var restored := run.save_store.load_run()
		check(restored != null and JSON.parse_string(JSON.stringify(restored.to_data())) == JSON.parse_string(JSON.stringify(run.state.to_data())), "selected party round-trips through run save")
	var before := run.state.to_data()
	for invalid: Array[String] in [Array([], TYPE_STRING, "", null), Array(["archer", "archer"], TYPE_STRING, "", null), Array(["missing"], TYPE_STRING, "", null), Array(["vanguard", "archer", "wizard", "cleric", "extra"], TYPE_STRING, "", null)]:
		check(not run.new_run_with_party(invalid, 1) and run.state.to_data() == before, "invalid party preserves existing state")
	var configuration := run.config.duplicate() as RunConfig
	configuration.starting_character_roster = [configuration.starting_character_roster[0], configuration.starting_character_roster[0]]
	check(not configuration.inspect_starting_roster().errors.is_empty(), "duplicate authored roster IDs rejected")
	configuration.starting_character_roster = [null]
	check(not configuration.inspect_starting_roster().errors.is_empty(), "missing roster scenes rejected")
	# Compatibility callers still get the original two-member fixed party.
	check(run.new_run(37) and _party_ids() == ["archer", "vanguard"], "legacy new_run retains the fixed party")


func _test_hub() -> void:
	var before := run.state.to_data()
	var saved_text := FileAccess.get_file_as_string(run.save_path)
	manager.show_map_button.pressed.emit()
	await frames()
	check(hub.visible and not manager.level_select.visible and not manager.replace_run_dialog.visible, "New Run opens hub without replacing the save")
	check(hub.slots == ["", "", "", ""] and hub.start_button.disabled, "four initially empty slots disable Start")
	hub.start_button.pressed.emit()
	check(run.state.to_data() == before, "empty Start is ignored")
	await capture("hub_empty_1280")
	# Exercise native GUI input on the available card.
	await click(hub.cards.wizard)
	check(hub.slots[0] == "wizard", "clicking a card fills first empty slot")
	hub.toggle_character("cleric")
	hub.toggle_character("vanguard")
	hub.toggle_character("archer")
	check(hub.get_selected_ids() == ["wizard", "cleric", "vanguard", "archer"], "four unique selections fit")
	hub.toggle_character("cleric")
	check(hub.slots == ["wizard", "", "vanguard", "archer"], "selected card removes without shifting others")
	hub.slot_buttons[2].pressed.emit()
	check(hub.slots == ["wizard", "", "", "archer"], "occupied slot removes without shifting others")
	check(hub.get_selected_ids() == ["wizard", "archer"], "launch order omits empty slots")
	hub.toggle_character("vanguard")
	hub.toggle_character("cleric")
	check(hub.get_selected_ids() == ["wizard", "vanguard", "cleric", "archer"], "new selection fills the earliest hole")
	await frames()
	await capture("hub_selected_1280")
	for resolution in [Vector2i(800, 600), Vector2i(640, 480)]:
		root.size = resolution
		# Exercise a smaller logical viewport as well as the project's window scaling.
		root.content_scale_size = resolution
		await frames(5)
		check(hub.roster_grid.columns < 4 and hub.roster_grid.size.x <= hub.scroll.size.x, "small hub wraps columns without horizontal clipping")
		check(hub.start_button.get_global_rect().end.y <= hub.size.y and hub.back_button.get_global_rect().end.x <= hub.size.x, "hub actions remain reachable")
		await capture("hub_small_%d" % resolution.x)
		hub.scroll.scroll_vertical = int(hub.scroll.get_v_scroll_bar().max_value)
		await frames()
		check(hub.slot_buttons[3].get_global_rect().intersects(hub.scroll.get_global_rect()), "scroll reaches fourth party slot")
		await capture("hub_slots_%d" % resolution.x)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	await frames()
	hub.start_button.pressed.emit()
	check(manager.replace_run_dialog.visible and hub.start_button.disabled, "Start asks to replace existing progress and prevents duplicate starts")
	var selected := hub.slots.duplicate()
	hub.start_button.pressed.emit()
	manager.replace_run_dialog.canceled.emit()
	manager.replace_run_dialog.hide()
	check(hub.slots == selected and not hub.start_button.disabled and run.state.to_data() == before, "cancel keeps selection and previous run")
	var valid_config := run.config
	run.config = valid_config.duplicate()
	run.config.starting_character_roster = []
	hub.start_button.pressed.emit()
	manager.replace_run_dialog.confirmed.emit()
	manager.replace_run_dialog.hide()
	check(hub.visible and hub.error_label.visible and hub.slots == selected and run.state.to_data() == before, "validation failure stays in hub and preserves draft and run")
	run.config = valid_config
	# Block the temporary file, forcing the actual save store to fail before rotation.
	var blocker := ProjectSettings.globalize_path(run.save_path + ".tmp")
	DirAccess.make_dir_absolute(blocker)
	hub.start_button.pressed.emit()
	manager.replace_run_dialog.confirmed.emit()
	manager.replace_run_dialog.hide()
	check(hub.visible and hub.error_label.visible and not hub.start_button.disabled, "failed save stays in hub with an error and allows retry")
	check(hub.slots == selected and run.state.to_data() == before and FileAccess.get_file_as_string(run.save_path) == saved_text, "failed save preserves draft, in-memory state, and disk save")
	DirAccess.remove_absolute(blocker)
	hub.start_button.pressed.emit()
	manager.replace_run_dialog.confirmed.emit()
	manager.replace_run_dialog.hide()
	check(not hub.visible and manager.run_map_screen.visible and _party_ids() == ["wizard", "vanguard", "cleric", "archer"], "successful Start opens map with slot order")
	var started := run.state
	hub.start_button.pressed.emit()
	manager._start_new_run()
	check(run.state == started, "repeated Start after success is ignored")
	manager.hide_run_map()
	manager.show_run_map()
	check(hub.get_selected_ids().is_empty(), "reopening New Run creates a fresh draft")
	hub.toggle_character("cleric")
	hub.back_button.pressed.emit()
	check(manager.level_select.visible and not hub.visible and run.state == started, "Back returns to menu without changing progress")
	var original := run.config
	run.config = original.duplicate()
	run.config.starting_character_roster = []
	run.state = run.save_store.load_run()
	manager.continue_run()
	check(manager.run_map_screen.visible and _party_ids() == ["wizard", "vanguard", "cleric", "archer"], "Continue restores exact saved roster without consulting hub configuration")
	run.config = original
	manager.hide_run_map()


func _test_cleric_combat() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var grid := IsometricGrid.new()
	world.add_child(grid)
	var cleric := load("res://scenes/friendlies/cleric.tscn").instantiate() as TacticalCharacter
	cleric.starting_grid_cell = Vector2i(1, 1)
	world.add_child(cleric)
	cleric.initialize(grid)
	var enemy := load("res://scenes/enemies/goblin_warrior.tscn").instantiate() as TacticalCharacter
	enemy.starting_grid_cell = Vector2i(2, 1)
	world.add_child(enemy)
	enemy.initialize(grid)
	var executor := AbilityExecutor.new()
	world.add_child(executor)
	var targeting := AbilityTargeting.new(grid.grid_size)
	var units: Array[TacticalCharacter] = [cleric, enemy]
	var health := enemy.current_health
	cleric.reset_ability_action()
	check(await executor.execute(cleric, load("res://resources/abilities/beam.tres"), enemy.grid_cell, units, grid, targeting), "solo Cleric casts Beam without equipment")
	check(enemy.current_health < health, "level-one Beam deals damage")
	cleric.apply_damage(6)
	health = cleric.current_health
	cleric.reset_ability_action()
	check(await executor.execute(cleric, load("res://resources/abilities/heal.tres"), cleric.grid_cell, units, grid, targeting), "solo Cleric casts Heal on self")
	check(cleric.current_health > health, "level-one Heal restores health")
	world.queue_free()
	await frames()


func _test_four_character_battles() -> void:
	for type in [RunMapGraph.NodeType.NORMAL_COMBAT, RunMapGraph.NodeType.HARD_COMBAT, RunMapGraph.NodeType.BOSS]:
		check(run.new_run_with_party(IDS, 37), "four-character run created")
		if type == RunMapGraph.NodeType.BOSS:
			for index in range(RunMapGenerator.ROOM_FLOORS):
				run.state.route.append(run.state.available_rooms()[0])
		var node := run.state.graph.get_node_by_id(run.state.available_rooms()[0])
		node.type = type
		check(run.select_room(node.id), "four-character encounter checkpoint commits: " + run.error_message)
		await frames()
		var battle := manager.current_battle
		check(battle != null and battle.initialization_succeeded, "four-character encounter initializes: %d" % type)
		if battle == null:
			continue
		var friends := _friends(battle)
		check(friends.size() == 4, "all four characters enter the battle")
		for index in range(friends.size()):
			check(friends[index].scenario_unit_id == IDS[index] and friends[index].grid_cell == CELLS[index], "battle follows original slot order and spawn cells")
		await capture("battle_four_%d" % type)
		if type == RunMapGraph.NodeType.NORMAL_COMBAT:
			for character in friends:
				character.set_facing(TacticalCharacter.Facing.LEFT)
			await capture("battle_four_left")
		manager.return_to_level_select()
		run.state = run.save_store.load_run()
		manager.continue_run()
		await frames()
		check(manager.current_battle != null and _friends(manager.current_battle).size() == 4, "Continue restores four-character entry checkpoint")
		if manager.current_battle != null:
			for enemy in manager.current_battle._characters.duplicate():
				if not enemy.is_friendly() and enemy.current_health > 0:
					enemy.apply_damage(enemy.current_health)
			await frames(5)
			check(bool(run.state.pending.get("resolved", false)) and run.state.party.size() == 4, "four-character victory commits every member's result")
		manager.return_to_level_select()
		await frames()
	# Preserve a lost second member's index through results, another encounter, and reload.
	check(run.new_run_with_party(IDS, 37), "loss fixture creates")
	var first := run.state.graph.get_node_by_id(run.state.available_rooms()[0])
	first.type = RunMapGraph.NodeType.NORMAL_COMBAT
	run.select_room(first.id)
	await frames()
	var battle := manager.current_battle
	if battle == null:
		check(false, "loss fixture battle exists")
		return
	var friends := _friends(battle)
	friends[1].apply_damage(friends[1].current_health)
	for enemy in battle._characters.duplicate():
		if not enemy.is_friendly() and enemy.current_health > 0:
			enemy.apply_damage(enemy.current_health)
	await frames(5)
	check(run.state.party.size() == 4 and run.state.party[1].lost, "battle results retain a lost member at original index")
	run.complete_room()
	var second := run.state.graph.get_node_by_id(run.state.available_rooms()[0])
	second.type = RunMapGraph.NodeType.HARD_COMBAT
	check(run.select_room(second.id), "survivors enter next battle")
	await frames()
	manager.return_to_level_select()
	run.state = run.save_store.load_run()
	manager.continue_run()
	await frames()
	battle = manager.current_battle
	check(battle != null, "Continue restores survivors")
	if battle != null:
		friends = _friends(battle)
		check(friends.size() == 3, "lost character stays absent")
		for character in friends:
			check(character.grid_cell == CELLS[IDS.find(character.scenario_unit_id)], "survivors retain original spawn indices")
	manager.return_to_level_select()
	# Insufficient legacy and template maps fail before writing any checkpoint.
	var tiny := (load("res://resources/run/goblin_skirmish_map.tres") as BattleMapDefinition).duplicate() as BattleMapDefinition
	var map := tiny.map_scene.instantiate()
	map.get_node("PartySpawns/Member4").free()
	var packed := PackedScene.new()
	packed.pack(map)
	map.free()
	tiny.map_scene = packed
	check(not RunConfig.validate_encounter_capacity(tiny, 4).is_empty(), "legacy encounter rejects insufficient capacity")
	var encounter := run.config.boss_encounter
	var original_map := encounter.battle_map
	encounter.battle_map = tiny
	var before := run.state.to_data()
	check(not run.new_run_with_party(IDS, 37) and run.state.to_data() == before, "invalid boss capacity blocks new run without replacing progress")
	var next := run.state.graph.get_node_by_id(int(run.state.pending.node_id))
	run.state.pending = {}
	next.type = RunMapGraph.NodeType.BOSS
	var text_before := FileAccess.get_file_as_string(run.save_path)
	check(not run.select_room(next.id) and run.state.pending.is_empty() and FileAccess.get_file_as_string(run.save_path) == text_before, "capacity error cannot create an encounter checkpoint")
	encounter.battle_map = original_map


func _friends(battle: TacticalBattle) -> Array[TacticalCharacter]:
	var friends: Array[TacticalCharacter] = []
	for character in battle._characters:
		if character.is_friendly():
			friends.append(character)
	return friends


func _party_ids() -> Array[String]:
	var result: Array[String] = []
	for member in run.state.party:
		result.append(member.id)
	return result


func click(button: Button) -> void:
	var position := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await frames()


func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await frames()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + "/" + name + ".png")
