class_name AIBoardSnapshot
extends RefCounted

var grid_size: Vector2i
var wall_cells: Dictionary = {}
var terrain_definitions: Dictionary = {}
var units: Array[TacticalCharacter] = []
var unit_cells: Dictionary = {}
var unit_health: Dictionary = {}


static func from_battle(
	battle_units: Array[TacticalCharacter],
	initial_grid_size: Vector2i,
	walls: Dictionary = {},
	terrain: Dictionary = {}
) -> AIBoardSnapshot:
	var snapshot := AIBoardSnapshot.new()
	snapshot.grid_size = initial_grid_size
	snapshot.wall_cells = walls.duplicate()
	snapshot.terrain_definitions = terrain.duplicate()
	for unit in battle_units:
		if not is_instance_valid(unit):
			continue
		snapshot.units.append(unit)
		snapshot.unit_cells[unit] = unit.grid_cell
		snapshot.unit_health[unit] = unit.current_health
	return snapshot


func duplicate_state() -> AIBoardSnapshot:
	var result := AIBoardSnapshot.new()
	result.grid_size = grid_size
	result.wall_cells = wall_cells.duplicate()
	result.terrain_definitions = terrain_definitions.duplicate()
	result.units = units.duplicate()
	result.unit_cells = unit_cells.duplicate()
	result.unit_health = unit_health.duplicate()
	return result


func is_living(unit: TacticalCharacter) -> bool:
	return is_instance_valid(unit) and int(unit_health.get(unit, 0)) > 0


func get_cell(unit: TacticalCharacter) -> Vector2i:
	return unit_cells.get(unit, Vector2i(-1, -1)) as Vector2i


func set_cell(unit: TacticalCharacter, cell: Vector2i) -> void:
	if unit_cells.has(unit):
		unit_cells[unit] = cell


func get_health(unit: TacticalCharacter) -> int:
	return int(unit_health.get(unit, 0))


func set_health(unit: TacticalCharacter, value: int) -> void:
	if unit_health.has(unit):
		unit_health[unit] = clampi(value, 0, unit.get_max_health())


func get_terrain(cell: Vector2i) -> TileDefinition:
	return terrain_definitions.get(cell) as TileDefinition


func get_living_unit_at(cell: Vector2i) -> TacticalCharacter:
	for unit in units:
		if is_living(unit) and get_cell(unit) == cell:
			return unit
	return null


func get_blocked_cells(except_unit: TacticalCharacter = null) -> Dictionary:
	var blocked := wall_cells.duplicate()
	for unit in units:
		# Defeated units intentionally remain blockers until death removal exists.
		if is_instance_valid(unit) and unit != except_unit:
			blocked[get_cell(unit)] = true
	return blocked


func get_living_opponents(unit: TacticalCharacter) -> Array[TacticalCharacter]:
	var result: Array[TacticalCharacter] = []
	for candidate in units:
		if is_living(candidate) and candidate.is_friendly() != unit.is_friendly():
			result.append(candidate)
	return result


func get_living_allies(unit: TacticalCharacter, include_self: bool = true) -> Array[TacticalCharacter]:
	var result: Array[TacticalCharacter] = []
	for candidate in units:
		if (
			is_living(candidate)
			and candidate.is_friendly() == unit.is_friendly()
			and (include_self or candidate != unit)
		):
			result.append(candidate)
	return result
