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
	_check(mover.grid_cell == Vector2i(1, 0), "lethal entry damage must stop movement on the Fire cell")
	_check(mover.current_health == 0, "Fire entry must apply damage during animated movement")

	var starter := _make_unit(Vector2i(0, 1), grid)
	terrain.apply_trigger(starter, TileTriggeredEffectDefinition.Trigger.TURN_START)
	_check(starter.current_health == 99, "Fire must damage a unit that starts its turn on the tile")
	_check(grid.get_terrain_definition(Vector2i(1, 0)) == fire, "terrain must register with the grid renderer")

	var main_scene := load("res://main.tscn") as PackedScene
	var main := main_scene.instantiate()
	get_root().add_child(main)
	await process_frame
	var friend_a := main.get_node("Characters/FriendA") as TacticalCharacter
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
	definition.max_health = 100
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
