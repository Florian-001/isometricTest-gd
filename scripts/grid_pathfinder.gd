class_name GridPathfinder
extends RefCounted

const ORTHOGONAL_COST := 1.0
const DIAGONAL_COST := 1.414
const COST_EPSILON := 0.0001
const DIRECTIONS := [
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
	Vector2i(1, -1),
]

var grid_size: Vector2i
var cell_cost_multipliers: Dictionary = {}


func _init(initial_grid_size: Vector2i = Vector2i.ONE) -> void:
	grid_size = Vector2i(maxi(1, initial_grid_size.x), maxi(1, initial_grid_size.y))


func set_grid_size(value: Vector2i) -> void:
	grid_size = Vector2i(maxi(1, value.x), maxi(1, value.y))


func set_cell_cost_multipliers(costs: Dictionary) -> void:
	cell_cost_multipliers.clear()
	for cell_value in costs:
		if cell_value is Vector2i:
			cell_cost_multipliers[cell_value] = maxf(0.0, float(costs[cell_value]))


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


func get_reachable(start: Vector2i, budget: float, blocked_cells: Dictionary = {}) -> Dictionary:
	return build_reachability(start, budget, blocked_cells)["costs"] as Dictionary


## Runs one deterministic weighted search and retains enough information to reconstruct
## any path in the result without searching the grid again.
func build_reachability(
	start: Vector2i,
	budget: float,
	blocked_cells: Dictionary = {},
	cell_preference_penalties: Dictionary = {}
) -> Dictionary:
	var costs: Dictionary = {}
	var preference_costs: Dictionary = {}
	var came_from: Dictionary = {}
	if not is_in_bounds(start) or budget < 0.0:
		return {
			"start": start,
			"costs": costs,
			"preference_costs": preference_costs,
			"came_from": came_from,
		}

	var open_cells: Array[Vector2i] = [start]
	costs[start] = 0.0
	preference_costs[start] = 0.0
	while not open_cells.is_empty():
		var current := _pop_lowest_cost(open_cells, costs, preference_costs)
		var current_cost: float = costs[current]
		for neighbor in _get_neighbors(current, blocked_cells):
			var new_cost := current_cost + get_step_cost(current, neighbor)
			if new_cost > budget + COST_EPSILON:
				continue
			var new_preference_cost := (
				float(preference_costs[current])
				+ maxf(0.0, float(cell_preference_penalties.get(neighbor, 0.0)))
			)
			var is_cheaper := (
				not costs.has(neighbor)
				or new_cost < float(costs[neighbor]) - COST_EPSILON
			)
			var is_safer_tie := (
				costs.has(neighbor)
				and is_equal_approx(new_cost, float(costs[neighbor]))
				and new_preference_cost < float(preference_costs[neighbor]) - COST_EPSILON
			)
			if is_cheaper or is_safer_tie:
				costs[neighbor] = new_cost
				preference_costs[neighbor] = new_preference_cost
				came_from[neighbor] = current
				if not open_cells.has(neighbor):
					open_cells.append(neighbor)

	return {
		"start": start,
		"costs": costs,
		"preference_costs": preference_costs,
		"came_from": came_from,
	}


func reconstruct_reachable_path(result: Dictionary, destination: Vector2i) -> Array[Vector2i]:
	var start := result.get("start", Vector2i(-1, -1)) as Vector2i
	var costs := result.get("costs", {}) as Dictionary
	if not costs.has(destination):
		return [] as Array[Vector2i]
	if destination == start:
		return [start] as Array[Vector2i]
	return _reconstruct_path(
		start,
		destination,
		result.get("came_from", {}) as Dictionary
	)


func find_path(
	start: Vector2i,
	destination: Vector2i,
	budget: float = INF,
	blocked_cells: Dictionary = {},
	cell_preference_penalties: Dictionary = {}
) -> Array[Vector2i]:
	var empty_path: Array[Vector2i] = []
	if not is_in_bounds(start) or not is_in_bounds(destination):
		return empty_path
	if start == destination:
		var same_cell_path: Array[Vector2i] = [start]
		return same_cell_path
	if blocked_cells.has(destination):
		return empty_path

	var costs: Dictionary = {start: 0.0}
	var preference_costs: Dictionary = {start: 0.0}
	var came_from: Dictionary = {}
	var open_cells: Array[Vector2i] = [start]

	while not open_cells.is_empty():
		var current := _pop_lowest_cost(open_cells, costs, preference_costs)
		if current == destination:
			return _reconstruct_path(start, destination, came_from)

		var current_cost: float = costs[current]
		for neighbor in _get_neighbors(current, blocked_cells):
			var new_cost := current_cost + get_step_cost(current, neighbor)
			var new_preference_cost := (
				float(preference_costs[current])
				+ maxf(0.0, float(cell_preference_penalties.get(neighbor, 0.0)))
			)
			if new_cost > budget + COST_EPSILON:
				continue
			var is_cheaper := (
				not costs.has(neighbor)
				or new_cost < float(costs[neighbor]) - COST_EPSILON
			)
			var is_safer_tie := (
				costs.has(neighbor)
				and is_equal_approx(new_cost, float(costs[neighbor]))
				and new_preference_cost < float(preference_costs[neighbor]) - COST_EPSILON
			)
			if is_cheaper or is_safer_tie:
				costs[neighbor] = new_cost
				preference_costs[neighbor] = new_preference_cost
				came_from[neighbor] = current
				if not open_cells.has(neighbor):
					open_cells.append(neighbor)

	return empty_path


func get_path_cost(path: Array[Vector2i]) -> float:
	var total := 0.0
	for index in range(1, path.size()):
		total += get_step_cost(path[index - 1], path[index])
	return total


func get_step_cost(from_cell: Vector2i, to_cell: Vector2i) -> float:
	var difference := to_cell - from_cell
	var base_cost := (
		DIAGONAL_COST
		if difference.x != 0 and difference.y != 0
		else ORTHOGONAL_COST
	)
	return base_cost * float(cell_cost_multipliers.get(to_cell, 1.0))


func is_path_walkable(path: Array[Vector2i], blocked_cells: Dictionary = {}) -> bool:
	if path.is_empty() or not is_in_bounds(path[0]):
		return false
	for index in range(1, path.size()):
		var from_cell := path[index - 1]
		var to_cell := path[index]
		var difference := to_cell - from_cell
		if (
			not is_in_bounds(to_cell)
			or blocked_cells.has(to_cell)
			or difference == Vector2i.ZERO
			or absi(difference.x) > 1
			or absi(difference.y) > 1
		):
			return false
		if difference.x != 0 and difference.y != 0:
			var horizontal_side := from_cell + Vector2i(difference.x, 0)
			var vertical_side := from_cell + Vector2i(0, difference.y)
			if (
				not _is_walkable(horizontal_side, blocked_cells)
				or not _is_walkable(vertical_side, blocked_cells)
			):
				return false
	return true


func _get_neighbors(cell: Vector2i, blocked_cells: Dictionary) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for direction: Vector2i in DIRECTIONS:
		var neighbor := cell + direction
		if not _is_walkable(neighbor, blocked_cells):
			continue

		if direction.x != 0 and direction.y != 0:
			var horizontal_side := cell + Vector2i(direction.x, 0)
			var vertical_side := cell + Vector2i(0, direction.y)
			if not _is_walkable(horizontal_side, blocked_cells) or not _is_walkable(vertical_side, blocked_cells):
				continue

		neighbors.append(neighbor)
	return neighbors


func _is_walkable(cell: Vector2i, blocked_cells: Dictionary) -> bool:
	return is_in_bounds(cell) and not blocked_cells.has(cell)


func _pop_lowest_cost(
	open_cells: Array[Vector2i],
	costs: Dictionary,
	preference_costs: Dictionary = {}
) -> Vector2i:
	var best_index := 0
	var best_cost: float = costs[open_cells[0]]
	var best_preference := float(preference_costs.get(open_cells[0], 0.0))
	for index in range(1, open_cells.size()):
		var candidate_cost: float = costs[open_cells[index]]
		var candidate_preference := float(preference_costs.get(open_cells[index], 0.0))
		if (
			candidate_cost < best_cost
			or (
				is_equal_approx(candidate_cost, best_cost)
				and candidate_preference < best_preference
			)
		):
			best_cost = candidate_cost
			best_preference = candidate_preference
			best_index = index
	return open_cells.pop_at(best_index)


func _reconstruct_path(start: Vector2i, destination: Vector2i, came_from: Dictionary) -> Array[Vector2i]:
	var path: Array[Vector2i] = [destination]
	var current := destination
	while current != start:
		if not came_from.has(current):
			var empty_path: Array[Vector2i] = []
			return empty_path
		current = came_from[current]
		path.push_front(current)
	return path
