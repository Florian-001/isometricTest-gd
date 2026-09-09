class_name KnockbackSystem
extends RefCounted


## Pure grid geometry, shared by live movement and simulated boards. The path
## includes the starting cell; collision_cell may be outside the board.
static func trace(start: Vector2i, direction: Vector2i, distance: int,
	grid_size: Vector2i, walls: Dictionary, occupants: Dictionary) -> Dictionary:
	var path: Array[Vector2i] = [start]
	var result := {"path": path, "landing": start, "collided": false,
		"collision_cell": start, "collision_unit": null}
	if direction == Vector2i.ZERO or absi(direction.x) > 1 or absi(direction.y) > 1:
		return result
	var current := start
	for _step in range(maxi(0, distance)):
		var next := current + direction
		var wall_hit := (not Rect2i(Vector2i.ZERO, grid_size).has_point(next) or walls.has(next))
		# Diagonal effects must not pass through wall corners. Ram itself is cardinal.
		if direction.x != 0 and direction.y != 0:
			wall_hit = wall_hit or walls.has(current + Vector2i(direction.x, 0)) or walls.has(current + Vector2i(0, direction.y))
		if wall_hit or occupants.has(next):
			result.collided = true
			result.collision_cell = next
			result.collision_unit = null if wall_hit else occupants[next]
			break
		path.append(next)
		current = next
	result.landing = current
	return result


static func live_occupants(units: Array[TacticalCharacter], except_unit: TacticalCharacter) -> Dictionary:
	var occupants := {}
	for unit in units:
		# Match normal board occupancy, including defeated friendlies and bone piles.
		if is_instance_valid(unit) and unit != except_unit and (unit.is_friendly() or unit.current_health > 0):
			occupants[unit.grid_cell] = unit
	return occupants


static func snapshot_trace(caster: TacticalCharacter, target: TacticalCharacter,
	effect: KnockbackEffectDefinition, snapshot: AIBoardSnapshot) -> Dictionary:
	var occupants := {}
	for unit in snapshot.units:
		if is_instance_valid(unit) and unit != target and (unit.is_friendly() or snapshot.is_living(unit)):
			occupants[snapshot.get_cell(unit)] = unit
	return trace(snapshot.get_cell(target), (snapshot.get_cell(target) - snapshot.get_cell(caster)).sign(),
		effect.distance, snapshot.grid_size, snapshot.wall_cells, occupants)


static func collision_recipients(target: TacticalCharacter, result: Dictionary) -> Array[TacticalCharacter]:
	var recipients: Array[TacticalCharacter] = []
	if result.collided:
		recipients.append(target)
		if is_instance_valid(result.collision_unit) and result.collision_unit != target:
			recipients.append(result.collision_unit)
	return recipients
