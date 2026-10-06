extends SceneTree

const DIRECTORY := "res://.godot/auto_battle_validation"
var checks := 0
var failures: Array[String] = []
var arena: Node2D
var grid: IsometricGrid
var targeting: AbilityTargeting
var executor: AbilityExecutor
var units: Array[TacticalCharacter] = []
var ability: AbilityDefinition


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _until(predicate: Callable, message: String) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(predicate.call(), message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	for friendly in [true, false]:
		await _test_per_hit(friendly)
	await _test_per_hit_constraints()
	await _test_per_hit_effects()
	await _test_per_hit_healing()
	await _test_deferred_handback()
	await _test_toggle_during_cast()
	await _test_toggle_during_move()
	await _test_defeated_handback()
	await _test_takeover_manual_actions()
	await _test_enemy_turn_toggle()
	await _test_pause_and_dev()
	await _test_checkpoint_and_restart()
	await _test_automatic_completion()
	await _test_layout()
	paused = false
	print("AUTO_BATTLE_TESTS_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _make_arena() -> void:
	units.clear()
	arena = Node2D.new()
	root.add_child(arena)
	grid = IsometricGrid.new()
	grid.grid_size = Vector2i(12, 12)
	arena.add_child(grid)
	targeting = AbilityTargeting.new(grid.grid_size)
	executor = AbilityExecutor.new()
	arena.add_child(executor)
	ability = (load("res://resources/abilities/multiple_arrows.tres") as AbilityDefinition).duplicate(true)
	ability.projectile_speed = 10000.0


func _unit(friendly: bool, cell: Vector2i, health := -1) -> TacticalCharacter:
	var unit := TacticalCharacter.new()
	unit.name = "AutoTest%d" % units.size()
	unit.definition = CharacterDefinition.new()
	unit.definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	unit.definition.constitution = 50
	unit.definition.dexterity = 10
	unit.movement_range_override = 0
	unit.starting_grid_cell = cell
	unit.override_template_abilities = true
	unit.ability_overrides = [ability]
	unit.use_complete_equipment_override = true
	var bow := (load("res://resources/items/weapons/goblin_bow.tres") as ItemDefinition).duplicate(true)
	bow.weapon_damage = 10
	unit.complete_equipment_overrides = [bow]
	arena.add_child(unit)
	unit.initialize(grid)
	unit.reset_action_points()
	unit.reset_movement()
	unit.spend_movement(unit.remaining_movement)
	if health >= 0:
		unit.apply_damage(unit.current_health - health)
	units.append(unit)
	return unit


func _choose(actor: TacticalCharacter, walls: Dictionary = {}) -> EnemyTurnPlan:
	return EnemyAIPlanner.new().choose_plan(actor, units, GridPathfinder.new(grid.grid_size), targeting, walls, {}, units)


func _verify_forecast(actor: TacticalCharacter, plan: EnemyTurnPlan) -> void:
	var planner := EnemyAIPlanner.new()
	var forecast := planner._simulate_plan(actor, plan,
		AIBoardSnapshot.from_battle(units, grid.grid_size), targeting, EnemyAIProfile.new(), GridPathfinder.new(grid.grid_size))
	check(await executor.execute_targets(actor, plan.ability, plan.selected_targets, units, grid, targeting), "complete planned selection executes")
	for unit in units:
		check(unit.current_health == forecast.get_health(unit), "per-hit forecast matches health for %s: actual %d, expected %d; %s" % [unit.name, unit.current_health, forecast.get_health(unit), plan.get_debug_summary()])
		check(unit.current_armor == forecast.get_armor(unit), "per-hit forecast matches armor for " + str(unit.name))
		check(unit.grid_cell == forecast.get_cell(unit), "per-hit forecast matches cell for " + str(unit.name))
	check(actor.action_points == forecast.get_action_points(actor), "forecast pays AP once for the whole cast")
	check(actor.get_ability_cooldown(plan.ability) == forecast.get_ability_cooldown(actor, plan.ability), "forecast and runtime agree on cooldown")


func _test_per_hit(friendly: bool) -> void:
	_make_arena()
	var actor := _unit(friendly, Vector2i(1, 1))
	var first := _unit(not friendly, Vector2i(3, 1), 16)
	var second := _unit(not friendly, Vector2i(4, 1), 32)
	var plan := _choose(actor)
	check(plan.ability == ability, "both factions choose Multiple Arrows")
	check(plan.selected_targets == [first, second, second], "greedy hits distribute damage after an early kill")
	check(plan.get_debug_summary().contains("hits ["), "AI logs describe the complete target list")
	await _verify_forecast(actor, plan)
	arena.free()
	await process_frame


func _test_per_hit_constraints() -> void:
	_make_arena()
	var actor := _unit(true, Vector2i(1, 1))
	var first := _unit(false, Vector2i(3, 1))
	var second := _unit(false, Vector2i(4, 1))
	var ally := _unit(true, Vector2i(2, 2))
	ability.allow_repeated_targets = false
	check(_choose(actor).ability == null, "too few distinct targets never produce an incomplete cast")
	var third := _unit(false, Vector2i(4, 2))
	var plan := _choose(actor)
	check(plan.selected_targets.size() == 3 and plan.selected_targets.has(first) and plan.selected_targets.has(second) and plan.selected_targets.has(third), "distinct casts fill every slot with a different opponent")
	check(not plan.selected_targets.has(ally), "friendly damage targeting excludes allies")
	await _verify_forecast(actor, plan)
	ability.hit_count = 4
	var fourth := _unit(false, Vector2i(3, 2))
	actor.reset_combat_abilities()
	actor.reset_action_points()
	plan = _choose(actor)
	check(plan.selected_targets.size() == 4 and plan.selected_targets.has(fourth), "distinct selections can exceed the normal three-target candidate cutoff")
	ability.hit_count = 3
	actor.reset_combat_abilities()
	actor.reset_action_points()
	ability.allow_repeated_targets = true
	check(_choose(actor, {Vector2i(2, 1): true, Vector2i(2, 2): true}).ability == null, "walls block per-hit selections")
	var taunt := load("res://resources/statuses/taunted.tres") as StatusEffectDefinition
	actor.apply_status(taunt, ability, second)
	plan = _choose(actor)
	check(plan.selected_targets == [second, second, second], "every selected hit respects taunt")
	ability.allow_repeated_targets = false
	check(_choose(actor).ability == null, "taunt cannot bypass the distinct-target requirement")
	actor.remove_negative_statuses()
	ability.allow_repeated_targets = true
	actor.spend_ability_action(ability)
	actor.reset_action_points()
	check(_choose(actor).ability == null, "per-hit abilities respect their cooldown")
	actor.reset_combat_abilities()
	actor.spend_action_points(actor.action_points)
	check(_choose(actor).ability == null, "per-hit abilities require AP")
	actor.reset_action_points()
	ability.range = 0
	check(_choose(actor).ability == null, "per-hit abilities respect range")
	arena.free()
	await process_frame


func _test_per_hit_effects() -> void:
	_make_arena()
	var actor := _unit(true, Vector2i(1, 1))
	_unit(false, Vector2i(3, 1), 16)
	var survivor := _unit(false, Vector2i(4, 1))
	ability.status_effect = load("res://resources/statuses/burning.tres") as StatusEffectDefinition
	ability.on_kill_status = load("res://resources/statuses/dexterity_up.tres") as StatusEffectDefinition
	var plan := _choose(actor)
	await _verify_forecast(actor, plan)
	check(AIBoardSnapshot.from_battle(units, grid.grid_size).get_status_remaining(actor, &"dexterity_up") > 0 and AIBoardSnapshot.from_battle(units, grid.grid_size).get_status_remaining(survivor, &"burning") > 0, "ordered forecasts preserve on-kill and on-hit effects")
	arena.free()
	await process_frame
	_make_arena()
	actor = _unit(false, Vector2i(1, 1))
	var defender := _unit(true, Vector2i(2, 1))
	defender.override_template_passives = true
	defender.passive_overrides = [load("res://resources/passives/counter.tres") as PassiveAbilityDefinition]
	plan = _choose(actor)
	var counter_count := [0]
	executor.ability_started.connect(func(caster, _ability, _cell):
		if caster == defender: counter_count[0] += 1)
	await _verify_forecast(actor, plan)
	check(counter_count[0] == 1, "three selected hits trigger only one defender counter after the cast")
	arena.free()
	await process_frame
	_make_arena()
	actor = _unit(true, Vector2i(1, 1))
	defender = _unit(false, Vector2i(2, 1))
	ability.range = 2
	var push := KnockbackEffectDefinition.new()
	push.distance = 1
	ability.effects = [push]
	plan = _choose(actor)
	await _verify_forecast(actor, plan)
	check(defender.grid_cell == Vector2i(4, 1), "later selected hits skip a recipient pushed out of range")
	arena.free()
	await process_frame


func _test_per_hit_healing() -> void:
	_make_arena()
	ability.effect = AbilityDefinition.PrimaryEffect.HEAL
	ability.effect_amount = 10
	ability.scaling_amount = 0
	ability.requires_weapon = false
	ability.target_flags = AbilityDefinition.TargetFlags.FRIEND | AbilityDefinition.TargetFlags.SELF
	ability.delivery_type = AbilityDefinition.DeliveryType.CAST_ON_TARGET
	var actor := _unit(false, Vector2i(1, 1))
	var first := _unit(false, Vector2i(3, 1))
	var second := _unit(false, Vector2i(4, 1))
	first.apply_damage(30)
	second.apply_damage(20)
	var opponent := _unit(true, Vector2i(2, 2), 1)
	var plan := _choose(actor)
	check(plan.ability == ability and plan.selected_targets == [first, first, second], "per-hit support spreads healing using changing missing health")
	check(not plan.selected_targets.has(opponent), "support targeting excludes opponents")
	await _verify_forecast(actor, plan)
	arena.free()
	await process_frame


func _test_deferred_handback() -> void:
	var battle := _battle()
	var caster := battle.turn_manager.current_unit
	caster.set_dev_ability_loadout([])
	caster.spend_action_points(caster.action_points)
	caster.spend_movement(caster.remaining_movement)
	battle.set_auto_battle_enabled(true)
	battle.set_auto_battle_enabled(false)
	await process_frame
	await process_frame
	check(battle.turn_manager.current_unit == caster and not battle._movement_locked, "switching off before a deferred AI start preserves the current turn")
	check(caster.action_points == 0 and caster.remaining_movement == 0, "instant handback does not replenish spent resources")
	var ended := [0]
	battle.turn_manager.turn_ended.connect(func(unit):
		if unit == caster:
			ended[0] += 1
			battle.set_auto_battle_enabled(false))
	battle.set_auto_battle_enabled(true)
	await _until(func(): return ended[0] > 0, "automation advances a unit with no available actions")
	check(ended[0] == 1, "an instant AI turn advances exactly once")
	await _remove_battle(battle)


func _battle(shipped := false) -> TacticalBattle:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres") as BattleMapDefinition
	root.add_child(battle)
	for unit in battle._characters:
		unit.movement_animation_speed = 1000.0
	var caster := battle.turn_manager.current_unit
	ability = load("res://resources/abilities/multiple_arrows.tres") as AbilityDefinition
	if not shipped:
		ability = ability.duplicate(true)
		ability.projectile_speed = 10000.0
	caster.set_dev_ability_loadout([ability])
	var enemy := _enemy(battle)
	enemy._set_runtime_grid_cell_immediate(Vector2i(5, 9))
	return battle


func _enemy(battle: TacticalBattle) -> TacticalCharacter:
	for unit in battle._characters:
		if not unit.is_friendly():
			return unit
	return null


func _remove_battle(battle: TacticalBattle) -> void:
	paused = false
	battle.shutdown_battle()
	battle.queue_free()
	await process_frame


func _test_toggle_during_cast() -> void:
	var battle := _battle()
	var caster := battle.turn_manager.current_unit
	var casts := [0]
	battle._on_ability_selected(ability)
	battle._selected_hit_targets.assign([_enemy(battle), _enemy(battle), _enemy(battle)])
	battle._ability_executor.ability_started.connect(func(unit, _ability, _cell):
		if unit == caster:
			casts[0] += 1
			for enabled in [false, true, false, true, false]:
				battle.set_auto_battle_enabled(enabled))
	var movement := caster.remaining_movement
	battle.auto_battle_button.set_pressed(true)
	check(not battle.target_selection_panel.visible and battle._selected_hit_targets.is_empty(), "takeover discards pending manual targeting")
	check(battle.end_turn_button.disabled and battle._movement_locked, "takeover disables manual turn controls")
	battle._on_end_turn_pressed()
	check(battle.turn_manager.current_unit == caster, "Space cannot skip an AI-controlled turn")
	await _until(func(): return casts[0] > 0 and not battle._movement_locked, "switching off waits for the complete cast")
	check(casts[0] == 1 and caster.action_points == 1 and caster.remaining_movement == movement, "rapid toggles preserve one cast and remaining resources")
	check(battle.turn_manager.current_unit == caster and battle._selected_character == caster, "handback restores the same friendly turn")
	check(not battle.end_turn_button.disabled and not battle.auto_battle_button.button_pressed, "manual controls and toggle state refresh after handback")
	await _remove_battle(battle)


func _test_toggle_during_move() -> void:
	var battle := _battle()
	var caster := battle.turn_manager.current_unit
	ability.range = 1
	_enemy(battle)._set_runtime_grid_cell_immediate(Vector2i(9, 8))
	var casts := [0]
	var started := [false]
	caster.movement_started.connect(func(_unit):
		started[0] = true
		battle.set_auto_battle_enabled(false))
	battle._ability_executor.ability_started.connect(func(_unit, _ability, _cell): casts[0] += 1)
	var origin := caster.grid_cell
	var movement := caster.remaining_movement
	battle.set_auto_battle_enabled(true)
	await _until(func(): return started[0] and not battle._movement_locked, "switching off waits for AI movement")
	check(caster.grid_cell != origin and caster.remaining_movement < movement, "the current movement completes and pays its cost")
	check(casts[0] == 0 and caster.action_points == 2 and battle.turn_manager.current_unit == caster, "switching off before a planned cast preserves AP and the turn")
	await _remove_battle(battle)


func _test_takeover_manual_actions() -> void:
	var battle := _battle()
	var caster := battle.turn_manager.current_unit
	caster.movement_started.connect(func(_unit): battle.set_auto_battle_enabled(true))
	var casts := [0]
	battle._ability_executor.ability_started.connect(func(unit, _ability, _cell):
		if unit == caster:
			casts[0] += 1
			battle.set_auto_battle_enabled(false))
	var completed_moves: Array[Dictionary] = []
	caster.movement_finished.connect(func(unit): completed_moves.append({"cell": unit.grid_cell, "remaining": unit.remaining_movement}))
	var path: Array[Vector2i] = [caster.grid_cell, caster.grid_cell + Vector2i.LEFT]
	var movement := caster.remaining_movement
	battle._begin_friendly_move(path)
	await _until(func(): return casts[0] == 1 and not battle._movement_locked, "takeover waits for manual movement then runs AI")
	check(not completed_moves.is_empty() and completed_moves[0].cell == path[1] and completed_moves[0].remaining == movement - 1 and caster.action_points == 1, "takeover preserves the manual move's cost: %s, expected cell %s, starting movement %s, AP %s" % [completed_moves, path[1], movement, caster.action_points])
	await _remove_battle(battle)
	battle = _battle()
	caster = battle.turn_manager.current_unit
	var first := ability
	var second := ability.duplicate(true)
	second.display_name = "Second Volley"
	caster.set_dev_ability_loadout([first, second])
	casts = [0]
	battle._ability_executor.ability_started.connect(func(_unit, _ability, _cell):
		casts[0] += 1
		battle.set_auto_battle_enabled(casts[0] == 1))
	battle._on_ability_selected(first)
	battle._selected_hit_targets.assign([_enemy(battle), _enemy(battle), _enemy(battle)])
	battle._begin_selected_targets_cast()
	await _until(func(): return casts[0] == 2 and not battle._movement_locked, "takeover waits for the manual cast then uses remaining AP")
	check(caster.action_points == 0 and battle.turn_manager.current_unit == caster, "manual cast takeover does not reset AP or skip the turn")
	await _remove_battle(battle)


func _test_defeated_handback() -> void:
	var battle := _battle()
	var caster := battle.turn_manager.current_unit
	ability.range = 1
	_enemy(battle)._set_runtime_grid_cell_immediate(Vector2i(9, 8))
	var started := [false]
	caster.movement_started.connect(func(_unit):
		started[0] = true
		battle.set_auto_battle_enabled(false)
		caster.apply_damage(caster.current_health))
	battle.set_auto_battle_enabled(true)
	await _until(func(): return started[0] and battle.turn_manager.current_unit != caster, "a unit defeated during handback does not strand the turn")
	check(not battle._combat_over and not battle.auto_battle_enabled, "a surviving party member can continue after an automated unit is defeated")
	await _remove_battle(battle)


func _test_enemy_turn_toggle() -> void:
	var battle := _battle()
	var enemy := _enemy(battle)
	enemy.equip_item(load("res://resources/items/weapons/goblin_bow.tres") as ItemDefinition)
	enemy.set_dev_ability_loadout([ability])
	battle.turn_manager.current_unit = enemy
	battle.turn_manager.current_index = battle.turn_manager.turn_order.find(enemy)
	enemy.reset_action_points()
	var casts := [0]
	battle._ability_executor.ability_started.connect(func(unit, _ability, _cell):
		if unit == enemy:
			casts[0] += 1
			battle.set_auto_battle_enabled(false))
	battle._on_turn_started(enemy)
	battle.set_auto_battle_enabled(true)
	await _until(func(): return casts[0] == 1 and battle.turn_manager.current_unit != enemy, "switching off during an enemy cast still completes its turn")
	check(enemy.action_points == 1, "enemy AI uses the shared per-hit executor even with auto battle off")
	await _remove_battle(battle)


func _test_pause_and_dev() -> void:
	var battle := _battle()
	var caster := battle.turn_manager.current_unit
	battle._ability_executor.ability_started.connect(func(_unit, _ability, _cell): battle._on_levels_button_pressed(), CONNECT_ONE_SHOT)
	battle.set_auto_battle_enabled(true)
	await _until(func(): return paused, "return dialog pauses an automated cast")
	var enemy_health := _enemy(battle).current_health
	await create_timer(0.05, true).timeout
	check(battle.turn_manager.current_unit == caster and _enemy(battle).current_health == enemy_health, "paused automation does not advance turns or damage")
	battle.set_auto_battle_enabled(false)
	battle._on_return_to_levels_canceled()
	battle.return_to_levels_dialog.hide()
	await _until(func(): return not battle._movement_locked, "canceling the dialog resumes the current cast and hands back control")
	await _remove_battle(battle)
	battle = _battle()
	caster = battle.turn_manager.current_unit
	var second := ability.duplicate(true)
	second.display_name = "After Dev"
	caster.set_dev_ability_loadout([ability, second])
	var casts := [0]
	battle._ability_executor.ability_started.connect(func(_unit, _ability, _cell):
		casts[0] += 1
		if casts[0] == 1: battle._on_dev_button_pressed()
		else: battle.set_auto_battle_enabled(false))
	battle.set_auto_battle_enabled(true)
	await _until(func(): return battle._dev_open, "Dev opens after the complete automated action")
	check(paused and caster.action_points == 1 and battle.auto_battle_enabled and battle.auto_battle_button.disabled, "Dev preserves the partial AI turn and disables the toggle")
	battle._on_dev_play_requested()
	await _until(func(): return casts[0] == 2 and not battle._movement_locked, "Dev resumes the same AI turn using its remaining AP")
	check(caster.action_points == 0 and battle.turn_manager.current_unit == caster, "Dev resume neither resets AP nor duplicates the AI runner")
	await _remove_battle(battle)


func _test_checkpoint_and_restart() -> void:
	var battle := _battle(true)
	var caster := battle.turn_manager.current_unit
	caster.spend_action_points(1)
	var movement := caster.remaining_movement
	battle._ability_executor.ability_started.connect(func(_unit, _ability, _cell): battle.set_auto_battle_enabled(false), CONNECT_ONE_SHOT)
	battle.set_auto_battle_enabled(true)
	await _until(func(): return not battle.auto_battle_enabled and not battle._movement_locked, "checkpoint fixture finishes its automated cast")
	var checkpoint := battle._ai_debug_checkpoints[0].duplicate(true)
	check(ScenarioSaveStore.validate_payload(checkpoint).ok, "friendly AI checkpoints remain valid exact saves")
	await _remove_battle(battle)
	var restored := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	restored.map_definition = load("res://resources/maps/goblin_skirmish.tres") as BattleMapDefinition
	restored.pending_restore_payload = checkpoint
	root.add_child(restored)
	await process_frame
	check(not restored.auto_battle_enabled and not restored._movement_locked, "restored friendly AI checkpoint starts in manual mode")
	check(restored.turn_manager.current_unit.action_points == 1 and restored.turn_manager.current_unit.remaining_movement == movement, "exact restore preserves pre-decision AP and movement")
	var reloads: Array[Dictionary] = []
	restored.battle_reload_requested.connect(func(payload): reloads.append(payload))
	restored.set_auto_battle_enabled(true)
	restored._on_restart_button_pressed()
	check(reloads.size() == 1 and reloads[0].runtime.fresh_start, "restart produces a fresh battle payload during auto battle")
	await _remove_battle(restored)
	var restarted := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	restarted.map_definition = load("res://resources/maps/goblin_skirmish.tres") as BattleMapDefinition
	restarted.pending_restore_payload = reloads[0]
	paused = true
	root.add_child(restarted)
	paused = false
	await process_frame
	check(not restarted.auto_battle_enabled and not restarted.auto_battle_button.button_pressed, "restarted battle defaults to manual control")
	check(not restarted._movement_locked, "a fresh restart initialized under the Dev pause restores usable controls")
	await _remove_battle(restarted)


func _test_automatic_completion() -> void:
	var battle := _battle()
	var lethal := AbilityDefinition.new()
	lethal.display_name = "Completion Fixture"
	lethal.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	lethal.innate_damage = 10000
	lethal.scaling_amount = 0
	lethal.range = 30
	lethal.delivery_type = AbilityDefinition.DeliveryType.CAST_ON_TARGET
	lethal.cooldown_turns = 0
	var seen: Dictionary = {battle.turn_manager.current_unit.is_friendly(): true}
	for unit in battle._characters:
		unit.set_dev_ability_loadout([lethal])
	battle.turn_manager.turn_started.connect(func(unit): seen[unit.is_friendly()] = true)
	battle.set_auto_battle_enabled(true)
	await _until(func(): return battle._combat_over and battle._combat_finalized, "auto battle progresses multiple turns to completion without player input")
	check(seen.has(true) and seen.has(false), "both factions take automated turns")
	check(battle.auto_battle_button.disabled and battle.end_turn_button.disabled, "battle completion disables combat controls")
	var round_number := battle.turn_manager.round_number
	await create_timer(0.05).timeout
	check(battle.turn_manager.round_number == round_number, "automation stops at the battle result")
	await _remove_battle(battle)


func _test_layout() -> void:
	for resolution in [Vector2i(1280, 720), Vector2i(800, 600)]:
		root.size = resolution
		var battle := _battle()
		await process_frame
		await process_frame
		var actions := battle.auto_battle_button.get_parent() as Control
		check(actions.get_global_rect().position.x >= 0 and actions.get_global_rect().end.x <= battle.get_viewport_rect().size.x, "battle action row fits " + str(resolution))
		var previous_end := 0.0
		for child in actions.get_children():
			var button := child as Button
			check(button.get_global_rect().position.x >= previous_end, "battle buttons do not overlap at " + str(resolution))
			previous_end = button.get_global_rect().end.x
		if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(DIRECTORY.path_join("auto_battle_%dx%d.png" % [resolution.x, resolution.y])))
			paused = true
			battle.set_auto_battle_enabled(true)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(DIRECTORY.path_join("auto_battle_on_%dx%d.png" % [resolution.x, resolution.y])))
			paused = false
		await _remove_battle(battle)
