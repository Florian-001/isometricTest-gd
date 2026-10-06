extends SceneTree

const CAPTURE_DIR := "res://.godot/movement_attack_preview"
var failures: Array[String] = []
var checks := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(30.0).timeout.connect(func(): push_error("Movement attack preview timed out"); quit(1))
	var suite = load("res://tests/test_tactical_foundation.gd").new()
	for method in [
		"test_attack_preview_uses_hypothetical_origin_and_equipment_range",
		"test_grid_movement_attack_preview_preserves_and_clears_overlays",
		"test_grid_render_cache_reuses_geometry_for_overlays",
	]:
		suite._reset()
		suite.setup()
		suite.call(method)
		suite.teardown()
		suite._free_tracked()
		check(not suite._failed, "%s: %s" % [method, suite._message])
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	root.add_child(battle)
	battle.set_process(false)
	check(battle.initialization_succeeded, "battle initializes")
	if not battle.initialization_succeeded:
		battle.shutdown_battle()
		battle.queue_free()
		quit(1)
		return
	var caster := battle._characters[0]
	caster.set_grid_cell_immediate(Vector2i(4, 6))
	battle.turn_manager.current_unit = caster
	battle.turn_manager.current_index = battle.turn_manager.turn_order.find(caster)
	caster.reset_dev_ability_loadout()
	caster.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, null)
	caster.reset_movement()
	caster.reset_action_points()
	battle._on_turn_started(caster)
	var destination := Vector2i(5, 6)
	battle.tactical_camera.position = battle.grid.grid_to_global(Vector2i(6, 6))
	battle.tactical_camera.force_update_scroll()
	await process_frame
	var world_point := battle.grid.grid_to_global(destination)
	battle._last_mouse_screen_position = battle.get_viewport().get_canvas_transform() * world_point
	battle._has_mouse_screen_position = true
	var state_before := caster.capture_runtime_state()
	var position_before := caster.global_position
	battle._update_hover(world_point)
	check(battle.grid._movement_attack_cells.size() == 8, "unarmed movement hover highlights eight empty neighbors")
	check(battle.grid._movement_attack_cells.has(Vector2i(6, 7)), "range follows destination instead of current cell")
	check(battle.grid._path_cells == [caster.grid_cell, destination], "movement path remains visible")
	check(not battle.grid._reachable_cells.is_empty(), "movement range remains visible")
	check(not battle.grid._ability_mode and battle._selected_ability == null, "preview does not enter ability targeting")
	check(caster.capture_runtime_state() == state_before and caster.global_position == position_before, "hover preserves all unit runtime state and position")

	caster.equip_item(load("res://resources/items/weapons/spear.tres"))
	check(not battle._has_hovered_cell, "equipment change invalidates cached hover")
	battle._process(0.0)
	check(battle.grid._movement_attack_cells.has(Vector2i(7, 7)), "stationary cursor immediately gains spear reach")
	await _capture("spear_hover")
	caster.equip_item(load("res://resources/items/weapons/long_sword.tres"))
	battle._process(0.0)
	check(not battle.grid._movement_attack_cells.has(Vector2i(7, 7)), "stationary cursor loses extended reach after sword swap")
	caster.equip_item(load("res://resources/items/weapons/short_bow.tres"))
	battle._process(0.0)
	var bow_cells := battle.grid._movement_attack_cells.duplicate()
	check(bow_cells.has(Vector2i(10, 6)), "stationary cursor changes to ranged basic attack")
	await _capture("bow_hover")
	var shoot := caster.get_basic_attack_ability()
	check(caster.spend_ability_action(shoot), "fixture puts basic attack on cooldown")
	caster.spend_action_points(caster.action_points)
	battle._refresh_reachable_cells()
	battle._process(0.0)
	check(battle.grid._movement_attack_cells == bow_cells, "range stays visible with zero AP and active cooldown")
	var reachable_before_slow := battle._reachable_cells.size()
	caster.apply_status(load("res://resources/statuses/slow.tres"))
	check(not battle._has_hovered_cell, "status change invalidates cached hover")
	battle._process(0.0)
	check(battle._reachable_cells.size() < reachable_before_slow, "Slow immediately refreshes movement range")
	check(battle.grid._movement_attack_cells == bow_cells, "stationary cursor restores attack preview after status refresh")

	for invalid_cell in [caster.grid_cell, Vector2i(-1, -1), Vector2i(23, 23), battle._characters[1].grid_cell]:
		battle._update_hover(battle.grid.grid_to_global(invalid_cell))
		check(battle.grid._movement_attack_cells.is_empty() and battle.grid._path_cells.is_empty(), "invalid movement hover clears both previews: %s" % invalid_cell)
	battle._update_hover(world_point)
	check(not battle.grid._movement_attack_cells.is_empty(), "returning to a valid destination restores preview")
	caster.spend_movement(caster.remaining_movement)
	check(not battle._has_hovered_cell, "movement budget change invalidates cached hover")
	battle._process(0.0)
	check(battle.grid._movement_attack_cells.is_empty(), "stationary cursor clears when destination becomes unreachable")
	caster.reset_movement()
	battle._process(0.0)
	check(not battle.grid._movement_attack_cells.is_empty(), "movement reset restores stationary preview")
	caster.set_dev_ability_loadout([])
	battle._process(0.0)
	check(battle.grid._movement_attack_cells.is_empty(), "an override without the basic attack omits its range")
	check(battle.grid._path_cells.size() > 1, "missing basic attack preserves movement path")
	caster.reset_dev_ability_loadout()
	battle._process(0.0)
	check(not battle.grid._movement_attack_cells.is_empty(), "restoring default loadout restores stationary preview")

	caster.advance_ability_cooldowns()
	caster.reset_action_points()
	battle._on_ability_selected(shoot)
	check(battle.grid._movement_attack_cells.is_empty() and battle.grid._ability_mode, "selecting an ability replaces movement preview")
	battle._cancel_ability_targeting()
	battle._process(0.0)
	battle._on_turn_ended(caster)
	check(battle.grid._movement_attack_cells.is_empty(), "turn end clears preview")
	battle._select_character(caster)
	battle._process(0.0)
	battle.clear_selection()
	check(battle.grid._movement_attack_cells.is_empty(), "deselection clears preview")
	battle._select_character(caster)
	battle._process(0.0)
	var path := battle.grid._path_cells.duplicate()
	battle._begin_friendly_move(path)
	check(battle.grid._movement_attack_cells.is_empty(), "movement start clears preview before animation")
	while caster.is_moving:
		await process_frame
	check(caster.grid_cell == destination, "preview does not interfere with actual movement")
	check(battle.grid._movement_attack_cells.is_empty(), "arrival does not retain obsolete destination preview")

	battle.shutdown_battle()
	battle.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("MOVEMENT_ATTACK_PREVIEW: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture") or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(CAPTURE_DIR.path_join(label + ".png")) == OK, "visual capture saves")
