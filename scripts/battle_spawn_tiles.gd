@tool
class_name BattleSpawnTiles
extends Node2D

const FRIENDLY_COLOR := Color(0.2, 0.55, 1.0, 0.45)
const ENEMY_COLOR := Color(1.0, 0.22, 0.2, 0.45)

## Party order maps to this array order. Lost run members retain their original slot.
@export var friendly_cells: Array[Vector2i] = []:
	set(value):
		friendly_cells = value.duplicate()
		queue_redraw()
## One enemy per cell at most. Unused spawn cells stay empty.
@export var enemy_cells: Array[Vector2i] = []:
	set(value):
		enemy_cells = value.duplicate()
		queue_redraw()

var _warning_hash: int = 0


func _ready() -> void:
	visible = Engine.is_editor_hint()
	set_process(Engine.is_editor_hint())


func _process(_delta: float) -> void:
	queue_redraw()
	var warnings := _get_configuration_warnings()
	if hash(warnings) != _warning_hash:
		_warning_hash = hash(warnings)
		update_configuration_warnings()


func set_cells(friendlies: Array[Vector2i], enemies: Array[Vector2i]) -> void:
	friendly_cells = friendlies
	enemy_cells = enemies
	update_configuration_warnings()


## Pure stroke calculation, shared by editor commands and validation tests.
func painted_cells(cells: Array[Vector2i], enemy: bool, erase: bool) -> Dictionary:
	var friendlies := friendly_cells.duplicate()
	var enemies := enemy_cells.duplicate()
	for cell in cells:
		if erase:
			friendlies.erase(cell)
			enemies.erase(cell)
		elif enemy:
			friendlies.erase(cell)
			if not enemies.has(cell):
				enemies.append(cell)
		else:
			enemies.erase(cell)
			if not friendlies.has(cell):
				friendlies.append(cell)
	return {"friendly": friendlies, "enemy": enemies}


func validate_layout(grid: IsometricGrid, walls: Node, party_slots: int = 0) -> PackedStringArray:
	var errors := PackedStringArray()
	if grid == null:
		errors.append("SpawnTiles needs a BattleMap parent with a Grid.")
		return errors
	if friendly_cells.size() < party_slots:
		errors.append("Paint at least %d friendly spawn cells, one per original party member." % party_slots)
	if enemy_cells.is_empty():
		errors.append("Paint at least one enemy spawn cell.")
	var occupied := {}
	var wall_cells := {}
	if walls != null:
		for child in walls.get_children():
			if child is TacticalWall:
				wall_cells[child.grid_cell] = true
	for cell in friendly_cells + enemy_cells:
		if not grid.is_in_bounds(cell):
			errors.append("Spawn cell %s is outside the grid." % cell)
		if wall_cells.has(cell):
			errors.append("Spawn cell %s overlaps a wall." % cell)
		if occupied.has(cell):
			errors.append("Spawn cell %s is duplicated or assigned to both factions." % cell)
		occupied[cell] = true
	return errors


func _get_configuration_warnings() -> PackedStringArray:
	var map := get_parent() as BattleMap
	if map == null:
		return PackedStringArray(["BattleSpawnTiles must be a direct child of BattleMap named SpawnTiles."])
	return validate_layout(map.get_grid(), map.get_walls())


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var map := get_parent() as BattleMap
	var grid := map.get_grid() if map != null else null
	if grid == null:
		return
	for index in range(friendly_cells.size()):
		_draw_cell(grid, friendly_cells[index], FRIENDLY_COLOR, "F%d" % (index + 1))
	for cell in enemy_cells:
		_draw_cell(grid, cell, ENEMY_COLOR, "E")


func _draw_cell(grid: IsometricGrid, cell: Vector2i, color: Color, label: String) -> void:
	var center := grid.grid_to_world(cell)
	var half := grid.cell_size * 0.5
	var points := PackedVector2Array()
	for offset in [Vector2(0, -half.y), Vector2(half.x, 0), Vector2(0, half.y), Vector2(-half.x, 0)]:
		points.append(to_local(grid.to_global(center + offset)))
	draw_colored_polygon(points, color)
	points.append(points[0])
	draw_polyline(points, Color(color, 0.95), 2.0, true)
	draw_string(ThemeDB.fallback_font, to_local(grid.to_global(center)) + Vector2(-9, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
