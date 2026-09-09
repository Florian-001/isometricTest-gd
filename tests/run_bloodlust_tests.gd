extends SceneTree

const DIRECTORY := "res://.godot/bloodlust_validation"
var failures: Array[String] = []
var checks := 0
var arena: Node2D
var grid: IsometricGrid
var targeting: AbilityTargeting
var executor: AbilityExecutor
var units: Array[TacticalCharacter] = []
var bloodlust: AbilityDefinition
var reward: StatusEffectDefinition
var serial := 0


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	bloodlust = load("res://resources/abilities/bloodlust.tres")
	reward = load("res://resources/statuses/strength_up.tres")
	arena = Node2D.new()
	root.add_child(arena)
	grid = IsometricGrid.new()
	grid.grid_size = Vector2i(10, 10)
	arena.add_child(grid)
	targeting = AbilityTargeting.new(grid.grid_size)
	executor = AbilityExecutor.new()
	arena.add_child(executor)
	_test_resources_and_targeting()
	await _test_damage_and_rewards()
	await _test_stacking_and_saves()
	await _test_removal_and_reassemble()
	await _test_reusable_rewards()
	await _test_reaction_and_dot_exclusions()
	_clear()
	arena.free()
	await _test_battle_ui_and_cleanup()
	for failure in failures:
		push_error(failure)
	print("BLOODLUST_TESTS_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _fast_ability() -> AbilityDefinition:
	var ability := bloodlust.duplicate() as AbilityDefinition
	ability.melee_lunge_duration = 0.02
	ability.melee_return_duration = 0.02
	ability.melee_slash_duration = 0.02
	return ability


func _unit(friendly: bool, cell: Vector2i, ability: AbilityDefinition = null) -> TacticalCharacter:
	var unit := TacticalCharacter.new()
	serial += 1
	unit.name = "BloodlustTest%d" % serial
	unit.scenario_unit_id = unit.name
	unit.definition = CharacterDefinition.new()
	unit.definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	unit.definition.constitution = 20
	unit.definition.strength = 5
	unit.definition.movement_range = 4.0
	unit.starting_grid_cell = cell
	unit.override_template_abilities = true
	unit.ability_overrides = [ability if ability != null else bloodlust]
	unit.use_complete_equipment_override = true
	var weapon := ItemDefinition.new()
	weapon.weapon_damage = 4
	unit.complete_equipment_overrides = [weapon]
	arena.add_child(unit)
	unit.initialize(grid)
	unit.reset_ability_action()
	unit.reset_movement()
	units.append(unit)
	return unit


func _armor(unit: TacticalCharacter, amount: int) -> void:
	var item := ItemDefinition.new()
	item.slot = ItemDefinition.EquipmentSlot.ARMOR
	item.armor = amount
	unit.set_dev_equipment(ItemDefinition.EquipmentSlot.ARMOR, item)


func _stacks(unit: TacticalCharacter) -> int:
	for status in unit.get_active_statuses():
		if status.definition.status_id == reward.status_id:
			return status.stack_count
	return 0


func _clear() -> void:
	for unit in units:
		if is_instance_valid(unit):
			unit.free()
	units.clear()


func _forecast(caster: TacticalCharacter, ability: AbilityDefinition, cell: Vector2i) -> Dictionary:
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
	var live := caster.capture_runtime_state()
	var score := EnemyAIPlanner.new()._forecast_ability(caster, ability, cell, snapshot, targeting, EnemyAIProfile.new())
	check(caster.capture_runtime_state() == live, "forecast preserves live caster state")
	return {"snapshot": snapshot, "score": score}


func _matches(snapshot: AIBoardSnapshot) -> void:
	for unit in units:
		if not is_instance_valid(unit):
			continue
		check(snapshot.get_health(unit) == unit.current_health and snapshot.get_armor(unit) == unit.current_armor, "forecast matches health and armor")
		check(snapshot.get_effective_stat(unit, UnitStat.Type.STRENGTH) == unit.get_effective_stat(UnitStat.Type.STRENGTH), "forecast matches effective Strength")
		check(int(snapshot.get_status_state(unit, reward.status_id).get("stack_count", 0)) == _stacks(unit), "forecast matches reward stacks")


func _test_resources_and_targeting() -> void:
	var defaults := AbilityDefinition.new()
	check(defaults.on_kill_status == null and defaults.on_kill_status_stacks == 1, "existing abilities default to no reward")
	check(bloodlust.display_name == "Bloodlust" and bloodlust.on_kill_status == reward and bloodlust.on_kill_status_stacks == 2, "Bloodlust configures two shared Strength Up stacks")
	check(bloodlust.get_hit_count() == 1 and bloodlust.get_effective_area_span() == 1 and not bloodlust.moves_caster(), "one stationary single-target hit")
	check(bloodlust.get_description().contains("On kill: caster gains Strength Up ×2") and bloodlust.get_description().contains("Until battle ends"), "description includes caster, condition, count and lifetime")
	var warrior := load("res://resources/classes/warrior.tres") as CharacterClassDefinition
	var actor := _unit(true, Vector2i(4, 4))
	actor.definition.starting_class = warrior
	actor.override_template_abilities = false
	check(not actor.get_abilities().has(bloodlust), "Warrior 1 excludes Bloodlust")
	actor.set_class_level(warrior, 2)
	check(actor.get_abilities().map(func(a: AbilityDefinition): return a.display_name) == ["Strike", "Charge", "Bloodlust"], "Warrior 2 orders Bloodlust after Charge")
	check((load("res://resources/dev_tool_catalog.tres") as DevToolCatalog).abilities.count(bloodlust) == 1, "developer catalog has one Bloodlust")
	check(bloodlust.calculate_damage(actor) == 9, "four weapon damage plus five Strength")
	check(not executor.can_execute(actor, bloodlust, Vector2i(5, 4), units, grid, targeting), "empty adjacent cell rejected")
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, -1)]:
		var target := _unit(false, actor.grid_cell + offset)
		check(executor.can_execute(actor, bloodlust, target.grid_cell, units, grid, targeting), "adjacent target accepted %s" % offset)
	var far := _unit(false, Vector2i(6, 4))
	check(not executor.can_execute(actor, bloodlust, far.grid_cell, units, grid, targeting), "distance two rejected")
	check(not executor.can_execute(actor, bloodlust, Vector2i(2, 2), units, grid, targeting), "empty target rejected")
	check(not executor.can_execute(actor, bloodlust, actor.grid_cell, units, grid, targeting), "self rejected")
	var ally := _unit(true, Vector2i(3, 4))
	check(not targeting._matches_unit_flag(actor, ally, bloodlust), "allies excluded")
	check(not executor.can_execute(actor, bloodlust, Vector2i(5, 5), units, grid, targeting, {Vector2i(5, 4): true}), "blocked diagonal corner rejected")
	actor.get_equipped_weapon().weapon_range_bonus = 3.0
	check(not executor.can_execute(actor, bloodlust, far.grid_cell, units, grid, targeting) and bloodlust.get_effective_range(actor) == 1.414, "weapon reach never extends Bloodlust")
	actor.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, null)
	check(not bloodlust.can_be_used_by(actor), "unarmed warrior cannot use Bloodlust")
	actor.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, load("res://resources/items/weapons/goblin_bow.tres"))
	check(not bloodlust.can_be_used_by(actor), "ranged equipment rejected")
	check(ResourceSaver.save(bloodlust, DIRECTORY + "/ability.tres") == OK, "ability resource saves")
	var restored := ResourceLoader.load(DIRECTORY + "/ability.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as AbilityDefinition
	check(restored.on_kill_status == reward and restored.on_kill_status_stacks == 2, "Inspector properties survive resource reload")
	_clear()


func _test_damage_and_rewards() -> void:
	for scenario in [[20, 0, false], [9, 0, true], [1, 0, true], [1, 9, false], [5, 4, true], [6, 4, false]]:
		var ability := _fast_ability()
		var caster := _unit(true, Vector2i(4, 4), ability)
		var target := _unit(false, Vector2i(5, 4))
		target.current_health = scenario[0]
		_armor(target, scenario[1])
		var forecast := _forecast(caster, ability, target.grid_cell)
		var no_reward := ability.duplicate() as AbilityDefinition
		no_reward.on_kill_status = null
		var plain := _forecast(caster, no_reward, target.grid_cell)
		check(is_equal_approx(forecast.score - plain.score, 4.0 if scenario[2] else 0.0), "AI values two stacks only for an actual kill")
		var movement := caster.remaining_movement
		check(await executor.execute(caster, ability, target.grid_cell, units, grid, targeting), "valid Bloodlust executes")
		check(_stacks(caster) == (2 if scenario[2] else 0), "reward matches lethal outcome %s" % str(scenario))
		check(not caster.ability_available and caster.remaining_movement == movement and caster.grid_cell == Vector2i(4, 4), "cast spends only one ability action")
		check(not await executor.execute(caster, ability, target.grid_cell, units, grid, targeting), "spent action cannot cast again")
		_matches(forecast.snapshot)
		_clear()
	var caster := _unit(true, Vector2i(4, 4))
	var ally := _unit(true, Vector2i(4, 5))
	var pack := load("res://resources/passives/pack_tactics.tres") as PassiveAbilityDefinition
	caster.set_dev_passive_loadout([pack])
	ally.set_dev_passive_loadout([pack])
	check(bloodlust.calculate_damage(caster) == 10, "normal passive weapon damage contributes")
	_clear()


func _test_stacking_and_saves() -> void:
	var ability := _fast_ability()
	var caster := _unit(true, Vector2i(4, 4), ability)
	caster.apply_status(reward)
	for index in range(2):
		var target := _unit(false, Vector2i(5, 4))
		target.current_health = ability.calculate_damage(caster)
		var forecast := _forecast(caster, ability, target.grid_cell)
		caster.reset_ability_action()
		await executor.execute(caster, ability, target.grid_cell, units, grid, targeting)
		check(_stacks(caster) == 3 + index * 2, "each cast adds two to existing stacks")
		_matches(forecast.snapshot)
		units.erase(target)
		target.free()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(caster.capture_runtime_state()))
	caster.remove_status(reward.status_id)
	caster.restore_runtime_state(saved, {caster.scenario_unit_id: caster})
	check(_stacks(caster) == 5 and caster.get_effective_stat(UnitStat.Type.STRENGTH) == 10, "runtime save restores earned stacks and Strength")
	for turn in range(3):
		caster.expire_turn_start_statuses()
		caster.process_status_turn_start()
		caster.advance_status_durations()
	check(_stacks(caster) == 5, "earned stacks survive owner turns")
	caster.remove_negative_statuses()
	check(_stacks(caster) == 5, "Cleanse preserves reward")
	check(caster.remove_battle_end_statuses() == 1 and _stacks(caster) == 0, "battle cleanup removes entire stack")
	_clear()


func _test_removal_and_reassemble() -> void:
	var ability := _fast_ability()
	var caster := _unit(true, Vector2i(4, 4), ability)
	var target := _unit(false, Vector2i(5, 4))
	target.current_health = 1
	target.defeated.connect(func(unit):
		units.erase(unit)
		unit.queue_free()
	)
	check(await executor.execute(caster, ability, target.grid_cell, units, grid, targeting), "defeat callback can remove target")
	check(_stacks(caster) == 2 and not is_instance_valid(target), "removed target still awards exactly two stacks")
	_clear()
	caster = _unit(true, Vector2i(4, 4), ability)
	target = _unit(false, Vector2i(5, 4))
	target.set_dev_passive_loadout([load("res://resources/passives/reassemble.tres")])
	target.current_health = 1
	var forecast := _forecast(caster, ability, target.grid_cell)
	await executor.execute(caster, ability, target.grid_cell, units, grid, targeting)
	check(target.is_bone_pile and _stacks(caster) == 0, "collapse is not defeat")
	_matches(forecast.snapshot)
	caster.reset_ability_action()
	forecast = _forecast(caster, ability, target.grid_cell)
	await executor.execute(caster, ability, target.grid_cell, units, grid, targeting)
	check(target.current_health == 0 and _stacks(caster) == 2, "destroying bone pile awards reward")
	_matches(forecast.snapshot)
	_clear()


func _test_reusable_rewards() -> void:
	# Area/multi-hit and legacy additional damage share the same per-defeat reward.
	for nested in [false, true]:
		var ability := _fast_ability()
		ability.delivery_type = AbilityDefinition.DeliveryType.CAST_ON_TARGET
		ability.caster_centered = true
		ability.range = 1.5
		ability.hit_count = 2
		if nested:
			ability.effect = AbilityDefinition.PrimaryEffect.NONE
			ability.effects = [DamageEffectDefinition.new()]
		var caster := _unit(true, Vector2i(4, 4), ability)
		var first := _unit(false, Vector2i(5, 4))
		var second := _unit(false, Vector2i(4, 5))
		first.current_health = 9
		second.current_health = 11
		var forecast := _forecast(caster, ability, caster.grid_cell)
		await executor.execute(caster, ability, caster.grid_cell, units, grid, targeting)
		check(first.current_health == 0 and second.current_health == 0 and _stacks(caster) == 4, "area kills award once each and strengthen subsequent damage")
		_matches(forecast.snapshot)
		_clear()
	var ability := _fast_ability()
	ability.hit_count = 2
	var caster := _unit(true, Vector2i(4, 4), ability)
	var target := _unit(false, Vector2i(5, 4))
	target.current_health = 18
	var forecast := _forecast(caster, ability, target.grid_cell)
	await executor.execute(caster, ability, target.grid_cell, units, grid, targeting)
	check(_stacks(caster) == 2, "second-hit kill awards one reward")
	_matches(forecast.snapshot)
	_clear()


func _test_reaction_and_dot_exclusions() -> void:
	var ability := _fast_ability()
	var caster := _unit(true, Vector2i(4, 4), ability)
	var target := _unit(false, Vector2i(5, 4))
	caster.set_dev_passive_loadout([load("res://resources/passives/counter.tres")])
	target.set_dev_passive_loadout([load("res://resources/passives/counter.tres")])
	var before := caster.current_health
	var forecast := _forecast(caster, ability, target.grid_cell)
	await executor.execute(caster, ability, target.grid_cell, units, grid, targeting)
	check(caster.current_health == before - 9 and _stacks(caster) == 0, "surviving target counters normally without a reward")
	_matches(forecast.snapshot)
	caster.reset_ability_action()
	target.current_health = 1
	before = caster.current_health
	await executor.execute(caster, ability, target.grid_cell, units, grid, targeting)
	check(caster.current_health == before and _stacks(caster) == 2, "killed defender cannot counter")
	_clear()
	caster = _unit(true, Vector2i(4, 4), ability)
	target = _unit(false, Vector2i(5, 4))
	var burning := load("res://resources/statuses/burning.tres") as StatusEffectDefinition
	caster.get_equipped_weapon().status_effect = burning
	target.current_health = 10
	await executor.execute(caster, ability, target.grid_cell, units, grid, targeting)
	check(target.current_health == 1 and not target.get_active_statuses().is_empty(), "surviving target receives normal weapon status")
	target.process_status_turn_start()
	check(target.current_health == 0 and _stacks(caster) == 0, "later weapon damage-over-time kill gives no reward")
	_clear()
	caster = _unit(true, Vector2i(4, 4), ability)
	target = _unit(false, Vector2i(5, 4))
	target.current_health = 1
	caster.set_dev_passive_loadout([load("res://resources/passives/counter.tres")])
	check(await executor.execute_counter_attack(caster, target, units, grid, targeting), "separate basic Counter can kill")
	check(target.current_health == 0 and _stacks(caster) == 0, "knowing Bloodlust does not reward a Counter kill")
	_clear()


func _test_battle_ui_and_cleanup() -> void:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	root.add_child(battle)
	for frame in range(4):
		await process_frame
	battle.set_process(false)
	var actor := battle._characters[1]
	var target := battle._characters[2]
	for index in range(battle._characters.size()):
		battle._characters[index].set_grid_cell_immediate(Vector2i(index, 8))
	actor.set_grid_cell_immediate(Vector2i(4, 4))
	target.set_grid_cell_immediate(Vector2i(5, 4))
	actor.set_class_level(load("res://resources/classes/warrior.tres"), 2)
	for entry in actor.get_class_levels():
		if entry.character_class.class_id != &"warrior":
			actor.set_class_level(entry.character_class, 0)
	actor.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, load("res://resources/items/weapons/iron_sword.tres"))
	actor.reset_ability_action()
	battle.turn_manager.current_unit = actor
	battle.turn_manager.current_index = battle.turn_manager.turn_order.find(actor)
	battle._on_turn_started(actor)
	battle._refresh_ability_bar()
	var buttons := battle.ability_bar.get_node("Margin/HBox")
	check(buttons.get_child_count() == 3 and (buttons.get_child(2) as Button).text.contains("Bloodlust"), "battle bar displays Bloodlust after Charge")
	check((buttons.get_child(2) as Button).tooltip_text.contains("Strength Up ×2"), "battle tooltip includes reward")
	battle._on_ability_selected(bloodlust)
	check(battle._ability_target_cells.has(target.grid_cell), "Bloodlust targets through battle UI")
	battle._update_ability_hover(target.global_position + Vector2(0, -85))
	check(battle.grid._ability_area_cells == [target.grid_cell], "hover previews one target")
	battle._cancel_ability_targeting()
	target.current_health = 1
	target.set_dev_equipment(ItemDefinition.EquipmentSlot.ARMOR, null)
	await battle._ability_executor.execute(actor, bloodlust, target.grid_cell, battle._characters, battle.grid, battle._ability_targeting, battle._get_wall_cells())
	check(_stacks(actor) == 2 and actor._get_status_icon_entries()[0].stack_count == 2, "real cast shows a two-stack badge")
	var payload := battle.capture_save_payload(false)
	check(ScenarioSaveStore.validate_payload(payload).ok, "earned reward produces a valid scenario save")
	actor.remove_status(reward.status_id)
	check(battle._restore_runtime_state(payload.runtime) and _stacks(actor) == 2, "battle save restores earned reward")
	check(actor.get_active_statuses()[0].source == bloodlust and actor.get_active_statuses()[0].source_unit == actor, "restored reward retains ability and caster sources")
	if DisplayServer.get_name() != "headless" and "--capture" in OS.get_cmdline_user_args():
		battle._refresh_ability_bar()
		for frame in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(DIRECTORY + "/bloodlust.png") == OK, "capture Bloodlust and earned status badge")
	var last_enemy: TacticalCharacter
	for unit in battle._characters:
		if not unit.is_friendly() and unit.current_health > 0:
			last_enemy = unit
	check(last_enemy != null, "cleanup fixture retains one last enemy")
	if last_enemy != null:
		for unit in battle._characters:
			if not unit.is_friendly() and unit != last_enemy:
				unit.current_health = 0
		last_enemy.set_grid_cell_immediate(Vector2i(4, 5))
		last_enemy.set_dev_equipment(ItemDefinition.EquipmentSlot.ARMOR, null)
		last_enemy.current_health = 1
		actor.reset_ability_action()
		var observed := [false]
		battle._ability_executor.melee_delivery.melee_finished.connect(func(_caster, _ability, _cell):
			observed[0] = true
			check(_stacks(actor) == 4 and not battle._combat_finalized, "last-enemy reward exists before resolution completes")
		)
		await battle._ability_executor.execute(actor, bloodlust, last_enemy.grid_cell, battle._characters, battle.grid, battle._ability_targeting, battle._get_wall_cells())
		battle._finalize_combat()
		for frame in range(4):
			await process_frame
		check(observed[0] and battle._combat_finalized and _stacks(actor) == 0, "finalization clears rewards after complete cast (observed=%s, finalized=%s, stacks=%d, living=%s)" % [observed[0], battle._combat_finalized, _stacks(actor), battle._characters.filter(func(u): return u.current_health > 0).map(func(u): return str(u.name))])
	battle.shutdown_battle()
	battle.free()
	await process_frame
