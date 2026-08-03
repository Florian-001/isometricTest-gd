extends SceneTree

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var battle := Node2D.new()
	get_root().add_child(battle)

	var grid := IsometricGrid.new()
	grid.name = "Grid"
	grid.grid_size = Vector2i(3, 2)
	battle.add_child(grid)

	var walls := Node2D.new()
	walls.name = "Walls"
	battle.add_child(walls)

	var terrain := TacticalTerrain.new()
	terrain.name = "Terrain"
	battle.add_child(terrain)
	var fire := load("res://resources/tiles/fire.tres") as TileDefinition
	for cell in [Vector2i(1, 0), Vector2i(0, 1)]:
		var tile := TacticalTile.new()
		tile.definition = fire
		tile.grid_cell = cell
		terrain.add_child(tile)
	terrain.initialize(grid)

	var mover := _make_unit(Vector2i(0, 0), grid)
	mover.current_health = 1
	mover.movement_animation_speed = 5000.0
	mover.cell_entered.connect(func(unit: TacticalCharacter, _cell: Vector2i) -> void:
		terrain.apply_trigger(unit, TileTriggeredEffectDefinition.Trigger.ENTER)
	)
	await mover.move_along([
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(2, 0),
	])
	_check(mover.grid_cell == Vector2i(2, 0), "Fire should no longer interrupt movement with immediate damage")
	_check(mover.current_health == 1, "entering Fire should apply Burning without immediate damage")
	_check(mover.get_active_statuses().size() == 1, "animated Fire entry should apply one Burning status")
	mover.process_status_turn_start()
	_check(mover.current_health == 0, "Burning should deal lethal damage at the next turn start")

	var starter := _make_unit(Vector2i(0, 1), grid)
	terrain.apply_trigger(starter, TileTriggeredEffectDefinition.Trigger.TURN_START)
	starter.process_status_turn_start()
	_check(starter.current_health == 99, "Fire must damage a unit that starts its turn on the tile")
	_check(starter.get_active_statuses()[0].source == fire, "turn-start terrain should be recorded as the status source")
	_check(grid.get_terrain_definition(Vector2i(1, 0)) == fire, "terrain must register with the grid renderer")

	var ice := load("res://resources/tiles/ice.tres") as TileDefinition
	var slowed := _make_unit(Vector2i(2, 1), grid)
	slowed.movement_range_override = 6.0
	ice.apply_trigger(slowed, TileTriggeredEffectDefinition.Trigger.ENTER)
	_check(is_equal_approx(slowed.get_movement_range(), 4.2), "Ice should reduce movement from 6 to 4.2")
	_check(slowed.get_active_statuses()[0].source == ice, "Ice should be recorded as the Slow source")

	var doomed := _make_unit(Vector2i(0, 1), grid)
	var survivor := _make_unit(Vector2i(2, 0), grid)
	doomed.current_health = 1
	var manager := TurnManager.new()
	battle.add_child(manager)
	var started_units: Array[TacticalCharacter] = []
	manager.turn_starting.connect(func(unit: TacticalCharacter):
		terrain.apply_trigger(unit, TileTriggeredEffectDefinition.Trigger.TURN_START)
	)
	manager.turn_started.connect(func(unit: TacticalCharacter): started_units.append(unit))
	var ordered_units: Array[TacticalCharacter] = [doomed, survivor]
	manager.start_combat(ordered_units)
	await process_frame
	_check(doomed.current_health == 0, "lethal turn-start Burning should defeat the unit before it acts")
	_check(manager.current_unit == survivor, "combat should advance past a unit defeated by turn-start status damage")
	_check(started_units == [survivor], "a unit defeated during turn-start processing should not emit an actionable turn")

	var main_scene := load("res://scenes/battle.tscn") as PackedScene
	var main := main_scene.instantiate()
	main.map_definition = load("res://resources/maps/terrain_showcase.tres") as BattleMapDefinition
	get_root().add_child(main)
	await process_frame
	var friend_a := main.characters_container.get_node("FriendA") as TacticalCharacter
	var movement_before := friend_a.remaining_movement
	var mud_path: Array[Vector2i] = [Vector2i(2, 3), Vector2i(3, 4)]
	await main._begin_friendly_move(mud_path)
	_check(friend_a.grid_cell == Vector2i(3, 4), "friendly movement should enter the sample Mud tile")
	_check(
		is_equal_approx(
			friend_a.remaining_movement,
			movement_before - GridPathfinder.DIAGONAL_COST * 2.0
		),
		"friendly movement must spend the terrain-weighted cost of the path actually traversed"
	)

	main.queue_free()
	battle.queue_free()
	await process_frame
	if _failed:
		quit(1)
	else:
		print("TERRAIN_INTEGRATION_OK")
		quit(0)


func _make_unit(cell: Vector2i, grid: IsometricGrid) -> TacticalCharacter:
	var definition := CharacterDefinition.new()
	definition.constitution = 25
	var unit := TacticalCharacter.new()
	unit.definition = definition
	unit.starting_grid_cell = cell
	get_root().add_child(unit)
	unit.initialize(grid)
	return unit


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
