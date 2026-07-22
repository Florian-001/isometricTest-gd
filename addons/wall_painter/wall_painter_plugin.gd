@tool
extends EditorPlugin

const WallScript = preload("res://scripts/tactical_wall.gd")

var _paint_button: Button
var _painting := false
var _erasing := false
var _stroke_cells: Dictionary = {}
var _hover_cell := Vector2i(-1, -1)
var _hover_valid := false


func _enter_tree() -> void:
	_paint_button = Button.new()
	_paint_button.text = "Wall Paint"
	_paint_button.tooltip_text = "Left-drag to paint walls, right-drag to erase, Escape to exit"
	_paint_button.toggle_mode = true
	_paint_button.toggled.connect(_on_paint_toggled)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _paint_button)


func _exit_tree() -> void:
	if is_instance_valid(_paint_button):
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _paint_button)
		_paint_button.queue_free()
	_paint_button = null


func _handles(object: Object) -> bool:
	return object is IsometricGrid or object is TacticalWall or object is Node2D


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if _paint_button == null or not _paint_button.button_pressed:
		return false
	var context := _get_context()
	if context.is_empty():
		return false

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_paint_button.button_pressed = false
		return true

	if event is InputEventMouseMotion:
		_update_hover(event.position, context)
		if _painting or _erasing:
			_collect_stroke_cell(_hover_cell, context)
		return true

	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
			return false
		_update_hover(event.position, context)
		if event.pressed:
			_painting = event.button_index == MOUSE_BUTTON_LEFT
			_erasing = event.button_index == MOUSE_BUTTON_RIGHT
			_stroke_cells.clear()
			_collect_stroke_cell(_hover_cell, context)
		else:
			_commit_stroke(context)
			_painting = false
			_erasing = false
		return true

	return false


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if _paint_button == null or not _paint_button.button_pressed or _hover_cell == Vector2i(-1, -1):
		return
	var context := _get_context()
	if context.is_empty():
		return
	var grid := context.grid as IsometricGrid
	if not grid.is_in_bounds(_hover_cell):
		return
	var viewport := get_editor_interface().get_editor_viewport_2d()
	var transform := viewport.get_canvas_transform()
	var center := transform * grid.grid_to_global(_hover_cell)
	var half_width := grid.cell_size.x * 0.5 * transform.get_scale().x
	var half_height := grid.cell_size.y * 0.5 * transform.get_scale().y
	var points := PackedVector2Array([
		center + Vector2(0.0, -half_height),
		center + Vector2(half_width, 0.0),
		center + Vector2(0.0, half_height),
		center + Vector2(-half_width, 0.0),
	])
	var color := Color(0.2, 0.95, 0.45, 0.45) if _hover_valid else Color(1.0, 0.2, 0.2, 0.45)
	overlay.draw_colored_polygon(points, color)
	points.append(points[0])
	overlay.draw_polyline(points, color.lightened(0.25), 2.0, true)


func _on_paint_toggled(enabled: bool) -> void:
	if not enabled:
		_painting = false
		_erasing = false
		_stroke_cells.clear()
		_hover_cell = Vector2i(-1, -1)
	update_overlays()


func _update_hover(screen_position: Vector2, context: Dictionary) -> void:
	var viewport := get_editor_interface().get_editor_viewport_2d()
	var world_position := viewport.get_canvas_transform().affine_inverse() * screen_position
	var grid := context.grid as IsometricGrid
	_hover_cell = grid.global_to_grid(world_position)
	_hover_valid = _can_edit_cell(_hover_cell, context)
	update_overlays()


func _collect_stroke_cell(cell: Vector2i, context: Dictionary) -> void:
	if not _can_edit_cell(cell, context):
		return
	_stroke_cells[cell] = true


func _commit_stroke(context: Dictionary) -> void:
	if _stroke_cells.is_empty():
		return
	var root := context.root as Node
	var walls := context.walls as Node
	var undo := get_undo_redo()
	undo.create_action("Erase Tactical Walls" if _erasing else "Paint Tactical Walls")
	if _erasing:
		for cell: Vector2i in _stroke_cells.keys():
			var wall := _get_wall_at(cell, walls)
			if wall == null:
				continue
			undo.add_do_method(walls, "remove_child", wall)
			undo.add_undo_method(walls, "add_child", wall)
			undo.add_undo_method(wall, "set_owner", root)
			undo.add_undo_reference(wall)
	else:
		for cell: Vector2i in _stroke_cells.keys():
			if _get_wall_at(cell, walls) != null:
				continue
			var wall := WallScript.new() as TacticalWall
			wall.name = "Wall_%d_%d" % [cell.x, cell.y]
			wall.grid_cell = cell
			undo.add_do_method(walls, "add_child", wall)
			undo.add_do_method(wall, "set_owner", root)
			undo.add_undo_method(walls, "remove_child", wall)
			undo.add_do_reference(wall)
	undo.commit_action()
	_stroke_cells.clear()
	update_overlays()


func _can_edit_cell(cell: Vector2i, context: Dictionary) -> bool:
	var grid := context.grid as IsometricGrid
	if not grid.is_in_bounds(cell):
		return false
	var wall := _get_wall_at(cell, context.walls)
	if _erasing:
		return wall != null
	if wall != null:
		return false
	var characters := (context.root as Node).get_node_or_null("Characters")
	if characters != null:
		for child in characters.get_children():
			if child is TacticalCharacter and child.starting_grid_cell == cell:
				return false
	return true


func _get_wall_at(cell: Vector2i, walls: Node) -> TacticalWall:
	for child in walls.get_children():
		if child is TacticalWall and child.grid_cell == cell:
			return child as TacticalWall
	return null


func _get_context() -> Dictionary:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		return {}
	var grid := root.get_node_or_null("Grid") as IsometricGrid
	var walls := root.get_node_or_null("Walls")
	if grid == null or walls == null:
		return {}
	return {"root": root, "grid": grid, "walls": walls}
