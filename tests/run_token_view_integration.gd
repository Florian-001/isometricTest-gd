extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(InputMap.has_action(&"battle_token_view"), "token view is exposed in Input Map")
	var ctrl_binding := false
	for event in InputMap.action_get_events(&"battle_token_view"):
		if event is InputEventKey and event.physical_keycode == KEY_CTRL:
			ctrl_binding = true
	_check(ctrl_binding, "token view binds the physical Ctrl key")
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres") as BattleMapDefinition
	root.add_child(battle)
	await process_frame
	_check(battle.initialization_succeeded, "battle initializes")
	var unit := battle.turn_manager.current_unit
	var label := unit.get_node("UnitNameLabel") as Label
	var name_position := label.position
	var payload := battle.capture_save_payload(false)
	var initial_selection := battle._selected_character
	_check_all(battle, false)
	await _ctrl(KEY_LOCATION_LEFT, true)
	_check_all(battle, true)
	_check(label.position.y > unit._get_token_radius(), "name moves below the token")
	_check(battle.capture_save_payload(false) == payload, "token view does not change combat or saves")
	_check(battle._selected_character == initial_selection, "selection survives switching views")
	var enemy := battle._characters[2]
	var hidden_art_point := enemy.global_position + Vector2(0, -70)
	_check(battle._get_ability_cell_at_global_point(hidden_art_point) == battle.grid.global_to_grid(hidden_art_point),
		"ability targeting uses the tile underneath hidden artwork")
	_check(unit.contains_global_point(unit.global_position), "token center is clickable")
	_check(not unit.contains_global_point(unit.global_position + Vector2(0, -70)), "hidden artwork is not clickable")
	_check(not unit.contains_global_point(unit.global_position + Vector2(19, 19)), "token hit area is circular")
	for character in battle._characters:
		_check(battle._get_character_at_global_point(character.global_position) == character,
			"each token center picks its own unit")
	await _ctrl(KEY_LOCATION_RIGHT, true)
	await _ctrl(KEY_LOCATION_LEFT, false)
	_check_all(battle, true)
	await _ctrl(KEY_LOCATION_RIGHT, false)
	_check_all(battle, false)
	_check(label.position == name_position, "normal name position is restored")
	_check(unit.contains_global_point(unit.global_position + Vector2(0, -70)), "normal sprite hit area returns")
	await _ctrl(KEY_LOCATION_RIGHT, true)
	await _ctrl(KEY_LOCATION_LEFT, true)
	await _ctrl(KEY_LOCATION_RIGHT, false)
	_check_all(battle, true)
	await _ctrl(KEY_LOCATION_LEFT, false)
	_check_all(battle, false)
	# Presentation keys still work while actions or an enemy turn block gameplay.
	var was_locked := battle._movement_locked
	battle._movement_locked = true
	await _ctrl(KEY_LOCATION_LEFT, true)
	_check_all(battle, true)
	await _ctrl(KEY_LOCATION_LEFT, false)
	_check_all(battle, false)
	battle._movement_locked = was_locked

	battle.set_unit_names_visible(false)
	await _ctrl(KEY_LOCATION_LEFT, true)
	_check(not label.visible, "token view respects hidden names")
	root.focus_exited.emit()
	_check_all(battle, false)
	await _ctrl(KEY_LOCATION_LEFT, false)
	root.focus_entered.emit()
	await process_frame
	_check_all(battle, false)
	_check(not label.visible, "focus restoration preserves hidden names")
	root.focus_exited.emit()
	# Simulate arriving in the window with Ctrl already held.
	Input.action_press(&"battle_token_view")
	root.focus_entered.emit()
	_check_all(battle, true)
	Input.action_release(&"battle_token_view")
	await process_frame
	_check_all(battle, false)
	battle.set_unit_names_visible(true)

	# The battle root processes while developer mode pauses map simulation.
	battle._open_dev_mode()
	_check(paused, "developer mode pauses simulation")
	await _ctrl(KEY_LOCATION_LEFT, true)
	_check_all(battle, true)
	var scene := load("res://scenes/enemies/skeleton_warrior.tscn") as PackedScene
	battle._add_dev_unit(scene, _open_cell(battle))
	var skeleton: TacticalCharacter = battle._characters.back()
	_check(skeleton.is_token_view_enabled(), "new units inherit held token view")
	skeleton.apply_damage(999)
	_check(skeleton.is_bone_pile, "skeleton turns into a bone pile")
	_check(skeleton._get_token_texture() == skeleton.get_reassembly_effect().pile_texture,
		"bone pile token uses pile art")
	await _ctrl(KEY_LOCATION_LEFT, false)
	_check_all(battle, false)
	_check(skeleton.is_bone_pile, "releasing Ctrl preserves the current form")

	# Small cells constrain the badge; assigned portraits override facing artwork.
	var small_grid := IsometricGrid.new()
	small_grid.cell_size = Vector2(32, 16)
	root.add_child(small_grid)
	var fallback := TacticalCharacter.new()
	fallback.name = "Fallback"
	root.add_child(fallback)
	fallback.initialize(small_grid)
	fallback.set_token_view_enabled(true)
	_check(fallback._get_token_radius() < 8.0, "token fits a small grid cell")
	_check(fallback._get_token_texture() == null, "missing artwork uses initials")
	fallback.definition = CharacterDefinition.new()
	fallback.definition.portrait = unit.facing_right_texture
	_check(fallback._get_token_texture() == unit.facing_right_texture, "assigned portrait takes priority")
	fallback.queue_free()
	small_grid.queue_free()
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture(battle, skeleton)
	paused = false
	battle.queue_free()
	await process_frame
	# A scene loaded while Ctrl is already held starts in token view.
	await _ctrl(KEY_LOCATION_LEFT, true)
	var next_battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	next_battle.map_definition = load("res://resources/maps/goblin_skirmish.tres") as BattleMapDefinition
	root.add_child(next_battle)
	await process_frame
	_check_all(next_battle, true)
	await _ctrl(KEY_LOCATION_LEFT, false)
	_check_all(next_battle, false)
	next_battle.queue_free()
	await process_frame
	await _test_movement()
	if _failures.is_empty():
		print("TOKEN_VIEW_INTEGRATION_OK")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_movement() -> void:
	var grid := IsometricGrid.new()
	root.add_child(grid)
	var actor := (load("res://scenes/friendlies/friend_a.tscn") as PackedScene).instantiate() as TacticalCharacter
	var authored_name_position := (actor.get_node("UnitNameLabel") as Label).position
	actor.set_token_view_enabled(true)
	root.add_child(actor)
	actor.initialize(grid)
	actor.movement_animation_speed = 150.0
	actor.set_token_view_enabled(true)
	actor.move_along([Vector2i.ZERO, Vector2i(1, 0)])
	await create_timer(0.08).timeout
	_check(actor.is_moving and actor.global_position != grid.grid_to_global(Vector2i.ZERO),
		"token follows the unit during animated movement")
	_check(actor.contains_global_point(actor.global_position), "moving token stays clickable at its rendered position")
	actor.set_token_view_enabled(false)
	_check((actor.get_node("UnitNameLabel") as Label).position == authored_name_position,
		"enabling before ready still restores the authored name position")
	_check(actor.is_moving, "restoring artwork does not interrupt movement")
	if actor.is_moving:
		await actor.movement_finished
	_check(actor.grid_cell == Vector2i(1, 0), "movement reaches the same destination after switching views")
	actor.queue_free()
	grid.queue_free()
	await process_frame


func _ctrl(location: KeyLocation, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_CTRL
	event.physical_keycode = KEY_CTRL
	event.location = location
	event.pressed = pressed
	event.ctrl_pressed = pressed
	Input.parse_input_event(event)
	await process_frame


func _check_all(battle: TacticalBattle, enabled: bool) -> void:
	for unit in battle._characters:
		_check(unit.is_token_view_enabled() == enabled, "%s token mode should be %s" % [unit.name, enabled])


func _open_cell(battle: TacticalBattle) -> Vector2i:
	for y in range(battle.grid.grid_size.y):
		for x in range(battle.grid.grid_size.x):
			var cell := Vector2i(x, y)
			if battle._is_valid_dev_cell(cell):
				return cell
	return Vector2i(-1, -1)


func _capture(battle: TacticalBattle, skeleton: TacticalCharacter) -> void:
	battle.dev_mode_panel.close_panel()
	battle._dev_open = false
	battle.set_process(false)
	battle.set_unit_names_visible(false)
	# Place a friendly, an enemy, and a pile on adjacent cells for comparison.
	battle._characters[0].set_grid_cell_immediate(Vector2i(4, 4))
	battle._characters[1].set_grid_cell_immediate(Vector2i(5, 4))
	skeleton.set_grid_cell_immediate(Vector2i(4, 5))
	var center := battle.grid.grid_to_global(Vector2i(4, 4))
	battle.tactical_camera.position = center
	DirAccess.make_dir_recursive_absolute("res://.godot/token_view_validation")
	for zoom_level in [1.0, 1.8]:
		battle.tactical_camera.zoom = Vector2.ONE * zoom_level
		for enabled in [false, true]:
			for character in battle._characters:
				character.set_token_view_enabled(enabled)
			await process_frame
			await RenderingServer.frame_post_draw
			var path := "res://.godot/token_view_validation/%s_%s.png" % ["tokens" if enabled else "normal", zoom_level]
			_check(root.get_texture().get_image().save_png(path) == OK, "screenshot saves")
	# Inspect an intermediate movement position without advancing paused combat.
	var moving: TacticalCharacter = battle._characters[0]
	moving.position = moving.position.lerp(battle.grid.grid_to_global(Vector2i(5, 5)), 0.5)
	battle.set_unit_names_visible(true)
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://.godot/token_view_validation/moving_names.png") == OK,
		"movement/name screenshot saves")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
