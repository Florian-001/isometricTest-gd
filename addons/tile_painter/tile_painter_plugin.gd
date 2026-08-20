@tool
extends EditorPlugin

const TileScript = preload("res://scripts/tactical_tile.gd")
const TileStatusInspector = preload("res://addons/tile_painter/tile_status_inspector.gd")
const ItemArrayInspector = preload("res://addons/tile_painter/item_array_inspector.gd")
const ItemAbilityInspector = preload("res://addons/tile_painter/item_ability_inspector.gd")
const ItemModifierInspector = preload("res://addons/tile_painter/item_modifier_inspector.gd")

var _paint_button: Button
var _palette_picker: OptionButton
var _painting := false
var _erasing := false
var _stroke_cells: Dictionary = {}
var _hover_cell := Vector2i(-1, -1)
var _hover_valid := false
var _palette_tiles: Array[TileDefinition] = []
var _tile_status_inspector: EditorInspectorPlugin
var _item_array_inspector: EditorInspectorPlugin
var _item_ability_inspector: EditorInspectorPlugin
var _item_modifier_inspector: EditorInspectorPlugin


func _enter_tree() -> void:
	_tile_status_inspector = TileStatusInspector.new()
	_tile_status_inspector.setup(get_editor_interface().get_resource_filesystem())
	add_inspector_plugin(_tile_status_inspector)
	_item_array_inspector = ItemArrayInspector.new()
	_item_array_inspector.setup(get_editor_interface().get_resource_filesystem())
	add_inspector_plugin(_item_array_inspector)
	_item_ability_inspector = ItemAbilityInspector.new()
	_item_ability_inspector.setup(get_editor_interface().get_resource_filesystem())
	add_inspector_plugin(_item_ability_inspector)
	_item_modifier_inspector = ItemModifierInspector.new()
	_item_modifier_inspector.setup(get_undo_redo())
	add_inspector_plugin(_item_modifier_inspector)

	_palette_picker = OptionButton.new()
	_palette_picker.tooltip_text = "Terrain template used by Tile Paint"
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _palette_picker)

	_paint_button = Button.new()
	_paint_button.text = "Tile Paint"
	_paint_button.tooltip_text = "Left-drag to paint or replace tiles, right-drag to erase, Escape to exit"
	_paint_button.toggle_mode = true
	_paint_button.toggled.connect(_on_paint_toggled)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _paint_button)
	_refresh_palette()


func _exit_tree() -> void:
	if _item_modifier_inspector != null:
		remove_inspector_plugin(_item_modifier_inspector)
		_item_modifier_inspector = null
	if _item_ability_inspector != null:
		remove_inspector_plugin(_item_ability_inspector)
		_item_ability_inspector = null
	if _item_array_inspector != null:
		remove_inspector_plugin(_item_array_inspector)
		_item_array_inspector = null
	if _tile_status_inspector != null:
		remove_inspector_plugin(_tile_status_inspector)
		_tile_status_inspector = null
	if is_instance_valid(_palette_picker):
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _palette_picker)
		_palette_picker.queue_free()
	if is_instance_valid(_paint_button):
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _paint_button)
		_paint_button.queue_free()
	_palette_picker = null
	_paint_button = null


func _handles(object: Object) -> bool:
	call_deferred("_refresh_palette")
	return (
		object is IsometricGrid
		or object is TacticalTerrain
		or object is TacticalTile
		or object is Node2D
	)


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if _paint_button == null or not _paint_button.button_pressed:
		return false
	var context := _get_context()
	if context.is_empty() or _get_selected_definition() == null:
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
		if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
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
	if (
		_paint_button == null
		or not _paint_button.button_pressed
		or _hover_cell == Vector2i(-1, -1)
	):
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
	var definition := _get_selected_definition()
	var color := (
		Color(definition.tile_color, 0.65)
		if _hover_valid and definition != null
		else Color(1.0, 0.2, 0.2, 0.5)
	)
	overlay.draw_colored_polygon(points, color)
	points.append(points[0])
	overlay.draw_polyline(points, color.lightened(0.25), 2.0, true)


func _on_paint_toggled(enabled: bool) -> void:
	if enabled:
		_refresh_palette()
	else:
		_painting = false
		_erasing = false
		_stroke_cells.clear()
		_hover_cell = Vector2i(-1, -1)
	update_overlays()


func _refresh_palette() -> void:
	if _palette_picker == null:
		return
	_palette_picker.clear()
	_palette_tiles.clear()
	var context := _get_context()
	if not context.is_empty():
		var terrain := context.terrain as TacticalTerrain
		if terrain.palette != null:
			for definition in terrain.palette.tiles:
				if definition != null:
					_palette_tiles.append(definition)
					_palette_picker.add_item(definition.display_name)
	var has_tiles := not _palette_tiles.is_empty()
	_palette_picker.disabled = not has_tiles
	if _paint_button != null:
		_paint_button.disabled = not has_tiles
		_paint_button.tooltip_text = (
			"Left-drag to paint or replace tiles, right-drag to erase, Escape to exit"
			if has_tiles
			else "Assign Tile Definitions to the TacticalTerrain palette first"
		)


func _get_selected_definition() -> TileDefinition:
	if (
		_palette_picker == null
		or _palette_picker.selected < 0
		or _palette_picker.selected >= _palette_tiles.size()
	):
		return null
	return _palette_tiles[_palette_picker.selected]


func _update_hover(screen_position: Vector2, context: Dictionary) -> void:
	var viewport := get_editor_interface().get_editor_viewport_2d()
	var world_position := viewport.get_canvas_transform().affine_inverse() * screen_position
	var grid := context.grid as IsometricGrid
	_hover_cell = grid.global_to_grid(world_position)
	_hover_valid = _can_edit_cell(_hover_cell, context)
	update_overlays()


func _collect_stroke_cell(cell: Vector2i, context: Dictionary) -> void:
	if _can_edit_cell(cell, context):
		_stroke_cells[cell] = true


func _commit_stroke(context: Dictionary) -> void:
	if _stroke_cells.is_empty():
		return
	var root := context.root as Node
	var terrain := context.terrain as TacticalTerrain
	var definition := _get_selected_definition()
	var undo := get_undo_redo()
	undo.create_action("Erase Tactical Tiles" if _erasing else "Paint Tactical Tiles")
	for cell: Vector2i in _stroke_cells.keys():
		var existing := _get_tile_at(cell, terrain)
		if _erasing:
			if existing == null:
				continue
			undo.add_do_method(terrain, "remove_child", existing)
			undo.add_undo_method(terrain, "add_child", existing)
			undo.add_undo_method(existing, "set_owner", root)
			undo.add_undo_reference(existing)
			continue
		if existing != null and existing.definition == definition:
			continue
		if existing != null:
			undo.add_do_method(terrain, "remove_child", existing)
			undo.add_undo_method(terrain, "add_child", existing)
			undo.add_undo_method(existing, "set_owner", root)
			undo.add_undo_reference(existing)
		var tile := TileScript.new() as TacticalTile
		tile.name = "%s_%d_%d" % [
			_sanitize_name(definition.display_name),
			cell.x,
			cell.y,
		]
		tile.definition = definition
		tile.grid_cell = cell
		undo.add_do_method(terrain, "add_child", tile)
		undo.add_do_method(tile, "set_owner", root)
		undo.add_undo_method(terrain, "remove_child", tile)
		undo.add_do_reference(tile)
	undo.add_do_method(terrain, "refresh")
	undo.add_undo_method(terrain, "refresh")
	undo.commit_action()
	_stroke_cells.clear()
	update_overlays()


func _can_edit_cell(cell: Vector2i, context: Dictionary) -> bool:
	var grid := context.grid as IsometricGrid
	if not grid.is_in_bounds(cell):
		return false
	var terrain := context.terrain as TacticalTerrain
	if _erasing:
		return _get_tile_at(cell, terrain) != null
	var walls := context.walls as Node
	if walls != null:
		for child in walls.get_children():
			if child is TacticalWall and child.grid_cell == cell:
				return false
	return _get_selected_definition() != null


func _get_tile_at(cell: Vector2i, terrain: TacticalTerrain) -> TacticalTile:
	for child in terrain.get_children():
		if child is TacticalTile and child.grid_cell == cell:
			return child as TacticalTile
	return null


func _get_context() -> Dictionary:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		return {}
	var grid := root.get_node_or_null("Grid") as IsometricGrid
	var terrain := root.get_node_or_null("Terrain") as TacticalTerrain
	var walls := root.get_node_or_null("Walls")
	if grid == null or terrain == null:
		return {}
	return {
		"root": root,
		"grid": grid,
		"terrain": terrain,
		"walls": walls,
	}


func _sanitize_name(value: String) -> String:
	var result := value.strip_edges().replace(" ", "_")
	return result if not result.is_empty() else "Tile"
