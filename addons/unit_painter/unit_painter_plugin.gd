@tool
extends EditorPlugin

const CharacterScript = preload("res://scripts/initiative_actor.gd")

var _definition_picker: OptionButton
var _ai_picker: OptionButton
var _paint_button: Button
var _definitions: Array[CharacterDefinition] = []
var _ai_profiles: Array[EnemyAIProfile] = []
var _hover_cell := Vector2i(-1, -1)
var _hover_valid := false


func _enter_tree() -> void:
	_definition_picker = OptionButton.new()
	_definition_picker.tooltip_text = "Character Template placed by Unit Paint"
	_definition_picker.item_selected.connect(_on_definition_selected)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _definition_picker)

	_ai_picker = OptionButton.new()
	_ai_picker.tooltip_text = "Enemy AI Profile assigned to newly placed enemy units"
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _ai_picker)

	_paint_button = Button.new()
	_paint_button.text = "Unit Paint"
	_paint_button.tooltip_text = "Left-click to place or replace a unit, right-click to erase, Escape to exit"
	_paint_button.toggle_mode = true
	_paint_button.toggled.connect(_on_paint_toggled)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _paint_button)
	_refresh_resources()


func _exit_tree() -> void:
	for control in [_definition_picker, _ai_picker, _paint_button]:
		if is_instance_valid(control):
			remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, control)
			control.queue_free()
	_definition_picker = null
	_ai_picker = null
	_paint_button = null


func _handles(object: Object) -> bool:
	return (
		object is IsometricGrid
		or object is TacticalCharacter
		or object is Node2D
	)


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
		return true

	if event is InputEventMouseButton and event.pressed:
		if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			return false
		_update_hover(event.position, context, event.button_index == MOUSE_BUTTON_RIGHT)
		if event.button_index == MOUSE_BUTTON_LEFT:
			_place_unit(_hover_cell, context)
		else:
			_erase_unit(_hover_cell, context)
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
	var scale := transform.get_scale()
	var half_width := grid.cell_size.x * 0.5 * scale.x
	var half_height := grid.cell_size.y * 0.5 * scale.y
	var points := PackedVector2Array([
		center + Vector2(0.0, -half_height),
		center + Vector2(half_width, 0.0),
		center + Vector2(0.0, half_height),
		center + Vector2(-half_width, 0.0),
	])
	var definition := _get_selected_definition()
	var color := (
		Color(definition.body_color, 0.5)
		if _hover_valid and definition != null
		else Color(1.0, 0.2, 0.2, 0.5)
	)
	overlay.draw_colored_polygon(points, Color(color, 0.28))
	points.append(points[0])
	overlay.draw_polyline(points, color.lightened(0.2), 2.0, true)
	overlay.draw_circle(center + Vector2(0.0, -29.0 * scale.y), 16.0 * scale.x, color)


func _on_paint_toggled(enabled: bool) -> void:
	if enabled:
		_refresh_resources()
	else:
		_hover_cell = Vector2i(-1, -1)
		_hover_valid = false
	update_overlays()


func _on_definition_selected(_index: int) -> void:
	_update_ai_picker_state()
	update_overlays()


func _refresh_resources() -> void:
	if _definition_picker == null or _ai_picker == null:
		return
	var selected_definition_path := ""
	var selected_definition := _get_selected_definition()
	if selected_definition != null:
		selected_definition_path = selected_definition.resource_path
	var selected_ai_path := ""
	var selected_ai := _get_selected_ai_profile()
	if selected_ai != null:
		selected_ai_path = selected_ai.resource_path

	_definitions.clear()
	_ai_profiles.clear()
	_find_resources("res://resources", _definitions, _ai_profiles)
	_definitions.sort_custom(func(a: CharacterDefinition, b: CharacterDefinition):
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0
	)
	_ai_profiles.sort_custom(func(a: EnemyAIProfile, b: EnemyAIProfile):
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0
	)

	_definition_picker.clear()
	for index in _definitions.size():
		var definition := _definitions[index]
		_definition_picker.add_item(definition.display_name)
		_definition_picker.set_item_tooltip(index, definition.resource_path)
		if definition.resource_path == selected_definition_path:
			_definition_picker.select(index)

	_ai_picker.clear()
	for index in _ai_profiles.size():
		var profile := _ai_profiles[index]
		_ai_picker.add_item(profile.display_name)
		_ai_picker.set_item_tooltip(index, profile.resource_path)
		if profile.resource_path == selected_ai_path:
			_ai_picker.select(index)

	var has_definitions := not _definitions.is_empty()
	_definition_picker.disabled = not has_definitions
	_paint_button.disabled = not has_definitions
	_paint_button.tooltip_text = (
		"Left-click to place or replace a unit, right-click to erase, Escape to exit"
		if has_definitions
		else "Create a CharacterDefinition resource under res://resources first"
	)
	_update_ai_picker_state()


func _find_resources(
	path: String,
	definitions: Array[CharacterDefinition],
	ai_profiles: Array[EnemyAIProfile]
) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file_name in directory.get_files():
		if file_name.get_extension().to_lower() not in ["tres", "res"]:
			continue
		var resource := load(path.path_join(file_name))
		if resource is CharacterDefinition:
			definitions.append(resource as CharacterDefinition)
		elif resource is EnemyAIProfile:
			ai_profiles.append(resource as EnemyAIProfile)
	for directory_name in directory.get_directories():
		_find_resources(path.path_join(directory_name), definitions, ai_profiles)


func _update_ai_picker_state() -> void:
	if _ai_picker == null:
		return
	var definition := _get_selected_definition()
	var needs_ai := (
		definition != null
		and definition.faction == CharacterDefinition.Faction.ENEMY
	)
	_ai_picker.disabled = not needs_ai or _ai_profiles.is_empty()
	_ai_picker.visible = needs_ai


func _get_selected_definition() -> CharacterDefinition:
	if (
		_definition_picker == null
		or _definition_picker.selected < 0
		or _definition_picker.selected >= _definitions.size()
	):
		return null
	return _definitions[_definition_picker.selected]


func _get_selected_ai_profile() -> EnemyAIProfile:
	if (
		_ai_picker == null
		or _ai_picker.selected < 0
		or _ai_picker.selected >= _ai_profiles.size()
	):
		return null
	return _ai_profiles[_ai_picker.selected]


func _update_hover(
	screen_position: Vector2,
	context: Dictionary,
	erasing: bool = false
) -> void:
	var viewport := get_editor_interface().get_editor_viewport_2d()
	var world_position := viewport.get_canvas_transform().affine_inverse() * screen_position
	var grid := context.grid as IsometricGrid
	_hover_cell = grid.global_to_grid(world_position)
	_hover_valid = _can_edit_cell(_hover_cell, context, erasing)
	update_overlays()


func _place_unit(cell: Vector2i, context: Dictionary) -> void:
	if not _can_edit_cell(cell, context, false):
		return
	var root := context.root as Node
	var characters := context.characters as Node2D
	var grid := context.grid as IsometricGrid
	var existing := _get_unit_at(cell, characters)
	var definition := _get_selected_definition()
	var unit := CharacterScript.new() as TacticalCharacter
	unit.name = "%s_%d_%d" % [_sanitize_name(definition.display_name), cell.x, cell.y]
	unit.definition = definition
	unit.starting_grid_cell = cell
	unit.position = characters.to_local(grid.grid_to_global(cell))
	unit.z_index = 100 + cell.x + cell.y
	if definition.faction == CharacterDefinition.Faction.ENEMY:
		unit.enemy_ai_profile = _get_selected_ai_profile()

	var undo := get_undo_redo()
	undo.create_action("Replace Tactical Unit" if existing != null else "Place Tactical Unit")
	if existing != null:
		undo.add_do_method(characters, "remove_child", existing)
		undo.add_undo_method(characters, "add_child", existing)
		undo.add_undo_method(existing, "set_owner", root)
		undo.add_undo_reference(existing)
	undo.add_do_method(characters, "add_child", unit)
	undo.add_do_method(unit, "set_owner", root)
	undo.add_undo_method(characters, "remove_child", unit)
	undo.add_do_reference(unit)
	undo.commit_action()
	_select_unit(unit)
	update_overlays()


func _erase_unit(cell: Vector2i, context: Dictionary) -> void:
	if not _can_edit_cell(cell, context, true):
		return
	var root := context.root as Node
	var characters := context.characters as Node2D
	var unit := _get_unit_at(cell, characters)
	if unit == null:
		return
	var undo := get_undo_redo()
	undo.create_action("Erase Tactical Unit")
	undo.add_do_method(characters, "remove_child", unit)
	undo.add_undo_method(characters, "add_child", unit)
	undo.add_undo_method(unit, "set_owner", root)
	undo.add_undo_reference(unit)
	undo.commit_action()
	update_overlays()


func _can_edit_cell(cell: Vector2i, context: Dictionary, erasing: bool) -> bool:
	var grid := context.grid as IsometricGrid
	if not grid.is_in_bounds(cell):
		return false
	var characters := context.characters as Node2D
	if erasing:
		return _get_unit_at(cell, characters) != null
	var definition := _get_selected_definition()
	if definition == null:
		return false
	if (
		definition.faction == CharacterDefinition.Faction.ENEMY
		and _get_selected_ai_profile() == null
	):
		return false
	var walls := context.walls as Node
	if walls != null:
		for child in walls.get_children():
			if child is TacticalWall and child.grid_cell == cell:
				return false
	return true


func _get_unit_at(cell: Vector2i, characters: Node2D) -> TacticalCharacter:
	for child in characters.get_children():
		if child is TacticalCharacter and child.starting_grid_cell == cell:
			return child as TacticalCharacter
	return null


func _get_context() -> Dictionary:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		return {}
	var grid := root.get_node_or_null("Grid") as IsometricGrid
	var characters := root.get_node_or_null("Characters") as Node2D
	if grid == null or characters == null:
		return {}
	return {
		"root": root,
		"grid": grid,
		"characters": characters,
		"walls": root.get_node_or_null("Walls"),
	}


func _select_unit(unit: TacticalCharacter) -> void:
	var selection := get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(unit)


func _sanitize_name(value: String) -> String:
	var result := value.strip_edges().replace(" ", "_")
	return result if not result.is_empty() else "Unit"
