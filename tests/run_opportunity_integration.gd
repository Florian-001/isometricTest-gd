extends SceneTree

var _failures: Array[String] = []
var _grid: IsometricGrid
var _pathfinder: GridPathfinder
var _targeting: AbilityTargeting
var _executor: AbilityExecutor
var _units: Array[TacticalCharacter] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var battlefield := Node2D.new()
	battlefield.name = "OpportunityIntegration"
	root.add_child(battlefield)

	_grid = IsometricGrid.new()
	_grid.grid_size = Vector2i(9, 7)
	battlefield.add_child(_grid)
	_pathfinder = GridPathfinder.new(_grid.grid_size)
	_targeting = AbilityTargeting.new(_grid.grid_size)
	_executor = AbilityExecutor.new()
	battlefield.add_child(_executor)

	var strike := (load("res://resources/abilities/strike.tres") as AbilityDefinition).duplicate(true) as AbilityDefinition
	strike.melee_lunge_duration = 0.02
	strike.melee_return_duration = 0.02
	strike.melee_slash_duration = 0.02

	var attacker := _make_unit(battlefield, "Attacker", true, Vector2i(1, 1), 15, strike, 5)
	var mover := _make_unit(battlefield, "Mover", false, Vector2i(2, 1), 10, null, 0)
	_units = [attacker, mover]
	attacker.reset_ability_action()
	attacker.reset_opportunity_reaction()
	mover.reset_movement()
	var expected_damage := strike.calculate_damage(attacker)
	await mover.move_along(
		[Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1)],
		Callable(self, "_resolve_step")
	)
	_check(mover.current_health == 100 - expected_damage, "a surviving mover should be struck exactly once")
	_check(mover.grid_cell == Vector2i(4, 1), "a surviving mover should resume and finish its path")
	_check(is_equal_approx(mover.remaining_movement, 4.0), "resumed movement should spend only its two traversed steps")
	_check(not attacker.opportunity_reaction_available, "the opportunity attack should consume the separate reaction")
	_check(attacker.ability_available, "the opportunity attack must not consume the normal ability action")

	var fast := _make_unit(battlefield, "Fast", true, Vector2i(1, 2), 18, strike, 1)
	var slow := _make_unit(battlefield, "Slow", true, Vector2i(1, 4), 8, strike, 1)
	var surrounded := _make_unit(battlefield, "Surrounded", false, Vector2i(2, 3), 10, null, 0)
	_units = [slow, surrounded, fast]
	fast.reset_opportunity_reaction()
	slow.reset_opportunity_reaction()
	fast.reset_ability_action()
	fast.spend_ability_action()
	surrounded.reset_movement()
	var attack_order: Array[String] = []
	_executor.ability_started.connect(func(caster: TacticalCharacter, _ability, _cell):
		if caster == fast or caster == slow:
			attack_order.append(caster.name)
	)
	await surrounded.move_along(
		[Vector2i(2, 3), Vector2i(3, 3)],
		Callable(self, "_resolve_step")
	)
	_check(attack_order == ["Fast", "Slow"], "multiple attackers should react in initiative order")
	_check(not fast.opportunity_reaction_available and not slow.opportunity_reaction_available, "every reacting attacker should spend its own reaction")
	_check(not fast.ability_available, "a unit should react even after spending its normal ability action")

	var lethal_attacker := _make_unit(battlefield, "Lethal", true, Vector2i(1, 5), 12, strike, 100)
	var doomed := _make_unit(battlefield, "Doomed", false, Vector2i(2, 5), 10, null, 0)
	_units = [lethal_attacker, doomed]
	lethal_attacker.reset_opportunity_reaction()
	doomed.reset_movement()
	var movement_before := doomed.remaining_movement
	await doomed.move_along(
		[Vector2i(2, 5), Vector2i(3, 5)],
		Callable(self, "_resolve_step")
	)
	_check(doomed.current_health == 0, "lethal opportunity damage should defeat the mover")
	_check(not doomed.is_present_on_map() and not doomed.visible, "opportunity defeat should remove an enemy from the map")
	_check(doomed.grid_cell == Vector2i(2, 5), "a defeated mover should remain in its pre-step cell")
	_check(is_equal_approx(doomed.remaining_movement, movement_before), "a lethal pre-step reaction should not charge the untraversed step")

	battlefield.queue_free()
	await process_frame
	if _failures.is_empty():
		print("OPPORTUNITY_INTEGRATION_OK")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _resolve_step(
	mover: TacticalCharacter,
	current_cell: Vector2i,
	next_cell: Vector2i
) -> bool:
	for attacker in OpportunityAttackSystem.get_initiative_order(_units):
		if not OpportunityAttackSystem.can_trigger(
			attacker,
			mover,
			current_cell,
			next_cell
		):
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
	return mover.spend_movement(_pathfinder.get_step_cost(current_cell, next_cell))


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
	if ability != null:
		var weapon := ItemDefinition.new()
		weapon.weapon_type = ItemDefinition.WeaponType.MELEE
		weapon.weapon_damage = weapon_damage
		unit.equip_item(weapon)
	return unit


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
