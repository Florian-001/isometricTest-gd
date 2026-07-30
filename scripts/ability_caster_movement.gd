class_name AbilityCasterMovement
extends RefCounted


## Returns the grid path from the caster's current cell to the open cell immediately
## before the target. An empty result means the charge is invalid.
static func get_charge_path(
	start_cell: Vector2i,
	target_cell: Vector2i,
	grid_size: Vector2i,
	blocked_cells: Dictionary = {}
) -> Array[Vector2i]:
	var empty_path: Array[Vector2i] = []
	if (
		grid_size.x <= 0
		or grid_size.y <= 0
		or not _is_in_bounds(start_cell, grid_size)
		or not _is_in_bounds(target_cell, grid_size)
		or start_cell == target_cell
	):
		return empty_path

	var difference := target_cell - start_cell
	if not _is_straight_direction(difference):
		return empty_path

	var direction := Vector2i(signi(difference.x), signi(difference.y))
	var distance := maxi(absi(difference.x), absi(difference.y))
	var landing_cell := target_cell - direction
	if blocked_cells.has(landing_cell):
		return empty_path

	var path: Array[Vector2i] = [start_cell]
	for step in range(1, distance):
		path.append(start_cell + direction * step)

	var pathfinder := GridPathfinder.new(grid_size)
	if not pathfinder.is_path_walkable(path, blocked_cells):
		return empty_path
	return path


static func get_landing_cell(path: Array[Vector2i]) -> Vector2i:
	return path[path.size() - 1] if not path.is_empty() else Vector2i(-1, -1)


static func _is_straight_direction(difference: Vector2i) -> bool:
	return (
		difference.x == 0
		or difference.y == 0
		or absi(difference.x) == absi(difference.y)
	)


static func _is_in_bounds(cell: Vector2i, grid_size: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.y >= 0
		and cell.x < grid_size.x
		and cell.y < grid_size.y
	)
