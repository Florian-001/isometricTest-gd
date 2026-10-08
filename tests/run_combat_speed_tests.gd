extends SceneTree

const SettingsScript = preload("res://scripts/combat_speed_settings.gd")
const DIRECTORY := "res://.godot/combat_speed_validation"
const ACTIONS := ["movement", "melee", "projectile", "charge", "knockback"]

var settings: Node
var checks := 0
var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	settings = root.get_node("CombatSpeedSettings")
	settings.settings_path = DIRECTORY.path_join("session.cfg")
	settings.load_settings()
	_test_settings()
	await _test_battle_lifecycle()
	await _test_final_cast_completion()
	for action in ACTIONS:
		var normal := await _measure(action, 1)
		for speed in [2, 3]:
			var accelerated := await _measure(action, speed)
			check(absf(accelerated * speed - normal) < normal * 0.25 + 0.06,
				"%s runs at %d× (%0.3fs vs %0.3fs)" % [action, speed, accelerated, normal])
		var changed := await _measure(action, 1, true)
		check(changed < normal * 0.8, "%s speeds up during an action (%0.3fs vs %0.3fs)" % [action, changed, normal])
		await _measure(action, 2, false, true)
	await _test_real_time_controls()
	await _test_layout()
	settings.set_speed(1)
	paused = false
	print("COMBAT_SPEED_TESTS_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_settings() -> void:
	var store := SettingsScript.new()
	store.settings_path = DIRECTORY.path_join("missing.cfg")
	if FileAccess.file_exists(store.settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(store.settings_path))
	root.add_child(store)
	check(store.speed == 1 and Engine.time_scale == 1.0, "missing settings default to 1× outside combat")
	var config := ConfigFile.new()
	config.set_value("other", "retained", true)
	config.save(store.settings_path)
	store.load_settings()
	var signals: Array[int] = []
	store.speed_changed.connect(func(value): signals.append(value))
	store.set_speed(3)
	store.set_speed(0)
	store.set_speed(4)
	store.set_speed(3)
	check(store.speed == 3 and signals == [3], "invalid and repeated speeds do not change or emit")
	config.load(store.settings_path)
	check(config.get_value("combat", "speed") == 3 and config.get_value("other", "retained"), "speed saves without discarding other preferences")
	store.free()
	store = SettingsScript.new()
	store.settings_path = DIRECTORY.path_join("missing.cfg")
	root.add_child(store)
	check(store.speed == 3 and Engine.time_scale == 1.0, "a newly loaded settings instance restores the preference without accelerating menus")
	for invalid in [0, 4, "2", 2.0]:
		config.set_value("combat", "speed", invalid)
		config.save(store.settings_path)
		store.load_settings()
		check(store.speed == 1, "invalid saved value defaults to 1×: " + str(invalid))
	var file := FileAccess.open(store.settings_path, FileAccess.WRITE)
	file.store_string("[invalid config")
	file.close()
	var report_errors := Engine.print_error_messages
	Engine.print_error_messages = false
	store.load_settings()
	Engine.print_error_messages = report_errors
	check(store.speed == 1, "unreadable configuration defaults to 1×")
	store.settings_path = DIRECTORY.path_join("absent_directory/settings.cfg")
	store.set_speed(2)
	check(store.speed == 2, "failed persistence retains the session preference")
	store.free()


func _battle(payload: Dictionary = {}) -> TacticalBattle:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres") as BattleMapDefinition
	battle.pending_restore_payload = payload
	root.add_child(battle)
	check(battle.initialization_succeeded, "battle fixture initializes")
	return battle


func _test_battle_lifecycle() -> void:
	settings.set_speed(1)
	var battle := _battle()
	for expected in [2, 3, 1]:
		battle.speed_button.pressed.emit()
		check(settings.speed == expected and Engine.time_scale == float(expected)
			and battle.speed_button.text == "Speed: %d×" % expected, "speed button cycles and displays %d×" % expected)
	settings.set_speed(3)
	battle._on_levels_button_pressed()
	check(paused and battle.speed_button.disabled, "return confirmation pauses combat and disables speed")
	battle._on_speed_button_pressed()
	check(settings.speed == 3, "speed cannot change through return confirmation")
	battle.return_to_levels_dialog.hide()
	battle._on_return_to_levels_canceled()
	check(not paused and not battle.speed_button.disabled and Engine.time_scale == 3.0, "canceling return resumes the selected speed")
	battle._on_dev_button_pressed()
	check(paused and battle.speed_button.disabled, "Dev mode pauses combat and disables speed")
	battle._on_speed_button_pressed()
	check(settings.speed == 3, "speed cannot change through Dev mode")
	battle._on_dev_play_requested()
	check(not paused and not battle.speed_button.disabled and Engine.time_scale == 3.0, "Dev resume retains speed")
	var checkpoint := battle.capture_save_payload(false)
	var reloads: Array[Dictionary] = []
	battle.battle_reload_requested.connect(func(payload): reloads.append(payload))
	battle._on_restart_button_pressed()
	check(reloads.size() == 1, "restart produces a replacement payload")
	var replacement := _battle(reloads[0])
	battle.shutdown_battle()
	battle.free()
	check(Engine.time_scale == 3.0 and replacement.speed_button.text == "Speed: 3×", "old battle cleanup does not reset replacement speed")
	var invalid := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	var report_errors := Engine.print_error_messages
	Engine.print_error_messages = false
	root.add_child(invalid)
	Engine.print_error_messages = report_errors
	invalid.free()
	check(Engine.time_scale == 3.0, "failed replacement initialization leaves active battle timing intact")
	replacement.shutdown_battle()
	replacement.free()
	check(Engine.time_scale == 1.0 and settings.speed == 3, "shutdown restores normal time without resetting preference")
	battle = _battle(checkpoint)
	check(Engine.time_scale == 3.0 and battle.speed_button.text == "Speed: 3×", "scenario and checkpoint restoration retain the global preference")
	for unit in battle._characters:
		if not unit.is_friendly():
			unit.apply_damage(unit.current_health + unit.current_armor)
	await process_frame
	await process_frame
	check(battle._combat_finalized and Engine.time_scale == 1.0 and battle.speed_button.disabled,
		"combat completion restores normal time and disables speed")
	battle.free()
	battle = _battle()
	battle._on_return_to_levels_confirmed()
	check(Engine.time_scale == 1.0 and settings.speed == 3, "confirmed return restores menu timing")
	battle.free()
	battle = _battle()
	battle.free()
	check(Engine.time_scale == 1.0, "direct scene removal restores normal timing")
	await process_frame


func _test_final_cast_completion() -> void:
	settings.set_speed(3)
	var battle := _battle()
	var caster := battle.turn_manager.current_unit
	var enemies: Array[TacticalCharacter] = []
	for unit in battle._characters:
		if not unit.is_friendly():
			enemies.append(unit)
	for index in range(1, enemies.size()):
		enemies[index].apply_damage(enemies[index].current_health + enemies[index].current_armor)
	var target := enemies[0]
	target._set_runtime_grid_cell_immediate(caster.grid_cell + Vector2i.RIGHT)
	var ability := AbilityDefinition.new()
	ability.delivery_type = AbilityDefinition.DeliveryType.MELEE
	ability.requires_weapon = false
	ability.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	ability.innate_damage = 99999
	ability.scaling_amount = 0.0
	ability.melee_lunge_duration = 0.1
	ability.melee_return_duration = 0.6
	ability.melee_slash_duration = 0.6
	caster.set_dev_ability_loadout([ability])
	var impact_speed := [0.0]
	target.defeated.connect(func(_unit): impact_speed[0] = Engine.time_scale)
	var casts := [0]
	battle._ability_executor.ability_started.connect(func(_unit, _ability, _cell): casts[0] += 1)
	battle.set_auto_battle_enabled(true)
	var deadline := Time.get_ticks_msec() + 10000
	while not battle._combat_finalized and Time.get_ticks_msec() < deadline:
		await process_frame
	check(casts[0] == 1 and impact_speed[0] == 3.0, "Auto Battle executes a finishing cast at the chosen speed")
	check(battle._combat_finalized and not battle._ability_executor.is_resolving()
		and caster.global_position == battle.grid.grid_to_global(caster.grid_cell) and Engine.time_scale == 1.0,
		"finishing melee returns completely before combat restores normal timing")
	battle.free()
	await process_frame


func _fixture(kind: String) -> Dictionary:
	var arena := Node2D.new()
	arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(arena)
	var grid := IsometricGrid.new()
	grid.grid_size = Vector2i(12, 8)
	arena.add_child(grid)
	var caster := _unit(arena, grid, true, Vector2i(1, 2))
	var target := _unit(arena, grid, false, Vector2i(2, 2) if kind in ["melee", "knockback"] else Vector2i(5, 2))
	var ability := AbilityDefinition.new()
	ability.requires_weapon = false
	ability.range = 8.0
	ability.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	ability.innate_damage = 7
	ability.scaling_amount = 0.0
	ability.delivery_type = AbilityDefinition.DeliveryType.MELEE if kind in ["melee", "charge"] else AbilityDefinition.DeliveryType.PROJECTILE
	ability.melee_lunge_duration = 0.2
	ability.melee_return_duration = 0.5
	ability.melee_slash_duration = 0.5
	ability.projectile_speed = (caster.global_position + Vector2(0, -29)).distance_to(target.global_position + Vector2(0, -18)) / 0.6
	if kind == "charge":
		ability.caster_movement = AbilityDefinition.CasterMovement.CHARGE_TO_TARGET
	caster.set_dev_ability_loadout([ability])
	var executor := AbilityExecutor.new()
	arena.add_child(executor)
	return {"arena": arena, "grid": grid, "caster": caster, "target": target, "ability": ability,
		"executor": executor, "units": [caster, target], "targeting": AbilityTargeting.new(grid.grid_size)}


func _unit(arena: Node2D, grid: IsometricGrid, friendly: bool, cell: Vector2i) -> TacticalCharacter:
	var unit := TacticalCharacter.new()
	unit.definition = CharacterDefinition.new()
	unit.definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	unit.definition.constitution = 50
	unit.definition.movement_range = 8.0
	unit.starting_grid_cell = cell
	unit.movement_animation_speed = grid.grid_to_global(cell).distance_to(grid.grid_to_global(cell + Vector2i.RIGHT)) / 0.4
	arena.add_child(unit)
	unit.initialize(grid)
	unit.reset_movement()
	unit.reset_ability_action()
	return unit


func _measure(kind: String, speed: int, change := false, pause_action := false) -> float:
	var fixture := _fixture(kind)
	settings.set_speed(speed)
	settings.activate_battle(fixture.arena)
	# Let initialization settle before measuring, excluding first-frame load deltas.
	await create_timer(0.05, true, false, true).timeout
	for _frame in range(6):
		await process_frame
	var completed := [false]
	if change or pause_action:
		_adjust_during_action.call_deferred(fixture, completed, pause_action)
	var began := Time.get_ticks_msec()
	var caster: TacticalCharacter = fixture.caster
	var target: TacticalCharacter = fixture.target
	var movement_before := caster.remaining_movement
	if kind == "movement":
		var path: Array[Vector2i] = [caster.grid_cell, caster.grid_cell + Vector2i.RIGHT]
		await caster.move_along(path)
		check(caster.grid_cell == Vector2i(2, 2) and not caster.is_moving, "movement completes at selected speed")
	elif kind == "knockback":
		var effect := KnockbackEffectDefinition.new()
		effect.distance = 2
		var units: Array[TacticalCharacter] = [caster, target]
		await fixture.executor._apply_knockback(caster, target, effect, units, fixture.grid, {})
		check(target.grid_cell == Vector2i(4, 2) and not target.is_moving, "knockback completes at selected speed")
	else:
		var units: Array[TacticalCharacter] = [caster, target]
		var succeeded: bool = await fixture.executor.execute(caster, fixture.ability, target.grid_cell,
			units, fixture.grid, fixture.targeting)
		check(succeeded and target.current_health == target.get_max_health() - 7, kind + " preserves damage")
		check(caster.action_points == 1 and caster.get_ability_cooldown(fixture.ability) == 1, kind + " preserves AP and cooldown")
		check(caster.remaining_movement == movement_before, kind + " preserves movement resources")
		if kind == "charge":
			check(caster.grid_cell == Vector2i(4, 2), "charge reaches the same destination at every speed")
	completed[0] = true
	var elapsed := (Time.get_ticks_msec() - began) / 1000.0
	settings.deactivate_battle(fixture.arena)
	fixture.arena.free()
	await process_frame
	return elapsed


func _adjust_during_action(fixture: Dictionary, completed: Array, pause_action: bool) -> void:
	await create_timer(0.15, true, false, true).timeout
	check(not completed[0], "timing fixture is still resolving when speed or pause changes")
	if pause_action:
		paused = true
		var caster_position: Vector2 = fixture.caster.global_position
		var target_position: Vector2 = fixture.target.global_position
		await create_timer(0.4, true, false, true).timeout
		check(not completed[0] and fixture.caster.global_position == caster_position
			and fixture.target.global_position == target_position, "pause freezes the active action, including melee return and knockback")
		paused = false
	settings.set_speed(3)


func _test_real_time_controls() -> void:
	var camera := TacticalCameraController.new()
	root.add_child(camera)
	Input.action_press("ui_right")
	var key := InputEventKey.new()
	key.keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	var distance := 0.0
	for speed in [1, 2, 3]:
		Engine.time_scale = float(speed)
		camera.position = Vector2.ZERO
		camera._process(0.1 * speed)
		if speed == 1:
			distance = camera.position.x
		check(distance > 0.0 and is_equal_approx(camera.position.x, distance), "camera pan retains real-time speed at %d×" % speed)
	key.pressed = false
	Input.parse_input_event(key)
	Input.action_release("ui_right")
	camera.free()
	var counter := (load("res://scripts/fps_counter.gd") as GDScript).new() as Label
	root.add_child(counter)
	for speed in [1, 2, 3]:
		Engine.time_scale = float(speed)
		counter._elapsed = 0.0
		counter._process(0.2 * speed)
		check(is_equal_approx(counter._elapsed, 0.2), "FPS refresh retains real-time interval at %d×" % speed)
	counter.free()
	Engine.time_scale = 1.0


func _test_layout() -> void:
	for resolution in [Vector2i(1280, 720), Vector2i(800, 600)]:
		root.size = resolution
		var battle := _battle()
		for speed in [1, 2, 3]:
			settings.set_speed(speed)
			await process_frame
			await process_frame
			var actions := battle.speed_button.get_parent() as Control
			check(actions.get_global_rect().position.x >= 0 and actions.get_global_rect().end.x <= battle.get_viewport_rect().size.x,
				"action row fits %s at %d×" % [resolution, speed])
			var previous_end := 0.0
			for button in actions.get_children():
				check(button.get_global_rect().position.x >= previous_end, "buttons do not overlap at " + str(resolution))
				previous_end = button.get_global_rect().end.x
			if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(ProjectSettings.globalize_path(DIRECTORY.path_join("speed_%d_%dx%d.png" % [speed, resolution.x, resolution.y])))
		battle.shutdown_battle()
		battle.free()
		await process_frame
