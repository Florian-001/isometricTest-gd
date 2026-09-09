extends SceneTree

var _failures: Array[String] = []
var _classes: Dictionary = {}
var _directory := "res://.godot/class_validation"


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _names(unit: TacticalCharacter) -> Array[String]:
	var names: Array[String] = []
	for ability in unit.get_abilities():
		names.append(ability.display_name)
	return names


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
	for id in ["warrior", "archer", "wizard", "cleric"]:
		_classes[id] = load("res://resources/classes/%s.tres" % id)
	_test_unlocks_and_isolation()
	_test_validation_and_setup()
	await _test_execution()
	await _test_battle_ui_and_saves()
	if _failures.is_empty():
		print("CHARACTER_CLASS_TESTS_OK")
	for failure in _failures:
		push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_unlocks_and_isolation() -> void:
	var expected := {
		"warrior": ["Strike", "Charge", "Battle Stomp", "Taunt", "Multi Attack"], "archer": ["Strike", "Focus", "Multiple Arrows", "Dagger Throw"],
		"wizard": ["Strike", "Ice Shard", "Searing Dagger", "Slow", "Fireball", "Beam"],
		"cleric": ["Strike", "Heal", "Beam", "Focus", "Empower", "Cleanse"],
	}
	for id in expected:
		var unit := TacticalCharacter.new()
		unit.definition = CharacterDefinition.new()
		unit.definition.starting_class = _classes[id]
		_check(unit.get_character_level() == 1, "%s starts at level one" % id)
		for level in range(1, expected[id].size() + 1):
			_check(unit.set_class_level(_classes[id], level), "%s level can be edited" % id)
			var count: int = mini(level + 2, 6) if id == "cleric" else level + 1 if id == "wizard" else level
			_check(_names(unit) == expected[id].slice(0, count), "%s level %d unlock boundary" % [id, level])
		unit.set_class_level(_classes[id], 150)
		_check(_names(unit) == expected[id], "levels beyond last unlock remain valid")
		unit.free()
	var scene := load("res://scenes/friendlies/friend_b.tscn") as PackedScene
	var first := scene.instantiate() as TacticalCharacter
	var second := scene.instantiate() as TacticalCharacter
	first.set_class_level(_classes.warrior, 2)
	first.set_class_level(_classes.wizard, 1)
	_check(first.get_character_level() == 3 and _names(first) == ["Strike", "Charge", "Ice Shard"], "Warrior 2 / Wizard 1 resolves separate class levels")
	_check(second.get_character_level() == 1 and _names(second) == ["Strike"], "scene instances do not share mutable class levels")
	var snapshot := first.get_class_levels()
	snapshot[0].level = 50
	_check(first.get_character_level() == 3, "returned level entries cannot mutate the character")
	first.set_class_level(_classes.warrior, 1)
	_check(not _names(first).has("Charge"), "lowering levels removes locked abilities")
	first.set_class_level(_classes.warrior, 0)
	_check(not first.set_class_level(_classes.wizard, 0), "last class cannot be removed")
	first.set_class_level(_classes.wizard, 5)
	first.set_class_level(_classes.cleric, 3)
	first.set_class_level(_classes.archer, 2)
	_check(_names(first).count("Beam") == 1 and _names(first).count("Focus") == 1, "multiclass shared abilities are deduplicated")
	_check(_names(first) == ["Strike", "Ice Shard", "Searing Dagger", "Slow", "Fireball", "Beam", "Heal", "Focus", "Empower"], "equipment attack precedes stable class and unlock ordering")
	var unsorted := CharacterClassDefinition.new()
	unsorted.class_id = &"test_order"
	for level in [3, 1, 2, 1]:
		var unlock := ClassAbilityUnlock.new()
		unlock.required_level = level
		unlock.ability = AbilityDefinition.new()
		unsorted.ability_unlocks.append(unlock)
	_check(unsorted.get_sorted_unlocks() == [unsorted.ability_unlocks[1], unsorted.ability_unlocks[3], unsorted.ability_unlocks[2], unsorted.ability_unlocks[0]], "equal-level unlocks retain authored order")
	first.free()
	second.free()


func _test_validation_and_setup() -> void:
	var scene := load("res://scenes/friendlies/friend_a.tscn") as PackedScene
	var unit := scene.instantiate() as TacticalCharacter
	unit.scenario_unit_id = "class_archer"
	unit.set_class_level(_classes.archer, 2)
	unit.set_class_level(_classes.cleric, 3)
	var setup := unit.capture_setup_state()
	_check(CharacterClassProgression.validate_data(setup.class_levels).is_empty(), "valid allocation validates")
	for bad in [null, {}, [], [{"class": "res://resources/classes/archer.tres", "level": 0}], [{"class": "res://resources/classes/archer.tres", "level": 1.5}], [{"class": "res://resources/classes/archer.tres", "level": true}], [{"class": "res://resources/abilities/arrow.tres", "level": 1}], [{"class": "res://missing_class.tres", "level": 1}], [setup.class_levels[0], setup.class_levels[0]]]:
		_check(not CharacterClassProgression.validate_data(bad).is_empty(), "malformed class allocation is rejected")
	var duplicate := _classes.archer.duplicate() as CharacterClassDefinition
	var duplicate_levels: Array[CharacterClassLevel] = [CharacterClassLevel.create(_classes.archer), CharacterClassLevel.create(duplicate)]
	_check(not CharacterClassProgression.validate_levels(duplicate_levels).is_empty(), "duplicate IDs on different class resources are rejected")
	var invalid_unlock := ClassAbilityUnlock.new()
	duplicate.ability_unlocks = [invalid_unlock]
	_check(not duplicate.validate().is_empty(), "missing unlock ability is rejected")
	invalid_unlock.ability = load("res://resources/abilities/arrow.tres")
	invalid_unlock.required_level = 0
	_check(not duplicate.validate().is_empty(), "nonpositive unlock level is rejected")
	var restored := scene.instantiate() as TacticalCharacter
	restored.apply_setup_state(JSON.parse_string(JSON.stringify(setup)))
	_check(restored.get_character_level() == 5 and _names(restored) == _names(unit), "setup JSON round-trip restores multiclass abilities")
	var legacy := setup.duplicate(true)
	legacy.erase("class_levels")
	legacy.override_abilities = true
	legacy.abilities = ["res://resources/abilities/fireball.tres"]
	_check(CharacterClassProgression.prepare_setup(legacy).is_empty(), "legacy setup migrates")
	restored.apply_setup_state(legacy)
	_check(restored.get_character_level() == 1 and restored.get_class_levels()[0].character_class == _classes.archer, "legacy setup uses scene class at level one")
	_check(_names(restored) == ["Fireball"], "legacy developer bypass is preserved")
	var member := RunPartyMember.from_character(unit)
	var data := member.to_data()
	_check(RunPartyMember.from_data(data).setup.class_levels == setup.class_levels, "run member round-trip preserves class allocation")
	data.setup.class_levels[0].level = -1
	_check(RunPartyMember.from_data(data) == null, "run member rejects invalid classes")
	var enemy := (load("res://scenes/enemies/goblin_warrior.tscn") as PackedScene).instantiate() as TacticalCharacter
	var enemy_abilities := enemy.get_abilities().duplicate()
	_check(not enemy.set_class_level(_classes.wizard, 10) and enemy.get_character_level() == 0 and enemy.get_class_levels().is_empty(), "enemies have no class progression")
	_check(enemy.get_abilities() == enemy_abilities, "enemy abilities remain unchanged")
	var unassigned := TacticalCharacter.new()
	unassigned.definition = CharacterDefinition.new()
	_check(not unassigned._get_configuration_warnings().is_empty(), "missing friendly class has an authoring warning")
	var invalid_party := Node2D.new()
	invalid_party.add_child(unassigned)
	unassigned.owner = invalid_party
	var invalid_scene := PackedScene.new()
	invalid_scene.pack(invalid_party)
	var invalid_config := (load("res://resources/run/default_run.tres") as RunConfig).duplicate() as RunConfig
	invalid_config.starting_party = invalid_scene
	_check(not invalid_config.validate_configuration().errors.is_empty(), "run configuration rejects a missing starting class")
	invalid_party.free()
	enemy.free()
	unit.free()
	restored.free()


func _test_execution() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var grid := IsometricGrid.new()
	grid.grid_size = Vector2i(8, 8)
	world.add_child(grid)
	var caster := (load("res://scenes/friendlies/friend_b.tscn") as PackedScene).instantiate() as TacticalCharacter
	caster.starting_grid_cell = Vector2i(1, 1)
	world.add_child(caster)
	caster.initialize(grid)
	caster.equip_item(load("res://resources/items/weapons/iron_sword.tres"))
	var enemy := (load("res://scenes/enemies/goblin_warrior.tscn") as PackedScene).instantiate() as TacticalCharacter
	enemy.starting_grid_cell = Vector2i(3, 1)
	world.add_child(enemy)
	enemy.initialize(grid)
	var executor := AbilityExecutor.new()
	world.add_child(executor)
	var targeting := AbilityTargeting.new(grid.grid_size)
	var units: Array[TacticalCharacter] = [caster, enemy]
	var charge := load("res://resources/abilities/charge.tres") as AbilityDefinition
	caster.reset_ability_action()
	_check(not await executor.execute(caster, charge, enemy.grid_cell, units, grid, targeting), "direct execution cannot cast a locked ability")
	_check(caster.ability_available, "rejected locked casts spend no action")
	caster.set_class_level(_classes.warrior, 2)
	_check(executor.can_execute(caster, charge, enemy.grid_cell, units, grid, targeting), "unlocked Charge can execute")
	_check(OpportunityAttackSystem.get_opportunity_attack_ability(caster).display_name == "Strike", "equipment-derived Strike enables opportunity attacks")
	caster.unequip_item(ItemDefinition.EquipmentSlot.WEAPON)
	_check(not executor.can_execute(caster, charge, enemy.grid_cell, units, grid, targeting), "class unlocks still require matching equipment")
	caster.equip_item(load("res://resources/items/weapons/iron_sword.tres"))
	caster.set_class_level(_classes.warrior, 1)
	caster.set_dev_ability_loadout([charge])
	_check(await executor.execute(caster, charge, enemy.grid_cell, units, grid, targeting), "explicit developer bypass executes locked class ability")
	_check(not caster.ability_available, "successful bypass cast spends normal action")
	caster.reset_dev_ability_loadout()
	_check(_names(caster) == ["Strike"], "disabling bypass restores equipment and class abilities")
	world.free()
	await process_frame


func _test_battle_ui_and_saves() -> void:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	root.add_child(battle)
	_check(battle.initialization_succeeded, "class-enabled battle initializes")
	var actor := battle._characters[0]
	actor.set_class_level(_classes.archer, 2)
	battle._on_ability_selected(load("res://resources/abilities/focus.tres"))
	_check(battle._selected_ability != null, "an unlocked ability can enter targeting")
	actor.set_class_level(_classes.archer, 1)
	_check(battle._selected_ability == null and battle.ability_bar.get_node("Margin/HBox").get_child_count() == 1, "lowering a class level cancels removed targeting and refreshes the bar")
	battle._on_dev_button_pressed()
	var panel := battle.dev_mode_panel
	panel.select_unit(actor)
	_check(panel.class_editor.visible and panel.class_entries.get_child_count() == 1, "developer panel shows friendly classes")
	panel.class_entries.get_child(0).get_node("Level").value = 2
	_check(actor.get_character_level() == 2 and battle._dev_dirty, "developer level control updates character and restart setup")
	for index in range(panel.class_picker.item_count):
		if panel.class_picker.get_item_metadata(index) == _classes.cleric:
			panel.class_picker.select(index)
	panel.add_class_button.pressed.emit()
	_check(actor.get_character_level() == 3 and actor.get_class_levels().size() == 2, "developer picker adds a class at level one")
	_check(panel.ability_entries.get_child_count() == 9, "developer preview includes Empower and Cleanse among both classes' locked and unlocked entries")
	panel.ability_bypass.button_pressed = true
	_check(actor.override_template_abilities and panel.ability_bypass.button_pressed, "developer bypass is explicit and visible")
	panel.ability_bypass.button_pressed = false
	_check(not actor.override_template_abilities, "developer bypass turns off")
	panel.class_entries.get_child(1).get_node("Remove").pressed.emit()
	_check(actor.get_class_levels().size() == 1 and panel.class_entries.get_child(0).get_node("Remove").disabled, "developer removal retains at least one class")
	actor.set_class_level(_classes.wizard, 1)
	panel.select_unit(actor)
	await _capture("developer_classes")
	if OS.get_cmdline_user_args().has("--capture"):
		var unit_scroll := panel.tabs.get_child(DevModePanel.UNIT_TAB) as ScrollContainer
		unit_scroll.ensure_control_visible(panel.ability_bypass)
		unit_scroll.scroll_vertical += 220
		await _capture("developer_unlocks")
		panel.ability_bypass.button_pressed = true
		await _capture("developer_bypass")
		panel.ability_bypass.button_pressed = false
		unit_scroll.scroll_vertical = 0
	battle.inventory_screen.open_for(actor)
	_check(battle.inventory_screen.stats_entries.get_node("ClassProgression").text.contains("Wizard 1"), "inventory displays multiclass summary")
	panel.hide()
	await _capture("inventory_classes")
	panel.show()
	battle.inventory_screen.close_screen()
	var payload := battle.capture_save_payload(true)
	var validated := ScenarioSaveStore.validate_payload(payload)
	_check(validated.ok, "multiclass developer snapshot validates")
	var saved := ScenarioSaveStore.save_new(payload, _directory)
	_check(saved.ok, "multiclass developer snapshot writes")
	if saved.ok:
		_check(ScenarioSaveStore.load_save(saved.path, _directory).ok, "multiclass developer snapshot reads")
	var legacy := payload.duplicate(true)
	for entry in legacy.setup.units:
		entry.erase("class_levels")
	_check(ScenarioSaveStore.validate_payload(legacy).ok, "legacy developer snapshots migrate")
	var malformed := payload.duplicate(true)
	malformed.setup.units[0].class_levels = []
	_check(not ScenarioSaveStore.validate_payload(malformed).ok, "developer snapshots reject empty friendly class allocations")
	panel.select_unit(battle._characters[2])
	_check(not panel.class_editor.visible and not panel.ability_bypass.visible, "enemy developer UI keeps class controls hidden")
	paused = false
	battle.shutdown_battle()
	battle.free()
	await process_frame
	var restored := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	restored.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	restored.pending_restore_payload = validated.payload
	root.add_child(restored)
	_check(restored.initialization_succeeded and restored._characters[0].get_character_level() == 3, "battle restart restores multiclass snapshot")
	restored.shutdown_battle()
	restored.free()
	var controller := RunController.new()
	controller.config = load("res://resources/run/default_run.tres")
	controller.save_store.path = _directory + "/class_run.json"
	_check(controller.new_run(1337), "new run accepts configured classes")
	_check(controller.state.party.size() == 2, "starting party still contains two characters")
	_check(controller.state.party[0].get_class_summary() == "Level 1 · Archer 1" and controller.state.party[1].get_class_summary() == "Level 1 · Warrior 1", "new run starts both characters at level one")
	controller.state.party[0].setup.class_levels = [{"class": "res://resources/classes/archer.tres", "level": 2}, {"class": "res://resources/classes/wizard.tres", "level": 1}]
	_check(controller.save_store.save_run(controller.state), "multiclass run saves")
	_check(controller.save_store.load_run().party[0].get_class_summary() == "Level 3 · Archer 2 / Wizard 1", "multiclass run resumes")
	var screen := (load("res://scenes/run_map_screen.tscn") as PackedScene).instantiate() as RunMapScreen
	root.add_child(screen)
	screen.setup(controller)
	screen.open_map()
	_check(screen.party_entries.get_child(0).get_node("Classes").text == "Level 3 · Archer 2 / Wizard 1", "run party UI displays saved multiclass levels")
	await _capture("run_party_classes")
	screen.free()
	var request := {}
	controller.battle_requested.connect(func(encounter, members, inventory, node_id):
		request.assign({"encounter": encounter, "members": members, "inventory": inventory, "node_id": node_id})
	)
	var next_room: int = controller.state.available_rooms()[0]
	controller.state.graph.get_node_by_id(next_room).type = RunMapGraph.NodeType.NORMAL_COMBAT
	_check(controller.select_room(next_room) and not request.is_empty(), "run emits a committed multiclass battle entry")
	var run_battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	run_battle.run_encounter = request.encounter
	run_battle.map_definition = request.encounter.battle_map
	run_battle.run_party_input = request.members
	run_battle.run_inventory_input = request.inventory
	run_battle.template_setup_input = controller.state.pending.template_setup
	root.add_child(run_battle)
	_check(run_battle.initialization_succeeded, "run battle initializes with saved multiclass entry")
	var run_actor: TacticalCharacter
	for character in run_battle._characters:
		if character.scenario_unit_id == "archer":
			run_actor = character
	_check(run_actor != null and run_actor.get_character_level() == 3 and _names(run_actor) == ["Shoot", "Focus", "Ice Shard"], "run battle restores equipment attacks and independent class unlocks")
	run_actor.set_class_level(_classes.wizard, 2)
	var results := run_battle.capture_run_party()
	var malformed_results: Array[Dictionary] = results.duplicate(true)
	malformed_results[0].class_levels = []
	_check(not controller.finish_battle(next_room, true, malformed_results, run_battle.general_inventory.capture_state()), "invalid result allocations are rejected transactionally")
	_check(not controller.state.pending.resolved and controller.state.party[0].get_class_summary() == "Level 3 · Archer 2 / Wizard 1", "rejected results retain entry classes")
	_check(controller.finish_battle(next_room, true, results, run_battle.general_inventory.capture_state()), "valid class allocations carry through battle results")
	_check(controller.save_store.load_run().party[0].get_class_summary() == "Level 4 · Archer 2 / Wizard 2", "updated result class levels persist on disk")
	run_battle.shutdown_battle()
	run_battle.free()
	controller.free()


func _capture(image_name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture") or DisplayServer.get_name() == "headless":
		return
	var was_paused := paused
	paused = false
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(_directory + "/" + image_name + ".png") == OK, "visual capture saves")
	paused = was_paused
