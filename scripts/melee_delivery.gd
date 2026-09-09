class_name MeleeDelivery
extends Node

signal melee_started(caster: TacticalCharacter, ability: AbilityDefinition, target_cell: Vector2i)
signal melee_impact(caster: TacticalCharacter, ability: AbilityDefinition, target_cell: Vector2i)
signal melee_finished(caster: TacticalCharacter, ability: AbilityDefinition, target_cell: Vector2i)
signal melee_cancelled(
	caster: TacticalCharacter,
	ability: AbilityDefinition,
	target_cell: Vector2i,
	reason: StringName
)


static func can_reach(
	caster_cell: Vector2i,
	target_cell: Vector2i,
	wall_cells: Dictionary = {},
	reach: float = GridPathfinder.DIAGONAL_COST
) -> bool:
	var offset := (target_cell - caster_cell).abs()
	if offset == Vector2i.ZERO:
		return false
	var diagonal_steps := mini(offset.x, offset.y)
	var distance := float(maxi(offset.x, offset.y) - diagonal_steps) + diagonal_steps * GridPathfinder.DIAGONAL_COST
	if distance > reach + 0.0001:
		return false
	var line := GridLineOfSight.new().get_line_cells(caster_cell, target_cell)
	for index in range(1, line.size()):
		var current := line[index]
		var previous := line[index - 1]
		if wall_cells.has(current):
			return false
		var step := current - previous
		if step.x != 0 and step.y != 0:
			if wall_cells.has(previous + Vector2i(step.x, 0)) or wall_cells.has(previous + Vector2i(0, step.y)):
				return false
	return true


func perform(
	caster: TacticalCharacter,
	ability: AbilityDefinition,
	target_cell: Vector2i,
	grid: IsometricGrid,
	impact_callback: Callable,
	wall_cells: Dictionary = {},
	affected_cells: Array[Vector2i] = []
) -> bool:
	var invalid_reason := _get_invalid_reason(caster, ability, target_cell, grid, wall_cells)
	if not invalid_reason.is_empty():
		melee_cancelled.emit(caster, ability, target_cell, invalid_reason)
		return false

	var original_position := caster.global_position
	var target_position := grid.grid_to_global(target_cell)
	var lunge_position := original_position.lerp(target_position, ability.melee_lunge_ratio)
	melee_started.emit(caster, ability, target_cell)

	var lunge_tween := caster.create_tween()
	lunge_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	lunge_tween.tween_property(
		caster,
		"global_position",
		lunge_position,
		ability.melee_lunge_duration
	)
	await lunge_tween.finished
	if not is_instance_valid(caster):
		melee_cancelled.emit(caster, ability, target_cell, &"caster_removed")
		return false

	var slash := _create_slash_visual(caster, ability, target_position, original_position)
	if ability.shape == AbilityDefinition.Shape.LINE_IN_FRONT:
		var points := PackedVector2Array()
		for cell in affected_cells:
			points.append(grid.grid_to_global(cell) - target_position)
		if points.size() > 1:
			slash.rotation = 0.0
			slash.points = points
			slash.scale = Vector2.ONE
	grid.get_parent().add_child(slash)
	melee_impact.emit(caster, ability, target_cell)
	if impact_callback.is_valid():
		impact_callback.call()

	var return_tween := caster.create_tween()
	return_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return_tween.tween_property(
		caster,
		"global_position",
		original_position,
		ability.melee_return_duration
	)
	var slash_tween := slash.create_tween()
	slash_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	slash_tween.tween_property(slash, "scale", Vector2.ONE * 1.2, ability.melee_slash_duration)
	slash_tween.parallel().tween_property(slash, "modulate:a", 0.0, ability.melee_slash_duration)

	await get_tree().create_timer(
		maxf(ability.melee_return_duration, ability.melee_slash_duration)
	).timeout
	if is_instance_valid(caster):
		caster.global_position = original_position
	if is_instance_valid(slash):
		slash.queue_free()
	melee_finished.emit(caster, ability, target_cell)
	return true


func _get_invalid_reason(
	caster: TacticalCharacter,
	ability: AbilityDefinition,
	target_cell: Vector2i,
	grid: IsometricGrid,
	wall_cells: Dictionary
) -> StringName:
	if not is_instance_valid(caster) or caster.current_health <= 0:
		return &"invalid_caster"
	if ability == null or ability.delivery_type != AbilityDefinition.DeliveryType.MELEE:
		return &"invalid_ability"
	if not ability.can_be_used_by(caster):
		return &"incompatible_weapon"
	if grid == null or not grid.is_in_bounds(target_cell):
		return &"invalid_target"
	if not can_reach(caster.grid_cell, target_cell, wall_cells, ability.get_effective_melee_reach(caster)):
		return &"target_out_of_reach"
	return &""


func _create_slash_visual(
	_caster: TacticalCharacter,
	ability: AbilityDefinition,
	target_position: Vector2,
	original_position: Vector2
) -> Line2D:
	var slash := Line2D.new()
	slash.name = "MeleeSlash"
	slash.z_index = 4091
	slash.global_position = target_position + Vector2(0.0, -29.0)
	slash.rotation = (target_position - original_position).angle() - PI * 0.5
	slash.width = 7.0
	slash.default_color = ability.melee_slash_color
	slash.begin_cap_mode = Line2D.LINE_CAP_ROUND
	slash.end_cap_mode = Line2D.LINE_CAP_ROUND
	slash.joint_mode = Line2D.LINE_JOINT_ROUND
	slash.points = PackedVector2Array([
		Vector2(-21.0, 12.0),
		Vector2(-8.0, -7.0),
		Vector2(8.0, -16.0),
		Vector2(22.0, -7.0),
	])
	slash.scale = Vector2.ONE * 0.45
	return slash
