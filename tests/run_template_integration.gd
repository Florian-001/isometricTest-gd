extends SceneTree

const DEMO := "res://resources/maps/spawn_template_demo.tres"
const ENCOUNTER := "res://resources/run/spawn_template_normal.tres"
var _failures: Array[String] = []
var _save_paths: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _run() -> void:
	await _test_standalone()
	await _test_run_checkpoint()
	for path in _save_paths:
		for suffix in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	if _failures.is_empty():
		print("TEMPLATE_INTEGRATION_OK")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _battle(template: BattleMapDefinition, payload: Dictionary = {}) -> TacticalBattle:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = template
	battle.pending_restore_payload = payload
	battle.center_camera_on_start = false
	root.add_child(battle)
	return battle


func _test_standalone() -> void:
	var template := load(DEMO) as BattleMapTemplateDefinition
	var battle := _battle(template)
	_check(battle.initialization_succeeded, "Standalone template battle initializes")
	_check(battle._characters.size() == 5, "Demo spawns two friendlies and three CR-1 enemies")
	var friendly_cells: Array[Vector2i] = []
	var occupied := {}
	var total := 0
	for actor in battle._characters:
		_check(not occupied.has(actor.starting_grid_cell), "Every spawned unit has a unique cell")
		occupied[actor.starting_grid_cell] = true
		if actor.is_friendly():
			friendly_cells.append(actor.starting_grid_cell)
		else:
			total += (actor.definition as EnemyDefinition).combat_rating
	_check(friendly_cells == [Vector2i(4, 9), Vector2i(7, 9)], "Standalone party follows friendly paint order")
	_check(total == 3, "Standalone enemy CR matches the budget")
	_check(not battle.battle_map.get_node("SpawnTiles").visible, "Spawn overlays are hidden in actual battles")
	var payload := battle.capture_save_payload(true)
	var validation := ScenarioSaveStore.validate_payload(payload)
	_check(validation.ok, "Generated units fit the existing scenario save schema: %s" % str(validation.errors))
	var initial_units: Array = payload.setup.units.duplicate(true)
	battle.shutdown_battle()
	battle.queue_free()
	await process_frame
	var restored := _battle(template, validation.payload)
	_check(restored.initialization_succeeded, "Standalone restart initializes from captured units")
	_check(restored.capture_save_payload(true).setup.units == initial_units, "Restart preserves exact scene choices, cells, stats, and equipment overrides")
	restored.shutdown_battle()
	restored.queue_free()
	await process_frame
	var map := template.map_scene.instantiate() as BattleMap
	_check(map.get_characters().get_child_count() == 0, "Generation never writes units into the template scene")
	map.free()
	var authored := _battle(load("res://resources/maps/terrain_showcase.tres"))
	_check(authored.initialization_succeeded, "Existing authored map still initializes")
	authored.shutdown_battle()
	authored.queue_free()
	await process_frame


func _test_run_checkpoint() -> void:
	var manager := (load("res://main.tscn") as PackedScene).instantiate() as MapManager
	var controller := manager.get_node("RunController") as RunController
	controller.config = (load("res://resources/run/default_run.tres") as RunConfig).duplicate()
	# This fixture exercises legacy, fixed-budget template encounters.
	controller.config.combat_stages = []
	controller.config.normal_encounters = [load(ENCOUNTER)]
	controller.save_path = "res://.godot/template_validation/run_%d.json" % Time.get_ticks_usec()
	_save_paths.append(controller.save_path)
	root.add_child(manager)
	_check(manager.levels.size() == 3 and manager.levels.back() is BattleMapTemplateDefinition, "Menu registers the additive template demo")
	_check(controller.new_run(37), "An isolated run begins")
	controller.state.party[0].id = "template_enemy_0"
	controller.state.party[0].setup.id = "template_enemy_0"
	var room_id := controller.state.available_rooms()[0]
	_check(controller.select_room(room_id), "Entering a template room saves a checkpoint and starts combat")
	var saved := controller.save_store.load_run()
	_check(saved != null and saved.pending.has("template_setup"), "Checkpoint contains a concrete generated enemy roster")
	var first_setup: Dictionary = controller.state.pending.get("template_setup", {}).duplicate(true)
	var battle := manager.current_battle
	_check(battle != null and battle.initialization_succeeded, "Run template battle initializes through MapManager")
	if battle == null:
		manager.queue_free()
		await process_frame
		return
	_check(battle._characters.size() == 5, "Run party and generated enemies are both present")
	var first_units: Array = battle.capture_save_payload(true).setup.units
	for actor in battle._characters:
		if not actor.is_friendly():
			continue
		var member := controller.state.party.filter(func(value: RunPartyMember) -> bool: return value.id == actor.scenario_unit_id)[0] as RunPartyMember
		_check(actor.current_health == member.health, "Run party health restores from entry checkpoint")
	manager.return_to_level_select()
	await process_frame
	controller.battle_open = false
	controller.state = controller.save_store.load_run()
	controller.resume_room()
	_check(manager.current_battle != null and manager.current_battle.initialization_succeeded, "Continue restores a template encounter")
	_check(manager.current_battle.capture_save_payload(true).setup.units == first_units, "Continue preserves generated roster, cells, and scene overrides")
	_check(controller.state.pending.template_setup == JSON.parse_string(JSON.stringify(first_setup)), "Continue does not consume randomness or rewrite the roster")
	manager.return_to_level_select()
	await process_frame
	controller.battle_open = false
	controller.state.party[0].lost = true
	controller.state.party[0].health = 0
	controller.state.party[0].equipment.clear()
	_check(controller.save_store.save_run(controller.state), "A checkpoint with a lost first party member is valid")
	controller.resume_room()
	var survivors: Array[TacticalCharacter] = []
	for actor in manager.current_battle._characters:
		if actor.is_friendly():
			survivors.append(actor)
	_check(survivors.size() == 1 and survivors[0].starting_grid_cell == Vector2i(7, 9), "Lost party member keeps its slot; survivor stays on friendly cell 2")
	manager.return_to_level_select()
	await process_frame
	controller.battle_open = false
	var malformed := controller.state.to_data()
	malformed.pending.template_setup.enemies[0].cell = [99, 99]
	_check(RunState.from_data(malformed) == null, "Checkpoint validation rejects invalid generated positions")
	# Failed generation must not commit a room or consume the route.
	_check(controller.new_run(37), "Fresh run for failure rollback")
	var before := controller.state.to_data()
	var template := load(DEMO) as BattleMapTemplateDefinition
	var original_budget := template.combat_rating
	template.combat_rating = 0
	_check(not controller.select_room(controller.state.available_rooms()[0]), "Invalid template generation is rejected")
	_check(controller.state.to_data() == before and not controller.battle_open, "Failed generation keeps the prior run state")
	template.combat_rating = original_budget
	# A failed checkpoint write also rolls back the generated room transaction.
	var valid_path := controller.save_store.path
	controller.save_store.path = "res://project.godot/impossible_checkpoint.json"
	_check(not controller.select_room(controller.state.available_rooms()[0]), "Failed checkpoint save prevents battle startup")
	_check(controller.state.to_data() == before and not controller.battle_open, "Failed checkpoint save rolls back the generated roster")
	controller.save_store.path = valid_path
	manager.queue_free()
	await process_frame
