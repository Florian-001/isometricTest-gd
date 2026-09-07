extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var battlefield := Node2D.new()
	battlefield.name = "MeleeIntegration"
	root.add_child(battlefield)

	var grid := IsometricGrid.new()
	grid.grid_size = Vector2i(6, 6)
	battlefield.add_child(grid)

	var caster := _make_character(true, Vector2i(1, 1))
	var target := _make_character(false, Vector2i(2, 1))
	caster.initial_facing = TacticalCharacter.Facing.LEFT
	battlefield.add_child(caster)
	battlefield.add_child(target)
	caster.initialize(grid)
	target.initialize(grid)
	var weapon := ItemDefinition.new()
	weapon.weapon_damage = 20
	caster.equip_item(weapon)
	caster.reset_movement()
	caster.reset_ability_action()

	var executor := AbilityExecutor.new()
	battlefield.add_child(executor)
	var targeting := AbilityTargeting.new(grid.grid_size)
	var strike := (load("res://resources/abilities/strike.tres") as AbilityDefinition).duplicate(true) as AbilityDefinition
	strike.melee_lunge_duration = 0.02
	strike.melee_return_duration = 0.02
	strike.melee_slash_duration = 0.02
	caster.set_dev_ability_loadout([strike])
	var units: Array[TacticalCharacter] = [caster, target]
	var original_position := caster.global_position
	var original_cell := caster.grid_cell
	var original_movement := caster.remaining_movement
	var signal_order: Array[String] = []
	executor.melee_delivery.melee_started.connect(func(_caster, _ability, _cell): signal_order.append("started"))
	executor.melee_delivery.melee_impact.connect(func(_caster, _ability, _cell): signal_order.append("impact"))
	executor.melee_delivery.melee_finished.connect(func(_caster, _ability, _cell): signal_order.append("finished"))

	var succeeded: bool = await executor.execute(
		caster,
		strike,
		target.grid_cell,
		units,
		grid,
		targeting,
		{}
	)
	await process_frame

	_check(succeeded, "Strike should complete successfully")
	_check(target.current_health == 70, "Strike should deal 30 damage at impact")
	var damage_numbers := target.get_children().filter(func(child): return child.has_meta("damage_number"))
	_check(damage_numbers.size() == 1, "Taking damage should create one floating damage number")
	_check(damage_numbers[0].text == "-30", "The floating number should show the actual health lost")
	_check(not caster.ability_available, "Strike should consume the ability action")
	_check(caster.grid_cell == original_cell, "Strike must not change grid occupancy")
	_check(caster.global_position.is_equal_approx(original_position), "The caster should return to its exact starting position")
	_check(caster.current_facing == TacticalCharacter.Facing.RIGHT, "using an ability should face the caster toward a target on screen-right")
	_check(is_equal_approx(caster.remaining_movement, original_movement), "Strike must not consume movement")
	_check(signal_order == ["started", "impact", "finished"], "Melee signals should fire once in order")
	_check(not battlefield.has_node("MeleeSlash"), "The slash visual should be cleaned up")

	caster.reset_ability_action()
	var focus := load("res://resources/abilities/focus.tres") as AbilityDefinition
	caster.set_dev_ability_loadout([focus])
	var focus_succeeded: bool = await executor.execute(
		caster,
		focus,
		caster.grid_cell,
		units,
		grid,
		targeting,
		{}
	)
	_check(focus_succeeded, "Focus should execute through the normal ability pipeline")
	_check(caster.get_active_statuses().size() == 1, "Focus should add one active status")
	_check(is_equal_approx(caster.get_effective_stat(UnitStat.Type.STRENGTH), 12.0), "Focus should grant Strength")

	caster.reset_ability_action()
	var slow := load("res://resources/abilities/slow.tres") as AbilityDefinition
	caster.set_dev_ability_loadout([slow])
	var slow_succeeded: bool = await executor.execute(
		caster,
		slow,
		target.grid_cell,
		units,
		grid,
		targeting,
		{}
	)
	_check(slow_succeeded, "Slow should execute through the normal ability pipeline")
	_check(target.get_active_statuses().size() == 1, "Slow should add one active status")
	_check(is_equal_approx(target.get_movement_range(), 4.2), "Slow should reduce Movement Range by 30%")
	_check(target.get_initiative() == 10, "Slow should leave initiative unchanged")

	battlefield.queue_free()
	if _failures.is_empty():
		print("MELEE_INTEGRATION_OK")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _make_character(friendly: bool, cell: Vector2i) -> TacticalCharacter:
	var definition := CharacterDefinition.new()
	definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	definition.constitution = 25
	definition.movement_range = 6.0
	var character := TacticalCharacter.new()
	character.definition = definition
	character.starting_grid_cell = cell
	return character


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
