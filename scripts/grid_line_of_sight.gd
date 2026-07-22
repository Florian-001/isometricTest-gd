class_name GridLineOfSight
extends RefCounted


func get_line_cells(start: Vector2i, destination: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var x0 := start.x
	var y0 := start.y
	var x1 := destination.x
	var y1 := destination.y
	var dx := absi(x1 - x0)
	var sx := 1 if x0 < x1 else -1
	var dy := -absi(y1 - y0)
	var sy := 1 if y0 < y1 else -1
	var error := dx + dy

	while true:
		cells.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var doubled_error := error * 2
		if doubled_error >= dy:
			error += dy
			x0 += sx
		if doubled_error <= dx:
			error += dx
			y0 += sy
	return cells


func has_line_of_sight(start: Vector2i, destination: Vector2i, wall_cells: Dictionary = {}) -> bool:
	return get_first_blocking_wall(start, destination, wall_cells) == Vector2i(-1, -1)


func get_first_blocking_wall(
	start: Vector2i,
	destination: Vector2i,
	wall_cells: Dictionary = {}
) -> Vector2i:
	var line := get_line_cells(start, destination)
	for index in range(1, line.size()):
		if wall_cells.has(line[index]):
			return line[index]
	return Vector2i(-1, -1)
