@tool
class_name IsometricGrid
extends Node2D

@export var grid_size: Vector2i = Vector2i(24, 24):
	set(value):
		var clamped := Vector2i(maxi(1, value.x), maxi(1, value.y))
		if grid_size == clamped:
			return
		grid_size = clamped
		_invalidate_board_cache()

@export var cell_size: Vector2 = Vector2(96.0, 48.0):
	set(value):
		var clamped := Vector2(maxf(8.0, value.x), maxf(4.0, value.y))
		if cell_size == clamped:
			return
		cell_size = clamped
		_invalidate_board_cache()

@export_group("Board Colors")
@export var cell_color: Color = Color("17273b"):
	set(value):
		if cell_color == value:
			return
		cell_color = value
		_invalidate_board_cache()
@export var alternate_cell_color: Color = Color("1b3048"):
	set(value):
		if alternate_cell_color == value:
			return
		alternate_cell_color = value
		_invalidate_board_cache()
@export var grid_line_color: Color = Color("55718f"):
	set(value):
		if grid_line_color == value:
			return
		grid_line_color = value
		queue_redraw()
@export_range(0.5, 6.0, 0.5) var grid_line_width: float = 1.5:
	set(value):
		if grid_line_width == value:
			return
		grid_line_width = value
		queue_redraw()

@export_group("Movement Overlay")
@export var reachable_color: Color = Color(0.16, 0.78, 0.88, 0.38)
@export var movement_attack_color: Color = Color(1.0, 0.40, 0.08, 0.55)
@export var selected_color: Color = Color(0.20, 0.52, 1.0, 0.65)
@export var hover_color: Color = Color(1.0, 0.78, 0.18, 0.68)
@export var path_color: Color = Color("ffd65a")
@export_range(1.0, 12.0, 0.5) var path_line_width: float = 5.0

@export_group("Ability Overlay")
@export var ability_targetable_color: Color = Color(0.55, 0.30, 0.94, 0.38)
@export var ability_valid_target_color: Color = Color(0.72, 0.44, 1.0, 0.62)
@export var ability_area_color: Color = Color(1.0, 0.30, 0.12, 0.48)
@export var ability_valid_color: Color = Color(1.0, 0.72, 0.18, 0.72)
@export var ability_invalid_color: Color = Color(0.88, 0.12, 0.18, 0.68)
@export var ability_trajectory_color: Color = Color("ff9d42")
@export_range(1.0, 12.0, 0.5) var ability_line_width: float = 4.0

var _has_selection := false
var _selected_cell := Vector2i.ZERO
var _reachable_cells: Dictionary = {}
var _has_hover := false
var _hover_cell := Vector2i.ZERO
var _path_cells: Array[Vector2i] = []
var _movement_attack_cells: Dictionary = {}
var _ability_mode := false
var _ability_range_cells: Dictionary = {}
var _ability_target_cells: Dictionary = {}
var _ability_area_cells: Array[Vector2i] = []
var _ability_trajectory_cells: Array[Vector2i] = []
var _ability_hover_valid := false
var _terrain_definitions: Dictionary = {}
var _terrain_colors: Dictionary = {}
var _board_mesh: ArrayMesh
var _grid_line_points := PackedVector2Array()
var _board_cache_dirty := true
var _has_dev_brush_preview := false
var _dev_brush_cell := Vector2i.ZERO
var _dev_brush_color := Color(0.72, 0.78, 0.84, 0.58)
var _dev_brush_valid := true


func grid_to_world(cell: Vector2i) -> Vector2:
	return Vector2(
		float(cell.x - cell.y) * cell_size.x * 0.5,
		float(cell.x + cell.y) * cell_size.y * 0.5
	)


func world_to_grid(local_point: Vector2) -> Vector2i:
	var grid_x := local_point.y / cell_size.y + local_point.x / cell_size.x
	var grid_y := local_point.y / cell_size.y - local_point.x / cell_size.x
	return Vector2i(roundi(grid_x), roundi(grid_y))


func global_to_grid(global_point: Vector2) -> Vector2i:
	return world_to_grid(to_local(global_point))


func grid_to_global(cell: Vector2i) -> Vector2:
	return to_global(grid_to_world(cell))


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


func set_terrain_definitions(definitions: Dictionary) -> void:
	_terrain_definitions = definitions.duplicate()
	var colors: Dictionary = {}
	for cell: Vector2i in _terrain_definitions:
		var definition := get_terrain_definition(cell)
		if definition != null:
			colors[cell] = definition.tile_color
	if colors != _terrain_colors:
		_terrain_colors = colors
		_invalidate_board_cache()


func get_terrain_definition(cell: Vector2i) -> TileDefinition:
	return _terrain_definitions.get(cell) as TileDefinition


func show_dev_brush_preview(cell: Vector2i, color: Color, is_valid: bool) -> void:
	if (_has_dev_brush_preview and _dev_brush_cell == cell
		and _dev_brush_color == color and _dev_brush_valid == is_valid):
		return
	_has_dev_brush_preview = true
	_dev_brush_cell = cell
	_dev_brush_color = color
	_dev_brush_valid = is_valid
	queue_redraw()


func clear_dev_brush_preview() -> void:
	if not _has_dev_brush_preview:
		return
	_has_dev_brush_preview = false
	queue_redraw()


func get_local_bounds() -> Rect2:
	var half_width := cell_size.x * 0.5
	var half_height := cell_size.y * 0.5
	return Rect2(
		Vector2(-float(grid_size.y) * half_width, -half_height),
		Vector2(float(grid_size.x + grid_size.y) * half_width, float(grid_size.x + grid_size.y) * half_height)
	)


func show_reachable(selected_cell: Vector2i, reachable_cells: Dictionary) -> void:
	_clear_ability_state()
	clear_path()
	_has_selection = true
	_selected_cell = selected_cell
	_reachable_cells = reachable_cells.duplicate()
	_reachable_cells.erase(selected_cell)
	queue_redraw()


func show_path(hover_cell: Vector2i, path_cells: Array[Vector2i]) -> void:
	if _has_hover and _hover_cell == hover_cell and _path_cells == path_cells:
		return
	_has_hover = true
	_hover_cell = hover_cell
	_path_cells.clear()
	_path_cells.append_array(path_cells)
	queue_redraw()


func show_movement_attack_preview(range_cells: Dictionary) -> void:
	if _movement_attack_cells == range_cells:
		return
	_movement_attack_cells = range_cells.duplicate()
	queue_redraw()


func clear_path() -> void:
	if not _has_hover and _path_cells.is_empty() and _movement_attack_cells.is_empty():
		return
	_has_hover = false
	_path_cells.clear()
	_movement_attack_cells.clear()
	queue_redraw()


func clear_overlays() -> void:
	if (not _has_selection and not _has_hover and not _ability_mode
		and _reachable_cells.is_empty() and _path_cells.is_empty()
		and _movement_attack_cells.is_empty()
		and _ability_range_cells.is_empty() and _ability_target_cells.is_empty()
		and _ability_area_cells.is_empty() and _ability_trajectory_cells.is_empty()
		and not _ability_hover_valid):
		return
	_has_selection = false
	_has_hover = false
	_reachable_cells.clear()
	_path_cells.clear()
	_movement_attack_cells.clear()
	_clear_ability_state()
	queue_redraw()


func show_ability_targets(
	caster_cell: Vector2i,
	range_cells: Dictionary,
	valid_target_cells: Dictionary = {}
) -> void:
	_has_selection = true
	_selected_cell = caster_cell
	_reachable_cells.clear()
	_has_hover = false
	_path_cells.clear()
	_movement_attack_cells.clear()
	_ability_mode = true
	_ability_range_cells = range_cells.duplicate()
	_ability_target_cells = valid_target_cells.duplicate()
	_ability_area_cells.clear()
	_ability_trajectory_cells.clear()
	queue_redraw()


func show_ability_preview(
	selected_cell: Vector2i,
	affected_cells: Array[Vector2i],
	trajectory_cells: Array[Vector2i],
	is_valid: bool
) -> void:
	if (_has_hover and _hover_cell == selected_cell and _ability_hover_valid == is_valid
		and _ability_area_cells == affected_cells and _ability_trajectory_cells == trajectory_cells):
		return
	_has_hover = true
	_hover_cell = selected_cell
	_ability_hover_valid = is_valid
	_ability_area_cells.clear()
	_ability_area_cells.append_array(affected_cells)
	_ability_trajectory_cells.clear()
	_ability_trajectory_cells.append_array(trajectory_cells)
	queue_redraw()


func clear_ability_preview() -> void:
	if not _has_hover and _ability_area_cells.is_empty() and _ability_trajectory_cells.is_empty():
		return
	_has_hover = false
	_ability_area_cells.clear()
	_ability_trajectory_cells.clear()
	queue_redraw()


func _draw() -> void:
	_ensure_board_cache()
	draw_mesh(_board_mesh, null)
	draw_multiline(_grid_line_points, grid_line_color, grid_line_width, true)

	if _ability_mode:
		for range_cell: Vector2i in _ability_range_cells.keys():
			if is_in_bounds(range_cell):
				_draw_cell(range_cell, ability_targetable_color)
		for target_cell: Vector2i in _ability_target_cells.keys():
			if is_in_bounds(target_cell):
				_draw_cell(target_cell, ability_valid_target_color)
		for area_cell in _ability_area_cells:
			if is_in_bounds(area_cell):
				_draw_cell(area_cell, ability_area_color)
	else:
		for reachable_cell: Vector2i in _reachable_cells.keys():
			if is_in_bounds(reachable_cell):
				_draw_cell(reachable_cell, reachable_color)
		for attack_cell: Vector2i in _movement_attack_cells:
			if is_in_bounds(attack_cell):
				_draw_cell(attack_cell, movement_attack_color)

	if _has_selection and is_in_bounds(_selected_cell):
		_draw_cell(_selected_cell, selected_color)

	if _has_hover and is_in_bounds(_hover_cell):
		var hovered_color := ability_valid_color if _ability_hover_valid else ability_invalid_color
		_draw_cell(_hover_cell, hovered_color if _ability_mode else hover_color)

	if _path_cells.size() > 1:
		var points := PackedVector2Array()
		for path_cell in _path_cells:
			points.append(grid_to_world(path_cell))
		draw_polyline(points, path_color, path_line_width, true)
		for point in points:
			draw_circle(point, path_line_width * 0.72, path_color)

	if _ability_trajectory_cells.size() > 1:
		var trajectory_color := ability_trajectory_color if _ability_hover_valid else ability_invalid_color
		var trajectory_points := PackedVector2Array([
			grid_to_world(_ability_trajectory_cells[0]),
			grid_to_world(_ability_trajectory_cells[_ability_trajectory_cells.size() - 1]),
		])
		draw_polyline(trajectory_points, trajectory_color, ability_line_width, true)
		draw_circle(trajectory_points[0], ability_line_width * 0.75, trajectory_color)
		draw_circle(trajectory_points[1], ability_line_width * 0.75, trajectory_color)

	if _has_dev_brush_preview and is_in_bounds(_dev_brush_cell):
		_draw_cell(
			_dev_brush_cell,
			_dev_brush_color if _dev_brush_valid else ability_invalid_color
		)


func _invalidate_board_cache() -> void:
	_board_cache_dirty = true
	queue_redraw()


func _ensure_board_cache() -> void:
	if not _board_cache_dirty and _board_mesh != null:
		return
	var cell_count := grid_size.x * grid_size.y
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize(cell_count * 4)
	colors.resize(cell_count * 4)
	indices.resize(cell_count * 6)
	var half_width := cell_size.x * 0.5
	var half_height := cell_size.y * 0.5
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell := Vector2i(x, y)
			var center := grid_to_world(cell)
			var cell_index := y * grid_size.x + x
			var vertex_index := cell_index * 4
			vertices[vertex_index] = Vector3(center.x, center.y - half_height, 0.0)
			vertices[vertex_index + 1] = Vector3(center.x + half_width, center.y, 0.0)
			vertices[vertex_index + 2] = Vector3(center.x, center.y + half_height, 0.0)
			vertices[vertex_index + 3] = Vector3(center.x - half_width, center.y, 0.0)
			var base_color := cell_color if (x + y) % 2 == 0 else alternate_cell_color
			var fill_color: Color = _terrain_colors.get(cell, base_color)
			for corner in range(4):
				colors[vertex_index + corner] = fill_color
			var index_offset := cell_index * 6
			indices[index_offset] = vertex_index
			indices[index_offset + 1] = vertex_index + 1
			indices[index_offset + 2] = vertex_index + 2
			indices[index_offset + 3] = vertex_index
			indices[index_offset + 4] = vertex_index + 2
			indices[index_offset + 5] = vertex_index + 3
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	_board_mesh = ArrayMesh.new()
	_board_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# Full rows and columns share their edges, so each grid line is drawn once.
	_grid_line_points.clear()
	for x in range(grid_size.x + 1):
		_grid_line_points.append(_project_grid_point(Vector2(float(x) - 0.5, -0.5)))
		_grid_line_points.append(_project_grid_point(Vector2(float(x) - 0.5, float(grid_size.y) - 0.5)))
	for y in range(grid_size.y + 1):
		_grid_line_points.append(_project_grid_point(Vector2(-0.5, float(y) - 0.5)))
		_grid_line_points.append(_project_grid_point(Vector2(float(grid_size.x) - 0.5, float(y) - 0.5)))
	_board_cache_dirty = false


func _project_grid_point(point: Vector2) -> Vector2:
	return Vector2(
		(point.x - point.y) * cell_size.x * 0.5,
		(point.x + point.y) * cell_size.y * 0.5
	)


func _clear_ability_state() -> void:
	_ability_mode = false
	_ability_range_cells.clear()
	_ability_target_cells.clear()
	_ability_area_cells.clear()
	_ability_trajectory_cells.clear()
	_ability_hover_valid = false


func _draw_cell(cell: Vector2i, fill_color: Color) -> void:
	var center := grid_to_world(cell)
	var half_width := cell_size.x * 0.5
	var half_height := cell_size.y * 0.5
	var points := PackedVector2Array([
		center + Vector2(0.0, -half_height),
		center + Vector2(half_width, 0.0),
		center + Vector2(0.0, half_height),
		center + Vector2(-half_width, 0.0),
	])
	draw_colored_polygon(points, fill_color)
