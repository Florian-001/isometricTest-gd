extends SceneTree

const DIRECTORY := "res://.godot/multiple_arrows_validation"
var failures: Array[String] = []
var checks := 0
var arena: Node2D
var grid: IsometricGrid
var targeting: AbilityTargeting
var executor: AbilityExecutor
var units: Array[TacticalCharacter] = []
var ability: AbilityDefinition
var launches: Array[Vector2i] = []
var starts := 0
var finishes := 0


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	arena = Node2D.new()
	root.add_child(arena)
	grid = IsometricGrid.new()
	grid.grid_size = Vector2i(12, 12)
	arena.add_child(grid)
	targeting = AbilityTargeting.new(grid.grid_size)
	executor = AbilityExecutor.new()
	arena.add_child(executor)
	executor.projectile_delivery.projectile_launched.connect(func(_caster, _ability, cell): launches.append(cell))
	executor.ability_started.connect(func(_caster, _ability, _cell): starts += 1)
	executor.ability_finished.connect(func(_caster, _ability, _cell): finishes += 1)
	_test_resources_and_validation()
	_test_existing_projectile_rules()
	await _test_sequences()
	await _test_invalidated_targets()
	await _test_other_deliveries()
	_test_ai()
	_clear()
	arena.free()
	await _test_battle_ui()
	for failure in failures:
		push_error(failure)
	print("MULTIPLE_ARROWS_TESTS_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _unit(friendly: bool, cell: Vector2i) -> TacticalCharacter:
	var unit := TacticalCharacter.new()
	unit.name = "ArrowsTest%d" % units.size()
	unit.definition = CharacterDefinition.new()
	unit.definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	unit.definition.constitution = 50
	unit.definition.dexterity = 10
	unit.starting_grid_cell = cell
	unit.override_template_abilities = true
	unit.ability_overrides = [ability]
	unit.use_complete_equipment_override = true
	var bow := ItemDefinition.new()
	bow.weapon_type = ItemDefinition.WeaponType.RANGED
	bow.weapon_damage = 10
	unit.complete_equipment_overrides = [bow]
	arena.add_child(unit)
	unit.initialize(grid)
	unit.reset_ability_action()
	unit.reset_movement()
	units.append(unit)
	return unit


func _clear() -> void:
	for child in arena.get_children():
		if child is TacticalCharacter:
			child.free()
	units.clear()
	launches.clear()
	starts = 0
	finishes = 0
	ability = (load("res://resources/abilities/multiple_arrows.tres") as AbilityDefinition).duplicate(true)
	ability.projectile_speed = 10000.0


func _cast(caster: TacticalCharacter, targets: Array[TacticalCharacter]) -> bool:
	return await executor.execute_targets(caster, ability, targets, units, grid, targeting)


func _can_cast(caster: TacticalCharacter, targets: Array[TacticalCharacter], walls: Dictionary = {}) -> bool:
	return executor.can_execute_targets(caster, ability, targets, units, grid, targeting, walls)


func _test_resources_and_validation() -> void:
	_clear()
	var defaults := AbilityDefinition.new()
	check(not defaults.selects_per_hit() and defaults.allow_repeated_targets and defaults.hit_count == 1, "legacy defaults remain compatible")
	check(ability.hit_count == 3 and ability.selects_per_hit() and ability.allow_repeated_targets, "Multiple Arrows uses three independently selected hits with repeats")
	var caster := _unit(true, Vector2i(1, 1))
	var target := _unit(false, Vector2i(3, 1))
	var ally := _unit(true, Vector2i(1, 2))
	var arrow := load("res://resources/abilities/arrow.tres") as AbilityDefinition
	check(ability.calculate_hit_damage(caster) == 16 and ability.calculate_hit_damage(caster) == arrow.calculate_hit_damage(caster), "per-arrow formula matches Shoot with real stats and bow")
	check(ability.range == arrow.range and ability.calculate_damage(caster) == 48, "range matches Shoot and potential cast total is three hits")
	check(ability.get_description(caster).contains("48 potential cast total") and not ability.get_description(caster).contains("same target"), "description identifies distributed hits and potential total")
	check(_can_cast(caster, [target, target, target]), "three repeated selections are valid")
	for raw_targets in [[], [target], [target, target], [target, target, target, target], [target, ally, target], [target, null, target]]:
		var targets: Array[TacticalCharacter] = []
		targets.assign(raw_targets)
		check(not _can_cast(caster, targets), "incomplete, excess, allied and null selections reject")
	check(not executor.can_execute(caster, ability, target.grid_cell, units, grid, targeting), "single-cell API cannot bypass target selection")
	check(not _can_cast(caster, [target, target, target], {Vector2i(2, 1): true}), "wall trajectory rejects the complete cast")
	target.set_grid_cell_immediate(Vector2i(10, 10))
	check(not _can_cast(caster, [target, target, target]), "out-of-range target rejects")
	target.set_grid_cell_immediate(Vector2i(3, 1))
	ability.allow_repeated_targets = false
	check(not _can_cast(caster, [target, target, target]), "distinct-only authoring rejects duplicates")
	ability.allow_repeated_targets = true
	for property in {"target_flags": 10, "area_of_effect": 3, "shape": AbilityDefinition.Shape.LINE_FROM_CASTER, "caster_centered": true, "caster_movement": AbilityDefinition.CasterMovement.CHARGE_TO_TARGET}:
		var old_value: Variant = ability.get(property)
		var invalid_values := {"target_flags": 10, "area_of_effect": 3, "shape": AbilityDefinition.Shape.LINE_FROM_CASTER, "caster_centered": true, "caster_movement": AbilityDefinition.CasterMovement.CHARGE_TO_TARGET}
		ability.set(property, invalid_values[property])
		check(not ability.get_targeting_configuration_error().is_empty() and not _can_cast(caster, [target, target, target]), "invalid authoring rejected: %s" % property)
		ability.set(property, old_value)
	caster.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, null)
	check(not _can_cast(caster, [target, target, target]) and caster.ability_available, "missing bow rejects without spending an action")
	var archer := load("res://resources/classes/archer.tres") as CharacterClassDefinition
	caster.override_template_abilities = false
	caster.set_class_level(archer, 2)
	var shipped := load("res://resources/abilities/multiple_arrows.tres") as AbilityDefinition
	check(not caster.get_abilities().has(shipped), "Archer level 2 has no Multiple Arrows")
	caster.set_class_level(archer, 3)
	check(caster.get_abilities().has(shipped) and caster.get_abilities().size() == 3, "Archer level 3 unlocks Multiple Arrows after the equipment attack and Focus")
	check((load("res://resources/dev_tool_catalog.tres") as DevToolCatalog).abilities.has(shipped), "developer catalog contains Multiple Arrows")
	check(ResourceSaver.save(ability, DIRECTORY + "/ability.tres") == OK, "new fields save")
	var saved := ResourceLoader.load(DIRECTORY + "/ability.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as AbilityDefinition
	check(saved.selects_per_hit() and saved.hit_count == 3 and saved.allow_repeated_targets, "new fields survive reload")


func _test_sequences() -> void:
	for pattern in [[0, 1, 2], [0, 0, 0], [0, 1, 0]]:
		_clear()
		var caster := _unit(true, Vector2i(1, 1))
		var enemies: Array[TacticalCharacter] = [_unit(false, Vector2i(3, 1)), _unit(false, Vector2i(3, 2)), _unit(false, Vector2i(3, 3))]
		var initial_health := enemies[0].current_health
		var movement := caster.remaining_movement
		var selected: Array[TacticalCharacter] = []
		var cells: Array[Vector2i] = []
		for index in pattern:
			selected.append(enemies[index])
			cells.append(enemies[index].grid_cell)
		caster.get_equipped_weapon().status_effect = load("res://resources/statuses/slow.tres")
		check(await _cast(caster, selected), "cast succeeds for %s" % str(pattern))
		check(launches == cells, "one ordered projectile per selected slot: %s" % str(pattern))
		for index in range(3):
			check(enemies[index].current_health == initial_health - pattern.count(index) * 16, "damage matches selected arrow count")
			check(enemies[index].get_active_statuses().size() == (1 if pattern.has(index) else 0), "weapon status reaches only selected living targets")
		check(starts == 1 and finishes == 1 and not caster.ability_available and caster.remaining_movement == movement, "one action and one lifecycle pair, no movement cost")
		check(not await _cast(caster, selected), "cannot cast a second time with the spent action")
	_clear()
	var caster := _unit(true, Vector2i(1, 1))
	var ally := _unit(true, Vector2i(1, 2))
	var target := _unit(false, Vector2i(3, 1))
	caster.set_dev_passive_loadout([load("res://resources/passives/pack_tactics.tres")])
	ally.set_dev_passive_loadout([load("res://resources/passives/pack_tactics.tres")])
	var health := target.current_health
	check(await _cast(caster, [target, target, target]) and target.current_health == health - 51, "passive bow bonus applies once per arrow")


func _test_existing_projectile_rules() -> void:
	var suite := load("res://tests/test_tactical_foundation.gd").new() as McpTestSuite
	for method in ["test_ability_weighted_range_flags_and_projectile_blockers",
		"test_all_projectile_abilities_share_delivery_geometry",
		"test_projectile_target_filters_remain_ability_specific",
		"test_blocked_projectile_does_not_spend_action",
		"test_future_projectile_uses_shared_delivery_without_special_case",
		"test_ability_targets_require_clear_sight_and_reject_walls"]:
		suite._reset()
		suite.setup()
		suite.call(method)
		suite.teardown()
		suite._free_tracked()
		check(not suite._failed, "%s: %s" % [method, suite._message])


func _test_invalidated_targets() -> void:
	_clear()
	var caster := _unit(true, Vector2i(1, 1))
	var fragile := _unit(false, Vector2i(3, 1))
	var survivor := _unit(false, Vector2i(3, 2))
	fragile.apply_damage(fragile.current_health - 1)
	var health := survivor.current_health
	check(await _cast(caster, [fragile, fragile, survivor]), "early kill still completes cast")
	check(launches == [fragile.grid_cell, survivor.grid_cell] and survivor.current_health == health - 16, "skip dead repeat and continue to later target")
	_clear()
	caster = _unit(true, Vector2i(1, 1))
	var moved := _unit(false, Vector2i(3, 1))
	var replacement := _unit(false, Vector2i(8, 8))
	survivor = _unit(false, Vector2i(3, 2))
	var original_cell := moved.grid_cell
	executor.projectile_delivery.projectile_launched.connect(func(_c, _a, _cell):
		moved.set_grid_cell_immediate(Vector2i(10, 10))
		replacement.set_grid_cell_immediate(original_cell)
	, CONNECT_ONE_SHOT)
	health = moved.current_health
	check(await _cast(caster, [moved, moved, survivor]), "moving target is handled during flight")
	check(moved.current_health == health and replacement.current_health == health and survivor.current_health == health - 16, "no impact redirects to the replacement occupant")
	check(launches.size() == 2, "invalid later selection is skipped")
	_clear()
	caster = _unit(true, Vector2i(1, 1))
	var removed := _unit(false, Vector2i(3, 1))
	survivor = _unit(false, Vector2i(3, 2))
	executor.projectile_delivery.projectile_launched.connect(func(_c, _a, _cell):
		units.erase(removed)
		removed.free()
	, CONNECT_ONE_SHOT)
	check(await _cast(caster, [removed, removed, survivor]) and launches.size() == 2, "freed target references are skipped safely during and between hits")
	_clear()
	caster = _unit(true, Vector2i(1, 1))
	var target := _unit(false, Vector2i(3, 1))
	health = target.current_health
	executor.projectile_delivery.projectile_launched.connect(func(_c, _a, _cell): caster.apply_status(load("res://resources/statuses/stun.tres")), CONNECT_ONE_SHOT)
	check(await _cast(caster, [target, target, target]), "interrupted cast retains its spent action")
	check(launches.size() == 1 and target.current_health == health and finishes == 1, "caster stun stops further shots and invalidates the pending impact")
	_clear()
	caster = _unit(true, Vector2i(1, 1))
	target = _unit(false, Vector2i(3, 1))
	target.apply_damage(target.current_health)
	check(not await _cast(caster, [target, target, target]) and caster.ability_available and starts == 0, "stale selection rejects atomically before action consumption")


func _test_other_deliveries() -> void:
	for delivery in [AbilityDefinition.DeliveryType.CAST_ON_TARGET, AbilityDefinition.DeliveryType.MELEE]:
		_clear()
		ability.delivery_type = delivery
		ability.melee_lunge_duration = 0.02
		ability.melee_return_duration = 0.02
		ability.melee_slash_duration = 0.02
		var caster := _unit(true, Vector2i(1, 1))
		var first := _unit(false, Vector2i(2, 1))
		var second := _unit(false, Vector2i(1, 2))
		var health := first.current_health
		check(await _cast(caster, [first, second, first]), "configured unit delivery supports per-hit selection")
		check(first.current_health == health - 32 and second.current_health == health - 16, "delivery preserves one effect per slot")


func _test_ai() -> void:
	_clear()
	var actor := _unit(false, Vector2i(1, 1))
	_unit(true, Vector2i(3, 1))
	var planner := EnemyAIPlanner.new()
	var plan := planner.choose_plan(actor, units, GridPathfinder.new(grid.grid_size), targeting)
	check(plan == null or plan.ability != ability, "AI never emits an incomplete per-hit cast")


func _capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(DIRECTORY + "/" + name + ".png") == OK, "capture %s" % name)


func _click_control(control: Control) -> void:
	await process_frame
	await process_frame
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame


func _test_battle_ui() -> void:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	root.add_child(battle)
	battle.set_process(false)
	check(battle.initialization_succeeded, "real battle initializes")
	var caster := battle._characters[0]
	caster.set_class_level(load("res://resources/classes/archer.tres"), 3)
	caster.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, load("res://resources/items/weapons/ranger_bow.tres"))
	ability = load("res://resources/abilities/multiple_arrows.tres")
	battle.turn_manager.current_unit = caster
	battle.turn_manager.current_index = battle.turn_manager.turn_order.find(caster)
	caster.reset_ability_action()
	caster.reset_movement()
	battle._on_turn_started(caster)
	caster.set_grid_cell_immediate(Vector2i(5, 5))
	var first := battle._characters[2]
	var second := battle._characters[3]
	first.set_grid_cell_immediate(Vector2i(6, 5))
	second.set_grid_cell_immediate(Vector2i(5, 6))
	battle._characters[4].set_grid_cell_immediate(Vector2i(9, 9))
	var panel := battle.target_selection_panel
	check(ability.calculate_hit_damage(caster) == caster.get_abilities()[0].calculate_hit_damage(caster), "real Archer Shoot and Multiple Arrows share per-hit damage")
	battle._on_ability_selected(ability)
	check(panel.visible and panel.target_rows.get_child_count() == 3 and panel.fire_button.disabled, "ability opens three empty slots with Fire disabled")
	battle._handle_ability_click(first.global_position + Vector2(0, -85))
	battle._handle_ability_click(first.global_position + Vector2(0, -85))
	check(battle._selected_hit_targets == [first, first] and caster.ability_available and panel.fire_button.disabled, "world clicks append repeated targets without casting")
	battle._append_hit_target(caster)
	check(battle._selected_hit_targets.size() == 2, "invalid friendly click does not consume a slot")
	battle._append_hit_target(second)
	check(not panel.fire_button.disabled and caster.ability_available, "third target enables Fire without auto-casting")
	battle._append_hit_target(second)
	check(battle._selected_hit_targets == [first, first, second], "full selection ignores additional clicks")
	await _click_control(panel.target_rows.get_child(1).get_child(1))
	check(battle._selected_hit_targets == [first, second] and panel.fire_button.disabled, "Remove compacts selections without a battlefield click")
	battle._append_hit_target(first)
	check((panel.target_rows.get_child(2).get_child(0) as Label).text.contains(str(first.name)), "panel identifies duplicate selection by unit name")
	battle._update_ability_hover(second.global_position + Vector2(0, -85))
	await _capture("three_targets")
	second.set_grid_cell_immediate(Vector2i(11, 11))
	battle._refresh_hit_target_selection()
	check(panel.fire_button.disabled, "stale target disables confirmation")
	await battle._begin_selected_targets_cast()
	check(caster.ability_available, "invalid confirmation does not spend action")
	second.set_grid_cell_immediate(Vector2i(5, 6))
	await _click_control(panel.cancel_button)
	check(not panel.visible and battle._selected_hit_targets.is_empty() and caster.ability_available, "Cancel clears without spending action")
	for transition in ["escape", "ability", "inventory", "dev", "levels", "restart"]:
		battle._on_ability_selected(ability)
		battle._append_hit_target(first)
		match transition:
			"escape":
				var event := InputEventKey.new()
				event.keycode = KEY_ESCAPE
				event.pressed = true
				battle._unhandled_input(event)
			"ability": battle._on_ability_selected(load("res://resources/abilities/arrow.tres"))
			"inventory": battle._on_inventory_button_toggled(true)
			"dev": battle._open_dev_mode()
			"levels": battle._on_levels_button_pressed()
			"restart": battle._on_restart_button_pressed()
		check(not panel.visible and battle._selected_hit_targets.is_empty() and caster.ability_available, "%s clears the target selection without spending action" % transition)
		if transition == "inventory": battle._on_inventory_button_toggled(false)
		if transition == "dev": battle._on_dev_play_requested()
		if transition == "levels":
			battle.return_to_levels_dialog.hide()
			battle._on_return_to_levels_canceled()
		battle._cancel_ability_targeting()
	battle._on_ability_selected(ability)
	battle._append_hit_target(first)
	battle._append_hit_target(second)
	battle._append_hit_target(first)
	var health := first.current_health
	var damage := ability.calculate_hit_damage(caster)
	await _click_control(panel.fire_button)
	for frame in range(240):
		if not battle._movement_locked:
			break
		await process_frame
	check(first.current_health == maxi(0, health - 2 * damage) and not caster.ability_available, "real battle confirmation executes chosen arrows and spends action")
	check(not panel.visible and battle._selected_hit_targets.is_empty() and not battle._movement_locked, "cast clears panel and restores battle interaction")
	caster.reset_ability_action()
	battle._on_ability_selected(ability)
	battle._append_hit_target(second)
	battle._on_turn_ended(caster)
	check(not panel.visible and battle._selected_hit_targets.is_empty(), "turn end clears pending selections")
	battle._cancel_ability_targeting()
	caster.reset_ability_action()
	battle._on_ability_selected(ability)
	battle._append_hit_target(second)
	battle.shutdown_battle()
	check(not panel.visible and battle._selected_hit_targets.is_empty(), "shutdown clears pending selections")
	battle.free()
	await process_frame
