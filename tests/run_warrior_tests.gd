extends SceneTree

const DIRECTORY := "res://.godot/warrior_validation"
var failures: Array[String] = []
var checks := 0
var arena: Node2D
var grid: IsometricGrid
var targeting: AbilityTargeting
var executor: AbilityExecutor
var units: Array[TacticalCharacter] = []
var stomp: AbilityDefinition
var taunt: AbilityDefinition
var multi: AbilityDefinition
var strike: AbilityDefinition
var taunted: StatusEffectDefinition
var impacts := 0


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	stomp = load("res://resources/abilities/battle_stomp.tres")
	taunt = load("res://resources/abilities/taunt.tres")
	multi = load("res://resources/abilities/multi_attack.tres").duplicate(true)
	strike = load("res://resources/abilities/strike.tres")
	taunted = load("res://resources/statuses/taunted.tres")
	multi.melee_lunge_duration = 0.02
	multi.melee_return_duration = 0.02
	multi.melee_slash_duration = 0.02
	arena = Node2D.new()
	root.add_child(arena)
	grid = IsometricGrid.new()
	grid.grid_size = Vector2i(10, 10)
	arena.add_child(grid)
	targeting = AbilityTargeting.new(grid.grid_size)
	executor = AbilityExecutor.new()
	arena.add_child(executor)
	executor.melee_delivery.melee_impact.connect(func(_caster, ability, _cell):
		if ability == multi:
			impacts += 1
	)
	_test_resources()
	await _test_areas()
	await _test_multi()
	_test_taunt_lifecycle()
	await _test_taunt_ai()
	_test_ranged_taunt()
	_clear()
	arena.free()
	await _test_battle_ui()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("WARRIOR_TESTS_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _unit(friendly: bool, cell: Vector2i, abilities: Array[AbilityDefinition] = []) -> TacticalCharacter:
	var unit := TacticalCharacter.new()
	unit.name = "WarriorTest%d" % units.size()
	unit.scenario_unit_id = unit.name
	unit.definition = CharacterDefinition.new()
	unit.definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	unit.definition.constitution = 50
	unit.definition.strength = 5
	unit.definition.movement_range = 4.0
	unit.starting_grid_cell = cell
	unit.override_template_abilities = true
	unit.ability_overrides = abilities
	unit.use_complete_equipment_override = true
	var weapon := ItemDefinition.new()
	weapon.weapon_damage = 4
	unit.complete_equipment_overrides = [weapon]
	unit.movement_animation_speed = 10000.0
	arena.add_child(unit)
	unit.initialize(grid)
	unit.reset_movement()
	unit.reset_ability_action()
	unit.spend_opportunity_reaction()
	units.append(unit)
	return unit


func _clear() -> void:
	for unit in units:
		if is_instance_valid(unit):
			unit.free()
	units.clear()


func _forecast(caster: TacticalCharacter, ability: AbilityDefinition, cell: Vector2i) -> AIBoardSnapshot:
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
	var planner := EnemyAIPlanner.new()
	planner._prepare_decision(caster, snapshot, units)
	planner._forecast_ability(caster, ability, cell, snapshot, targeting, EnemyAIProfile.new())
	return snapshot


func _test_resources() -> void:
	var defaults := AbilityDefinition.new()
	check(not defaults.caster_centered and defaults.hit_count == 1 and defaults.requires_weapon, "existing ability defaults remain compatible")
	var warrior := load("res://resources/classes/warrior.tres") as CharacterClassDefinition
	var actor := _unit(true, Vector2i(2, 2))
	actor.definition.starting_class = warrior
	actor.override_template_abilities = false
	var names := ["Strike", "Charge", "Battle Stomp", "Taunt", "Multi Attack"]
	for level in range(1, 6):
		actor.set_class_level(warrior, level)
		var actual: Array[String] = []
		for ability in actor.get_abilities():
			actual.append(ability.display_name)
		check(actual == names.slice(0, level), "warrior unlocks at level %d" % level)
	actor.set_class_level(warrior, 2)
	var enemy := _unit(false, Vector2i(3, 2))
	check(not executor.can_execute(actor, stomp, actor.grid_cell, units, grid, targeting), "locked Stomp cannot execute directly")
	check(not executor.can_execute(actor, load("res://resources/abilities/multi_attack.tres"), enemy.grid_cell, units, grid, targeting), "locked Multi Attack cannot execute directly")
	var catalog := load("res://resources/dev_tool_catalog.tres") as DevToolCatalog
	for ability in [stomp, taunt, load("res://resources/abilities/multi_attack.tres")]:
		check(catalog.abilities.has(ability), "%s appears in developer catalog" % ability.display_name)
	check(ResourceSaver.save(taunt, DIRECTORY + "/taunt.tres") == OK, "ability resource saves")
	var saved := ResourceLoader.load(DIRECTORY + "/taunt.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as AbilityDefinition
	check(saved.caster_centered and not saved.requires_weapon and saved.status_effect.effect == StatusEffectDefinition.Effect.TAUNT, "Inspector properties round-trip")
	_clear()


func _test_areas() -> void:
	var caster := _unit(true, Vector2i(4, 4), [stomp, taunt])
	var adjacent := _unit(false, Vector2i(5, 4))
	var diagonal := _unit(false, Vector2i(3, 3))
	var outside := _unit(false, Vector2i(6, 4))
	var ally := _unit(true, Vector2i(4, 5))
	var cells := targeting.get_affected_cells(caster.grid_cell, caster.grid_cell, stomp)
	check(cells.size() == 9 and cells.has(diagonal.grid_cell) and not cells.has(outside.grid_cell), "radius 1.5 contains all eight neighbors and excludes distance 2")
	check(targeting.get_valid_target_cells(caster, stomp, units).keys() == [caster.grid_cell], "caster-only confirmation independent of enemy recipient flags")
	check(not executor.can_execute(caster, stomp, adjacent.grid_cell, units, grid, targeting), "cannot aim Stomp at a neighboring enemy")
	var walls := {adjacent.grid_cell: true}
	check(not targeting.get_affected_cells(caster.grid_cell, caster.grid_cell, stomp, walls).has(adjacent.grid_cell), "wall cells excluded from area")
	var wide := stomp.duplicate(true) as AbilityDefinition
	wide.range = 3.0
	check(not targeting.get_affected_cells(caster.grid_cell, caster.grid_cell, wide, walls).has(outside.grid_cell), "radius obeys line of sight behind walls")
	check(targeting.get_affected_cells(Vector2i.ZERO, Vector2i.ZERO, stomp).size() == 4, "radius clips to board edges")
	var old_health := adjacent.current_health
	var predicted := _forecast(caster, stomp, caster.grid_cell)
	var movement := caster.remaining_movement
	check(await executor.execute(caster, stomp, caster.grid_cell, units, grid, targeting), "Stomp executes on caster cell")
	check(adjacent.current_health == old_health - 9 and diagonal.current_health == old_health - 9, "Stomp applies weapon 4 + Strength 5 to both enemies")
	check(adjacent.current_health == predicted.get_health(adjacent) and diagonal.current_health == predicted.get_health(diagonal), "area AI agrees with runtime")
	check(ally.current_health == old_health and caster.current_health == old_health and outside.current_health == old_health, "Stomp excludes allies, self and out-of-range units")
	check(not caster.ability_available and caster.remaining_movement == movement, "Stomp costs one ability action and no movement")
	check(not adjacent.is_stunned(), "Stomp does not stun")
	caster.reset_ability_action()
	caster.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, null)
	check(not stomp.can_be_used_by(caster) and not multi.can_be_used_by(caster) and taunt.can_be_used_by(caster), "only Taunt works without a melee weapon")
	check(await executor.execute(caster, taunt, caster.grid_cell, units, grid, targeting), "unarmed Taunt executes")
	check(adjacent.get_taunt_target() == caster and diagonal.get_taunt_target() == caster, "Taunt affects orthogonal and diagonal enemies")
	check(outside.get_taunt_target() == null and ally.get_taunt_target() == null and caster.get_taunt_target() == null, "Taunt excludes distant enemies and friendlies")
	check(not adjacent.is_stunned() and adjacent.current_health == old_health - 9, "Taunt neither damages nor stuns")
	_clear()


func _test_multi() -> void:
	var caster := _unit(true, Vector2i(3, 3), [multi])
	var ally := _unit(true, Vector2i(2, 3))
	var target := _unit(false, Vector2i(4, 3))
	var replacement := _unit(false, Vector2i(8, 8))
	caster.set_dev_passive_loadout([load("res://resources/passives/pack_tactics.tres")])
	ally.set_dev_passive_loadout([load("res://resources/passives/pack_tactics.tres")])
	var weapon := caster.get_equipped_weapon()
	weapon.status_effect = load("res://resources/statuses/slow.tres")
	check(multi.calculate_hit_damage(caster) == 8 and multi.calculate_damage(caster) == 16, "each hit rounds 4 + 2.5 to 7 then adds one passive damage")
	var health_changes: Array[int] = []
	target.health_changed.connect(func(value, _maximum): health_changes.append(value))
	var refreshes := [0]
	target.statuses_changed.connect(func(): refreshes[0] += 1)
	var before := target.current_health
	var snapshot := _forecast(caster, multi, target.grid_cell)
	impacts = 0
	var movement := caster.remaining_movement
	check(await executor.execute(caster, multi, target.grid_cell, units, grid, targeting), "Multi Attack executes")
	check(impacts == 2 and health_changes == [before - 8, before - 16], "two animations cause two distinct damage events")
	check(refreshes[0] == 2 and target.get_active_statuses().size() == 1, "weapon status applies on each hit and refreshes without stacking")
	check(target.current_health == snapshot.get_health(target), "two-hit forecast equals runtime")
	check(not caster.ability_available and caster.remaining_movement == movement, "both hits consume only one action")
	var bar := (load("res://scenes/ability_bar.tscn") as PackedScene).instantiate() as AbilityBar
	arena.add_child(bar)
	bar.rebuild(caster, true)
	var button := bar.get_node("Margin/HBox").get_child(0) as Button
	check(button.text.contains("2 × 8 DMG") and button.tooltip_text.contains("16 physical damage"), "ability bar shows per-hit damage and total")
	bar.set_damage_preview(caster, multi, Vector2i(8, 0))
	check(button.text.contains("2 × 7 DMG"), "movement preview updates damage per hit")
	bar.reset_damage_previews()
	check(button.text.contains("2 × 8 DMG"), "reset restores repeated-hit preview")
	bar.free()
	caster.reset_ability_action()
	target.current_health = 5
	target.remove_status(&"slow")
	health_changes.clear()
	snapshot = _forecast(caster, multi, target.grid_cell)
	impacts = 0
	var original_cell := target.grid_cell
	target.defeated.connect(func(_unit):
		target.set_grid_cell_immediate(Vector2i(9, 9))
		replacement.set_grid_cell_immediate(original_cell)
	)
	check(await executor.execute(caster, multi, target.grid_cell, units, grid, targeting), "first-hit defeat still completes the ability")
	check(impacts == 1 and target.current_health == 0 and snapshot.get_health(target) == 0, "first-hit kill stops second impact and agrees with AI")
	check(replacement.current_health == replacement.get_max_health(), "second hit never switches to a replacement occupant")
	check(target.get_active_statuses().is_empty(), "no weapon status after lethal damage")
	check(ally.current_health == ally.get_max_health(), "Multi Attack never damages nearby allies")
	_clear()


func _test_taunt_lifecycle() -> void:
	var source := _unit(true, Vector2i(3, 3))
	var second := _unit(true, Vector2i(4, 4))
	var enemy := _unit(false, Vector2i(4, 3), [strike])
	enemy.apply_status(taunted, taunt, source)
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
	check(snapshot.get_taunt_target(enemy) == source and snapshot.duplicate_state().get_taunt_target(enemy) == source, "snapshot and copies preserve taunt caster")
	var planner := EnemyAIPlanner.new()
	var old_key := planner._get_snapshot_key(snapshot)
	snapshot.forecast_status_application(second, enemy, taunted)
	check(snapshot.get_taunt_target(enemy) == second and old_key != planner._get_snapshot_key(snapshot), "simulated re-taunt changes caster and cache key")
	check(enemy.get_taunt_target() == source, "simulation does not mutate live status")
	enemy.apply_status(taunted, taunt, second)
	check(enemy.get_taunt_target() == second and enemy.get_active_statuses().size() == 1, "latest taunter replaces source without stacking")
	var saved := enemy.capture_runtime_state()
	enemy.remove_status(&"taunted")
	var by_id := {source.scenario_unit_id: source, second.scenario_unit_id: second, enemy.scenario_unit_id: enemy}
	enemy.restore_runtime_state(saved, by_id)
	check(enemy.get_taunt_target() == second, "runtime save restores caster")
	var manager := TurnManager.new()
	arena.add_child(manager)
	source.speed_override = 30
	second.speed_override = 20
	enemy.speed_override = 10
	manager.start_combat(units)
	manager.end_current_turn()
	check(enemy.get_taunt_target() == second, "Taunt survives other units' turns")
	manager.end_current_turn()
	check(manager.current_unit == enemy and enemy.get_taunt_target() == second, "Taunt remains throughout the affected enemy turn")
	manager.end_current_turn()
	check(enemy.get_taunt_target() == null and enemy.get_active_statuses().is_empty(), "Taunt expires at end of next enemy turn")
	manager.free()
	enemy.apply_status(taunted, taunt, second)
	second.current_health = 0
	check(enemy.get_taunt_target() == null and AIBoardSnapshot.from_battle(units, grid.grid_size).get_taunt_target(enemy) == null, "dead source releases Taunt")
	second.current_health = second.get_max_health()
	second.definition.faction = CharacterDefinition.Faction.ENEMY
	check(enemy.get_taunt_target() == null, "friendly source releases Taunt")
	second.definition.faction = CharacterDefinition.Faction.FRIENDLY
	var stale := AIBoardSnapshot.from_battle(units, grid.grid_size)
	units.erase(second)
	second.free()
	check(enemy.get_taunt_target() == null and stale.get_taunt_target(enemy) == null, "removed source is safely ignored")
	planner._get_snapshot_key(stale)
	_clear()


func _plan(enemy: TacticalCharacter, walls: Dictionary = {}) -> EnemyTurnPlan:
	return EnemyAIPlanner.new().choose_plan(enemy, units, GridPathfinder.new(grid.grid_size), targeting, walls)


func _test_taunt_ai() -> void:
	var source := _unit(true, Vector2i(3, 3))
	var enemy := _unit(false, Vector2i(2, 3), [strike])
	var decoy := _unit(true, Vector2i(2, 2))
	decoy.current_health = 1
	for cell in [Vector2i(1, 3), Vector2i(3, 2), Vector2i(1, 2)]:
		_unit(true, cell).current_health = 1
	enemy.apply_status(taunted, taunt, source)
	var plan := _plan(enemy)
	check(plan.ability == strike and plan.target_cell == source.grid_cell, "Taunt beats higher-value targets and top-three pruning")
	source.set_grid_cell_immediate(Vector2i(5, 3))
	plan = _plan(enemy)
	check(plan.ability == strike and plan.target_cell == source.grid_cell and plan.pre_cast_path.size() > 1, "enemy moves into range then attacks taunter")
	source.set_grid_cell_immediate(Vector2i(9, 3))
	enemy.spend_movement(enemy.remaining_movement - 2.0)
	plan = _plan(enemy)
	check(plan.ability == null and plan.pre_cast_path.size() > 1 and targeting.get_weighted_distance(plan.end_cell, source.grid_cell) < targeting.get_weighted_distance(enemy.grid_cell, source.grid_cell), "unreachable taunter is pursued despite available decoy attacks")
	var blocked := {}
	for x in range(8, 10):
		for y in range(2, 5):
			if Vector2i(x, y) != source.grid_cell:
				blocked[Vector2i(x, y)] = true
	plan = _plan(enemy, blocked)
	check(plan.ability == null and plan.pre_cast_path.size() > 1 and plan.end_cell.x > enemy.grid_cell.x, "no attack route still makes best-effort progress toward taunter")
	var enclosed := {}
	for offset in GridPathfinder.DIRECTIONS:
		enclosed[enemy.grid_cell + offset] = true
	plan = _plan(enemy, enclosed)
	check(plan.ability == null and plan.pre_cast_path.is_empty(), "fully blocked enemy holds without switching targets")
	enemy.apply_status(load("res://resources/statuses/stun.tres"), taunt, source)
	plan = _plan(enemy)
	check(plan.ability == null and plan.pre_cast_path.is_empty(), "stun overrides Taunt movement and attacks")
	enemy.remove_status(&"stun")
	var planner := EnemyAIPlanner.new()
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
	check(not planner.respects_taunt(enemy, enemy.grid_cell, strike, decoy.grid_cell, snapshot, targeting), "live execution guard rejects a stale other-target plan")
	source.current_health = 0
	plan = _plan(enemy)
	check(plan.ability == strike and plan.target_cell != source.grid_cell, "normal AI resumes when taunter dies")
	source.current_health = source.get_max_health()
	source.set_grid_cell_immediate(Vector2i(3, 3))
	enemy.ability_overrides = [multi]
	plan = _plan(enemy)
	check(plan.ability == multi and plan.target_cell == source.grid_cell, "repeated-hit ability can satisfy Taunt")
	enemy.ability_overrides = [stomp]
	plan = _plan(enemy)
	check(plan.ability == stomp and plan.target_cell == plan.get_cast_cell(enemy.grid_cell), "caster-centered attack uses its own origin while obeying Taunt")
	snapshot = _forecast(enemy, stomp, enemy.grid_cell)
	check(snapshot.get_health(source) < source.current_health and snapshot.get_health(decoy) < decoy.current_health, "area attack may damage other enemies while hitting taunter")
	var threat := planner._estimate_unit_action_against_target(enemy, source, AIBoardSnapshot.from_battle(units, grid.grid_size), GridPathfinder.new(grid.grid_size), targeting, EnemyAIProfile.new(), false)
	check(int(threat.damage) > 0, "centered attack contributes to AI threat forecast")
	enemy.ability_overrides = [strike]
	enemy.reset_opportunity_reaction()
	var before := decoy.current_health
	check(await executor.execute_opportunity_attack(enemy, strike, decoy.grid_cell, units, grid, targeting), "Taunt does not restrict opportunity reactions")
	check(decoy.current_health < before, "reaction can damage a unit other than taunter")
	_clear()


func _test_ranged_taunt() -> void:
	var source := _unit(true, Vector2i(8, 3))
	var shot := load("res://resources/abilities/arrow.tres") as AbilityDefinition
	var enemy := _unit(false, Vector2i(2, 3), [shot])
	_unit(true, Vector2i(2, 4)).current_health = 1
	enemy.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, load("res://resources/items/goblin_bow.tres"))
	enemy.apply_status(taunted, taunt, source)
	var plan := _plan(enemy)
	check(plan.ability == shot and plan.target_cell == source.grid_cell, "ranged enemy attacks taunter instead of adjacent decoy")
	enemy.spend_movement(enemy.remaining_movement)
	source.set_grid_cell_immediate(Vector2i(9, 9))
	plan = _plan(enemy)
	check(plan.ability == null and plan.pre_cast_path.is_empty(), "immobile ranged enemy cannot substitute a different target: %s / budget %s" % [plan.get_debug_summary(), enemy.remaining_movement])
	enemy.remove_status(&"taunted")
	plan = _plan(enemy)
	check(plan.ability == shot and plan.target_cell != source.grid_cell, "normal targeting returns after Taunt is removed")
	_clear()


func _capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(DIRECTORY + "/" + name + ".png") == OK, "capture %s" % name)


func _test_battle_ui() -> void:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	root.add_child(battle)
	check(battle.initialization_succeeded, "real battle initializes with new resources")
	battle.set_process(false)
	var actor := battle._characters[1]
	battle.turn_manager.current_unit = actor
	battle.turn_manager.current_index = battle.turn_manager.turn_order.find(actor)
	actor.reset_ability_action()
	actor.reset_movement()
	battle._on_turn_started(actor)
	actor.set_grid_cell_immediate(Vector2i(5, 5))
	battle._characters[2].set_grid_cell_immediate(Vector2i(6, 5))
	battle._characters[3].set_grid_cell_immediate(Vector2i(4, 6))
	battle._characters[4].set_grid_cell_immediate(Vector2i(6, 6))
	actor.set_class_level(load("res://resources/classes/warrior.tres"), 5)
	for entry in actor.get_class_levels():
		if entry.character_class.class_id != &"warrior":
			actor.set_class_level(entry.character_class, 0)
	actor.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, load("res://resources/items/iron_sword.tres"))
	battle._refresh_ability_bar()
	check(battle.ability_bar.get_node("Margin/HBox").get_child_count() == 5, "battle bar displays five warrior unlocks")
	battle._on_ability_selected(stomp)
	check(battle._ability_target_cells.keys() == [actor.grid_cell], "battle offers only caster confirmation")
	battle._update_ability_hover(actor.global_position + Vector2(0, -85))
	check(battle.grid._ability_area_cells == battle._ability_targeting.get_affected_cells(actor.grid_cell, actor.grid_cell, stomp, battle._get_wall_cells()), "battle hover area matches execution geometry")
	await _capture("battle_stomp_preview")
	battle._cancel_ability_targeting()
	battle._on_ability_selected(taunt)
	check(battle._ability_target_cells.keys() == [actor.grid_cell], "Taunt uses caster-only battle targeting")
	battle._update_ability_hover(actor.global_position + Vector2(0, -85))
	await _capture("taunt_preview")
	battle._cancel_ability_targeting()
	check(await battle._ability_executor.execute(actor, taunt, actor.grid_cell, battle._characters, battle.grid, battle._ability_targeting), "Taunt executes against real battle units")
	actor.reset_ability_action()
	battle._refresh_ability_bar()
	battle._on_ability_selected(load("res://resources/abilities/multi_attack.tres"))
	battle._update_ability_hover(battle._characters[2].global_position + Vector2(0, -85))
	await _capture("multi_attack_and_taunted")
	battle._cancel_ability_targeting()
	var payload := battle.capture_save_payload(false)
	var validated := ScenarioSaveStore.validate_payload(payload)
	check(validated.ok, "battle save validates with taunt source metadata")
	var enemy := battle._characters[2]
	enemy.remove_status(&"taunted")
	var decoy := battle._characters[0]
	decoy.set_grid_cell_immediate(Vector2i(7, 4))
	actor.set_grid_cell_immediate(Vector2i(2, 8))
	battle.turn_manager.current_unit = enemy
	battle.turn_manager.current_index = battle.turn_manager.turn_order.find(enemy)
	enemy.movement_animation_speed = 10000.0
	enemy.reset_ability_action()
	enemy.reset_movement()
	for unit in battle._characters:
		unit.spend_opportunity_reaction()
	var stale_plan := EnemyTurnPlan.new()
	stale_plan.sequence = EnemyTurnPlan.Sequence.MOVE_CAST
	stale_plan.ability = strike
	stale_plan.target_cell = decoy.grid_cell
	stale_plan.pre_cast_path = [enemy.grid_cell, Vector2i(6, 4)]
	var before := decoy.current_health
	enemy.cell_entered.connect(func(_unit, _cell): enemy.apply_status(taunted, taunt, actor), CONNECT_ONE_SHOT)
	check(not await battle._execute_enemy_plan(enemy, stale_plan), "execution rejects old target when movement applies Taunt")
	check(enemy.grid_cell == Vector2i(6, 4) and enemy.ability_available and decoy.current_health == before, "revalidation happens after movement and before action consumption")
	battle.shutdown_battle()
	battle.free()
	await process_frame
