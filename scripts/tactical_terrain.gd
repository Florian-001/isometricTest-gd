@tool
class_name TacticalTerrain
extends Node

signal tile_effect_triggered(
	unit: TacticalCharacter,
	cell: Vector2i,
	definition: TileDefinition,
	trigger: TileTriggeredEffectDefinition.Trigger
)
signal terrain_changed(definitions: Dictionary, movement_cost_multipliers: Dictionary)

@export_category("Tile Palette")
@export var palette: TilePalette

var _grid: IsometricGrid
var _definitions: Dictionary = {}
var _wall_cells: Dictionary = {}
var _report_runtime_warnings := false
var _watched_definitions: Array[TileDefinition] = []
var _batch_editing := false


func initialize(
	grid: IsometricGrid,
	wall_cells: Dictionary = {},
	report_warnings: bool = true
) -> void:
	_grid = grid
	_wall_cells = wall_cells.duplicate()
	_report_runtime_warnings = report_warnings
	refresh()


func refresh() -> void:
	if _batch_editing:
		return
	if _grid == null:
		_grid = _find_grid()
	if _grid == null:
		return
	if Engine.is_editor_hint():
		_wall_cells = _find_wall_cells()

	_disconnect_definition_watchers()
	_definitions.clear()
	for child in get_children():
		if not child is TacticalTile:
			continue
		var tile := child as TacticalTile
		if tile.definition == null:
			_warn("Ignoring tile %s: no Tile Definition is assigned." % tile.name)
		elif not _grid.is_in_bounds(tile.grid_cell):
			_warn("Ignoring tile %s: cell %s is outside the grid." % [tile.name, tile.grid_cell])
		elif _wall_cells.has(tile.grid_cell):
			_warn("Ignoring tile %s: cell %s contains a wall." % [tile.name, tile.grid_cell])
		elif _definitions.has(tile.grid_cell):
			_warn("Ignoring duplicate tile %s at cell %s." % [tile.name, tile.grid_cell])
		else:
			_definitions[tile.grid_cell] = tile.definition
			_watch_definition(tile.definition)
	_grid.set_terrain_definitions(_definitions)
	terrain_changed.emit(get_definitions(), get_movement_cost_multipliers())


func get_definition(cell: Vector2i) -> TileDefinition:
	return _definitions.get(cell) as TileDefinition


func get_definitions() -> Dictionary:
	return _definitions.duplicate()


func capture_setup_state() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell: Vector2i in _definitions:
		var definition := _definitions[cell] as TileDefinition
		if definition == null or definition.resource_path.is_empty():
			continue
		result.append({
			"cell": [cell.x, cell.y],
			"definition": definition.resource_path,
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_cell: Array = a["cell"]
		var b_cell: Array = b["cell"]
		return int(a_cell[1]) < int(b_cell[1]) or (
			int(a_cell[1]) == int(b_cell[1]) and int(a_cell[0]) < int(b_cell[0])
		)
	)
	return result


func begin_batch_edit() -> void:
	_batch_editing = true


func end_batch_edit(refresh_after := true) -> void:
	_batch_editing = false
	if refresh_after:
		refresh()


func replace_setup_state(entries: Array, refresh_after := true) -> void:
	for child in get_children():
		if child is TacticalTile:
			remove_child(child)
			child.queue_free()
	for entry_value in entries:
		var entry: Dictionary = entry_value
		var cell_value: Array = entry.get("cell", [0, 0])
		var definition_path := String(entry.get("definition", ""))
		var definition_resource := load(definition_path) as TileDefinition
		if definition_resource == null:
			continue
		var tile := TacticalTile.new()
		tile.name = "Tile_%d_%d" % [int(cell_value[0]), int(cell_value[1])]
		tile.grid_cell = Vector2i(int(cell_value[0]), int(cell_value[1]))
		tile.definition = definition_resource
		add_child(tile)
	if refresh_after:
		refresh()


func set_tile(cell: Vector2i, definition_resource: TileDefinition) -> bool:
	if definition_resource == null or (_grid != null and not _grid.is_in_bounds(cell)):
		return false
	var current := get_definition(cell)
	if current == definition_resource:
		return false
	_remove_tile_node(cell)
	var tile := TacticalTile.new()
	tile.name = "Tile_%d_%d" % [cell.x, cell.y]
	tile.grid_cell = cell
	tile.definition = definition_resource
	add_child(tile)
	return true


func erase_tile(cell: Vector2i) -> bool:
	return _remove_tile_node(cell)


func get_movement_cost_multipliers() -> Dictionary:
	var result: Dictionary = {}
	for cell: Vector2i in _definitions:
		var definition := _definitions[cell] as TileDefinition
		if definition != null:
			result[cell] = definition.get_movement_cost_multiplier()
	return result


func apply_trigger(
	unit: TacticalCharacter,
	trigger: TileTriggeredEffectDefinition.Trigger
) -> void:
	if not is_instance_valid(unit) or unit.current_health <= 0 or PassiveAbilityResolver.ignores_tile_effects(unit):
		return
	var definition := get_definition(unit.grid_cell)
	if definition == null:
		return
	definition.apply_trigger(unit, trigger)
	tile_effect_triggered.emit(unit, unit.grid_cell, definition, trigger)


func _find_grid() -> IsometricGrid:
	var root := get_parent()
	if root == null:
		return null
	return root.get_node_or_null("Grid") as IsometricGrid


func _remove_tile_node(cell: Vector2i) -> bool:
	for child in get_children():
		if child is TacticalTile and child.grid_cell == cell:
			remove_child(child)
			child.queue_free()
			return true
	return false


func _find_wall_cells() -> Dictionary:
	var result: Dictionary = {}
	var root := get_parent()
	var walls := root.get_node_or_null("Walls") if root != null else null
	if walls != null:
		for child in walls.get_children():
			if child is TacticalWall:
				result[child.grid_cell] = true
	return result


func _warn(message: String) -> void:
	if _report_runtime_warnings and not Engine.is_editor_hint():
		push_warning(message)


func _watch_definition(definition: TileDefinition) -> void:
	if _watched_definitions.has(definition):
		return
	_watched_definitions.append(definition)
	if not definition.changed.is_connected(_on_definition_changed):
		definition.changed.connect(_on_definition_changed)


func _disconnect_definition_watchers() -> void:
	for definition in _watched_definitions:
		if (
			is_instance_valid(definition)
			and definition.changed.is_connected(_on_definition_changed)
		):
			definition.changed.disconnect(_on_definition_changed)
	_watched_definitions.clear()


func _on_definition_changed() -> void:
	call_deferred("refresh")
