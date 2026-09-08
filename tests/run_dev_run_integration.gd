extends SceneTree

const DIRECTORY := "res://.godot/dev_run_validation"
var failures: Array[String] = []
var checks := 0
var manager: MapManager
var run: RunController


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func frames(count := 3) -> void:
	for index in range(count):
		await process_frame


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	for encounter in ["goblin_skirmish_normal", "goblin_skirmish_elite", "spawn_template_normal", "boss"]:
		if await _start(encounter):
			await _test_reload_flow(encounter)
		await _close()
	await _test_exit_checkpoint()
	await _close()
	await _test_deleted_party_member()
	await _close()
	await _test_completed_snapshot_reload()
	await _close()
	await _test_temporary_allies()
	await _close()
	for failure in failures:
		push_error(failure)
	print("DEV_RUN_INTEGRATION_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _start(encounter_name: String) -> bool:
	manager = (load("res://main.tscn") as PackedScene).instantiate() as MapManager
	run = manager.get_node("RunController") as RunController
	run.config = run.config.duplicate()
	run.config.combat_stages = []
	var encounter := load("res://resources/run/%s.tres" % encounter_name) as RunEncounterDefinition
	run.config.normal_encounters = [encounter]
	run.config.elite_encounters = [encounter]
	run.save_path = DIRECTORY + "/run_%s_%d.json" % [encounter_name, Time.get_ticks_usec()]
	root.add_child(manager)
	check(run.new_run(37), "isolated %s run starts" % encounter_name)
	if run.state == null:
		return false
	# Keep fixtures at a player action boundary without altering shared resources.
	run.state.party[0].setup.stat_overrides.speed = 1000
	if encounter_name == "boss":
		while run.state.graph.get_node_by_id(run.state.available_rooms()[0]).type != RunMapGraph.NodeType.BOSS:
			run.state.route.append(run.state.available_rooms()[0])
	var room_id := run.state.available_rooms()[0]
	if encounter_name.ends_with("elite"):
		run.state.graph.get_node_by_id(room_id).type = RunMapGraph.NodeType.HARD_COMBAT
	check(run.select_room(room_id), "%s encounter opens through RunController" % encounter_name)
	await frames()
	check(manager.current_battle != null and manager.current_battle.initialization_succeeded, "%s battle initializes" % encounter_name)
	return manager.current_battle != null and manager.current_battle.initialization_succeeded


func _close() -> void:
	if is_instance_valid(manager):
		manager.return_to_level_select()
		manager.queue_free()
	paused = false
	await frames()


func _friendly(battle: TacticalBattle) -> TacticalCharacter:
	for character in battle._characters:
		if character.is_friendly() and character.current_health > 0:
			return character
	return null


func _enemy(battle: TacticalBattle) -> TacticalCharacter:
	for character in battle._characters:
		if not character.is_friendly() and character.current_health > 0:
			return character
	return null


func _find(battle: TacticalBattle, id: String) -> TacticalCharacter:
	for character in battle._characters:
		if character.scenario_unit_id == id:
			return character
	return null


func _test_reload_flow(label: String) -> void:
	var battle := manager.current_battle
	var actor := _friendly(battle)
	var enemy := _enemy(battle)
	var actor_id := actor.scenario_unit_id
	var enemy_id := enemy.scenario_unit_id
	var node_id := battle.run_node_id
	var encounter := battle.run_encounter
	var template_setup := battle.template_setup_input.duplicate(true)
	var checkpoint_text := FileAccess.get_file_as_string(run.save_path)
	var before_gold := run.state.gold
	var gold_reward := int(run.state.pending.get("gold", 0))
	check(battle.dev_button.visible and not battle.dev_button.disabled and not battle.restart_button.visible, "%s shows usable Dev and hides manual Restart" % label)
	if label == "goblin_skirmish_normal":
		await _capture("run_dev_button")
	battle.enable_dev_tools = false
	battle._set_movement_locked(true)
	actor.is_moving = true
	battle.dev_button.pressed.emit()
	check(battle._dev_open_pending and not paused and battle.dev_button.visible, "Dev queues while an action is in progress")
	battle._set_movement_locked(false)
	await frames()
	check(not battle._dev_open, "moving unit prevents opening the drawer")
	actor.is_moving = false
	battle._set_movement_locked(false)
	await frames()
	check(battle._dev_open and paused and battle.dev_button.visible and battle.dev_button.disabled, "queued Dev opens at the player boundary even with legacy false")
	battle.dev_mode_panel.play_button.pressed.emit()
	check(not paused and not battle._dev_open and not battle.dev_button.disabled, "Resume returns to the same run battle")

	battle.dev_button.pressed.emit()
	battle.dev_mode_panel.select_unit(actor)
	battle.dev_mode_panel._set_class_level(3, load("res://resources/classes/archer.tres"))
	check(battle._dev_dirty, "class editor marks run setup dirty")
	if label == "goblin_skirmish_normal":
		await _capture("run_dev_editor")
	actor.apply_damage(7)
	actor.apply_status(load("res://resources/statuses/slow.tres"))
	actor.spend_ability_action()
	actor.spend_movement(1.0)
	enemy.apply_damage(3)
	enemy.set_dev_stat_override(UnitStat.Type.STRENGTH, 27)
	var inventory_item := load("res://resources/items/sage_charm.tres") as ItemDefinition
	battle.general_inventory.add_item(inventory_item)
	# Ordinary inventory equipment also survives a developer restart.
	actor.equip_item(load("res://resources/items/ranger_armor.tres"))
	var expected_health := mini(actor.current_health, actor.get_max_health_without_statuses())
	var expected_inventory := battle.general_inventory.capture_state()
	var expected_setup: Array = battle.capture_save_payload(true).setup.units
	var enemy_max := enemy.get_max_health()
	var enemy_constitution := enemy.constitution_override
	manager.levels = [] # Active run maps do not need a standalone level entry.
	var old_instance := battle.get_instance_id()
	battle.dev_mode_panel.play_button.pressed.emit()
	await frames()
	battle = manager.current_battle
	check(battle != null and battle.get_instance_id() != old_instance, "%s Restart & Play replaces the battle" % label)
	if battle == null:
		return
	actor = _find(battle, actor_id)
	enemy = _find(battle, enemy_id)
	check(battle.run_encounter == encounter and battle.run_node_id == node_id and run.battle_open, "replacement retains encounter and run node")
	check(battle.template_setup_input == template_setup and battle.capture_save_payload(true).setup.units == expected_setup, "developer setup remains authoritative without regeneration")
	check(actor.get_abilities().has(load("res://resources/abilities/multiple_arrows.tres")), "Archer level-three edit survives run restart")
	check(actor.current_health == expected_health and actor.permanent_defeat, "restart retains party health and permanent defeat")
	check(actor.get_active_statuses().is_empty() and actor.ability_available and is_equal_approx(actor.remaining_movement, actor.get_movement_range()), "restart resets statuses and current turn actions")
	check(battle.turn_manager.round_number == 1 and battle.general_inventory.capture_state() == expected_inventory, "restart resets round but preserves inventory")
	check(actor.get_equipped_items().has(load("res://resources/items/ranger_armor.tres")), "runtime equipment survives alongside the inventory")
	check(enemy.current_health == enemy_max and enemy.constitution_override == enemy_constitution and enemy.strength_override == 27, "enemy health resets without applying elite or boss scaling again")
	check(FileAccess.get_file_as_string(run.save_path) == checkpoint_text, "developer restart leaves encounter entry checkpoint unchanged")

	# A scenario snapshot must win over the original run-entry HP and inventory.
	battle.dev_button.pressed.emit()
	actor.apply_damage(2)
	enemy.apply_damage(4)
	actor.apply_status(load("res://resources/statuses/slow.tres"))
	actor.spend_ability_action()
	battle.turn_manager.round_number = 3
	var snapshot := battle.capture_save_payload(false)
	var saved := ScenarioSaveStore.save_new(snapshot, DIRECTORY + "/scenarios")
	check(saved.ok, "exact run scenario saves")
	var actor_health := actor.current_health
	var enemy_health := enemy.current_health
	actor.apply_damage(2)
	battle.general_inventory.add_item(inventory_item)
	var loaded := ScenarioSaveStore.load_save(saved.path, DIRECTORY + "/scenarios")
	battle.dev_mode_panel.load_payload_requested.emit(loaded.payload)
	await frames()
	battle = manager.current_battle
	actor = _find(battle, actor_id)
	enemy = _find(battle, enemy_id)
	check(actor.current_health == actor_health and enemy.current_health == enemy_health, "exact scenario restores captured health")
	check(not actor.ability_available and actor.get_active_statuses().size() == 1 and battle.turn_manager.round_number == 3, "exact scenario restores spent action, status and round")
	check(battle.general_inventory.capture_state() == expected_inventory and actor.permanent_defeat, "exact scenario restores inventory and run defeat rules")

	# An invalid load leaves the running encounter and checkpoint intact.
	battle.dev_button.pressed.emit()
	var broken := snapshot.duplicate(true)
	broken.map_definition = "res://missing_dev_run_map.tres"
	check(not manager.reload_battle_from_payload(broken, battle), "invalid run scenario load is rejected")
	check(manager.current_battle == battle and battle._dev_open and paused, "failed reload keeps original run and drawer usable")
	battle.dev_mode_panel.play_button.pressed.emit()

	if label == "spawn_template_normal":
		await _test_ai_checkpoint(battle, actor_id, enemy_id, node_id)
		battle = manager.current_battle
		actor = _find(battle, actor_id)
		enemy = _find(battle, enemy_id)
	if label == "goblin_skirmish_elite":
		# A dead member must remain dead through a fresh rebuild.
		var fallen: TacticalCharacter
		for character in battle._characters:
			if character.is_friendly() and character != actor:
				fallen = character
		fallen.apply_damage(fallen.current_health)
		var fallen_id := fallen.scenario_unit_id
		battle.dev_button.pressed.emit()
		battle._on_dev_setup_changed()
		battle.dev_mode_panel.play_button.pressed.emit()
		await frames()
		battle = manager.current_battle
		fallen = _find(battle, fallen_id)
		fallen.heal(1000)
		check(fallen.current_health == 0 and fallen.permanent_defeat, "fresh developer restart cannot revive a defeated party member")
		actor = _find(battle, actor_id)

	check(FileAccess.get_file_as_string(run.save_path) == checkpoint_text, "developer loads and checkpoints do not rewrite entry state")
	var expected_party_health := actor.current_health
	for character in battle._characters:
		if not character.is_friendly():
			character.apply_damage(100000)
	await frames(5)
	check(manager.current_battle == null and manager.run_map_screen.visible, "reloaded victory returns to run map")
	check(bool(run.state.pending.get("resolved", false)) and run.state.gold == before_gold + gold_reward, "run victory records the current room and pays its reward once")
	check(run.state.party[0].health == expected_party_health and run.state.party[0].setup.class_levels[0].level == 3, "party health and edited class level carry to run results")
	check(not run.finish_battle(node_id, true, [], []) and run.state.gold == before_gold + gold_reward, "duplicate result cannot reward the room again")
	check(run.save_store.load_run().pending.resolved, "reloaded battle result persists to disk")
	check(run.complete_room(), "run can acknowledge the reloaded encounter and advance")


func _test_ai_checkpoint(battle: TacticalBattle, actor_id: String, enemy_id: String, node_id: int) -> void:
	var enemy := _find(battle, enemy_id)
	var actor := _find(battle, actor_id)
	battle.turn_manager.current_unit = enemy
	battle.turn_manager.current_index = battle.turn_manager.turn_order.find(enemy)
	battle._set_movement_locked(true)
	var plan := EnemyTurnPlan.new()
	plan.sequence = EnemyTurnPlan.Sequence.HOLD
	plan.end_cell = enemy.grid_cell
	battle._update_ai_debug(enemy, plan)
	var health := enemy.current_health
	var inventory := battle.general_inventory.capture_state()
	check(battle.dev_button.visible and battle._ai_debug_checkpoints.size() == 1, "enemy turn keeps Dev and captures AI checkpoints during runs")
	enemy.apply_damage(3)
	battle.turn_manager.current_unit = actor
	battle.turn_manager.current_index = battle.turn_manager.turn_order.find(actor)
	battle._set_movement_locked(false)
	battle.dev_button.pressed.emit()
	battle.dev_mode_panel.ai_history_restore_requested.emit(0)
	await frames(5)
	var restored := manager.current_battle
	check(restored.run_node_id == node_id and restored.run_encounter != null and paused and restored._dev_open, "AI rewind keeps the run and reopens the paused drawer")
	check(_find(restored, enemy_id).current_health == health and restored.general_inventory.capture_state() == inventory, "AI rewind restores run battle HP and inventory")
	check(restored.turn_manager.current_unit == _find(restored, enemy_id) and restored._restored_ai_turn_pending, "AI rewind restores the enemy action boundary")
	# Return this fixture to the friendly boundary without launching asynchronous AI.
	restored._restored_ai_turn_pending = false
	restored.turn_manager.current_unit = _find(restored, actor_id)
	restored.turn_manager.current_index = restored.turn_manager.turn_order.find(restored.turn_manager.current_unit)
	restored._set_movement_locked(false)
	restored.dev_mode_panel.play_button.pressed.emit()


func _test_exit_checkpoint() -> void:
	if not await _start("goblin_skirmish_normal"):
		return
	var battle := manager.current_battle
	var actor := _friendly(battle)
	var original_health := actor.current_health
	actor.apply_damage(5)
	battle.dev_button.pressed.emit()
	battle.dev_mode_panel.select_unit(actor)
	battle.dev_mode_panel._set_class_level(3, load("res://resources/classes/archer.tres"))
	battle.dev_mode_panel.play_button.pressed.emit()
	await frames()
	manager.return_to_level_select()
	await frames()
	manager.continue_run()
	await frames()
	actor = _friendly(manager.current_battle)
	check(actor.current_health == original_health and not actor.get_abilities().has(load("res://resources/abilities/multiple_arrows.tres")), "Save & Exit / Continue still restores committed entry health and classes")
	check(manager.current_battle.dev_button.visible, "Dev remains visible after Continue Run")


func _test_deleted_party_member() -> void:
	if not await _start("goblin_skirmish_normal"):
		return
	var battle := manager.current_battle
	var removed_id := run.state.party[1].id
	battle.dev_button.pressed.emit()
	battle.dev_mode_panel.select_unit(_find(battle, removed_id))
	battle._on_dev_delete_selected()
	battle.dev_mode_panel.play_button.pressed.emit()
	await frames()
	battle = manager.current_battle
	check(_find(battle, removed_id) == null, "deleted run member stays deleted after restart")
	for character in battle._characters:
		if not character.is_friendly():
			character.apply_damage(100000)
	await frames(5)
	check(run.state.party[1].lost and manager.current_battle == null, "deleted member produces a complete loss result without blocking run progression")


func _test_completed_snapshot_reload() -> void:
	if not await _start("goblin_skirmish_normal"):
		return
	var battle := manager.current_battle
	var valid_path := run.save_store.path
	var expected_gold := run.state.gold + int(run.state.pending.gold)
	run.save_store.path = "res://project.godot/impossible_dev_result.json"
	for character in battle._characters:
		if not character.is_friendly():
			character.apply_damage(100000)
	await frames(5)
	check(manager.current_battle == battle and not manager._pending_run_result.is_empty(), "failed result save retains the completed run battle")
	check(battle.dev_button.visible, "Dev remains visible after a failed result save")
	battle.dev_button.pressed.emit()
	var snapshot := battle.capture_save_payload(false)
	check(battle._dev_open and snapshot.runtime.combat_over, "completed run snapshot can be inspected and saved")
	run.save_store.path = valid_path
	battle.dev_mode_panel.load_payload_requested.emit(snapshot)
	await frames(5)
	check(manager.current_battle == null and run.state.pending.resolved and run.state.gold == expected_gold, "restoring a completed snapshot delivers its result once after saving recovers")
	check(manager._pending_run_result.is_empty(), "completed restoration clears the obsolete retry result")


func _test_temporary_allies() -> void:
	if not await _start("goblin_skirmish_normal"):
		return
	var battle := manager.current_battle
	battle.dev_button.pressed.emit()
	for member in run.state.party:
		battle.dev_mode_panel.select_unit(_find(battle, member.id))
		battle._on_dev_delete_selected()
	battle._add_dev_unit(load("res://scenes/friendlies/friend_a.tscn"), Vector2i.ZERO)
	check(battle.dev_mode_panel.get_selected_unit().permanent_defeat, "developer-added run allies use permanent defeat")
	battle.dev_mode_panel.play_button.pressed.emit()
	await frames()
	battle = manager.current_battle
	for character in battle._characters:
		if not character.is_friendly():
			character.apply_damage(100000)
	await frames(5)
	check(manager.current_battle == null and run.state.status == RunState.Status.LOST, "a temporary helper cannot continue a run whose original members were all deleted")


func _capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await frames()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(DIRECTORY + "/" + name + ".png") == OK, "capture %s" % name)
