@tool
class_name TacticalWall
extends Node2D

@export_category("Wall Placement")
@export var grid_cell: Vector2i = Vector2i.ZERO:
	set(value):
		grid_cell = value
		_sync_with_grid()

@export_category("Wall Preset")
@export var definition: WallDefinition:
	set(value):
		_unwatch_definition()
		definition = value
		_watch_definition()
		queue_redraw()

@export_category("Wall Appearance")
@export_range(8.0, 160.0, 1.0) var wall_height: float = 68.0:
	set(value):
		wall_height = maxf(8.0, value)
		queue_redraw()
@export var top_color: Color = Color("8d7456"):
	set(value):
		top_color = value
		queue_redraw()
@export var left_color: Color = Color("574330"):
	set(value):
		left_color = value
		queue_redraw()
@export var right_color: Color = Color("6f563c"):
	set(value):
		right_color = value
		queue_redraw()
@export var outline_color: Color = Color("241b16"):
	set(value):
		outline_color = value
		queue_redraw()
@export_range(0.5, 6.0, 0.5) var outline_width: float = 1.5:
	set(value):
		outline_width = maxf(0.5, value)
		queue_redraw()

var _grid: IsometricGrid


func _ready() -> void:
	_watch_definition()
	_find_grid()
	_sync_with_grid()
	queue_redraw()


func initialize(grid: IsometricGrid) -> void:
	_grid = grid
	_sync_with_grid()
	queue_redraw()


func capture_setup_state() -> Dictionary:
	var style_path := ""
	if definition != null:
		style_path = definition.resource_path
	return {
		"cell": [grid_cell.x, grid_cell.y],
		"definition": style_path,
		"appearance": {
			"wall_height": get_resolved_wall_height(),
			"top_color": get_resolved_top_color().to_html(true),
			"left_color": get_resolved_left_color().to_html(true),
			"right_color": get_resolved_right_color().to_html(true),
			"outline_color": get_resolved_outline_color().to_html(true),
			"outline_width": get_resolved_outline_width(),
		},
	}


func apply_setup_state(state: Dictionary) -> void:
	var cell_value: Array = state.get("cell", [0, 0])
	grid_cell = Vector2i(int(cell_value[0]), int(cell_value[1]))
	var style_path := String(state.get("definition", ""))
	definition = load(style_path) as WallDefinition if not style_path.is_empty() else null
	var appearance: Dictionary = state.get("appearance", {})
	if definition == null and not appearance.is_empty():
		wall_height = float(appearance.get("wall_height", wall_height))
		top_color = Color(String(appearance.get("top_color", top_color.to_html(true))))
		left_color = Color(String(appearance.get("left_color", left_color.to_html(true))))
		right_color = Color(String(appearance.get("right_color", right_color.to_html(true))))
		outline_color = Color(String(appearance.get("outline_color", outline_color.to_html(true))))
		outline_width = float(appearance.get("outline_width", outline_width))


func get_resolved_wall_height() -> float:
	return definition.wall_height if definition != null else wall_height


func get_resolved_top_color() -> Color:
	return definition.top_color if definition != null else top_color


func get_resolved_left_color() -> Color:
	return definition.left_color if definition != null else left_color


func get_resolved_right_color() -> Color:
	return definition.right_color if definition != null else right_color


func get_resolved_outline_color() -> Color:
	return definition.outline_color if definition != null else outline_color


func get_resolved_outline_width() -> float:
	return definition.outline_width if definition != null else outline_width


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var board := _find_grid()
	if board == null:
		warnings.append("TacticalWall requires an IsometricGrid in the edited scene.")
		return warnings
	if not board.is_in_bounds(grid_cell):
		warnings.append("Wall cell %s is outside the grid bounds." % grid_cell)
	var root := get_tree().edited_scene_root if is_inside_tree() else null
	if root != null:
		var characters := root.get_node_or_null("Characters")
		if characters != null:
			for child in characters.get_children():
				if child is TacticalCharacter and child.starting_grid_cell == grid_cell:
					warnings.append("This cell is occupied by %s's starting position." % child.name)
					break
	if get_parent() != null:
		for sibling in get_parent().get_children():
			if sibling != self and sibling is TacticalWall and sibling.grid_cell == grid_cell:
				warnings.append("Another wall already occupies this cell.")
				break
	return warnings


func _find_grid() -> IsometricGrid:
	if is_instance_valid(_grid):
		return _grid
	if not is_inside_tree():
		return null
	var ancestor := get_parent()
	while ancestor != null:
		var nearby_grid := ancestor.get_node_or_null("Grid") as IsometricGrid
		if nearby_grid != null:
			_grid = nearby_grid
			return _grid
		ancestor = ancestor.get_parent()
	var root := get_tree().edited_scene_root if Engine.is_editor_hint() else null
	if root == null:
		root = get_tree().current_scene
	if root != null:
		_grid = root.get_node_or_null("Grid") as IsometricGrid
	return _grid


func _sync_with_grid() -> void:
	var board := _find_grid()
	if board == null:
		return
	global_position = board.grid_to_global(grid_cell)
	z_index = 100 + grid_cell.x + grid_cell.y
	queue_redraw()
	update_configuration_warnings()


func _draw() -> void:
	var board := _find_grid()
	var size := board.cell_size if board != null else Vector2(96.0, 48.0)
	var half_width := size.x * 0.46
	var half_height := size.y * 0.46
	var floor_top := Vector2(0.0, -half_height)
	var floor_right := Vector2(half_width, 0.0)
	var floor_bottom := Vector2(0.0, half_height)
	var floor_left := Vector2(-half_width, 0.0)
	var lift := Vector2(0.0, -get_resolved_wall_height())
	var top_top := floor_top + lift
	var top_right := floor_right + lift
	var top_bottom := floor_bottom + lift
	var top_left := floor_left + lift

	_draw_face(PackedVector2Array([top_left, top_bottom, floor_bottom, floor_left]), get_resolved_left_color())
	_draw_face(PackedVector2Array([top_bottom, top_right, floor_right, floor_bottom]), get_resolved_right_color())
	_draw_face(PackedVector2Array([top_top, top_right, top_bottom, top_left]), get_resolved_top_color())


func _draw_face(points: PackedVector2Array, color: Color) -> void:
	draw_colored_polygon(points, color)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, get_resolved_outline_color(), get_resolved_outline_width(), true)


func _watch_definition() -> void:
	if definition != null and not definition.changed.is_connected(_on_definition_changed):
		definition.changed.connect(_on_definition_changed)


func _unwatch_definition() -> void:
	if definition != null and definition.changed.is_connected(_on_definition_changed):
		definition.changed.disconnect(_on_definition_changed)


func _on_definition_changed() -> void:
	queue_redraw()
