@tool
extends EditorPlugin

const PaintMode = preload("res://addons/spawn_painter/paint_tool_mode.gd")

var _paint_button: Button
var _brush: OptionButton
var _painting := false
var _erasing := false
var _stroke_cells: Array[Vector2i] = []
var _hover_cell := Vector2i(-1, -1)
var _hover_valid := false


func _enter_tree() -> void:
	_brush = OptionButton.new()
	_brush.add_item("Friendly Spawn")
	_brush.add_item("Enemy Spawn")
	_brush.tooltip_text = "Friendly cells are numbered in party order. Enemy cells are available spawn positions."
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _brush)
	_paint_button = Button.new()
	_paint_button.text = "Spawn Paint"
	_paint_button.toggle_mode = true
	_paint_button.tooltip_text = "Left-drag to paint, right-drag to erase either faction, Escape to exit. Add SpawnTiles to the map first."
	_paint_button.toggled.connect(_on_paint_toggled)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _paint_button)
	PaintMode.register(_paint_button)
	scene_changed.connect(_on_scene_changed)


func _exit_tree() -> void:
	for control in [_brush, _paint_button]:
		if is_instance_valid(control):
			remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, control)
			control.queue_free()
	_brush = null
	_paint_button = null


func _handles(object: Object) -> bool:
	return object is Node2D or object is TacticalTerrain or object is TacticalTile


func _on_scene_changed(_root: Node) -> void:
	if _paint_button != null:
		_paint_button.button_pressed = false
	_on_paint_toggled(false)


func _on_paint_toggled(enabled: bool) -> void:
	if enabled:
		PaintMode.activate(_paint_button)
	_painting = false
	_erasing = false
	_stroke_cells.clear()
	_hover_cell = Vector2i(-1, -1)
	update_overlays()


func _get_context() -> Dictionary:
	var map := get_editor_interface().get_edited_scene_root() as BattleMap
	if map == null or not map.is_configured():
		return {}
	var spawns := map.get_node_or_null("SpawnTiles") as BattleSpawnTiles
	if spawns == null:
		return {}
	return {"grid": map.get_grid(), "walls": map.get_walls(), "spawns": spawns}


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if _paint_button == null or not _paint_button.button_pressed:
		return false
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_paint_button.button_pressed = false
		return true
	var context := _get_context()
	if context.is_empty():
		return false
	if event is InputEventMouseMotion:
		_update_hover(event.position, context)
		if _painting or _erasing:
			_collect_cell(context)
		return true
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		_update_hover(event.position, context)
		if event.pressed:
			_painting = event.button_index == MOUSE_BUTTON_LEFT
			_erasing = event.button_index == MOUSE_BUTTON_RIGHT
			_stroke_cells.clear()
			_collect_cell(context)
		else:
			if not _stroke_cells.is_empty():
				commit_paint(get_undo_redo(), context.spawns, _stroke_cells, _brush.selected == 1, _erasing)
			_stroke_cells.clear()
			_painting = false
			_erasing = false
		return true
	return false


static func can_paint(cell: Vector2i, grid: IsometricGrid, walls: Node) -> bool:
	if not grid.is_in_bounds(cell):
		return false
	for child in walls.get_children():
		if child is TacticalWall and child.grid_cell == cell:
			return false
	return true


## Same command works with EditorUndoRedoManager and a standalone UndoRedo in tests.
static func commit_paint(undo: Object, spawns: BattleSpawnTiles, cells: Array[Vector2i], enemy: bool, erase: bool) -> void:
	var next := spawns.painted_cells(cells, enemy, erase)
	if next.friendly == spawns.friendly_cells and next.enemy == spawns.enemy_cells:
		return
	undo.create_action("Erase Spawn Cells" if erase else "Paint Enemy Spawns" if enemy else "Paint Friendly Spawns")
	if undo is UndoRedo:
		undo.add_do_method(spawns.set_cells.bind(next.friendly, next.enemy))
		undo.add_undo_method(spawns.set_cells.bind(spawns.friendly_cells.duplicate(), spawns.enemy_cells.duplicate()))
	else:
		undo.add_do_method(spawns, "set_cells", next.friendly, next.enemy)
		undo.add_undo_method(spawns, "set_cells", spawns.friendly_cells.duplicate(), spawns.enemy_cells.duplicate())
	undo.commit_action()


func _update_hover(screen_position: Vector2, context: Dictionary) -> void:
	var viewport := get_editor_interface().get_editor_viewport_2d()
	var global_point := viewport.get_canvas_transform().affine_inverse() * screen_position
	_hover_cell = context.grid.global_to_grid(global_point)
	_hover_valid = can_paint(_hover_cell, context.grid, context.walls)
	update_overlays()


func _collect_cell(context: Dictionary) -> void:
	var spawns := context.spawns as BattleSpawnTiles
	var erasable := spawns.friendly_cells.has(_hover_cell) or spawns.enemy_cells.has(_hover_cell)
	if (_erasing and erasable) or (_painting and _hover_valid):
		if not _stroke_cells.has(_hover_cell):
			_stroke_cells.append(_hover_cell)


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if _paint_button == null or not _paint_button.button_pressed:
		return
	var context := _get_context()
	if context.is_empty() or not context.grid.is_in_bounds(_hover_cell):
		return
	var grid := context.grid as IsometricGrid
	var canvas := get_editor_interface().get_editor_viewport_2d().get_canvas_transform()
	var center := grid.grid_to_world(_hover_cell)
	var half := grid.cell_size * 0.5
	var points := PackedVector2Array()
	for offset in [Vector2(0, -half.y), Vector2(half.x, 0), Vector2(0, half.y), Vector2(-half.x, 0)]:
		points.append(canvas * grid.to_global(center + offset))
	var color := BattleSpawnTiles.ENEMY_COLOR if _brush.selected == 1 else BattleSpawnTiles.FRIENDLY_COLOR
	if not _hover_valid:
		color = Color(1.0, 0.65, 0.1, 0.6)
	overlay.draw_colored_polygon(points, color)
	points.append(points[0])
	overlay.draw_polyline(points, Color(color, 1.0), 2.0, true)
