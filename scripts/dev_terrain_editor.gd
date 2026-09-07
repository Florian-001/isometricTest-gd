class_name DevTerrainEditor
extends Node

signal environment_refresh_requested
signal environment_changed
signal history_changed(can_undo: bool, can_redo: bool)
signal message_requested(message: String, is_error: bool)

enum BrushKind {
	TILE,
	WALL,
	ERASE,
}

var _grid: IsometricGrid
var _terrain: TacticalTerrain
var _walls_container: Node2D
var _characters: Array[TacticalCharacter] = []
var _brush_kind := BrushKind.ERASE
var _brush_resource: Resource
var _stroke_active := false
var _stroke_before: Dictionary = {}
var _stroke_changed := false
var _last_stroke_cell := Vector2i.ZERO
var _visited_cells: Dictionary = {}
var _original_environment: Dictionary = {}
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _reported_invalid_wall := false
var _reported_invalid_cell := false


func setup(
	grid: IsometricGrid,
	terrain: TacticalTerrain,
	walls_container: Node2D,
	characters: Array[TacticalCharacter],
	original_environment: Dictionary = {}
) -> void:
	_grid = grid
	_terrain = terrain
	_walls_container = walls_container
	_characters.assign(characters)
	_original_environment = (
		capture_environment()
		if original_environment.is_empty()
		else original_environment.duplicate(true)
	)
	clear_history()


func set_characters(characters: Array[TacticalCharacter]) -> void:
	_characters.assign(characters)


func set_brush(kind: int, brush_resource: Resource) -> void:
	_brush_kind = kind
	_brush_resource = brush_resource


func begin_stroke(cell: Vector2i, force_erase := false) -> void:
	if _grid == null or _terrain == null or _walls_container == null:
		return
	end_stroke()
	_stroke_active = true
	_stroke_before = capture_environment()
	_terrain.begin_batch_edit()
	_stroke_changed = false
	_last_stroke_cell = cell
	_visited_cells.clear()
	_reported_invalid_wall = false
	_reported_invalid_cell = false
	_apply_stroke_cell(cell, force_erase)


func update_stroke(cell: Vector2i, force_erase := false) -> void:
	if not _stroke_active:
		return
	for interpolated_cell in _interpolate_cells(_last_stroke_cell, cell):
		_apply_stroke_cell(interpolated_cell, force_erase)
	_last_stroke_cell = cell


func end_stroke() -> bool:
	if not _stroke_active:
		return false
	_stroke_active = false
	_terrain.end_batch_edit(false)
	if not _stroke_changed:
		_visited_cells.clear()
		return false
	environment_refresh_requested.emit()
	var after := capture_environment()
	if after == _stroke_before:
		_visited_cells.clear()
		return false
	_push_history(_stroke_before, after)
	_visited_cells.clear()
	environment_changed.emit()
	return true


func cancel_stroke() -> void:
	if not _stroke_active:
		return
	if _stroke_changed:
		_apply_environment(_stroke_before)
	else:
		_terrain.end_batch_edit(false)
	_stroke_active = false
	_stroke_changed = false
	_visited_cells.clear()


func undo() -> bool:
	end_stroke()
	if _undo_stack.is_empty():
		return false
	var command: Dictionary = _undo_stack.pop_back()
	_apply_environment(command["before"])
	_redo_stack.append(command)
	_emit_history_state()
	environment_changed.emit()
	message_requested.emit("Terrain edit undone.", false)
	return true


func redo() -> bool:
	end_stroke()
	if _redo_stack.is_empty():
		return false
	var command: Dictionary = _redo_stack.pop_back()
	_apply_environment(command["after"])
	_undo_stack.append(command)
	_emit_history_state()
	environment_changed.emit()
	message_requested.emit("Terrain edit restored.", false)
	return true


func reset_to_map() -> bool:
	end_stroke()
	var before := capture_environment()
	if before == _original_environment:
		message_requested.emit("The map already matches its authored terrain.", false)
		return false
	_apply_environment(_original_environment)
	var after := capture_environment()
	_push_history(before, after)
	environment_changed.emit()
	message_requested.emit("Restored the map's authored terrain and walls.", false)
	return true


func clear_history() -> void:
	cancel_stroke()
	_undo_stack.clear()
	_redo_stack.clear()
	_emit_history_state()


func capture_environment() -> Dictionary:
	var terrain_entries: Array[Dictionary] = []
	if _terrain != null:
		for child in _terrain.get_children():
			if not child is TacticalTile:
				continue
			var tile := child as TacticalTile
			if tile.definition == null or tile.definition.resource_path.is_empty():
				continue
			terrain_entries.append({
				"cell": [tile.grid_cell.x, tile.grid_cell.y],
				"definition": tile.definition.resource_path,
			})
	var wall_entries: Array[Dictionary] = []
	if _walls_container != null:
		for child in _walls_container.get_children():
			if child is TacticalWall:
				wall_entries.append((child as TacticalWall).capture_setup_state())
	terrain_entries.sort_custom(_entry_cell_less)
	wall_entries.sort_custom(_entry_cell_less)
	return {
		"terrain": terrain_entries,
		"walls": wall_entries,
	}


func get_brush_preview(cell: Vector2i, force_erase := false) -> Dictionary:
	var kind := BrushKind.ERASE if force_erase else _brush_kind
	var valid := _grid != null and _grid.is_in_bounds(cell)
	var color := Color(0.72, 0.78, 0.84, 0.58)
	if kind == BrushKind.TILE and _brush_resource is TileDefinition:
		color = (_brush_resource as TileDefinition).tile_color.lightened(0.22)
	elif kind == BrushKind.WALL and _brush_resource is WallDefinition:
		color = (_brush_resource as WallDefinition).top_color.lightened(0.22)
		valid = valid and not _cell_reserved_by_unit(cell)
	elif kind != BrushKind.ERASE:
		valid = false
	return {"valid": valid, "color": color}


func _apply_stroke_cell(cell: Vector2i, force_erase: bool) -> void:
	if _visited_cells.has(cell):
		return
	_visited_cells[cell] = true
	if not _grid.is_in_bounds(cell):
		if not _reported_invalid_cell:
			message_requested.emit("That cell is outside the map.", true)
			_reported_invalid_cell = true
		return
	var kind := BrushKind.ERASE if force_erase else _brush_kind
	var changed := false
	match kind:
		BrushKind.TILE:
			if not _brush_resource is TileDefinition:
				return
			changed = _remove_wall(cell)
			changed = _terrain.set_tile(cell, _brush_resource as TileDefinition) or changed
		BrushKind.WALL:
			if not _brush_resource is WallDefinition:
				return
			if _cell_reserved_by_unit(cell):
				if not _reported_invalid_wall:
					message_requested.emit("Walls cannot be placed on a unit's current or restart cell.", true)
					_reported_invalid_wall = true
				return
			var existing_wall := _find_wall(cell)
			var same_wall := (
				existing_wall != null
				and existing_wall.definition == _brush_resource
				and _find_tile(cell) == null
			)
			if same_wall:
				return
			changed = _terrain.erase_tile(cell)
			changed = _remove_wall(cell) or changed
			var wall := TacticalWall.new()
			wall.name = "Wall_%d_%d" % [cell.x, cell.y]
			wall.grid_cell = cell
			wall.definition = _brush_resource as WallDefinition
			_walls_container.add_child(wall)
			wall.initialize(_grid)
			changed = true
		BrushKind.ERASE:
			changed = _terrain.erase_tile(cell)
			changed = _remove_wall(cell) or changed
	_stroke_changed = _stroke_changed or changed


func _cell_reserved_by_unit(cell: Vector2i) -> bool:
	for character in _characters:
		if not is_instance_valid(character):
			continue
		if character.grid_cell == cell or character.starting_grid_cell == cell:
			return true
	return false


func _find_tile(cell: Vector2i) -> TacticalTile:
	for child in _terrain.get_children():
		if child is TacticalTile and child.grid_cell == cell:
			return child as TacticalTile
	return null


func _find_wall(cell: Vector2i) -> TacticalWall:
	for child in _walls_container.get_children():
		if child is TacticalWall and child.grid_cell == cell:
			return child as TacticalWall
	return null


func _remove_wall(cell: Vector2i) -> bool:
	var wall := _find_wall(cell)
	if wall == null:
		return false
	_walls_container.remove_child(wall)
	wall.queue_free()
	return true


func _apply_environment(snapshot: Dictionary) -> void:
	_terrain.begin_batch_edit()
	_terrain.replace_setup_state(snapshot.get("terrain", []), false)
	for child in _walls_container.get_children():
		if child is TacticalWall:
			_walls_container.remove_child(child)
			child.queue_free()
	for raw_entry in snapshot.get("walls", []):
		var wall := TacticalWall.new()
		wall.apply_setup_state(raw_entry)
		wall.name = "Wall_%d_%d" % [wall.grid_cell.x, wall.grid_cell.y]
		_walls_container.add_child(wall)
		wall.initialize(_grid)
	_terrain.end_batch_edit(false)
	environment_refresh_requested.emit()


func _push_history(before: Dictionary, after: Dictionary) -> void:
	_undo_stack.append({
		"before": before.duplicate(true),
		"after": after.duplicate(true),
	})
	_redo_stack.clear()
	_emit_history_state()


func _emit_history_state() -> void:
	history_changed.emit(not _undo_stack.is_empty(), not _redo_stack.is_empty())


func _interpolate_cells(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var x0 := from_cell.x
	var y0 := from_cell.y
	var x1 := to_cell.x
	var y1 := to_cell.y
	var dx := absi(x1 - x0)
	var sx := 1 if x0 < x1 else -1
	var dy := -absi(y1 - y0)
	var sy := 1 if y0 < y1 else -1
	var error := dx + dy
	while true:
		result.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var doubled := 2 * error
		if doubled >= dy:
			error += dy
			x0 += sx
		if doubled <= dx:
			error += dx
			y0 += sy
	return result


func _entry_cell_less(a: Dictionary, b: Dictionary) -> bool:
	var a_cell: Array = a.get("cell", [0, 0])
	var b_cell: Array = b.get("cell", [0, 0])
	return int(a_cell[1]) < int(b_cell[1]) or (
		int(a_cell[1]) == int(b_cell[1]) and int(a_cell[0]) < int(b_cell[0])
	)
