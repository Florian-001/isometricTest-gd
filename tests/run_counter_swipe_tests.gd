extends SceneTree

const DIRECTORY := "res://.godot/counter_swipe_validation"
var failures: Array[String] = []
var checks := 0
var arena: Node2D
var grid: IsometricGrid
var targeting: AbilityTargeting
var executor: AbilityExecutor
var units: Array[TacticalCharacter] = []
var counter: AbilityDefinition
var swipe: AbilityDefinition
var strike: AbilityDefinition
var status: StatusEffectDefinition
var passive: PassiveAbilityDefinition
var started: Array[TacticalCharacter] = []


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	counter = load("res://resources/abilities/counter.tres")
	swipe = load("res://resources/abilities/swipe.tres")
	strike = load("res://resources/abilities/strike.tres")
	status = load("res://resources/statuses/counter.tres")
	passive = load("res://resources/passives/counter.tres")
	for ability in [strike, swipe]:
		_fast(ability)
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
		check(executor.is_resolving(), "resolution boundary covers every attack and counter")
	)
	_test_resources()
	await _test_swipe()
	await _test_lifetime()
	await _test_counter_attacks()
	await _test_counter_limits()
	await _test_counter_area_and_order()
	await _test_selected_hits()
	await _test_interrupted_reactions()
	_clear()
	arena.free()
	await _test_battle_ui()
	for failure in failures:
		push_error(failure)
	print("COUNTER_SWIPE_TESTS_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _fast(ability: AbilityDefinition) -> void:
	ability.melee_lunge_duration = 0.02
	ability.melee_return_duration = 0.02
	ability.melee_slash_duration = 0.02
	ability.projectile_speed = 10000.0


func _unit(friendly: bool, cell: Vector2i, abilities: Array[AbilityDefinition] = []) -> TacticalCharacter:
	var unit := TacticalCharacter.new()
	unit.name = "CounterSwipe%d" % units.size()
	unit.scenario_unit_id = unit.name
	unit.definition = CharacterDefinition.new()
	unit.definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	unit.definition.constitution = 50
	unit.definition.strength = 5
	unit.definition.movement_range = 4.0
	unit.starting_grid_cell = cell
	unit.override_template_abilities = true
	unit.ability_overrides.assign(abilities if not abilities.is_empty() else [strike, counter, swipe])
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


func _forecast(caster: TacticalCharacter, ability: AbilityDefinition, cell: Vector2i, walls: Dictionary = {}) -> AIBoardSnapshot:
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size, walls)
	var planner := EnemyAIPlanner.new()
	planner._prepare_decision(caster, snapshot, units)
	planner._forecast_ability(caster, ability, cell, snapshot, targeting, EnemyAIProfile.new())
	return snapshot


func _matches_forecast(snapshot: AIBoardSnapshot, label: String) -> void:
	for unit in units:
		if not is_instance_valid(unit):
			continue
		check(unit.current_health == snapshot.get_health(unit) and unit.current_armor == snapshot.get_armor(unit), label + " health and armor: " + str(unit.name))


func _test_resources() -> void:
	check(passive.validate().is_empty() and status.granted_passive == passive, "Counter grants a valid reusable passive")
	check(status.expires_at_turn_start and not status.is_negative(), "Counter has positive next-start expiry")
	check(not StatusEffectDefinition.new().expires_at_turn_start and StatusEffectDefinition.new().granted_passive == null, "existing statuses keep compatible defaults")
	check(swipe.shape == AbilityDefinition.Shape.LINE_IN_FRONT and swipe.get_effective_area_span() == 3, "Swipe is a three-cell front line")
	var warrior := load("res://resources/classes/warrior.tres") as CharacterClassDefinition
	var actor := _unit(true, Vector2i(4, 4))
	actor.override_template_abilities = false
	actor.definition.starting_class = warrior
	for level in range(1, 8):
		actor.set_class_level(warrior, level)
		check(actor.get_abilities().has(counter) == (level >= 6), "Counter unlock level %d" % level)
		check(actor.get_abilities().has(swipe) == (level >= 7), "Swipe unlock level %d" % level)
	actor.set_class_level(warrior, 5)
	check(not executor.can_execute(actor, counter, actor.grid_cell, units, grid, targeting), "locked Counter rejects direct execution")
	check(not executor.can_execute(actor, swipe, Vector2i(4, 3), units, grid, targeting), "locked Swipe rejects direct execution")
	var catalog := load("res://resources/dev_tool_catalog.tres") as DevToolCatalog
	check(catalog.abilities.has(counter) and catalog.abilities.has(swipe) and catalog.passive_abilities.has(passive), "new resources appear in developer catalog")
	check(ResourceSaver.save(status, DIRECTORY + "/counter_status.tres") == OK, "status resource saves")
	var restored := ResourceLoader.load(DIRECTORY + "/counter_status.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as StatusEffectDefinition
	check(restored.expires_at_turn_start and restored.granted_passive == passive, "status Inspector fields survive reload")
	var inline := passive.duplicate(true) as PassiveAbilityDefinition
	inline.resource_path = ""
	var encoded := PassiveLoadout.to_data([inline])
	check(PassiveLoadout.validate_setup({"override_passives": true, "passives": encoded}).is_empty(), "inline Counter effect validates")
	check(PassiveLoadout.from_data(encoded)[0].effects[0] is CounterPassiveEffect, "inline Counter effect survives save")
	_clear()


func _test_swipe() -> void:
	for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var actor := _unit(true, Vector2i(4, 4))
		var center: Vector2i = actor.grid_cell + direction
		var side := Vector2i(-direction.y, direction.x)
		var enemies: Array[TacticalCharacter] = []
		for offset in [-1, 0, 1]:
			enemies.append(_unit(false, center + side * offset))
		var ally := _unit(true, actor.grid_cell - direction)
		var pack := load("res://resources/passives/pack_tactics.tres") as PassiveAbilityDefinition
		actor.set_dev_passive_loadout([pack])
		ally.set_dev_passive_loadout([pack])
		actor.get_equipped_weapon().status_effect = load("res://resources/statuses/slow.tres")
		var armor := ItemDefinition.new()
		armor.slot = ItemDefinition.EquipmentSlot.ARMOR
		armor.armor = 5
		enemies[0].equip_item(armor)
		var cells := targeting.get_affected_cells(actor.grid_cell, center, swipe)
		check(cells.size() == 3 and cells.has(enemies[0].grid_cell) and cells.has(enemies[2].grid_cell), "Swipe geometry " + str(direction))
		check(targeting.get_valid_target_cells(actor, swipe, units).size() == 4, "four aim cells independent of occupancy")
		check(not targeting.is_valid_primary_target(actor, actor.grid_cell, swipe, units) and not targeting.is_valid_primary_target(actor, actor.grid_cell + Vector2i(1, 1), swipe, units), "self and diagonal aim rejected")
		var snapshot := _forecast(actor, swipe, center)
		var hp := enemies[0].current_health
		var movement := actor.remaining_movement
		check(await executor.execute(actor, swipe, center, units, grid, targeting), "Swipe executes " + str(direction))
		check(enemies[0].current_health == hp - 5 and enemies[1].current_health == hp - 10 and enemies[2].current_health == hp - 10, "Swipe uses Strike damage, passive bonus, and armor")
		check(enemies[0].get_active_statuses().size() == 1 and enemies[2].get_active_statuses().size() == 1, "weapon status on every surviving Swipe recipient")
		check(ally.current_health == ally.get_max_health() and actor.current_health == actor.get_max_health(), "Swipe excludes ally and caster")
		check(not actor.ability_available and actor.remaining_movement == movement, "Swipe consumes one action and no movement")
		_matches_forecast(snapshot, "Swipe")
		_clear()
	var actor := _unit(true, Vector2i(4, 4))
	var left := _unit(false, Vector2i(3, 3))
	var ally := _unit(true, Vector2i(5, 3))
	var center := Vector2i(4, 3)
	var walls := {Vector2i(3, 4): true}
	check(not targeting.get_affected_cells(actor.grid_cell, center, swipe, walls).has(left.grid_cell), "Swipe cannot cross a blocked diagonal corner")
	check(not targeting.is_valid_primary_target(actor, center, swipe, units, {center: true}), "wall at center blocks aim")
	check(targeting.get_affected_cells(Vector2i.ZERO, Vector2i.DOWN, swipe).size() == 2, "front row clips at board edge")
	check(await executor.execute(actor, swipe, center, units, grid, targeting), "empty center can hit a flank enemy")
	check(left.current_health == left.get_max_health() - 9 and ally.current_health == ally.get_max_health(), "empty-center cast hits enemy flank only")
	actor.reset_ability_action()
	check(await executor.execute(actor, swipe, Vector2i(4, 5), units, grid, targeting) and not actor.ability_available, "completely empty Swipe spends its action")
	actor.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, null)
	check(not swipe.can_be_used_by(actor) and counter.can_be_used_by(actor), "unarmed equipment rules")
	var bow := ItemDefinition.new()
	bow.weapon_type = ItemDefinition.WeaponType.RANGED
	actor.equip_item(bow)
	check(not swipe.can_be_used_by(actor) and counter.can_be_used_by(actor), "ranged equipment rules")
	# The AI must retain an empty center even if the enemy is only on one flank.
	actor.equip_item(load("res://resources/items/weapons/iron_sword.tres"))
	actor.reset_ability_action()
	var planner := EnemyAIPlanner.new()
	var board := AIBoardSnapshot.from_battle(units, grid.grid_size)
	check(planner._get_relevant_target_cells(actor, swipe, board, targeting).has(center), "AI retains empty Swipe center")
	check(not planner._is_valid_primary_target(actor, actor.grid_cell, Vector2i(5, 5), swipe, board, targeting), "AI rejects diagonal Swipe aim")
	_clear()


func _test_lifetime() -> void:
	var actor := _unit(true, Vector2i(4, 4))
	var enemy := _unit(false, Vector2i(4, 3))
	actor.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, null)
	var movement := actor.remaining_movement
	var granted_forecast := _forecast(actor, counter, actor.grid_cell)
	check(PassiveAbilityResolver.has_counter(actor, granted_forecast) and not PassiveAbilityResolver.has_counter(actor), "AI forecasts Counter acquisition without changing live state")
	check(await executor.execute(actor, counter, actor.grid_cell, units, grid, targeting), "unarmed Counter activates on self")
	check(not actor.ability_available and actor.remaining_movement == movement and actor.opportunity_reaction_available, "Counter activation costs only action")
	check(actor.get_passive_abilities() == [passive] and actor.get_passive_description().contains("basic attack"), "temporary passive exposed in unit UI")
	actor.advance_status_durations()
	enemy.process_status_turn_start()
	enemy.advance_status_durations()
	check(PassiveAbilityResolver.has_counter(actor), "activation-turn end and other turns do not expire Counter")
	actor.apply_status(status, counter, actor)
	check(actor.get_active_statuses().size() == 1 and actor.get_passive_abilities().size() == 1, "Counter refresh does not stack")
	var saved := actor.capture_runtime_state()
	actor.remove_negative_statuses()
	check(PassiveAbilityResolver.has_counter(actor), "Cleanse preserves Counter")
	actor.remove_status(&"counter")
	actor.restore_runtime_state(saved, {actor.scenario_unit_id: actor, enemy.scenario_unit_id: enemy})
	check(PassiveAbilityResolver.has_counter(actor), "runtime save restores Counter")
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
	var copy := snapshot.duplicate_state()
	snapshot.expire_turn_start_statuses(actor)
	check(not PassiveAbilityResolver.has_counter(actor, snapshot) and PassiveAbilityResolver.has_counter(actor, copy), "snapshot expiry is isolated from runtime and copied board")
	actor.apply_status(load("res://resources/statuses/stun.tres"))
	var manager := TurnManager.new()
	arena.add_child(manager)
	manager.turn_starting.connect(func(unit):
		if unit == actor:
			check(not PassiveAbilityResolver.has_counter(actor), "Counter expires before turn-start callbacks even when stunned")
	)
	manager.start_combat([actor])
	check(not PassiveAbilityResolver.has_counter(actor), "owner next turn expires Counter")
	manager.free()
	actor.set_dev_passive_loadout([passive])
	actor.apply_status(status)
	check(actor.get_passive_abilities().size() == 1, "temporary and authored Counter deduplicate")
	actor.expire_turn_start_statuses()
	check(PassiveAbilityResolver.has_counter(actor), "temporary expiry preserves authored passive")
	_clear()


func _test_counter_attacks() -> void:
	for delivery in [AbilityDefinition.DeliveryType.MELEE, AbilityDefinition.DeliveryType.PROJECTILE, AbilityDefinition.DeliveryType.CAST_ON_TARGET]:
		var attack := strike.duplicate(true) as AbilityDefinition
		attack.delivery_type = delivery
		if delivery != AbilityDefinition.DeliveryType.MELEE:
			attack.ability_type = AbilityDefinition.AbilityType.MAGIC
			attack.damage_type = DamageCalculator.Type.MAGICAL
		_fast(attack)
		var defender := _unit(true, Vector2i(4, 4))
		var attacker := _unit(false, Vector2i(4, 3), [attack])
		defender.apply_status(status)
		defender.spend_ability_action()
		defender.spend_opportunity_reaction()
		var movement := defender.remaining_movement
		var armor := ItemDefinition.new()
		armor.slot = ItemDefinition.EquipmentSlot.ARMOR
		armor.armor = 50
		defender.equip_item(armor)
		attacker.equip_item(armor)
		defender.get_equipped_weapon().status_effect = load("res://resources/statuses/slow.tres")
		var predicted := _forecast(attacker, attack, defender.grid_cell)
		var hp := defender.current_health
		check(await executor.execute(attacker, attack, defender.grid_cell, units, grid, targeting), "incoming delivery executes %d" % delivery)
		check(started == [attacker, defender], "one basic counter after incoming attack")
		check(defender.current_health == hp and attacker.current_armor == 41, "armor absorption still triggers Counter")
		check(attacker.get_active_statuses().size() == 1, "counter applies weapon status")
		check(not defender.ability_available and not defender.opportunity_reaction_available and defender.remaining_movement == movement, "counter preserves spent resources")
		_matches_forecast(predicted, "Counter delivery")
		check(not executor.is_resolving(), "resolution releases after retaliation")
		attacker.reset_ability_action()
		check(await executor.execute(attacker, attack, defender.grid_cell, units, grid, targeting), "subsequent cast can trigger another counter")
		check(started.size() == 4, "Counter has no per-round reaction cap")
		_clear()
	var multi := load("res://resources/abilities/multi_attack.tres").duplicate(true) as AbilityDefinition
	_fast(multi)
	var defender := _unit(true, Vector2i(4, 4))
	var attacker := _unit(false, Vector2i(4, 3), [multi])
	defender.apply_status(status)
	attacker.apply_status(status)
	attacker.current_health = 5
	var before := defender.current_health
	var predicted := _forecast(attacker, multi, defender.grid_cell)
	check(await executor.execute(attacker, multi, defender.grid_cell, units, grid, targeting), "multi-hit completes before counter")
	check(defender.current_health == before - 14 and attacker.current_health == 0 and started == [attacker, defender], "both hits land then one lethal counter; no recursion")
	_matches_forecast(predicted, "Multi Attack counter")
	_clear()
	defender = _unit(true, Vector2i(4, 4))
	attacker = _unit(false, Vector2i(4, 3), [strike])
	defender.apply_status(status)
	attacker.apply_status(status)
	check(await executor.execute_opportunity_attack(attacker, strike, defender.grid_cell, units, grid, targeting), "opportunity attack triggers Counter")
	check(started == [attacker, defender] and not attacker.opportunity_reaction_available and defender.opportunity_reaction_available, "counter does not chain or consume defender reaction")
	_clear()


func _test_counter_limits() -> void:
	var defender := _unit(true, Vector2i(4, 4))
	var attacker := _unit(false, Vector2i(4, 2), [strike])
	defender.apply_status(status)
	check(not executor.can_execute_counter_attack(defender, attacker, units, grid, targeting), "distant attacker outside basic reach")
	defender.get_equipped_weapon().weapon_range_bonus = 1.0
	check(executor.can_execute_counter_attack(defender, attacker, units, grid, targeting), "Counter accepts weapon reach bonus")
	check(not executor.can_execute_counter_attack(defender, attacker, units, grid, targeting, {Vector2i(4, 3): true}), "Counter respects intervening wall")
	check(await executor.execute_counter_attack(defender, attacker, units, grid, targeting), "extended-range counter executes")
	defender.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, null)
	attacker.set_grid_cell_immediate(Vector2i(4, 3))
	check(await executor.execute_counter_attack(defender, attacker, units, grid, targeting), "unarmed counter uses Strike")
	var bow := ItemDefinition.new()
	bow.weapon_type = ItemDefinition.WeaponType.RANGED
	bow.weapon_damage = 4
	defender.equip_item(bow)
	attacker.set_grid_cell_immediate(Vector2i(4, 1))
	var health := attacker.current_health
	check(await executor.execute_counter_attack(defender, attacker, units, grid, targeting), "ranged equipment counter uses Arrow")
	check(attacker.current_health == health - CounterAttackSystem.get_ability(defender).calculate_damage(defender), "equipped basic damage used")
	defender.apply_status(load("res://resources/statuses/stun.tres"))
	check(not executor.can_execute_counter_attack(defender, attacker, units, grid, targeting), "stunned defender cannot counter")
	defender.remove_status(&"stun")
	units.erase(attacker)
	check(not executor.can_execute_counter_attack(defender, attacker, units, grid, targeting), "removed attacker cannot be countered")
	units.append(attacker)
	started.clear()
	defender.apply_damage(1)
	load("res://resources/statuses/burning.tres").apply_turn_start(defender)
	check(started.is_empty(), "direct damage and damage over time cannot counter")
	_clear()
	# Incoming stun and lethal damage suppress queued counters, including in forecasts.
	for lethal in [false, true]:
		var attack := strike.duplicate(true) as AbilityDefinition
		attack.status_effect = load("res://resources/statuses/stun.tres") if not lethal else null
		defender = _unit(true, Vector2i(4, 4))
		attacker = _unit(false, Vector2i(4, 3), [attack])
		defender.apply_status(status)
		if lethal:
			defender.current_health = 1
		var predicted := _forecast(attacker, attack, defender.grid_cell)
		await executor.execute(attacker, attack, defender.grid_cell, units, grid, targeting)
		check(started == [attacker] and attacker.current_health == attacker.get_max_health(), "incoming stun/death prevents Counter")
		_matches_forecast(predicted, "suppressed Counter")
		_clear()
	# Strength changes inflicted by the attack must affect the following basic counter.
	var weakness := StatusEffectDefinition.new()
	weakness.status_id = &"weakness"
	weakness.effect = StatusEffectDefinition.Effect.STAT_MODIFIER
	weakness.affected_stat = UnitStat.Type.STRENGTH
	weakness.modifier_value_type = StatusEffectDefinition.ModifierValueType.FLAT
	weakness.flat_amount = 3
	var attack := strike.duplicate(true) as AbilityDefinition
	attack.status_effect = weakness
	defender = _unit(true, Vector2i(4, 4))
	attacker = _unit(false, Vector2i(4, 3), [attack])
	defender.apply_status(status)
	var predicted := _forecast(attacker, attack, defender.grid_cell)
	await executor.execute(attacker, attack, defender.grid_cell, units, grid, targeting)
	check(attacker.current_health == attacker.get_max_health() - 6, "counter uses stats after incoming effects")
	_matches_forecast(predicted, "weakened Counter")
	_clear()


func _test_counter_area_and_order() -> void:
	var first := _unit(true, Vector2i(3, 3))
	var second := _unit(true, Vector2i(5, 3))
	var attacker := _unit(false, Vector2i(4, 4), [swipe])
	first.definition.speed = 1
	second.definition.speed = 20
	first.apply_status(status)
	second.apply_status(status)
	attacker.current_health = 12
	var predicted := _forecast(attacker, swipe, Vector2i(4, 3))
	await executor.execute(attacker, swipe, Vector2i(4, 3), units, grid, targeting)
	check(started == [attacker, second, first] and attacker.current_health == 0, "area defenders counter once each in initiative order")
	_matches_forecast(predicted, "area Counter")
	_clear()
	first = _unit(true, Vector2i(3, 3))
	second = _unit(true, Vector2i(5, 3))
	attacker = _unit(false, Vector2i(4, 4), [swipe])
	first.apply_status(status)
	second.apply_status(status)
	attacker.current_health = 1
	await executor.execute(attacker, swipe, Vector2i(4, 3), units, grid, targeting)
	check(started == [attacker, first], "initiative ties use roster order and attacker death stops remaining counters")
	_clear()


func _test_selected_hits() -> void:
	var attack := strike.duplicate(true) as AbilityDefinition
	attack.target_flags = AbilityDefinition.TargetFlags.ENEMY
	attack.hit_count = 2
	attack.hit_targeting = AbilityDefinition.HitTargeting.SELECT_PER_HIT
	var attacker := _unit(true, Vector2i(4, 4), [attack])
	var defender := _unit(false, Vector2i(4, 3))
	defender.apply_status(status)
	var hp := attacker.current_health
	check(await executor.execute_targets(attacker, attack, [defender, defender], units, grid, targeting), "ordered repeated targets execute")
	check(started == [attacker, defender] and attacker.current_health == hp - 9, "per-hit target selection also triggers one counter per cast")
	_clear()


func _capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(DIRECTORY + "/" + name + ".png") == OK, "capture " + name)


func _test_interrupted_reactions() -> void:
	var defender := _unit(true, Vector2i(4, 4))
	var attacker := _unit(false, Vector2i(4, 3), [strike])
	defender.apply_status(status)
	defender.health_changed.connect(func(_hp, _maximum): defender.queue_free(), CONNECT_ONE_SHOT)
	await executor.execute(attacker, strike, defender.grid_cell, units, grid, targeting)
	check(not is_instance_valid(defender) and attacker.current_health == attacker.get_max_health(), "defender removed during delivery cannot counter")
	check(not executor.is_resolving(), "removal releases resolution boundary")
	_clear()
	defender = _unit(true, Vector2i(4, 4))
	attacker = _unit(false, Vector2i(4, 3), [strike])
	defender.apply_status(status)
	var remove_attacker := func(caster, _ability, _cell):
		units.erase(caster)
	executor.melee_delivery.melee_finished.connect(remove_attacker, CONNECT_ONE_SHOT)
	await executor.execute(attacker, strike, defender.grid_cell, units, grid, targeting)
	check(attacker.current_health == attacker.get_max_health() and started == [attacker], "attacker removed from roster after impact cannot be countered")
	units.append(attacker)
	_clear()
	defender = _unit(true, Vector2i(4, 4))
	attacker = _unit(false, Vector2i(4, 3), [strike])
	var replacement := _unit(false, Vector2i(8, 8))
	defender.apply_status(status)
	var swap_attacker := func(caster, _ability, _cell):
		if caster == defender:
			attacker.set_grid_cell_immediate(Vector2i(9, 9))
			replacement.set_grid_cell_immediate(Vector2i(4, 3))
	executor.ability_started.connect(swap_attacker)
	await executor.execute(attacker, strike, defender.grid_cell, units, grid, targeting)
	check(replacement.current_health == replacement.get_max_health() and attacker.current_health == attacker.get_max_health(), "counter never switches to a replacement occupant")
	executor.ability_started.disconnect(swap_attacker)
	_clear()


func _test_battle_ui() -> void:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	root.add_child(battle)
	check(battle.initialization_succeeded, "real battle initializes")
	battle.set_process(false)
	var actor := battle._characters[1]
	battle.turn_manager.current_unit = actor
	battle.turn_manager.current_index = battle.turn_manager.turn_order.find(actor)
	actor.reset_ability_action()
	actor.reset_movement()
	battle._on_turn_started(actor)
	actor.set_grid_cell_immediate(Vector2i(5, 5))
	battle._characters[2].set_grid_cell_immediate(Vector2i(4, 4))
	battle._characters[3].set_grid_cell_immediate(Vector2i(5, 4))
	battle._characters[4].set_grid_cell_immediate(Vector2i(6, 4))
	actor.set_class_level(load("res://resources/classes/warrior.tres"), 7)
	for entry in actor.get_class_levels():
		if entry.character_class.class_id != &"warrior":
			actor.set_class_level(entry.character_class, 0)
	actor.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, load("res://resources/items/weapons/iron_sword.tres"))
	battle._refresh_ability_bar()
	check(battle.ability_bar.get_node("Margin/HBox").get_child_count() == 8, "battle bar shows eight warrior skills")
	battle._on_ability_selected(counter)
	check(battle._ability_target_cells.keys() == [actor.grid_cell], "Counter has self confirmation")
	battle._cancel_ability_targeting()
	check(await battle._ability_executor.execute(actor, counter, actor.grid_cell, battle._characters, battle.grid, battle._ability_targeting), "Counter activates in real battle")
	var payload := battle.capture_save_payload(false)
	check(ScenarioSaveStore.validate_payload(payload).ok, "battle save with Counter validates")
	actor.remove_status(&"counter")
	check(battle._restore_runtime_state(payload.runtime) and PassiveAbilityResolver.has_counter(actor), "real battle runtime restore recovers Counter")
	actor.reset_ability_action()
	battle._refresh_ability_bar()
	battle._on_ability_selected(swipe)
	check(battle._ability_target_cells.size() == 4, "Swipe battle UI offers four directions")
	battle._update_ability_hover(battle._characters[3].global_position + Vector2(0, -85))
	var cells := battle._ability_targeting.get_affected_cells(actor.grid_cell, Vector2i(5, 4), swipe, battle._get_wall_cells())
	check(battle.grid._ability_area_cells == cells and cells.size() == 3, "Swipe hover matches runtime geometry")
	var buttons := battle.ability_bar.get_node("Margin/HBox")
	check((buttons.get_child(6) as Button).tooltip_text.contains("next turn start") and (buttons.get_child(7) as Button).tooltip_text.contains("3-cell row"), "new tooltips explain timing and geometry")
	await _capture("swipe_and_counter")
	battle._cancel_ability_targeting()
	# A lethal counter must not start the next turn while the defender returns from its lunge.
	var enemy := battle._characters[2]
	enemy.set_grid_cell_immediate(Vector2i(5, 4))
	battle._characters[3].set_grid_cell_immediate(Vector2i(8, 8))
	enemy.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, load("res://resources/items/weapons/iron_sword.tres"))
	enemy.override_template_abilities = true
	enemy.ability_overrides = [strike]
	enemy.reset_ability_action()
	enemy.current_health = 1
	battle.turn_manager.current_unit = enemy
	battle.turn_manager.current_index = battle.turn_manager.turn_order.find(enemy)
	# Keep this integration fixture from starting an unrelated autonomous enemy turn afterward.
	battle.turn_manager.turn_started.disconnect(battle._on_turn_started)
	var finishes := [0]
	battle._ability_executor.melee_delivery.melee_finished.connect(func(caster, _ability, _cell):
		if caster == actor and not battle._combat_over:
			finishes[0] += 1
			check(battle.turn_manager.current_unit == enemy and battle._ability_executor.is_resolving(), "defeated acting unit waits for counter animation")
			check(not battle._is_dev_stable(), "saving/developer mode unavailable inside Counter resolution")
	)
	check(await battle._ability_executor.execute(enemy, strike, actor.grid_cell, battle._characters, battle.grid, battle._ability_targeting), "real battle lethal counter completes")
	battle._process(0.0)
	check(finishes[0] == 1 and enemy.current_health == 0 and battle.turn_manager.current_unit != enemy, "turn advances only after completed retaliation")
	# Finishing the encounter must also wait before restoring armor or publishing results.
	var last_enemy := battle._characters[4]
	for unit in battle._characters:
		if not unit.is_friendly() and unit != last_enemy:
			unit.current_health = 0
	last_enemy.set_grid_cell_immediate(Vector2i(5, 4))
	last_enemy.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, load("res://resources/items/weapons/iron_sword.tres"))
	last_enemy.override_template_abilities = true
	last_enemy.ability_overrides = [strike]
	last_enemy.reset_ability_action()
	last_enemy.current_health = 1
	actor.set_dev_equipment(ItemDefinition.EquipmentSlot.ARMOR, load("res://resources/items/armor/plate_armor.tres"))
	actor.restore_armor()
	actor.apply_status(status)
	battle.turn_manager.current_unit = last_enemy
	battle.turn_manager.current_index = battle.turn_manager.turn_order.find(last_enemy)
	var finalization_checks := [0]
	battle._ability_executor.melee_delivery.melee_finished.connect(func(caster, _ability, _cell):
		if caster == actor and battle._combat_over:
			finalization_checks[0] += 1
			battle._finalize_combat()
			check(not battle._combat_finalized and actor.current_armor < actor.get_max_armor(), "combat finalization and armor restoration wait for counter return")
	)
	await battle._ability_executor.execute(last_enemy, strike, actor.grid_cell, battle._characters, battle.grid, battle._ability_targeting)
	battle._finalize_combat()
	check(finalization_checks[0] == 1 and battle._combat_finalized and actor.current_armor == actor.get_max_armor(), "last-enemy counter finalizes and restores armor after resolution")
	battle.queue_free()
	await process_frame
	await process_frame
