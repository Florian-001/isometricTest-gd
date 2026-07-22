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
	battlefield.add_child(caster)
	battlefield.add_child(target)
	caster.initialize(grid)
	target.initialize(grid)
	caster.reset_movement()
	caster.reset_ability_action()

	var executor := AbilityExecutor.new()
	battlefield.add_child(executor)
	var targeting := AbilityTargeting.new(grid.grid_size)
	var strike := (load("res://resources/abilities/strike.tres") as AbilityDefinition).duplicate(true) as AbilityDefinition
	strike.melee_lunge_duration = 0.02
	strike.melee_return_duration = 0.02
	strike.melee_slash_duration = 0.02
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
	_check(not caster.ability_available, "Strike should consume the ability action")
	_check(caster.grid_cell == original_cell, "Strike must not change grid occupancy")
	_check(caster.global_position.is_equal_approx(original_position), "The caster should return to its exact starting position")
	_check(is_equal_approx(caster.remaining_movement, original_movement), "Strike must not consume movement")
	_check(signal_order == ["started", "impact", "finished"], "Melee signals should fire once in order")
	_check(not battlefield.has_node("MeleeSlash"), "The slash visual should be cleaned up")

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
	definition.max_health = 100
	definition.movement_range = 6.0
	var character := TacticalCharacter.new()
	character.definition = definition
	character.starting_grid_cell = cell
	return character


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
