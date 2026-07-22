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


func _init(initial_grid_size: Vector2i = Vector2i.ONE) -> void:
	grid_size = Vector2i(maxi(1, initial_grid_size.x), maxi(1, initial_grid_size.y))


func set_grid_size(value: Vector2i) -> void:
	grid_size = Vector2i(maxi(1, value.x), maxi(1, value.y))


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


func get_reachable(start: Vector2i, budget: float, blocked_cells: Dictionary = {}) -> Dictionary:
	var costs: Dictionary = {}
	if not is_in_bounds(start) or budget < 0.0:
		return costs

	var open_cells: Array[Vector2i] = [start]
	costs[start] = 0.0

	while not open_cells.is_empty():
		var current := _pop_lowest_cost(open_cells, costs)
		var current_cost: float = costs[current]
		for neighbor in _get_neighbors(current, blocked_cells):
			var new_cost := current_cost + _step_cost(current, neighbor)
			if new_cost > budget + COST_EPSILON:
				continue
			if not costs.has(neighbor) or new_cost < float(costs[neighbor]) - COST_EPSILON:
				costs[neighbor] = new_cost
				if not open_cells.has(neighbor):
					open_cells.append(neighbor)

	return costs


func find_path(
	start: Vector2i,
	destination: Vector2i,
	budget: float = INF,
	blocked_cells: Dictionary = {}
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
	var came_from: Dictionary = {}
	var open_cells: Array[Vector2i] = [start]

	while not open_cells.is_empty():
		var current := _pop_lowest_cost(open_cells, costs)
		if current == destination:
			return _reconstruct_path(start, destination, came_from)

		var current_cost: float = costs[current]
		for neighbor in _get_neighbors(current, blocked_cells):
			var new_cost := current_cost + _step_cost(current, neighbor)
			if new_cost > budget + COST_EPSILON:
				continue
			if not costs.has(neighbor) or new_cost < float(costs[neighbor]) - COST_EPSILON:
				costs[neighbor] = new_cost
				came_from[neighbor] = current
				if not open_cells.has(neighbor):
					open_cells.append(neighbor)

	return empty_path


func get_path_cost(path: Array[Vector2i]) -> float:
	var total := 0.0
	for index in range(1, path.size()):
		total += _step_cost(path[index - 1], path[index])
	return total


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


func _step_cost(from_cell: Vector2i, to_cell: Vector2i) -> float:
	var difference := to_cell - from_cell
	return DIAGONAL_COST if difference.x != 0 and difference.y != 0 else ORTHOGONAL_COST


func _pop_lowest_cost(open_cells: Array[Vector2i], costs: Dictionary) -> Vector2i:
	var best_index := 0
	var best_cost: float = costs[open_cells[0]]
	for index in range(1, open_cells.size()):
		var candidate_cost: float = costs[open_cells[index]]
		if candidate_cost < best_cost:
			best_cost = candidate_cost
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
