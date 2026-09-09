extends SceneTree

const DIRECTORY := "res://.godot/ram_validation"
var failures: Array[String] = []
var checks := 0
var arena: Node2D
var grid: IsometricGrid
var targeting: AbilityTargeting
var executor: AbilityExecutor
var units: Array[TacticalCharacter] = []
var ram: AbilityDefinition
var strike: AbilityDefinition
var started: Array[TacticalCharacter] = []


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	ram = load("res://resources/abilities/ram.tres")
	strike = load("res://resources/abilities/strike.tres")
	for ability in [ram, strike]:
		ability.melee_lunge_duration = 0.02
		ability.melee_return_duration = 0.02
		ability.melee_slash_duration = 0.02
	arena = Node2D.new()
	root.add_child(arena)
	grid = IsometricGrid.new()
	grid.grid_size = Vector2i(10, 10)
	arena.add_child(grid)
	targeting = AbilityTargeting.new(grid.grid_size)
	executor = AbilityExecutor.new()
	arena.add_child(executor)
	executor.ability_started.connect(func(caster, _ability, _cell):
		started.append(caster)
		check(executor.is_resolving(), "every attack starts inside resolution")
	)
	_test_resources()
	await _test_directions_and_equipment()
	await _test_collisions()
	await _test_special_targets()
	await _test_counters()
	await _test_removal()
	await _test_reusable_effect()
	await _test_ai_and_effective_strength()
	_clear()
	arena.free()
	await _test_battle_ui()
	for failure in failures:
		push_error(failure)
	print("RAM_TESTS_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _unit(friendly: bool, cell: Vector2i) -> TacticalCharacter:
	var unit := TacticalCharacter.new()
	unit.name = "RamUnit%d" % units.size()
	unit.scenario_unit_id = unit.name
	unit.definition = CharacterDefinition.new()
	unit.definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	unit.definition.constitution = 50
	unit.definition.strength = 5
	unit.definition.movement_range = 4.0
	unit.starting_grid_cell = cell
	unit.override_template_abilities = true
	unit.ability_overrides = [ram, strike]
	unit.use_complete_equipment_override = true
	var weapon := ItemDefinition.new()
	weapon.weapon_damage = 4
	unit.complete_equipment_overrides = [weapon]
	unit.movement_animation_speed = 10000.0
	arena.add_child(unit)
	unit.initialize(grid)
	unit.reset_movement()
	unit.reset_ability_action()
	unit.reset_opportunity_reaction()
	units.append(unit)
	return unit


func _clear() -> void:
	for unit in units:
		if is_instance_valid(unit):
			unit.free()
	units.clear()
	started.clear()


func _armor(unit: TacticalCharacter, amount: int) -> void:
	var item := ItemDefinition.new()
	item.slot = ItemDefinition.EquipmentSlot.ARMOR
	item.armor = amount
	unit.equip_item(item)


func _forecast(caster: TacticalCharacter, cell: Vector2i, walls: Dictionary = {}, ability: AbilityDefinition = ram) -> AIBoardSnapshot:
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size, walls)
	var planner := EnemyAIPlanner.new()
	planner._prepare_decision(caster, snapshot, units)
	planner._forecast_ability(caster, ability, cell, snapshot, targeting, EnemyAIProfile.new())
	return snapshot


func _matches(snapshot: AIBoardSnapshot, label: String) -> void:
	for unit in units:
		if is_instance_valid(unit):
			check(unit.current_health == snapshot.get_health(unit), label + " health " + str(unit.name))
			check(unit.current_armor == snapshot.get_armor(unit), label + " armor " + str(unit.name))
			check(unit.grid_cell == snapshot.get_cell(unit), label + " cell " + str(unit.name))
	check(not executor.is_resolving(), label + " resolution completes")


func _preview(caster: TacticalCharacter, target: TacticalCharacter, walls: Dictionary = {}) -> Array[Dictionary]:
	return EnemyAIPlanner.new().get_knockback_preview(caster, ram, target.grid_cell,
		AIBoardSnapshot.from_battle(units, grid.grid_size, walls), targeting)


func _test_resources() -> void:
	var warrior := load("res://resources/classes/warrior.tres") as CharacterClassDefinition
	var actor := _unit(true, Vector2i(4, 4))
	actor.override_template_abilities = false
	actor.definition.starting_class = warrior
	for level in range(1, 10):
		actor.set_class_level(warrior, level)
		check(actor.get_abilities().has(ram) == (level >= 8), "Ram unlock level %d" % level)
	actor.set_class_level(warrior, 7)
	var enemy := _unit(false, Vector2i(4, 3))
	check(not executor.can_execute(actor, ram, enemy.grid_cell, units, grid, targeting), "locked Ram cannot execute")
	check((load("res://resources/dev_tool_catalog.tres") as DevToolCatalog).abilities.has(ram), "Ram in developer catalog")
	check(ram.effects.size() == 1 and ram.effects[0] is KnockbackEffectDefinition, "Ram authors a reusable knockback")
	check(ram.get_description(actor).contains("100%") and ram.get_description(actor).contains("armor applies"), "tooltip explains formula and collision")
	check(ResourceSaver.save(ram, DIRECTORY + "/ram.tres") == OK, "Ram resource saves")
	var restored := ResourceLoader.load(DIRECTORY + "/ram.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as AbilityDefinition
	check(restored.effects[0] is KnockbackEffectDefinition and restored.effects[0].distance == 2 and restored.effects[0].collision_damage == 1, "knockback settings survive reload")
	check(not restored.requires_weapon and restored.range == 1 and not restored.accepts_weapon_range_bonus, "Ram targeting settings survive reload")
	_clear()


func _test_directions_and_equipment() -> void:
	for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		for equipment in ["melee", "ranged", "unarmed"]:
			var actor := _unit(true, Vector2i(4, 4))
			var target := _unit(false, actor.grid_cell + direction)
			var ally := _unit(true, actor.grid_cell - direction)
			if equipment == "unarmed":
				actor.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, null)
			else:
				actor.get_equipped_weapon().weapon_type = ItemDefinition.WeaponType.RANGED if equipment == "ranged" else ItemDefinition.WeaponType.MELEE
				actor.get_equipped_weapon().weapon_damage = 999
				actor.get_equipped_weapon().weapon_range_bonus = 3
				actor.get_equipped_weapon().status_effect = load("res://resources/statuses/slow.tres")
			var pack := load("res://resources/passives/pack_tactics.tres") as PassiveAbilityDefinition
			actor.set_dev_passive_loadout([pack])
			ally.set_dev_passive_loadout([pack])
			check(ram.calculate_damage(actor) == 5, "Ram excludes all weapon contributions " + equipment)
			check(targeting.get_valid_target_cells(actor, ram, units).keys() == [target.grid_cell], "only adjacent enemy is targetable")
			for invalid in [actor.grid_cell, ally.grid_cell, actor.grid_cell + Vector2i(1, 1), actor.grid_cell + direction * 2]:
				check(not executor.can_execute(actor, ram, invalid, units, grid, targeting), "reject invalid Ram target " + str(invalid))
			var preview := _preview(actor, target)
			check(preview.size() == 1 and preview[0].landing == actor.grid_cell + direction * 3 and preview[0].path.size() == 3, "preview traces two tiles")
			var hp := target.current_health
			var facing := target.current_facing
			var movement := actor.remaining_movement
			var target_movement := target.remaining_movement
			var start := target.starting_grid_cell
			var entries := [0]
			var passive_refreshes := [0]
			target.cell_entered.connect(func(_unit, _cell): entries[0] += 1)
			target.passive_context_changed.connect(func(): passive_refreshes[0] += 1)
			var snapshot := _forecast(actor, target.grid_cell)
			check(await executor.execute(actor, ram, target.grid_cell, units, grid, targeting), "Ram executes " + equipment + str(direction))
			check(target.current_health == hp - 5 and target.get_active_statuses().is_empty(), "Strength damage only, no weapon status")
			check(target.grid_cell == start + direction * 2 and actor.grid_cell == Vector2i(4, 4), "push target, caster stays")
			check(passive_refreshes[0] >= 2, "each pushed tile refreshes positional passives")
			check(entries[0] == 0 and target.starting_grid_cell == start and target.current_facing == facing, "forced movement preserves setup/facing and skips entry signals")
			check(not actor.ability_available and actor.remaining_movement == movement and actor.opportunity_reaction_available, "caster spends only action")
			check(target.ability_available and target.remaining_movement == target_movement and target.opportunity_reaction_available, "target budgets unchanged")
			var saved := target.capture_runtime_state()
			target.set_forced_grid_cell(start)
			target.restore_runtime_state(saved, {target.scenario_unit_id: target})
			check(target.grid_cell == start + direction * 2 and target.current_health == hp - 5, "runtime save restores displaced cell and damage")
			_matches(snapshot, "open push")
			_clear()


func _test_collisions() -> void:
	for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		for step in [1, 2]:
			for obstruction in ["wall", "ally", "enemy", "edge"]:
				var origin := Vector2i(4, 4)
				if obstruction == "edge":
					if direction.x != 0:
						origin.x = (9 - step) if direction.x > 0 else step
					else:
						origin.y = (9 - step) if direction.y > 0 else step
				var actor := _unit(true, origin)
				var target := _unit(false, origin + direction)
				var block_cell: Vector2i = target.grid_cell + direction * step
				var walls := {block_cell: true} if obstruction == "wall" else {}
				var blocker: TacticalCharacter
				if obstruction in ["ally", "enemy"]:
					blocker = _unit(obstruction == "ally", block_cell)
					blocker.current_health = 1
				_armor(target, 5)
				var hp := target.current_health
				var preview := _preview(actor, target, walls)
				check(preview.size() == 1 and preview[0].collided and preview[0].collision_cell == block_cell and preview[0].landing == block_cell - direction, "collision preview " + obstruction)
				var snapshot := _forecast(actor, target.grid_cell, walls)
				check(await executor.execute(actor, ram, target.grid_cell, units, grid, targeting, walls), "blocked Ram executes")
				check(target.grid_cell == block_cell - direction and target.current_health == hp - 1 and target.current_armor == 0, "one collision after armor absorbs main hit")
				if blocker != null:
					check(blocker.current_health == 0 and blocker.grid_cell == block_cell, "blocker takes damage without moving; lethal blocker stops push")
				_matches(snapshot, "collision " + obstruction)
				_clear()
	var actor := _unit(true, Vector2i(4, 4))
	var target := _unit(false, Vector2i(5, 4))
	var blocker := _unit(false, Vector2i(6, 4))
	_armor(target, 6)
	_armor(blocker, 1)
	var snapshot := _forecast(actor, target.grid_cell)
	await executor.execute(actor, ram, target.grid_cell, units, grid, targeting)
	check(target.current_health == target.get_max_health() and blocker.current_health == blocker.get_max_health(), "armor absorbs both collision damage pools")
	check(target.current_armor == 0 and blocker.current_armor == 0, "collision consumes exactly one armor on each")
	_matches(snapshot, "armored collision")
	_clear()


func _test_special_targets() -> void:
	for kind in ["stunned", "killed", "reassemble", "bone_pile", "collision_kill"]:
		var actor := _unit(true, Vector2i(4, 4))
		var target := _unit(false, Vector2i(5, 4))
		if kind == "stunned":
			target.apply_status(load("res://resources/statuses/stun.tres"))
		if kind in ["reassemble", "bone_pile"]:
			target.set_dev_passive_loadout([load("res://resources/passives/reassemble.tres")])
			target.current_health = 1
			if kind == "bone_pile":
				target.apply_damage(1)
				_armor(target, 5)
		if kind == "killed":
			target.current_health = 5
		if kind == "collision_kill":
			target.current_health = 6
		var walls := {Vector2i(7, 4): true} if kind == "collision_kill" else {}
		var preview := _preview(actor, target, walls)
		check(preview.is_empty() == (kind == "killed"), "preview handles death/reassembly " + kind)
		var snapshot := _forecast(actor, target.grid_cell, walls)
		await executor.execute(actor, ram, target.grid_cell, units, grid, targeting, walls)
		var expected := Vector2i(5, 4) if kind == "killed" else (Vector2i(6, 4) if kind == "collision_kill" else Vector2i(7, 4))
		check(target.grid_cell == expected, "forced movement eligibility " + kind)
		if kind in ["killed", "collision_kill"]:
			check(target.current_health == 0, "lethal damage " + kind)
		if kind in ["reassemble", "bone_pile"]:
			check(target.is_bone_pile and target.current_health == 1, "living bones displaced")
		_matches(snapshot, kind)
		_clear()


func _test_counters() -> void:
	for kind in ["escaped", "blocked", "reach", "stunned", "blocker_only"]:
		var actor := _unit(true, Vector2i(4, 4))
		var target := _unit(false, Vector2i(5, 4))
		var status := load("res://resources/statuses/counter.tres") as StatusEffectDefinition
		var walls := {Vector2i(6, 4): true} if kind == "blocked" else {}
		if kind == "blocker_only":
			var blocker := _unit(false, Vector2i(6, 4))
			blocker.apply_status(status)
			blocker.get_equipped_weapon().weapon_range_bonus = 4
		else:
			target.apply_status(status)
		if kind == "reach":
			target.get_equipped_weapon().weapon_range_bonus = 2
		if kind == "stunned":
			target.apply_status(load("res://resources/statuses/stun.tres"))
			walls = {Vector2i(6, 4): true}
		var snapshot := _forecast(actor, target.grid_cell, walls)
		await executor.execute(actor, ram, target.grid_cell, units, grid, targeting, walls)
		var retaliates: bool = kind in ["blocked", "reach"]
		check(started.size() == (2 if retaliates else 1), "Counter revalidates final position and original defender " + kind)
		check(actor.current_health == actor.get_max_health() - (9 if retaliates else 0), "Counter damage " + kind)
		check(target._opportunity_reaction_available and target._ability_available, "Counter preserves stored target budgets, including during stun")
		_matches(snapshot, "counter " + kind)
		_clear()


func _interrupt_target(target: TacticalCharacter, kind: String) -> void:
	await create_timer(0.01).timeout
	if kind == "death":
		target.apply_damage(9999)
	elif kind == "roster":
		units.erase(target)
	else:
		units.erase(target)
		target.free()


func _test_removal() -> void:
	for kind in ["death", "roster", "free"]:
		var actor := _unit(true, Vector2i(4, 4))
		var target := _unit(false, Vector2i(5, 4))
		target.movement_started.connect(func(unit): _interrupt_target(unit, kind), CONNECT_ONE_SHOT)
		check(await executor.execute(actor, ram, target.grid_cell, units, grid, targeting), "interrupted push returns " + kind)
		check(not executor.is_resolving(), "interrupted push releases resolution " + kind)
		if is_instance_valid(target):
			check(not target.is_moving and target.grid_cell == Vector2i(5, 4), "interrupted step does not commit")
			if not units.has(target):
				target.free()
		_clear()


func _test_caster_removal() -> void:
	var actor := _unit(true, Vector2i(4, 4))
	var target := _unit(false, Vector2i(5, 4))
	target.movement_started.connect(func(_unit): _interrupt_target(actor, "free"), CONNECT_ONE_SHOT)
	await executor.execute(actor, ram, target.grid_cell, units, grid, targeting)
	check(not executor.is_resolving() and target.grid_cell == Vector2i(7, 4), "caster removal during impact cannot strand an already-started push")
	_clear()


func _test_reusable_effect() -> void:
	await _test_caster_removal()
	for delivery in [AbilityDefinition.DeliveryType.CAST_ON_TARGET, AbilityDefinition.DeliveryType.PROJECTILE]:
		var actor := _unit(true, Vector2i(4, 4))
		var target := _unit(false, Vector2i(5, 4))
		var custom := ram.duplicate(true) as AbilityDefinition
		custom.delivery_type = delivery
		custom.projectile_speed = 10000
		custom.effects[0].distance = 3
		custom.effects[0].collision_damage = 2
		actor.ability_overrides.append(custom)
		var walls := {Vector2i(8, 4): true}
		var snapshot := _forecast(actor, target.grid_cell, walls, custom)
		await executor.execute(actor, custom, target.grid_cell, units, grid, targeting, walls)
		check(target.grid_cell == Vector2i(7, 4) and target.current_health == target.get_max_health() - 7, "custom knockback settings and awaited delivery")
		_matches(snapshot, "custom delivery")
		_clear()


func _test_ai_and_effective_strength() -> void:
	for friendly_blocker in [true, false]:
		var actor := _unit(false, Vector2i(4, 4))
		var target := _unit(true, Vector2i(5, 4))
		var blocker := _unit(friendly_blocker, Vector2i(6, 4))
		actor.apply_status(load("res://resources/statuses/empowered.tres"))
		actor.ability_overrides = [ram]
		actor._remaining_movement = 0
		check(ram.calculate_damage(actor) == 6, "Ram uses status-modified effective Strength")
		var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size, {}, {Vector2i(6, 4): load("res://resources/tiles/fire.tres")})
		var planner := EnemyAIPlanner.new()
		planner._prepare_decision(actor, snapshot, units)
		var score := planner._forecast_ability(actor, ram, target.grid_cell, snapshot, targeting, EnemyAIProfile.new())
		check(score == (8.0 if friendly_blocker else 5.0), "AI scores collision damage by faction")
		check(snapshot.get_health(blocker) == blocker.current_health - 1, "AI applies collateral damage")
		check(not planner._is_valid_primary_target(actor, actor.grid_cell, Vector2i(5, 5), ram, snapshot, targeting), "AI rejects diagonal Ram")
		var plan := planner.choose_plan(actor, units, GridPathfinder.new(grid.grid_size), targeting)
		check(plan.ability == ram and plan.target_cell == target.grid_cell, "AI can choose valid Ram")
		await executor.execute(actor, ram, target.grid_cell, units, grid, targeting)
		_matches(snapshot, "AI Strength/collision")
		_clear()
	var actor := _unit(true, Vector2i(4, 4))
	var target := _unit(false, Vector2i(5, 4))
	var fire := load("res://resources/tiles/fire.tres") as TileDefinition
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size, {}, {Vector2i(6, 4): fire, Vector2i(7, 4): fire})
	var planner := EnemyAIPlanner.new()
	planner._forecast_ability(actor, ram, target.grid_cell, snapshot, targeting, EnemyAIProfile.new())
	check(snapshot.get_health(target) == target.current_health - 5 and snapshot.unit_statuses[target].is_empty(), "AI forced movement skips terrain triggers")
	planner._forecast_terrain_trigger(target, TileTriggeredEffectDefinition.Trigger.TURN_START, snapshot, EnemyAIProfile.new())
	check(not snapshot.unit_statuses[target].is_empty(), "AI still forecasts later turn-start terrain")
	actor.apply_status(load("res://resources/statuses/stun.tres"))
	check(not executor.can_execute(actor, ram, target.grid_cell, units, grid, targeting), "stunned caster cannot Ram")
	_clear()


func _test_battle_ui() -> void:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	root.add_child(battle)
	check(battle.initialization_succeeded, "battle initializes")
	battle.set_process(false)
	var actor := battle._characters[1]
	var target := battle._characters[2]
	var blocker := battle._characters[3]
	for index in range(battle._characters.size()):
		battle._characters[index].set_grid_cell_immediate(Vector2i(index, 8))
	actor.set_grid_cell_immediate(Vector2i(4, 4))
	target.set_grid_cell_immediate(Vector2i(5, 4))
	blocker.set_grid_cell_immediate(Vector2i(7, 4))
	target.current_health = target.get_max_health()
	actor.set_class_level(load("res://resources/classes/warrior.tres"), 8)
	for entry in actor.get_class_levels():
		if entry.character_class.class_id != &"warrior":
			actor.set_class_level(entry.character_class, 0)
	actor.reset_ability_action()
	actor.reset_movement()
	battle.turn_manager.current_unit = actor
	battle.turn_manager.current_index = battle.turn_manager.turn_order.find(actor)
	battle._on_turn_started(actor)
	battle._refresh_ability_bar()
	var buttons := battle.ability_bar.get_node("Margin/HBox")
	check(buttons.get_child_count() == 8, "battle bar shows Ram as eighth warrior ability")
	check((buttons.get_child(7) as Button).tooltip_text.contains("No chain push"), "Ram tooltip explains knockback")
	battle._on_ability_selected(ram)
	check(battle._ability_target_cells.has(target.grid_cell), "Ram selectable through battle UI")
	battle._update_ability_hover(target.global_position + Vector2(0, -85))
	check(battle.grid._ability_trajectory_cells == [Vector2i(5, 4), Vector2i(6, 4)], "hover shows actual blocked path")
	check(battle.grid._ability_area_cells.has(Vector2i(6, 4)) and battle.grid._ability_area_cells.has(blocker.grid_cell), "hover marks landing and colliding unit")
	if DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().has("--capture"):
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(DIRECTORY + "/ram_preview.png") == OK, "capture Ram UI")
	battle._cancel_ability_targeting()
	var fire := load("res://resources/tiles/fire.tres") as TileDefinition
	var terrain := TacticalTerrain.new()
	battle.add_child(terrain)
	for cell in [Vector2i(6, 4), Vector2i(7, 4)]:
		var tile := TacticalTile.new()
		tile.grid_cell = cell
		tile.definition = fire
		terrain.add_child(tile)
	terrain.initialize(battle.grid)
	target.cell_entered.connect(func(unit, _cell): terrain.apply_trigger(unit, TileTriggeredEffectDefinition.Trigger.ENTER))
	blocker.set_grid_cell_immediate(Vector2i(5, 3))
	blocker.reset_opportunity_reaction()
	var initial_reaction := blocker.opportunity_reaction_available
	var target_hp := target.current_health
	var saved_turn := battle.turn_manager.current_unit
	var moving_checks := [0]
	target.movement_started.connect(func(_unit):
		moving_checks[0] += 1
		check(battle._ability_executor.is_resolving() and not battle._is_dev_stable(), "save boundary covers push")
		check(battle.turn_manager.current_unit == saved_turn, "turn does not advance during push")
	)
	check(await battle._ability_executor.execute(actor, ram, target.grid_cell, battle._characters, battle.grid, battle._ability_targeting, battle._get_wall_cells()), "Ram executes in real battle")
	check(moving_checks[0] == 1 and target.grid_cell == Vector2i(7, 4), "battle push completes")
	check(target.current_health == target_hp - ram.calculate_damage(actor) and target.get_active_statuses().is_empty(), "no terrain damage/status or opportunity attack while pushed")
	check(blocker.opportunity_reaction_available == initial_reaction, "nearby enemy retains opportunity reaction")
	var payload := battle.capture_save_payload(false)
	check(ScenarioSaveStore.validate_payload(payload).ok, "battle Ram save validates")
	target.set_forced_grid_cell(Vector2i(5, 4))
	check(battle._restore_runtime_state(payload.runtime) and target.grid_cell == Vector2i(7, 4), "battle save restores knockback result")
	terrain.apply_trigger(target, TileTriggeredEffectDefinition.Trigger.TURN_START)
	target.process_status_turn_start()
	check(target.current_health == target_hp - ram.calculate_damage(actor) - 1, "normal next-turn terrain still applies")
	# Both last enemies die to one collision; finalization waits for the return animation.
	for unit in battle._characters:
		if not unit.is_friendly() and unit != target and unit != blocker:
			unit.current_health = 0
	target.current_health = ram.calculate_damage(actor) + 1
	target.set_dev_equipment(ItemDefinition.EquipmentSlot.ARMOR, null)
	target.set_grid_cell_immediate(Vector2i(5, 4))
	blocker.current_health = 1
	blocker.set_dev_equipment(ItemDefinition.EquipmentSlot.ARMOR, null)
	blocker.set_grid_cell_immediate(Vector2i(7, 4))
	actor.reset_ability_action()
	var finalization_checks := [0]
	battle._ability_executor.melee_delivery.melee_finished.connect(func(_caster, _ability, _cell):
		finalization_checks[0] += 1
		battle._finalize_combat()
		check(battle._combat_over and not battle._combat_finalized and battle._ability_executor.is_resolving(), "collision defeat waits for complete melee resolution")
	)
	await battle._ability_executor.execute(actor, ram, target.grid_cell, battle._characters, battle.grid, battle._ability_targeting, battle._get_wall_cells())
	battle._finalize_combat()
	check(finalization_checks[0] == 1 and battle._combat_finalized and target.current_health == 0 and blocker.current_health == 0, "battle finalizes after both collision casualties")
	battle.queue_free()
	await process_frame
	await process_frame
