extends SceneTree

var _failures: Array[String] = []
var _grid: IsometricGrid
var _terrain: TacticalTerrain
var _targeting: AbilityTargeting
var _executor: AbilityExecutor
var _units: Array[TacticalCharacter] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var battlefield := Node2D.new()
	battlefield.name = "ChargeIntegration"
	root.add_child(battlefield)

	_grid = IsometricGrid.new()
	_grid.grid_size = Vector2i(10, 7)
	battlefield.add_child(_grid)
	_terrain = TacticalTerrain.new()
	battlefield.add_child(_terrain)
	var hazard_definition := TileDefinition.new()
	hazard_definition.display_name = "Charge Hazard"
	hazard_definition.movement_cost_multiplier = 4.0
	hazard_definition.status_effect = load("res://resources/statuses/burning.tres") as StatusEffectDefinition
	hazard_definition.status_triggers = TileTriggeredEffectDefinition.Trigger.ENTER
	var hazard := TacticalTile.new()
	hazard.definition = hazard_definition
	hazard.grid_cell = Vector2i(3, 2)
	_terrain.add_child(hazard)
	_terrain.initialize(_grid)

	_targeting = AbilityTargeting.new(_grid.grid_size)
	_executor = AbilityExecutor.new()
	battlefield.add_child(_executor)
	var charge := (load("res://resources/abilities/charge.tres") as AbilityDefinition).duplicate(true) as AbilityDefinition
	charge.melee_lunge_duration = 0.02
	charge.melee_return_duration = 0.02
	charge.melee_slash_duration = 0.02
	var strike := (load("res://resources/abilities/strike.tres") as AbilityDefinition).duplicate(true) as AbilityDefinition
	strike.melee_lunge_duration = 0.02
	strike.melee_return_duration = 0.02
	strike.melee_slash_duration = 0.02

	var caster := _make_unit(battlefield, "Caster", true, Vector2i(1, 2), 10, charge, 20)
	var target := _make_unit(battlefield, "Target", false, Vector2i(6, 2), 8, null, 0)
	var reactor := _make_unit(battlefield, "Reactor", false, Vector2i(2, 1), 14, strike, 5)
	var caster_weapon := caster.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON)
	caster_weapon.status_effect = load("res://resources/statuses/slow.tres") as StatusEffectDefinition
	_units = [caster, target, reactor]
	caster.reset_movement()
	caster.reset_ability_action()
	reactor.reset_opportunity_reaction()
	reactor.reset_ability_action()
	var movement_before := caster.remaining_movement
	var reactor_damage := strike.calculate_damage(reactor)
	var target_damage := charge.calculate_damage(caster)
	var succeeded := await _executor.execute(
		caster,
		charge,
		target.grid_cell,
		_units,
		_grid,
		_targeting,
		{},
		Callable(self, "_resolve_charge_step")
	)
	await process_frame

	_check(succeeded, "a clear Charge should complete")
	_check(caster.grid_cell == Vector2i(5, 2), "Charge should leave the caster adjacent to the target")
	_check(target.current_health == 100 - target_damage, "Charge should resolve its normal centralized damage")
	_check(not caster.ability_available, "Charge should consume the normal ability action")
	_check(is_equal_approx(caster.remaining_movement, movement_before), "Charge steps and terrain costs should not consume movement points")
	_check(caster.current_health == 100 - reactor_damage, "Charge should trigger an opportunity attack when leaving reach")
	_check(not reactor.opportunity_reaction_available, "the reacting unit should consume its opportunity reaction")
	_check(reactor.ability_available, "the reaction should not consume the attacker's normal action")
	_check(_has_status(caster, &"burning"), "Charge should apply terrain entry statuses along its path")
	_check(_has_status(target, &"slow"), "Charge should apply its compatible weapon status after damage")
	var target_statuses := target.get_active_statuses()
	_check(not target_statuses.is_empty() and target_statuses[0].source == caster_weapon, "weapon status source metadata should remain unchanged")

	var doomed := _make_unit(battlefield, "Doomed", true, Vector2i(1, 4), 10, charge, 20)
	var untouched_target := _make_unit(battlefield, "Untouched", false, Vector2i(5, 4), 8, null, 0)
	var lethal_reactor := _make_unit(battlefield, "Lethal", false, Vector2i(2, 3), 16, strike, 100)
	_units = [doomed, untouched_target, lethal_reactor]
	doomed.reset_movement()
	doomed.reset_ability_action()
	lethal_reactor.reset_opportunity_reaction()
	var doomed_movement := doomed.remaining_movement
	var interrupted := await _executor.execute(
		doomed,
		charge,
		untouched_target.grid_cell,
		_units,
		_grid,
		_targeting,
		{},
		Callable(self, "_resolve_charge_step")
	)
	_check(not interrupted, "a lethal reaction should interrupt Charge")
	_check(doomed.current_health == 0, "the lethal opportunity attack should defeat the charging caster")
	_check(doomed.grid_cell == Vector2i(3, 4), "a defeated caster should stop before the interrupted step")
	_check(untouched_target.current_health == 100, "an interrupted Charge should not attack its target")
	_check(not doomed.ability_available, "an interrupted Charge should keep its spent ability action")
	_check(is_equal_approx(doomed.remaining_movement, doomed_movement), "an interrupted Charge should not spend normal movement")

	var stun := load("res://resources/statuses/stun.tres") as StatusEffectDefinition
	var stunned_charger := _make_unit(battlefield, "StunnedCharger", true, Vector2i(1, 5), 10, charge, 20)
	var stunned_target := _make_unit(battlefield, "StunnedTarget", false, Vector2i(6, 5), 8, null, 0)
	var stunning_reactor := _make_unit(battlefield, "StunningReactor", false, Vector2i(2, 4), 16, strike, 5)
	stunning_reactor.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON).status_effect = stun
	_units = [stunned_charger, stunned_target, stunning_reactor]
	stunned_charger.reset_movement()
	stunned_charger.reset_ability_action()
	stunning_reactor.reset_opportunity_reaction()
	var stunned_charge := await _executor.execute(
		stunned_charger,
		charge,
		stunned_target.grid_cell,
		_units,
		_grid,
		_targeting,
		{},
		Callable(self, "_resolve_charge_step")
	)
	_check(not stunned_charge, "an opportunity-applied Stun should interrupt Charge")
	_check(stunned_charger.grid_cell == Vector2i(3, 5), "Stun should stop Charge before its next cell")
	_check(stunned_target.current_health == 100, "a Stun-interrupted Charge should not resolve impact effects")
	_check(not stunned_charger.ability_available, "an interrupted Charge should keep its spent ability action")
	_check(is_zero_approx(stunned_charger.remaining_movement), "mid-Charge Stun should expose zero usable movement")

	var stun_tile_definition := TileDefinition.new()
	stun_tile_definition.display_name = "Stun Tile"
	stun_tile_definition.status_effect = stun
	stun_tile_definition.status_triggers = TileTriggeredEffectDefinition.Trigger.ENTER
	var stun_tile := TacticalTile.new()
	stun_tile.definition = stun_tile_definition
	stun_tile.grid_cell = Vector2i(3, 6)
	_terrain.add_child(stun_tile)
	_terrain.refresh()
	var walker := _make_unit(battlefield, "Walker", true, Vector2i(1, 6), 10, null, 0)
	walker.reset_movement()
	await walker.move_along(
		[Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6)],
		func(mover: TacticalCharacter, _current: Vector2i, _next: Vector2i) -> bool:
			return mover.spend_movement(1.0)
	)
	_check(walker.grid_cell == Vector2i(3, 6), "terrain-applied Stun should stop normal movement before the following cell")
	_check(walker.is_stunned(), "the entered tile should apply reusable Stun")
	_check(is_zero_approx(walker.remaining_movement), "a unit stunned mid-route should expose no remaining movement")

	battlefield.queue_free()
	await process_frame
	if _failures.is_empty():
		print("CHARGE_INTEGRATION_OK")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _resolve_charge_step(
	mover: TacticalCharacter,
	current_cell: Vector2i,
	next_cell: Vector2i
) -> bool:
	for attacker in OpportunityAttackSystem.get_initiative_order(_units):
		if not OpportunityAttackSystem.can_trigger(attacker, mover, current_cell, next_cell):
			continue
		var ability := OpportunityAttackSystem.get_opportunity_attack_ability(attacker)
		await _executor.execute_opportunity_attack(
			attacker,
			ability,
			current_cell,
			_units,
			_grid,
			_targeting
		)
		if mover.current_health <= 0:
			return false
	return true


func _make_unit(
	parent: Node,
	unit_name: String,
	friendly: bool,
	cell: Vector2i,
	speed: int,
	ability: AbilityDefinition,
	weapon_damage: int
) -> TacticalCharacter:
	var definition := CharacterDefinition.new()
	definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	definition.constitution = 25
	definition.movement_range = 6.0
	definition.strength = 10
	definition.speed = speed
	if ability != null:
		var abilities: Array[AbilityDefinition] = [ability]
		definition.abilities = abilities
	var unit := TacticalCharacter.new()
	unit.name = unit_name
	unit.definition = definition
	if friendly:
		unit.set_dev_ability_loadout(definition.abilities)
	unit.starting_grid_cell = cell
	unit.movement_animation_speed = 5000.0
	parent.add_child(unit)
	unit.initialize(_grid)
	unit.cell_entered.connect(func(character: TacticalCharacter, _cell: Vector2i):
		_terrain.apply_trigger(character, TileTriggeredEffectDefinition.Trigger.ENTER)
	)
	if ability != null:
		var weapon := ItemDefinition.new()
		weapon.weapon_type = ItemDefinition.WeaponType.MELEE
		weapon.weapon_damage = weapon_damage
		unit.equip_item(weapon)
	return unit


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _has_status(unit: TacticalCharacter, status_id: StringName) -> bool:
	for active_status in unit.get_active_statuses():
		if active_status.definition != null and active_status.definition.status_id == status_id:
			return true
	return false
