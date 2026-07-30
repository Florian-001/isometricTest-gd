class_name AbilityTargeting
extends RefCounted

const COST_EPSILON := 0.0001
const MeleeDeliveryScript = preload("res://scripts/melee_delivery.gd")
const AbilityCasterMovementScript = preload("res://scripts/ability_caster_movement.gd")

var grid_size: Vector2i
var _line_of_sight := GridLineOfSight.new()


func _init(initial_grid_size: Vector2i = Vector2i.ONE) -> void:
	set_grid_size(initial_grid_size)


func set_grid_size(value: Vector2i) -> void:
	grid_size = Vector2i(maxi(1, value.x), maxi(1, value.y))


func get_weighted_distance(from_cell: Vector2i, to_cell: Vector2i) -> float:
	var difference := (to_cell - from_cell).abs()
	var diagonal_steps := mini(difference.x, difference.y)
	var orthogonal_steps := maxi(difference.x, difference.y) - diagonal_steps
	return float(orthogonal_steps) + float(diagonal_steps) * GridPathfinder.DIAGONAL_COST


func get_valid_target_cells(
	caster: TacticalCharacter,
	ability: AbilityDefinition,
	units: Array[TacticalCharacter],
	wall_cells: Dictionary = {}
) -> Dictionary:
	return get_valid_target_cells_from(caster, caster.grid_cell, ability, units, wall_cells)


func get_valid_target_cells_from(
	caster: TacticalCharacter,
	caster_cell: Vector2i,
	ability: AbilityDefinition,
	units: Array[TacticalCharacter],
	wall_cells: Dictionary = {}
) -> Dictionary:
	var valid_cells: Dictionary = {}
	if not _is_living(caster) or ability == null or not ability.can_be_used_by(caster):
		return valid_cells
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell := Vector2i(x, y)
			if is_valid_primary_target_from(caster, caster_cell, cell, ability, units, wall_cells):
				valid_cells[cell] = get_weighted_distance(caster_cell, cell)
	return valid_cells


func get_cells_in_range(caster: TacticalCharacter, ability: AbilityDefinition) -> Dictionary:
	return (
		get_cells_in_range_from(caster.grid_cell, ability)
		if _is_living(caster) and ability != null and ability.can_be_used_by(caster)
		else {}
	)


func get_cells_in_range_from(caster_cell: Vector2i, ability: AbilityDefinition) -> Dictionary:
	var range_cells: Dictionary = {}
	if ability == null:
		return range_cells
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell := Vector2i(x, y)
			var distance := get_weighted_distance(caster_cell, cell)
			if distance <= ability.range + COST_EPSILON:
				range_cells[cell] = distance
	return range_cells


func is_valid_primary_target(
	caster: TacticalCharacter,
	selected_cell: Vector2i,
	ability: AbilityDefinition,
	units: Array[TacticalCharacter],
	wall_cells: Dictionary = {}
) -> bool:
	return is_valid_primary_target_from(
		caster,
		caster.grid_cell,
		selected_cell,
		ability,
		units,
		wall_cells
	)


func is_valid_primary_target_from(
	caster: TacticalCharacter,
	caster_cell: Vector2i,
	selected_cell: Vector2i,
	ability: AbilityDefinition,
	units: Array[TacticalCharacter],
	wall_cells: Dictionary = {}
) -> bool:
	if (
		not _is_living(caster)
		or ability == null
		or not ability.can_be_used_by(caster)
		or not _is_in_bounds(selected_cell)
	):
		return false
	if get_weighted_distance(caster_cell, selected_cell) > ability.range + COST_EPSILON:
		return false
	if wall_cells.has(selected_cell):
		return false
	if not _line_of_sight.has_line_of_sight(caster_cell, selected_cell, wall_cells):
		return false
	var delivery_origin := caster_cell
	if ability.moves_caster():
		var movement_path := get_caster_movement_path_from(
			caster,
			caster_cell,
			selected_cell,
			ability,
			units,
			wall_cells
		)
		if movement_path.is_empty():
			return false
		delivery_origin = AbilityCasterMovementScript.get_landing_cell(movement_path)
	if (
		ability.delivery_type == AbilityDefinition.DeliveryType.MELEE
		and not MeleeDeliveryScript.can_reach(delivery_origin, selected_cell, wall_cells)
	):
		return false
	if ability.moves_caster():
		return true
	if ability.has_target_flag(AbilityDefinition.TargetFlags.CELL):
		return true
	var occupant := _get_living_unit_at_from(selected_cell, units, caster, caster_cell)
	return occupant != null and _matches_unit_flag(caster, occupant, ability)


func get_caster_movement_path(
	caster: TacticalCharacter,
	selected_cell: Vector2i,
	ability: AbilityDefinition,
	units: Array[TacticalCharacter],
	wall_cells: Dictionary = {}
) -> Array[Vector2i]:
	return get_caster_movement_path_from(
		caster,
		caster.grid_cell if _is_living(caster) else Vector2i(-1, -1),
		selected_cell,
		ability,
		units,
		wall_cells
	)


func get_caster_movement_path_from(
	caster: TacticalCharacter,
	caster_cell: Vector2i,
	selected_cell: Vector2i,
	ability: AbilityDefinition,
	units: Array[TacticalCharacter],
	wall_cells: Dictionary = {}
) -> Array[Vector2i]:
	var empty_path: Array[Vector2i] = []
	if not _is_living(caster) or ability == null:
		return empty_path
	if not ability.moves_caster():
		return ability.get_caster_movement_path(
			caster_cell,
			selected_cell,
			grid_size,
			wall_cells
		)
	var target := _get_living_unit_at_from(selected_cell, units, caster, caster_cell)
	if target == null or target == caster or not _matches_unit_flag(caster, target, ability):
		return empty_path
	var blocked_cells := wall_cells.duplicate()
	for unit in units:
		if not is_instance_valid(unit) or unit == caster or unit == target:
			continue
		# Match runtime pathfinding: defeated units remain occupied until removal exists.
		blocked_cells[unit.grid_cell] = true
	return ability.get_caster_movement_path(
		caster_cell,
		selected_cell,
		grid_size,
		blocked_cells
	)


func get_affected_cells(
	caster_cell: Vector2i,
	selected_cell: Vector2i,
	ability: AbilityDefinition,
	wall_cells: Dictionary = {}
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if ability == null or not _is_in_bounds(selected_cell):
		return cells
	var span := ability.get_effective_area_span()
	var radius := floori(float(span - 1) / 2.0)
	match ability.shape:
		AbilityDefinition.Shape.SQUARE:
			for y in range(selected_cell.y - radius, selected_cell.y + radius + 1):
				for x in range(selected_cell.x - radius, selected_cell.x + radius + 1):
					_append_if_in_bounds(cells, Vector2i(x, y))
		AbilityDefinition.Shape.CIRCLE:
			for y in range(selected_cell.y - radius, selected_cell.y + radius + 1):
				for x in range(selected_cell.x - radius, selected_cell.x + radius + 1):
					var offset := Vector2i(x, y) - selected_cell
					if offset.length_squared() <= radius * radius:
						_append_if_in_bounds(cells, Vector2i(x, y))
		AbilityDefinition.Shape.PLUS:
			for offset in range(-radius, radius + 1):
				_append_if_in_bounds(cells, selected_cell + Vector2i(offset, 0))
				_append_if_in_bounds(cells, selected_cell + Vector2i(0, offset))
		AbilityDefinition.Shape.LINE_VERTICAL:
			for offset in range(-radius, radius + 1):
				_append_if_in_bounds(cells, selected_cell + Vector2i(0, offset))
		AbilityDefinition.Shape.LINE_HORIZONTAL:
			for offset in range(-radius, radius + 1):
				_append_if_in_bounds(cells, selected_cell + Vector2i(offset, 0))
		AbilityDefinition.Shape.LINE_FROM_CASTER:
			cells = _get_wide_line(caster_cell, selected_cell, radius)
	var visible_cells: Array[Vector2i] = []
	var sight_origin := caster_cell if ability.shape == AbilityDefinition.Shape.LINE_FROM_CASTER else selected_cell
	for cell in cells:
		if wall_cells.has(cell):
			continue
		if _line_of_sight.has_line_of_sight(sight_origin, cell, wall_cells):
			visible_cells.append(cell)
	return visible_cells


func get_trajectory_cells(
	caster_cell: Vector2i,
	selected_cell: Vector2i,
	wall_cells: Dictionary = {}
) -> Array[Vector2i]:
	var end_cell := selected_cell
	var blocking_wall := _line_of_sight.get_first_blocking_wall(caster_cell, selected_cell, wall_cells)
	if blocking_wall != Vector2i(-1, -1):
		end_cell = blocking_wall
	var straight_trajectory: Array[Vector2i] = [caster_cell, end_cell]
	return straight_trajectory


func get_affected_units(
	caster: TacticalCharacter,
	selected_cell: Vector2i,
	ability: AbilityDefinition,
	units: Array[TacticalCharacter],
	wall_cells: Dictionary = {}
) -> Array[TacticalCharacter]:
	return get_affected_units_from(
		caster,
		caster.grid_cell,
		selected_cell,
		ability,
		units,
		wall_cells
	)


func get_affected_units_from(
	caster: TacticalCharacter,
	caster_cell: Vector2i,
	selected_cell: Vector2i,
	ability: AbilityDefinition,
	units: Array[TacticalCharacter],
	wall_cells: Dictionary = {}
) -> Array[TacticalCharacter]:
	var affected: Array[TacticalCharacter] = []
	if not _is_living(caster) or ability == null or not ability.can_be_used_by(caster):
		return affected
	var cells := get_affected_cells(caster_cell, selected_cell, ability, wall_cells)
	for unit in units:
		var unit_cell := caster_cell if unit == caster else unit.grid_cell
		if _is_living(unit) and cells.has(unit_cell) and _matches_unit_flag(caster, unit, ability):
			affected.append(unit)
	return affected


func _get_wide_line(start: Vector2i, destination: Vector2i, radius: int) -> Array[Vector2i]:
	var center_line := _get_supercover_line(start, destination)
	if radius <= 0 or start == destination:
		return center_line
	var cells: Array[Vector2i] = []
	var start_vector := Vector2(start)
	var end_vector := Vector2(destination)
	var segment := end_vector - start_vector
	var segment_length_squared := segment.length_squared()
	var minimum := Vector2i(
		mini(start.x, destination.x) - radius,
		mini(start.y, destination.y) - radius
	)
	var maximum := Vector2i(
		maxi(start.x, destination.x) + radius,
		maxi(start.y, destination.y) + radius
	)
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			var cell := Vector2i(x, y)
			if not _is_in_bounds(cell):
				continue
			var point := Vector2(cell)
			var projection := clampf((point - start_vector).dot(segment) / segment_length_squared, 0.0, 1.0)
			var closest := start_vector + segment * projection
			if point.distance_to(closest) <= float(radius) + COST_EPSILON:
				cells.append(cell)
	for line_cell in center_line:
		if not cells.has(line_cell):
			cells.append(line_cell)
	return cells


func _get_supercover_line(start: Vector2i, destination: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var difference := destination - start
	var nx := absi(difference.x)
	var ny := absi(difference.y)
	var sign_x := signi(difference.x)
	var sign_y := signi(difference.y)
	var cell := start
	_append_if_in_bounds(cells, cell)
	var ix := 0
	var iy := 0
	while ix < nx or iy < ny:
		var horizontal_progress := (1 + 2 * ix) * ny
		var vertical_progress := (1 + 2 * iy) * nx
		if horizontal_progress == vertical_progress:
			cell += Vector2i(sign_x, sign_y)
			ix += 1
			iy += 1
		elif horizontal_progress < vertical_progress:
			cell.x += sign_x
			ix += 1
		else:
			cell.y += sign_y
			iy += 1
		_append_if_in_bounds(cells, cell)
	return cells


func _matches_unit_flag(
	caster: TacticalCharacter,
	target: TacticalCharacter,
	ability: AbilityDefinition
) -> bool:
	if target == caster:
		return ability.has_target_flag(AbilityDefinition.TargetFlags.SELF)
	if target.is_friendly() == caster.is_friendly():
		return ability.has_target_flag(AbilityDefinition.TargetFlags.FRIEND)
	return ability.has_target_flag(AbilityDefinition.TargetFlags.ENEMY)


func _get_living_unit_at(cell: Vector2i, units: Array[TacticalCharacter]) -> TacticalCharacter:
	for unit in units:
		if _is_living(unit) and unit.grid_cell == cell:
			return unit
	return null


func _get_living_unit_at_from(
	cell: Vector2i,
	units: Array[TacticalCharacter],
	caster: TacticalCharacter,
	caster_cell: Vector2i
) -> TacticalCharacter:
	for unit in units:
		if not _is_living(unit):
			continue
		var unit_cell := caster_cell if unit == caster else unit.grid_cell
		if unit_cell == cell:
			return unit
	return null


func _append_if_in_bounds(cells: Array[Vector2i], cell: Vector2i) -> void:
	if _is_in_bounds(cell) and not cells.has(cell):
		cells.append(cell)


func _is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


func _is_living(unit: TacticalCharacter) -> bool:
	return is_instance_valid(unit) and unit.current_health > 0
