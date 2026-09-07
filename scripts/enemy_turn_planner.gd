class_name EnemyMovementPlanner
extends RefCounted

const COST_EPSILON := 0.0001
const ADJACENT_DIRECTIONS := [
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
	Vector2i(1, -1),
]


func choose_path(
	enemy: TacticalCharacter,
	friendlies: Array[TacticalCharacter],
	all_units: Array[TacticalCharacter],
	pathfinder: GridPathfinder,
	static_blocked_cells: Dictionary = {}
) -> Array[Vector2i]:
	var no_move: Array[Vector2i] = []
	if enemy == null or enemy.current_health <= 0 or enemy.remaining_movement <= COST_EPSILON:
		return no_move

	var living_friendlies: Array[TacticalCharacter] = []
	for friendly in friendlies:
		if is_instance_valid(friendly) and friendly.current_health > 0:
			living_friendlies.append(friendly)
	if living_friendlies.is_empty():
		return no_move

	var blocked_cells := _get_blocked_cells(enemy, all_units, static_blocked_cells)
	var best_path: Array[Vector2i] = []
	var best_cost := INF

	for friendly in living_friendlies:
		for direction: Vector2i in ADJACENT_DIRECTIONS:
			var destination := friendly.grid_cell + direction
			if not pathfinder.is_in_bounds(destination) or blocked_cells.has(destination):
				continue
			var candidate_path := pathfinder.find_path(enemy.grid_cell, destination, INF, blocked_cells)
			if candidate_path.is_empty():
				continue
			var candidate_cost := pathfinder.get_path_cost(candidate_path)
			if candidate_cost < best_cost - COST_EPSILON:
				best_cost = candidate_cost
				best_path = candidate_path

	if not best_path.is_empty():
		return _trim_to_budget(best_path, enemy.remaining_movement, pathfinder)

	return _choose_fallback_path(enemy, living_friendlies, blocked_cells, pathfinder)


func _choose_fallback_path(
	enemy: TacticalCharacter,
	friendlies: Array[TacticalCharacter],
	blocked_cells: Dictionary,
	pathfinder: GridPathfinder
) -> Array[Vector2i]:
	var reachable := pathfinder.get_reachable(enemy.grid_cell, enemy.remaining_movement, blocked_cells)
	var best_cell := enemy.grid_cell
	var best_distance := _distance_to_nearest_friendly(best_cell, friendlies)
	var best_move_cost := 0.0

	for candidate: Vector2i in reachable.keys():
		var candidate_distance := _distance_to_nearest_friendly(candidate, friendlies)
		var candidate_move_cost: float = reachable[candidate]
		if candidate_distance < best_distance - COST_EPSILON:
			best_cell = candidate
			best_distance = candidate_distance
			best_move_cost = candidate_move_cost
		elif is_equal_approx(candidate_distance, best_distance) and candidate_move_cost < best_move_cost:
			best_cell = candidate
			best_move_cost = candidate_move_cost

	if best_cell == enemy.grid_cell:
		return _empty_path()
	return pathfinder.find_path(enemy.grid_cell, best_cell, enemy.remaining_movement, blocked_cells)


func _trim_to_budget(
	path: Array[Vector2i],
	budget: float,
	pathfinder: GridPathfinder
) -> Array[Vector2i]:
	if path.is_empty():
		return _empty_path()
	var result: Array[Vector2i] = [path[0]]
	var spent := 0.0
	for index in range(1, path.size()):
		var segment: Array[Vector2i] = [path[index - 1], path[index]]
		var step_cost := pathfinder.get_path_cost(segment)
		if spent + step_cost > budget + COST_EPSILON:
			break
		spent += step_cost
		result.append(path[index])
	if result.size() > 1:
		return result
	return _empty_path()


func _get_blocked_cells(
	enemy: TacticalCharacter,
	all_units: Array[TacticalCharacter],
	static_blocked_cells: Dictionary = {}
) -> Dictionary:
	var blocked: Dictionary = static_blocked_cells.duplicate()
	for unit in all_units:
		if is_instance_valid(unit) and unit != enemy and unit.is_present_on_map():
			blocked[unit.grid_cell] = true
	return blocked


func _distance_to_nearest_friendly(cell: Vector2i, friendlies: Array[TacticalCharacter]) -> float:
	var nearest := INF
	for friendly in friendlies:
		var difference := (friendly.grid_cell - cell).abs()
		var diagonal_steps := mini(difference.x, difference.y)
		var straight_steps := maxi(difference.x, difference.y) - diagonal_steps
		var distance := float(diagonal_steps) * GridPathfinder.DIAGONAL_COST + float(straight_steps)
		nearest = minf(nearest, distance)
	return nearest


func _empty_path() -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	return path
