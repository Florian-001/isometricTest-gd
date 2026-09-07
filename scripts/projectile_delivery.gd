class_name ProjectileDelivery
extends Node

signal projectile_launched(caster: TacticalCharacter, ability: AbilityDefinition, target_cell: Vector2i)
signal projectile_arrived(caster: TacticalCharacter, ability: AbilityDefinition, target_cell: Vector2i)
signal projectile_cancelled(
	caster: TacticalCharacter,
	ability: AbilityDefinition,
	target_cell: Vector2i,
	reason: StringName
)

var _line_of_sight := GridLineOfSight.new()


func get_preview(
	caster_cell: Vector2i,
	target_cell: Vector2i,
	wall_cells: Dictionary = {}
) -> Array[Vector2i]:
	var preview_end := target_cell
	var blocking_wall := _line_of_sight.get_first_blocking_wall(
		caster_cell,
		target_cell,
		wall_cells
	)
	if blocking_wall != Vector2i(-1, -1):
		preview_end = blocking_wall
	var preview: Array[Vector2i] = [caster_cell, preview_end]
	return preview


func has_clear_trajectory(
	caster_cell: Vector2i,
	target_cell: Vector2i,
	wall_cells: Dictionary = {}
) -> bool:
	return _line_of_sight.has_line_of_sight(caster_cell, target_cell, wall_cells)


func launch(
	caster: TacticalCharacter,
	ability: AbilityDefinition,
	target_cell: Vector2i,
	grid: IsometricGrid,
	wall_cells: Dictionary = {}
) -> bool:
	var invalid_reason := _get_invalid_reason(caster, ability, target_cell, grid, wall_cells)
	if not invalid_reason.is_empty():
		projectile_cancelled.emit(caster, ability, target_cell, invalid_reason)
		return false

	var visual := _create_visual(ability)
	visual.name = "AbilityProjectile"
	visual.z_index = 4090
	grid.get_parent().add_child(visual)
	visual.global_position = caster.global_position + Vector2(0.0, -29.0)
	projectile_launched.emit(caster, ability, target_cell)

	var target_position := grid.grid_to_global(target_cell) + Vector2(0.0, -18.0)
	var duration := maxf(
		0.08,
		visual.global_position.distance_to(target_position) / ability.projectile_speed
	)
	var tween := visual.create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(visual, "global_position", target_position, duration)
	tween.parallel().tween_property(visual, "rotation", TAU, duration)
	await tween.finished

	projectile_arrived.emit(caster, ability, target_cell)
	visual.queue_free()
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
	if ability == null or ability.delivery_type != AbilityDefinition.DeliveryType.PROJECTILE:
		return &"invalid_ability"
	if not ability.can_be_used_by(caster):
		return &"incompatible_weapon"
	if grid == null or not grid.is_in_bounds(target_cell):
		return &"invalid_target"
	if wall_cells.has(target_cell):
		return &"target_is_wall"
	if not has_clear_trajectory(caster.grid_cell, target_cell, wall_cells):
		return &"blocked_by_wall"
	return &""


func _create_visual(ability: AbilityDefinition) -> Node2D:
	var visual := Node2D.new()
	if ability.image != null:
		var sprite := Sprite2D.new()
		sprite.texture = ability.image
		var texture_size := ability.image.get_size()
		if texture_size.x > 0.0 and texture_size.y > 0.0:
			var scale_factor := 30.0 / maxf(texture_size.x, texture_size.y)
			sprite.scale = Vector2.ONE * scale_factor
		visual.add_child(sprite)
	else:
		var polygon := Polygon2D.new()
		polygon.polygon = PackedVector2Array([
			Vector2(0.0, -13.0),
			Vector2(11.0, -6.0),
			Vector2(11.0, 6.0),
			Vector2(0.0, 13.0),
			Vector2(-11.0, 6.0),
			Vector2(-11.0, -6.0),
		])
		polygon.color = ability.placeholder_color
		visual.add_child(polygon)
	return visual
