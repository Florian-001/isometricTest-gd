extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var legacy_wall := TacticalWall.new()
	legacy_wall.grid_cell = Vector2i(2, 2)
	legacy_wall.wall_height = 41.0
	legacy_wall.top_color = Color("765432")
	var legacy_wall_state := legacy_wall.capture_setup_state()
	var restored_legacy_wall := TacticalWall.new()
	restored_legacy_wall.apply_setup_state(legacy_wall_state)
	_check(restored_legacy_wall.definition == null, "walls without presets retain legacy mode")
	_check(is_equal_approx(restored_legacy_wall.wall_height, 41.0), "legacy wall height round-trips")
	_check(restored_legacy_wall.top_color == legacy_wall.top_color, "legacy wall colors round-trip")
	legacy_wall.free()
	restored_legacy_wall.free()

	var battle := _spawn_battle("res://resources/maps/terrain_showcase.tres")
	_check(battle.initialization_succeeded, "terrain-editor battle initializes")
	_check(battle.has_node("DevTerrainEditor"), "Battle authors the focused terrain editor controller")
	_check(battle.dev_tool_catalog.wall_styles.size() == 2, "the Dev catalog provides two wall presets")
	_check(
		battle.dev_mode_panel.has_node("Drawer/Margin/Main/Tabs/Terrain/TerrainContent/TileBrushes"),
		"the drawer authors the terrain brush palette"
	)
	_check(
		battle.dev_mode_panel.has_node("Drawer/Margin/Main/Tabs/Unit/UnitContent/PaletteScroll"),
		"the unit palette lives inside the Unit tab"
	)
	var authored_walls := battle.walls_container.get_children()
	_check(authored_walls.size() == 3, "Terrain Showcase retains its three authored walls")
	for wall in authored_walls:
		_check(
			wall is TacticalWall and wall.definition == battle.dev_tool_catalog.wall_styles[0],
			"Terrain Showcase walls use the Low Earthen Wall preset"
		)

	battle._open_dev_mode()
	_check(paused, "Terrain editing runs while combat is paused")
	battle.dev_mode_panel.tabs.current_tab = DevModePanel.TERRAIN_TAB
	var editor := battle.dev_terrain_editor
	var mud := load("res://resources/tiles/mud.tres") as TileDefinition
	var fire := load("res://resources/tiles/fire.tres") as TileDefinition
	var low_wall := load("res://resources/walls/low_earthen_wall.tres") as WallDefinition
	var tall_wall := load("res://resources/walls/tall_earthen_wall.tres") as WallDefinition

	editor.set_brush(DevTerrainEditor.BrushKind.TILE, mud)
	editor.begin_stroke(Vector2i(3, 4))
	_check(not editor.end_stroke(), "painting an identical terrain preset is a no-op")
	_check(not battle._dev_dirty, "a no-op terrain stroke does not mark setup dirty")

	editor.set_brush(DevTerrainEditor.BrushKind.WALL, low_wall)
	editor.begin_stroke(Vector2i(6, 3))
	_check(not editor.end_stroke(), "walls are rejected on a unit's restart cell")
	_check(not battle._dev_dirty, "an invalid wall stroke does not mark setup dirty")

	var unit := battle._characters[0]
	var unit_cell := unit.grid_cell
	var statuses_before := unit.get_active_statuses().size()
	editor.set_brush(DevTerrainEditor.BrushKind.TILE, fire)
	editor.begin_stroke(unit_cell)
	_check(editor.end_stroke(), "terrain can be painted beneath a unit")
	_check(battle.terrain.get_definition(unit_cell) == fire, "painted terrain refreshes immediately")
	_check(unit.get_active_statuses().size() == statuses_before, "painting does not trigger terrain effects while paused")
	_check(battle._dev_dirty, "an effective terrain edit marks setup dirty")
	_check(battle.dev_mode_panel.play_button.text == "Restart & Play", "terrain edits require a fresh restart")
	_check(battle.dev_terrain_editor.undo(), "the terrain edit can be undone")
	_check(battle.terrain.get_definition(unit_cell) == null, "Undo restores the prior terrain")
	_check(battle.dev_terrain_editor.redo(), "the terrain edit can be redone")
	_check(battle.terrain.get_definition(unit_cell) == fire, "Redo restores the painted terrain")

	editor.set_brush(DevTerrainEditor.BrushKind.TILE, mud)
	editor.begin_stroke(Vector2i(0, 0))
	editor.update_stroke(Vector2i(3, 0))
	_check(editor.end_stroke(), "an interpolated drag stroke commits once")
	for x in range(4):
		_check(battle.terrain.get_definition(Vector2i(x, 0)) == mud, "fast strokes fill every crossed cell")
	_check(
		is_equal_approx(battle._pathfinder.cell_cost_multipliers.get(Vector2i(2, 0), 1.0), 2.0),
		"movement costs refresh after a committed terrain stroke"
	)

	editor.set_brush(DevTerrainEditor.BrushKind.WALL, tall_wall)
	editor.begin_stroke(Vector2i(7, 4))
	_check(editor.end_stroke(), "painting a wall over terrain commits")
	_check(battle.terrain.get_definition(Vector2i(7, 4)) == null, "a wall automatically removes terrain")
	var replacement_wall := _find_wall(battle, Vector2i(7, 4))
	_check(replacement_wall != null and replacement_wall.definition == tall_wall, "the selected wall style is placed")
	_check(battle._get_wall_cells().has(Vector2i(7, 4)), "new walls block movement immediately")
	_check(
		not GridLineOfSight.new().has_line_of_sight(
			Vector2i(7, 3),
			Vector2i(7, 5),
			battle._get_wall_cells()
		),
		"new walls block line of sight immediately"
	)
	var planning_enemy: TacticalCharacter
	for character in battle._characters:
		if not character.is_friendly():
			planning_enemy = character
			break
	if planning_enemy != null:
		planning_enemy.reset_movement()
		var plan := battle._enemy_ai_planner.choose_plan(
			planning_enemy,
			battle._characters,
			battle._pathfinder,
			battle._ability_targeting,
			battle._get_wall_cells(),
			battle.terrain.get_definitions(),
			battle.turn_manager.get_rotating_order()
		)
		_check(
			not plan.pre_cast_path.has(Vector2i(7, 4))
			and not plan.post_cast_path.has(Vector2i(7, 4)),
			"enemy planning immediately treats painted walls as blocked"
		)

	editor.set_brush(DevTerrainEditor.BrushKind.TILE, fire)
	editor.begin_stroke(Vector2i(5, 4))
	_check(editor.end_stroke(), "painting terrain over a wall commits")
	_check(_find_wall(battle, Vector2i(5, 4)) == null, "terrain automatically removes the wall")
	_check(battle.terrain.get_definition(Vector2i(5, 4)) == fire, "replacement terrain becomes active")

	editor.begin_stroke(Vector2i(0, 0), true)
	editor.update_stroke(Vector2i(3, 0), true)
	_check(editor.end_stroke(), "right-drag erasing commits as one stroke")
	for x in range(4):
		_check(battle.terrain.get_definition(Vector2i(x, 0)) == null, "right-drag erases each crossed cell")

	var edited_environment := editor.capture_environment()
	_check(editor.reset_to_map(), "Reset to Map restores authored placement")
	_check(editor.capture_environment() == editor._original_environment, "Reset to Map restores terrain and walls atomically")
	_check(editor.undo(), "Reset to Map is undoable")
	_check(editor.capture_environment() == edited_environment, "Undo restores the environment from before reset")
	_check(editor.redo(), "Reset to Map can be redone")
	_check(editor.capture_environment() == editor._original_environment, "Redo reapplies the authored environment")

	editor.set_brush(DevTerrainEditor.BrushKind.WALL, tall_wall)
	_click_board_cell(battle, Vector2i(1, 1))
	_check(_find_wall(battle, Vector2i(1, 1)) != null, "Terrain-tab board input paints the chosen brush")
	var before_other_tab := editor.capture_environment()
	battle.dev_mode_panel.tabs.current_tab = 2
	_click_board_cell(battle, Vector2i(2, 1))
	_check(editor.capture_environment() == before_other_tab, "non-editing tabs ignore board clicks")

	var fresh_payload := battle.capture_save_payload(true)
	var validation := ScenarioSaveStore.validate_payload(fresh_payload)
	_check(validation.ok, "edited terrain and rich walls validate in a fresh snapshot")
	_check(fresh_payload.setup.has("terrain") and fresh_payload.setup.has("walls"), "new saves include complete environment setup")
	_check(fresh_payload.setup.wall_cells.size() == fresh_payload.setup.walls.size(), "legacy wall cells mirror rich wall setup")

	var duplicate_terrain := fresh_payload.duplicate(true)
	duplicate_terrain.setup.terrain.append(duplicate_terrain.setup.terrain[0].duplicate(true))
	_check(not ScenarioSaveStore.validate_payload(duplicate_terrain).ok, "duplicate terrain cells are rejected")
	var overlap := fresh_payload.duplicate(true)
	if not overlap.setup.terrain.is_empty() and not overlap.setup.walls.is_empty():
		overlap.setup.terrain[0].cell = overlap.setup.walls[0].cell.duplicate()
		_check(not ScenarioSaveStore.validate_payload(overlap).ok, "terrain and wall overlap is rejected")
	var missing_resource := fresh_payload.duplicate(true)
	missing_resource.setup.terrain[0].definition = "res://resources/tiles/missing.tres"
	_check(not ScenarioSaveStore.validate_payload(missing_resource).ok, "missing terrain resources are rejected")
	var wrong_terrain_type := fresh_payload.duplicate(true)
	wrong_terrain_type.setup.terrain[0].definition = "res://resources/walls/low_earthen_wall.tres"
	_check(not ScenarioSaveStore.validate_payload(wrong_terrain_type).ok, "wrong terrain resource types are rejected")
	var outside_terrain := fresh_payload.duplicate(true)
	outside_terrain.setup.terrain[0].cell = [-1, 0]
	_check(not ScenarioSaveStore.validate_payload(outside_terrain).ok, "out-of-bounds terrain cells are rejected")
	var missing_wall_resource := fresh_payload.duplicate(true)
	missing_wall_resource.setup.walls[0].definition = "res://resources/walls/missing.tres"
	_check(not ScenarioSaveStore.validate_payload(missing_wall_resource).ok, "missing wall resources are rejected")
	var duplicate_wall := fresh_payload.duplicate(true)
	duplicate_wall.setup.walls.append(duplicate_wall.setup.walls[0].duplicate(true))
	duplicate_wall.setup.wall_cells.append(duplicate_wall.setup.wall_cells[0].duplicate())
	_check(not ScenarioSaveStore.validate_payload(duplicate_wall).ok, "duplicate wall cells are rejected")
	var wall_spawn_conflict := fresh_payload.duplicate(true)
	wall_spawn_conflict.setup.walls[0].cell = wall_spawn_conflict.setup.units[0].cell.duplicate()
	wall_spawn_conflict.setup.wall_cells[0] = wall_spawn_conflict.setup.units[0].cell.duplicate()
	_check(not ScenarioSaveStore.validate_payload(wall_spawn_conflict).ok, "wall and unit spawn conflicts are rejected")

	var legacy_payload := battle.capture_save_payload(true)
	legacy_payload.setup.erase("terrain")
	legacy_payload.setup.erase("walls")
	var authored_wall_cells: Array[Array] = []
	for entry in editor._original_environment.walls:
		authored_wall_cells.append(entry.cell.duplicate())
	legacy_payload.setup.wall_cells = authored_wall_cells
	_check(ScenarioSaveStore.validate_payload(legacy_payload).ok, "legacy saves without rich environment fields remain valid")

	paused = false
	_remove_now(battle)
	var restored := _spawn_battle("res://resources/maps/terrain_showcase.tres", fresh_payload)
	_check(restored.initialization_succeeded, "an edited environment restores before battle initialization")
	_check(restored.dev_terrain_editor.capture_environment() == before_other_tab, "terrain and wall edits round-trip through a fresh save")
	var exact_payload := restored.capture_save_payload(false)
	_check(
		exact_payload.setup.terrain == fresh_payload.setup.terrain
		and exact_payload.setup.walls == fresh_payload.setup.walls,
		"a later exact snapshot preserves the edited environment"
	)
	_remove_now(restored)

	if _failures.is_empty():
		print("ALL_DEV_TERRAIN_INTEGRATION_OK")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _spawn_battle(map_path: String, restore_payload: Dictionary = {}) -> TacticalBattle:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load(map_path) as BattleMapDefinition
	battle.pending_restore_payload = restore_payload
	root.add_child(battle)
	return battle


func _click_board_cell(battle: TacticalBattle, cell: Vector2i) -> void:
	var screen_position := battle.get_canvas_transform() * battle.grid.grid_to_global(cell)
	var press := InputEventMouseButton.new()
	press.position = screen_position
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	battle._input(press)
	var release := InputEventMouseButton.new()
	release.position = screen_position
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	battle._input(release)


func _find_wall(battle: TacticalBattle, cell: Vector2i) -> TacticalWall:
	for child in battle.walls_container.get_children():
		if child is TacticalWall and child.grid_cell == cell:
			return child as TacticalWall
	return null


func _remove_now(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
