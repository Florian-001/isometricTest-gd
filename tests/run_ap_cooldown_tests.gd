extends SceneTree

const DIRECTORY := "res://.godot/ap_cd_validation"
var failures: Array[String] = []
var checks := 0
var arena: Node2D
var grid: IsometricGrid
var targeting: AbilityTargeting
var executor: AbilityExecutor
var units: Array[TacticalCharacter] = []


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	arena = Node2D.new()
	root.add_child(arena)
	grid = IsometricGrid.new()
	grid.grid_size = Vector2i(10, 10)
	arena.add_child(grid)
	targeting = AbilityTargeting.new(grid.grid_size)
	executor = AbilityExecutor.new()
	arena.add_child(executor)
	_test_authored_defaults("res://resources")
	await _test_turns_and_casts()
	await _test_multiple_hits_and_interruptions()
	await _test_reactions()
	_test_reassemble()
	_test_persistence_and_ai()
	_clear()
	arena.free()
	await _test_battle()
	for failure in failures:
		push_error(failure)
	print("AP_COOLDOWN_TESTS_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_authored_defaults(directory: String) -> void:
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".tres"):
			var resource := load(directory.path_join(file))
			if resource is AbilityDefinition:
				check(resource.ap_cost == 1 and resource.cooldown_turns == 1, "authored 1 AP / 1 CD: " + file)
	for child in DirAccess.get_directories_at(directory):
		_test_authored_defaults(directory.path_join(child))


func _ability(label: String) -> AbilityDefinition:
	var ability := AbilityDefinition.new()
	ability.display_name = label
	ability.requires_weapon = false
	ability.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	ability.innate_damage = 5
	ability.scaling_stat = DamageCalculator.ScalingSource.NONE
	ability.range = 8.0
	return ability


func _unit(friendly: bool, cell: Vector2i, abilities: Array[AbilityDefinition]) -> TacticalCharacter:
	var unit := TacticalCharacter.new()
	unit.name = "APTest%d" % units.size()
	unit.scenario_unit_id = unit.name
	unit.definition = CharacterDefinition.new()
	unit.definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	unit.definition.constitution = 50
	unit.definition.speed = 20 if friendly else 10
	unit.starting_grid_cell = cell
	unit.override_template_abilities = true
	unit.ability_overrides = abilities
	unit.use_complete_equipment_override = true
	arena.add_child(unit)
	unit.initialize(grid)
	unit.reset_ability_action()
	unit.reset_movement()
	units.append(unit)
	return unit


func _clear() -> void:
	for unit in units:
		unit.free()
	units.clear()


func _cast(unit: TacticalCharacter, ability: AbilityDefinition, target: TacticalCharacter) -> bool:
	return await executor.execute(unit, ability, target.grid_cell, units, grid, targeting)


func _test_turns_and_casts() -> void:
	var first := _ability("First")
	var second := _ability("Second")
	var third := _ability("Third")
	var caster := _unit(true, Vector2i(1, 1), [first, second, third])
	var target := _unit(false, Vector2i(3, 1), [first, second])
	var turns := TurnManager.new()
	arena.add_child(turns)
	turns.start_combat(units)
	check(turns.current_unit == caster and caster.action_points == 2 and target.action_points == 0, "only current unit receives 2 AP")
	var movement := caster.remaining_movement
	check(not await executor.execute(caster, first, Vector2i(9, 9), units, grid, targeting), "invalid cast is rejected")
	check(caster.action_points == 2 and caster.get_ability_cooldown(first) == 0, "rejected cast spends no AP or cooldown")
	check(await _cast(caster, first, target), "first ability executes")
	check(caster.action_points == 1 and caster.get_ability_cooldown(first) == 1, "first cast spends 1 AP and starts cooldown")
	third.ap_cost = 2
	check(not await _cast(caster, third, target) and caster.action_points == 1, "insufficient AP rejects a more expensive ability")
	third.ap_cost = 1
	check(not await _cast(caster, first, target) and caster.action_points == 1, "same ability cannot repeat this turn")
	check(await _cast(caster, second, target) and caster.action_points == 0, "different second ability spends remaining AP")
	check(not await _cast(caster, third, target) and caster.get_ability_cooldown(third) == 0, "third cast is rejected without cooldown")
	check(caster.remaining_movement == movement and caster.can_move(), "casts and zero AP do not consume or block movement")
	turns.end_current_turn()
	check(target.action_points == 2 and target.get_ability_cooldown(first) == 0 and caster.get_ability_cooldown(first) == 1, "shared resource cooldown belongs to its caster")
	turns.end_current_turn()
	check(caster.action_points == 2 and caster.get_ability_cooldown(first) == 0 and caster.can_activate_ability(first), "1 CD is ready on next owner turn")
	first.ap_cost = 2
	first.cooldown_turns = 2
	check(await _cast(caster, first, target) and caster.action_points == 0, "configurable 2 AP cost")
	turns.end_current_turn()
	turns.end_current_turn()
	check(caster.get_ability_cooldown(first) == 1 and not caster.can_activate_ability(first), "2 CD skips one owner turn")
	caster.apply_status(load("res://resources/statuses/stun.tres"))
	turns.end_current_turn()
	turns.end_current_turn()
	check(caster.get_ability_cooldown(first) == 0 and caster.action_points == 2 and caster.is_stunned(), "cooldown ticks and AP replenishes on stunned turns")
	caster.remove_status(&"stun")
	check(caster.spend_action_points(1), "prepare unspent AP at turn end")
	turns.end_current_turn()
	turns.end_current_turn()
	check(caster.action_points == 2, "unspent AP never carries over")
	caster.spend_ability_action(second)
	turns.start_combat(units)
	check(caster.action_points == 2 and caster.get_ability_cooldowns().is_empty(), "fresh combat clears cooldowns")
	second.cooldown_turns = 0
	check(await _cast(caster, second, target) and await _cast(caster, second, target), "zero cooldown permits repeats within AP budget")
	check(caster.action_points == 0 and caster.get_ability_cooldown(second) == 0, "zero cooldown still charges each cast")
	turns.free()
	_clear()


func _test_multiple_hits_and_interruptions() -> void:
	var ability := _ability("Triple")
	ability.hit_count = 3
	var caster := _unit(true, Vector2i(1, 1), [ability])
	var target := _unit(false, Vector2i(3, 1), [])
	var health := target.current_health
	check(await _cast(caster, ability, target) and target.current_health == health - 15, "all three hits resolve after AP/CD commitment")
	check(caster.action_points == 1 and caster.get_ability_cooldown(ability) == 1, "multi-hit ability pays once")
	caster.reset_ability_action()
	ability.hit_targeting = AbilityDefinition.HitTargeting.SELECT_PER_HIT
	check(not await executor.execute_targets(caster, ability, [target], units, grid, targeting), "incomplete target selection is rejected")
	check(caster.action_points == 2 and caster.get_ability_cooldown(ability) == 0, "incomplete selection costs nothing")
	check(await executor.execute_targets(caster, ability, [target, target, target], units, grid, targeting), "per-hit targeting executes")
	check(caster.action_points == 1 and target.current_health == health - 30, "per-hit cast pays once and delivers every hit")
	caster.reset_ability_action()
	ability.delivery_type = AbilityDefinition.DeliveryType.PROJECTILE
	ability.projectile_speed = 10000.0
	executor.projectile_delivery.projectile_launched.connect(func(_caster, _ability, _cell):
		caster.apply_status(load("res://resources/statuses/stun.tres")), CONNECT_ONE_SHOT)
	await executor.execute_targets(caster, ability, [target, target, target], units, grid, targeting)
	check(caster.action_points == 1 and caster.get_ability_cooldown(ability) == 1, "interrupted cast retains AP and cooldown")
	check(target.current_health == health - 30, "stun prevents pending and later impacts")
	_clear()


func _test_reactions() -> void:
	var strike := load("res://resources/abilities/strike.tres") as AbilityDefinition
	var caster := _unit(false, Vector2i(1, 1), [strike])
	var target := _unit(true, Vector2i(2, 1), [strike])
	var weapon := ItemDefinition.new()
	weapon.weapon_damage = 4
	caster.equip_item(weapon)
	target.equip_item(weapon)
	check(await _cast(caster, strike, target), "normal Strike starts its cooldown")
	caster.spend_action_points(1)
	var health := target.current_health
	check(await executor.execute_opportunity_attack(caster, strike, target.grid_cell, units, grid, targeting), "opportunity attack works at 0 AP while Strike is cooling down")
	check(caster.action_points == 0 and caster.get_ability_cooldown(strike) == 1 and target.current_health < health, "opportunity reaction neither pays AP nor alters cooldown")
	caster.apply_status(load("res://resources/statuses/counter.tres"))
	health = target.current_health
	check(await executor.execute_counter_attack(caster, target, units, grid, targeting), "counterattack works at 0 AP and with Strike cooldown")
	check(caster.action_points == 0 and caster.get_ability_cooldown(strike) == 1 and target.current_health < health, "counterattack leaves AP/CD unchanged")
	var cooldown := caster.get_ability_cooldown(strike)
	caster.unequip_item(ItemDefinition.EquipmentSlot.WEAPON)
	caster.equip_item(weapon)
	check(caster.get_ability_cooldown(strike) == cooldown, "equipment swaps retain cooldown")
	_clear()


func _test_reassemble() -> void:
	var ability := _ability("Reforming cast")
	ability.cooldown_turns = 2
	var friend := _unit(true, Vector2i(1, 1), [ability])
	var skeleton := _unit(false, Vector2i(3, 1), [ability])
	skeleton.set_dev_passive_loadout([load("res://resources/passives/reassemble.tres")])
	var turns := TurnManager.new()
	arena.add_child(turns)
	turns.start_combat(units)
	turns.end_current_turn()
	check(skeleton.spend_ability_action(ability), "skeleton spends AP before collapse")
	skeleton.apply_damage(9999)
	check(skeleton.is_bone_pile and skeleton.action_points == 0 and skeleton.get_ability_cooldown(ability) == 2, "collapse empties AP without clearing cooldown")
	turns.end_current_turn()
	turns.end_current_turn()
	check(not skeleton.is_bone_pile and skeleton.action_points == 2 and skeleton.get_ability_cooldown(ability) == 1, "reformation refreshes AP and ticks cooldown exactly once")
	check(friend.get_ability_cooldown(ability) == 0, "reformation does not affect other cooldowns")
	turns.free()
	_clear()


func _test_persistence_and_ai() -> void:
	var first := _ability("Saved first")
	var second := _ability("Saved second")
	ResourceSaver.save(first, DIRECTORY.path_join("first.tres"))
	ResourceSaver.save(second, DIRECTORY.path_join("second.tres"))
	first = load(DIRECTORY.path_join("first.tres"))
	second = load(DIRECTORY.path_join("second.tres"))
	var enemy := _unit(false, Vector2i(1, 1), [first, second])
	var target := _unit(true, Vector2i(3, 1), [first])
	check(enemy.spend_ability_action(first), "prepare partial turn")
	var state: Dictionary = JSON.parse_string(JSON.stringify(enemy.capture_runtime_state()))
	enemy.reset_ability_action()
	enemy.restore_runtime_state(state, {})
	check(enemy.action_points == 1 and enemy.get_ability_cooldown(first) == 1, "JSON save restores exact AP/CD without ticking")
	enemy.ability_overrides = [second]
	enemy.ability_overrides = [first, second]
	check(enemy.get_ability_cooldown(first) == 1, "removing and restoring an ability does not clear cooldown")
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
	var clone := snapshot.duplicate_state()
	check(clone.spend_ability_action(enemy, second), "snapshot supports second cast")
	check(clone.get_action_points(enemy) == 0 and snapshot.get_action_points(enemy) == 1 and enemy.action_points == 1, "simulation does not mutate source or live AP")
	check(clone.get_ability_cooldown(enemy, second) == 1 and snapshot.get_ability_cooldown(enemy, second) == 0, "snapshot cooldowns are deeply isolated")
	clone.start_ability_turn(enemy)
	check(clone.get_action_points(enemy) == 2 and clone.get_ability_cooldown(enemy, first) == 0, "snapshot future turn replenishes AP and cooldowns")
	var planner := EnemyAIPlanner.new()
	var pathfinder := GridPathfinder.new(grid.grid_size)
	var plan := planner.choose_plan(enemy, units, pathfinder, targeting)
	check(plan.ability == second, "AI chooses ready second ability instead of cooling first")
	var simulated := planner._simulate_plan(enemy, plan, snapshot, targeting, EnemyAIProfile.new(), pathfinder)
	check(simulated.get_action_points(enemy) == 0 and simulated.get_ability_cooldown(enemy, second) == 1, "AI active forecast pays AP/CD once")
	enemy.spend_action_points(1)
	check(planner.choose_plan(enemy, units, pathfinder, targeting).ability == null, "AI cannot cast at zero AP")
	state.erase("action_points")
	state.erase("ability_cooldowns")
	state.ability_available = true
	enemy.restore_runtime_state(state, {})
	check(enemy.action_points == 2 and enemy.get_ability_cooldowns().is_empty(), "legacy available action loads as 2 AP and no cooldowns")
	state.ability_available = false
	enemy.restore_runtime_state(state, {})
	check(enemy.action_points == 0, "legacy spent action loads as 0 AP")
	check(target.get_ability_cooldown(first) == 0, "restoring shared ability never affects another unit")


func _test_battle() -> void:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	battle.center_camera_on_start = false
	root.add_child(battle)
	await process_frame
	check(battle.initialization_succeeded, "real battle initializes")
	var first := load(DIRECTORY.path_join("first.tres")) as AbilityDefinition
	var second := load(DIRECTORY.path_join("second.tres")) as AbilityDefinition
	var friendly: TacticalCharacter
	var enemy: TacticalCharacter
	for unit in battle._characters:
		if unit.is_friendly() and friendly == null:
			friendly = unit
		elif not unit.is_friendly() and enemy == null:
			enemy = unit
	# Isolate a legal pair while keeping all setup/runtime entries for save validation.
	var cells := battle.grid.grid_size
	var index := 0
	for unit in battle._characters:
		unit.set_grid_cell_immediate(Vector2i(index % cells.x, cells.y - 1))
		index += 1
	friendly.set_grid_cell_immediate(Vector2i(1, 1))
	enemy.set_grid_cell_immediate(Vector2i(3, 1))
	for unit in [friendly, enemy]:
		unit.override_template_abilities = true
		unit.ability_overrides.assign([first, second])
		unit.reset_ability_action()
		unit.movement_animation_speed = 10000.0
	battle.turn_manager.current_unit = friendly
	battle.turn_manager.current_index = battle.turn_manager.turn_order.find(friendly)
	battle._on_turn_started(friendly)
	check(battle.action_points_label.text == "AP 2 / 2", "HUD shows initial AP")
	battle._on_ability_selected(first)
	battle._cancel_ability_targeting()
	check(friendly.action_points == 2 and friendly.get_ability_cooldown(first) == 0, "cancelled UI targeting is free")
	battle._on_ability_selected(first)
	await battle._begin_ability_cast(enemy.grid_cell)
	check(friendly.action_points == 1 and battle.action_points_label.text == "AP 1 / 2", "real cast updates AP HUD")
	var buttons := battle.ability_bar._get_entries().get_children()
	check(buttons[0].disabled and buttons[0].text.contains("CD 1") and buttons[0].text.contains("1 AP"), "used button shows cooldown and AP cost")
	check(not buttons[1].disabled and not battle.ability_bar.activate_slot(0), "ready second ability enabled and cooldown shortcut blocked")
	var payload := battle.capture_save_payload()
	var validation := ScenarioSaveStore.validate_payload(payload)
	check(validation.ok, "exact save accepts AP/CD: " + str(validation.errors))
	var invalid := payload.duplicate(true)
	invalid.runtime.units[0].action_points = 3
	check(not ScenarioSaveStore.validate_payload(invalid).ok, "save rejects AP above turn maximum")
	invalid = payload.duplicate(true)
	invalid.runtime.units[0].ability_cooldowns = {first.resource_path: -1}
	check(not ScenarioSaveStore.validate_payload(invalid).ok, "save rejects negative cooldown")
	invalid.runtime.units[0].ability_cooldowns = {"res://resources/items/weapons/staff.tres": 1}
	check(not ScenarioSaveStore.validate_payload(invalid).ok, "save rejects non-ability cooldown resource")
	var checkpoint := battle._capture_ai_debug_checkpoint()
	check(ScenarioSaveStore.validate_payload(checkpoint).ok, "AI checkpoint captures partial turn")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(DIRECTORY.path_join("ap_cooldown.png")))
	var restored := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	restored.map_definition = battle.map_definition
	restored.pending_restore_payload = payload
	root.add_child(restored)
	await process_frame
	check(restored.turn_manager.current_unit.action_points == 1 and restored.turn_manager.current_unit.get_ability_cooldown(first) == 1, "battle reload preserves partial turn")
	restored.free()
	# Freeze turn callbacks so the enemy loop can be observed without starting another turn.
	battle.turn_manager.turn_started.disconnect(battle._on_turn_started)
	battle.turn_manager.current_unit = enemy
	battle.turn_manager.current_index = battle.turn_manager.turn_order.find(enemy)
	enemy.reset_ability_action()
	enemy.spend_movement(enemy.remaining_movement)
	var casts: Array[AbilityDefinition] = []
	battle._ability_executor.ability_started.connect(func(caster, ability, _cell):
		if caster == enemy: casts.append(ability))
	await battle._run_enemy_unit_turn(enemy)
	check(casts.size() == 2 and casts[0] != casts[1] and enemy.action_points == 0, "enemy turn executes two different abilities then terminates")
	await process_frame
	check(battle.turn_manager.current_unit != enemy, "enemy turn advances safely after spending AP")
	battle.queue_free()
	await process_frame
