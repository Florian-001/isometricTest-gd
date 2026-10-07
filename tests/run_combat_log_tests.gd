extends SceneTree

var checks := 0
var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_manual_actions()
	await _test_reactions_and_interruptions()
	await _test_terrain_and_knockback()
	await _test_automated_actions_and_transitions()
	await _test_manual_checkpoint_navigation()
	await _test_defeated_transition_restore()
	await _test_layout()
	paused = false
	print("COMBAT_LOG_TESTS_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _battle() -> TacticalBattle:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres") as BattleMapDefinition
	root.add_child(battle)
	for unit in battle._characters:
		unit.movement_animation_speed = 10000.0
	return battle


func _enemy(battle: TacticalBattle) -> TacticalCharacter:
	for unit in battle._characters:
		if not unit.is_friendly():
			return unit
	return null


func _damage_ability() -> AbilityDefinition:
	var ability := AbilityDefinition.new()
	ability.display_name = "Log test volley"
	ability.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	ability.innate_damage = 3
	ability.scaling_amount = 0
	ability.range = 30
	ability.requires_weapon = false
	ability.cooldown_turns = 2
	return ability


func _state(checkpoint: Dictionary, unit: TacticalCharacter) -> Dictionary:
	for state in checkpoint.runtime.units:
		if state.id == unit.scenario_unit_id:
			return state
	return {}


func _remove(battle: TacticalBattle) -> void:
	paused = false
	battle.shutdown_battle()
	battle.queue_free()
	await process_frame


func _test_manual_actions() -> void:
	var battle := _battle()
	var actor := battle.turn_manager.current_unit
	var enemy := _enemy(battle)
	enemy._set_runtime_grid_cell_immediate(Vector2i(8, 8))
	var original_cell := actor.grid_cell
	var original_movement := actor.remaining_movement
	var empty_path: Array[Vector2i] = []
	await battle._begin_friendly_move(empty_path)
	_check(battle._ai_debug_history.is_empty(), "empty movement commands do not create checkpoints")
	var path: Array[Vector2i] = [original_cell, original_cell + Vector2i.LEFT]
	await battle._begin_friendly_move(path)
	_check(battle._ai_debug_history.size() == 1, "one manual move creates one entry")
	_check(battle._combat_log_entries[0].control == "Friendly · Manual", "manual friendly control is identified")
	_check(battle._combat_log_entries[0].paths[actor.scenario_unit_id] == path, "the actual traversed path is recorded")
	var saved := _state(battle._ai_debug_checkpoints[0], actor)
	_check(saved.cell == [original_cell.x, original_cell.y] and saved.remaining_movement == original_movement, "move checkpoint precedes movement spending")
	_check(battle._ai_debug_history[0].contains("Movement") and battle._ai_debug_history[0].contains("Actual path"), "movement costs and paths appear in copied details")

	var ability := _damage_ability()
	ability.hit_count = 3
	ability.hit_targeting = AbilityDefinition.HitTargeting.SELECT_PER_HIT
	var apply_buff := ApplyStatusEffectDefinition.new()
	apply_buff.status_effect = load("res://resources/statuses/strength_up.tres") as StatusEffectDefinition
	ability.effects = [apply_buff]
	actor.set_dev_ability_loadout([ability])
	enemy.set_dev_stat_override(UnitStat.Type.CONSTITUTION, 100)
	enemy.heal(enemy.get_max_health())
	enemy.equip_item(load("res://resources/items/armor/leather_armor.tres") as ItemDefinition)
	ability.innate_damage = enemy.current_armor + 3
	var hp_before := enemy.current_health
	var armor_before := enemy.current_armor
	var ap_before := actor.action_points
	var targets: Array[TacticalCharacter] = [enemy, enemy, enemy]
	_check(await battle._ability_executor.execute_targets(actor, ability, targets, battle._characters, battle.grid, battle._ability_targeting, battle._get_wall_cells()), "manual multi-hit cast executes")
	_check(battle._ai_debug_history.size() == 2, "a complete multi-hit cast creates one checkpoint")
	var entry := battle._combat_log_entries[1]
	var hits := 0
	var hp_delta := 0.0
	var armor_delta := 0.0
	for event in entry.events:
		if event.text.begins_with("Hit:"):
			hits += 1
		if event.get("unit_id", "") == enemy.scenario_unit_id:
			if event.kind == "health": hp_delta += event.amount
			if event.kind == "armor": armor_delta += event.amount
	_check(hits == 3, "each delivered hit is recorded inside the cast")
	_check(hp_delta == enemy.current_health - hp_before and armor_delta == enemy.current_armor - armor_before, "logged damage matches actual HP and armor losses")
	_check(entry.text.contains("Strength") and entry.text.contains("×3"), "status applications preserve stack counts")
	_check(entry.text.contains("ordered targets") and entry.text.contains("Cooldowns"), "ordered targets and cooldown changes are readable")
	saved = _state(battle._ai_debug_checkpoints[1], actor)
	_check(saved.action_points == ap_before and saved.ability_cooldowns.is_empty(), "cast checkpoint precedes AP and cooldown payment")
	_check(actor.action_points == ap_before - 1, "three hits pay AP once")

	var heal := AbilityDefinition.new()
	heal.display_name = "Log test heal"
	heal.effect = AbilityDefinition.PrimaryEffect.HEAL
	heal.effect_amount = 5
	heal.scaling_amount = 0
	heal.target_flags = AbilityDefinition.TargetFlags.SELF
	actor.set_dev_ability_loadout([heal])
	actor.current_health -= 10
	var wounded_health := actor.current_health
	_check(await battle._ability_executor.execute(actor, heal, actor.grid_cell, battle._characters, battle.grid, battle._ability_targeting), "manual healing executes")
	_check(actor.current_health == wounded_health + 5 and battle._ai_debug_history[-1].contains("+5.00"), "actual healing is recorded")
	var count := battle._ai_debug_history.size()
	actor.reset_combat_abilities()
	actor.reset_action_points()
	battle._on_ability_selected(heal)
	battle._cancel_ability_targeting()
	_check(battle._ai_debug_history.size() == count, "canceled targeting creates no checkpoint")
	_check(not await battle._ability_executor.execute(actor, heal, Vector2i(-1, -1), battle._characters, battle.grid, battle._ability_targeting), "invalid commands are rejected")
	_check(battle._ai_debug_history.size() == count, "rejected commands create no committed action")
	await _remove(battle)


func _test_reactions_and_interruptions() -> void:
	var battle := _battle()
	var actor := battle.turn_manager.current_unit
	var enemy := _enemy(battle)
	enemy._set_runtime_grid_cell_immediate(actor.grid_cell + Vector2i.RIGHT)
	enemy.set_dev_stat_override(UnitStat.Type.CONSTITUTION, 100)
	enemy.heal(enemy.get_max_health())
	enemy.equip_item(load("res://resources/items/weapons/goblin_club.tres") as ItemDefinition)
	enemy.set_dev_passive_loadout([load("res://resources/passives/counter.tres") as PassiveAbilityDefinition])
	var ability := _damage_ability()
	ability.hit_count = 3
	actor.set_dev_ability_loadout([ability])
	var ap_before := enemy.action_points
	_check(await battle._ability_executor.execute(actor, ability, enemy.grid_cell, battle._characters, battle.grid, battle._ability_targeting), "cast with counter executes")
	_check(battle._ai_debug_history.size() == 1 and battle._ai_debug_history[0].contains("Counter attack:"), "nested counter belongs to the complete cast entry")
	_check(enemy.action_points == ap_before, "counter logging does not charge AP")
	_check(battle._ai_debug_history[0].count("Counter attack:") == 1, "multi-hit cast records one eligible counter")
	await _remove(battle)

	battle = _battle()
	actor = battle.turn_manager.current_unit
	enemy = _enemy(battle)
	enemy._set_runtime_grid_cell_immediate(actor.grid_cell + Vector2i.RIGHT)
	enemy.equip_item(load("res://resources/items/weapons/goblin_club.tres") as ItemDefinition)
	var lethal := (load("res://resources/abilities/strike.tres") as AbilityDefinition).duplicate(true)
	lethal.innate_damage = 10000
	lethal.melee_lunge_duration = 0.02
	lethal.melee_return_duration = 0.02
	lethal.melee_slash_duration = 0.02
	enemy.set_dev_ability_loadout([lethal])
	enemy.reset_opportunity_reaction()
	var starting_cell := actor.grid_cell
	var path: Array[Vector2i] = [starting_cell, starting_cell + Vector2i.LEFT]
	await battle._begin_friendly_move(path)
	_check(actor.current_health == 0 and actor.grid_cell == starting_cell, "lethal opportunity attack interrupts movement")
	_check(battle._combat_log_entries[0].kind == "Move" and not battle._combat_log_entries[0].succeeded, "interrupted move keeps its pre-action checkpoint")
	_check(battle._ai_debug_history[0].contains("Opportunity attack:") and battle._ai_debug_history[0].contains("Defeated"), "reaction and defeat are recorded inside the interrupted move")
	_check(not enemy.opportunity_reaction_available, "recording preserves spent reaction availability")
	await _remove(battle)


func _test_automated_actions_and_transitions() -> void:
	var battle := _battle()
	var actor := battle.turn_manager.current_unit
	var enemy := _enemy(battle)
	enemy._set_runtime_grid_cell_immediate(Vector2i(5, 9))
	var ability := _damage_ability()
	actor.set_dev_ability_loadout([ability])
	battle._ability_executor.ability_started.connect(func(_actor, _ability, _cell): battle.set_auto_battle_enabled(false), CONNECT_ONE_SHOT)
	battle.set_auto_battle_enabled(true)
	await _until(func(): return not battle.auto_battle_enabled and not battle._movement_locked)
	_check(battle._ai_debug_history.size() == 1 and battle._combat_log_entries[0].control == "Friendly · Auto Battle", "automated friendly cast shares the combat timeline")
	_check(battle._ai_debug_history[0].contains("Top candidates:") and battle._ai_debug_history[0].contains("Search:"), "automated actions retain planner diagnostics")

	var burning := load("res://resources/statuses/burning.tres") as StatusEffectDefinition
	enemy.apply_status(burning, null, actor)
	enemy.action_points = 0
	enemy.spend_movement(enemy.remaining_movement)
	actor.spend_ability_action(ability)
	battle.turn_manager.turn_order = [actor, enemy]
	battle.turn_manager.current_unit = actor
	battle.turn_manager.current_index = 0
	var count := battle._ai_debug_history.size()
	battle.turn_manager.end_current_turn()
	_check(battle._ai_debug_history.size() == count + 1, "turn advancement produces one transition entry")
	_check(battle._ai_debug_history[-1].contains("Turn start:") and battle._ai_debug_history[-1].contains("AP") and battle._ai_debug_history[-1].contains("HP"), "transition includes status ticks and resource resets")
	_check(_state(battle._ai_debug_checkpoints[-1], enemy).action_points == 0, "transition checkpoint precedes the next unit reset")

	# Exercise the enemy runner with a complete action, then pause at its boundary.
	var enemy_ability := ability.duplicate(true)
	enemy_ability.cooldown_turns = 0
	enemy.set_dev_ability_loadout([enemy_ability])
	enemy.remove_negative_statuses()
	enemy.reset_combat_abilities()
	enemy.reset_action_points()
	_check(battle._ability_executor.can_execute(enemy, enemy_ability, actor.grid_cell, battle._characters, battle.grid, battle._ability_targeting, battle._get_wall_cells()), "enemy fixture has a legal cast")
	var plan := battle._enemy_ai_planner.choose_plan(enemy, battle._characters, battle._pathfinder, battle._ability_targeting, battle._get_wall_cells(), battle.terrain.get_definitions(), battle.turn_manager.get_rotating_order())
	_check(plan.ability != null, "enemy fixture selects a cast: %s" % plan.get_debug_summary())
	battle._ability_executor.ability_started.connect(func(_actor, _ability, _cell): battle._on_dev_button_pressed(), CONNECT_ONE_SHOT)
	await _until(func(): return battle._dev_open)
	_check(battle._ai_debug_history[-1].contains("Enemy · AI") and battle._ai_debug_history[-1].contains("AI decision:"), "enemy action contains outcome and diagnostics")
	_check(battle._combat_log_recorder.active.is_empty() and paused, "Dev opens after the entire action finishes")
	_check(battle._ai_debug_history.size() == battle._ai_debug_checkpoints.size() and battle._ai_debug_history.size() == battle._combat_log_entries.size(), "structured entries and checkpoints remain aligned")
	await _remove(battle)


func _test_terrain_and_knockback() -> void:
	var battle := _battle()
	var actor := battle.turn_manager.current_unit
	var enemy := _enemy(battle)
	enemy._set_runtime_grid_cell_immediate(Vector2i(8, 8))
	var path: Array[Vector2i] = [actor.grid_cell, actor.grid_cell + Vector2i.LEFT]
	battle.terrain.set_tile(path[-1], load("res://resources/tiles/fire.tres") as TileDefinition)
	battle.terrain.refresh()
	await battle._begin_friendly_move(path)
	_check(battle._ai_debug_history[0].contains("Terrain: Fire") and battle._ai_debug_history[0].contains("Burning"), "terrain entry records its source and resulting status")

	enemy._set_runtime_grid_cell_immediate(actor.grid_cell + Vector2i.RIGHT)
	var ability := _damage_ability()
	var push := KnockbackEffectDefinition.new()
	push.distance = 2
	ability.effects = [push]
	actor.set_dev_ability_loadout([ability])
	var enemy_cell := enemy.grid_cell
	_check(await battle._ability_executor.execute(actor, ability, enemy.grid_cell, battle._characters, battle.grid, battle._ability_targeting, battle._get_wall_cells()), "knockback cast executes")
	var entry := battle._combat_log_entries[-1]
	_check(entry.text.contains("Knockback:") and enemy.grid_cell != enemy_cell, "knockback is identified and actual displacement is recorded")
	_check(entry.paths[enemy.scenario_unit_id][0] == enemy_cell and entry.paths[enemy.scenario_unit_id][-1] == enemy.grid_cell, "forced movement tracks its actual path within the cast")
	_check(battle._ai_debug_history.size() == 2, "forced movement creates no extra action checkpoint")
	await _remove(battle)


func _test_manual_checkpoint_navigation() -> void:
	var manager := (load("res://main.tscn") as PackedScene).instantiate() as MapManager
	root.add_child(manager)
	_check(manager.load_level(load("res://resources/maps/goblin_skirmish.tres") as BattleMapDefinition), "manual navigation fixture loads")
	var battle := manager.current_battle
	battle.ai_debug_history_limit = 3
	var actor := battle.turn_manager.current_unit
	var actor_id := actor.scenario_unit_id
	var original_cell := actor.grid_cell
	var original_movement := actor.remaining_movement
	var enemy := _enemy(battle)
	enemy.set_dev_stat_override(UnitStat.Type.CONSTITUTION, 100)
	enemy.heal(enemy.get_max_health())
	enemy._set_runtime_grid_cell_immediate(original_cell + Vector2i.RIGHT)
	var enemy_id := enemy.scenario_unit_id
	var initial_enemy_health := enemy.current_health
	var first: Array[Vector2i] = [original_cell, original_cell + Vector2i.LEFT]
	var second: Array[Vector2i] = [first[-1], first[-1] + Vector2i.UP]
	await battle._begin_friendly_move(first)
	await battle._begin_friendly_move(second)
	var volley := load("res://resources/abilities/multiple_arrows.tres") as AbilityDefinition
	actor.set_dev_ability_loadout([volley])
	battle._on_ability_selected(volley)
	battle._selected_hit_targets.assign([enemy, enemy, enemy])
	await battle._begin_selected_targets_cast()
	_check(battle._ai_debug_history.size() == 3, "two manual moves and one cast produce three action boundaries")
	var live_health := enemy.current_health
	var live_ap := actor.action_points
	var live_cooldown := actor.get_ability_cooldown(volley)
	_check(live_health < initial_enemy_health, "navigation fixture has a real damage outcome")
	battle._open_dev_mode(DevModePanel.AI_LOG_TAB)
	battle.dev_mode_panel.history_back_button.pressed.emit()
	await process_frame
	await process_frame
	battle = manager.current_battle
	actor = _find_unit(battle, actor_id)
	enemy = _find_unit(battle, enemy_id)
	_check(actor.grid_cell == second[-1] and actor.action_points == TacticalCharacter.AP_PER_TURN, "Back restores the cast origin and pre-cast AP")
	_check(enemy.current_health == initial_enemy_health and actor.get_ability_cooldown(volley) == 0, "Back restores pre-hit health and cooldown")
	_check(battle._ai_debug_history.size() == 3 and battle._combat_log_recorder.active.is_empty(), "restoration creates no duplicate actions")
	battle.dev_mode_panel.history_forward_button.pressed.emit()
	await process_frame
	await process_frame
	battle = manager.current_battle
	actor = _find_unit(battle, actor_id)
	enemy = _find_unit(battle, enemy_id)
	_check(enemy.current_health == live_health and actor.action_points == live_ap and actor.get_ability_cooldown(volley) == live_cooldown, "Forward to live restores completed cast results")
	_check(paused and battle.ai_debug_history_limit == 3, "reload retains the configured history bound and pause")
	battle.dev_mode_panel.ai_log_entries.get_child(2).pressed.emit()
	await process_frame
	await process_frame
	battle = manager.current_battle
	actor = _find_unit(battle, actor_id)
	_check(actor.grid_cell == original_cell and actor.remaining_movement == original_movement, "oldest manual checkpoint restores the original position and movement")
	_check(battle.dev_mode_panel.history_back_button.disabled, "Back is disabled at the oldest manual action")
	battle.dev_mode_panel.play_button.pressed.emit()
	_check(battle._ai_debug_history.is_empty() and not paused, "Resume before the first action discards every old outcome")
	var changed_path: Array[Vector2i] = [original_cell, original_cell + Vector2i.UP]
	await battle._begin_friendly_move(changed_path)
	_check(battle._ai_debug_history.size() == 1 and battle._combat_log_entries[0].paths[actor_id] == changed_path, "changed manual action replaces the abandoned timeline")
	battle.shutdown_battle()
	manager.queue_free()
	await process_frame


func _find_unit(battle: TacticalBattle, unit_id: String) -> TacticalCharacter:
	for unit in battle._characters:
		if unit.scenario_unit_id == unit_id:
			return unit
	return null


func _test_defeated_transition_restore() -> void:
	var manager := (load("res://main.tscn") as PackedScene).instantiate() as MapManager
	root.add_child(manager)
	manager.load_level(load("res://resources/maps/goblin_skirmish.tres") as BattleMapDefinition)
	var battle := manager.current_battle
	var actor := battle.turn_manager.current_unit
	var next_friendly: TacticalCharacter
	for unit in battle._characters:
		if unit.is_friendly() and unit != actor:
			next_friendly = unit
	_check(next_friendly != null, "defeated transition fixture has a surviving friendly")
	actor.current_health = 0
	battle.turn_manager.turn_order = [actor, next_friendly]
	battle.turn_manager.current_index = 0
	battle.turn_manager.end_current_turn()
	_check(battle._ai_debug_checkpoints.size() == 1, "automatic defeated-unit transition is restorable")
	battle._open_dev_mode(DevModePanel.AI_LOG_TAB)
	battle.dev_mode_panel.history_back_button.pressed.emit()
	await process_frame
	await process_frame
	battle = manager.current_battle
	_check(battle.turn_manager.current_unit.current_health == 0 and paused, "rewinding can inspect the defeated unit before initiative advances")
	battle.dev_mode_panel.play_button.pressed.emit()
	_check(battle.turn_manager.current_unit.current_health > 0 and not battle._movement_locked, "Resume advances a defeated checkpoint to the surviving unit")
	_check(battle._ai_debug_history.size() == 1, "the replayed transition replaces its old outcome")
	battle.shutdown_battle()
	manager.queue_free()
	await process_frame


func _test_layout() -> void:
	for resolution in [Vector2i(1280, 720), Vector2i(800, 600)]:
		root.size = resolution
		var battle := _battle()
		battle._open_dev_mode(DevModePanel.AI_LOG_TAB)
		var entries: Array[String] = []
		for index in range(30):
			entries.append("Round %d · Friendly Archer · Friendly · Manual\nCompleted: Multiple Arrows\nOutcomes:\nTarget: HP 20 → 12 (-8.00)\nTarget: Armor 4 → 0 (-4.00)\nArcher: AP 2 → 0 (-2.00)\nArcher: Cooldowns none → Multiple Arrows: 2\nActual path: (4, 9) → (3, 9)\nHit 1: Archer → Goblin\nHit 2: Archer → Goblin\nHit 3: Archer → Goblin\nCounter attack: Goblin → Archer\nAI decision:\nSearch: 20 candidates\nTop candidates:\n1. Shoot\n2. Hold\n3. Move\nFull diagnostic details remain scrollable." % (index + 1))
		battle.dev_mode_panel.set_ai_history(entries, 14)
		await process_frame
		await process_frame
		var panel := battle.dev_mode_panel
		_check((panel.ai_log_entries.get_child(0) as Button).text.ends_with("Multiple Arrows"), "compact rows keep the action name visible")
		var bounds := panel.drawer.get_global_rect()
		for control in [panel.history_back_button, panel.history_forward_button, panel.copy_ai_log_button, panel.history_details, panel.ai_log_scroll]:
			_check(bounds.encloses(control.get_global_rect()), "combat log controls fit the drawer at %s" % resolution)
		_check(panel.history_details.size.y >= 150 and panel.ai_log_scroll.size.y > 50, "details and action list both have usable height")
		if DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().has("--capture"):
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.godot/combat_log_validation/combat_%dx%d.png" % [resolution.x, resolution.y]))
		await _remove(battle)


func _until(predicate: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(predicate.call(), "asynchronous action reaches its stable boundary")
