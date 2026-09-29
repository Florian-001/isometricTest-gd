extends SceneTree

const DIRECTORY := "res://.godot/ranged_shoot_validation"
var checks := 0
var failures: Array[String] = []
var arena: Node2D
var grid: IsometricGrid
var targeting: AbilityTargeting
var executor: AbilityExecutor
var units: Array[TacticalCharacter] = []
var power: AbilityDefinition = load("res://resources/abilities/power_shoot.tres")
var piercing: AbilityDefinition = load("res://resources/abilities/piercing_shoot.tres")
var launch_cells: Array[Vector2i] = []
var impact_positions: Array[Vector2] = []


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	arena = Node2D.new()
	root.add_child(arena)
	grid = IsometricGrid.new()
	grid.grid_size = Vector2i(14, 14)
	arena.add_child(grid)
	targeting = AbilityTargeting.new(grid.grid_size)
	executor = AbilityExecutor.new()
	arena.add_child(executor)
	executor.projectile_delivery.projectile_launched.connect(func(_caster, _ability, aim): launch_cells.append(aim))
	executor.projectile_delivery.projectile_arrived.connect(func(_caster, _ability, _aim):
		var visual = arena.get_node_or_null("AbilityProjectile")
		if visual != null:
			impact_positions.append(visual.global_position)
	)
	_test_resources()
	_test_geometry()
	await _test_power()
	await process_frame
	await _test_armor()
	await process_frame
	await _test_piercing()
	await process_frame
	await _test_walls()
	await process_frame
	await _test_ai()
	_clear()
	arena.free()
	await _test_battle_preview()
	for failure in failures:
		push_error(failure)
	print("RANGED_SHOOT_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _unit(friendly: bool, cell: Vector2i) -> TacticalCharacter:
	var unit := TacticalCharacter.new()
	unit.definition = CharacterDefinition.new()
	unit.definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	unit.definition.constitution = 100
	unit.definition.dexterity = 10
	unit.definition.movement_range = 0.0
	unit.override_template_abilities = true
	unit.ability_overrides = [power, piercing]
	unit.use_complete_equipment_override = true
	var bow := ItemDefinition.new()
	bow.weapon_type = ItemDefinition.WeaponType.RANGED
	bow.weapon_damage = 7
	unit.complete_equipment_overrides = [bow]
	unit.starting_grid_cell = cell
	arena.add_child(unit)
	unit.initialize(grid)
	unit.reset_ability_action()
	unit.reset_movement()
	units.append(unit)
	return unit


func _clear() -> void:
	for unit in units:
		if is_instance_valid(unit):
			unit.free()
	units.clear()
	launch_cells.clear()
	impact_positions.clear()


func _test_resources() -> void:
	var catalog: DevToolCatalog = load("res://resources/dev_tool_catalog.tres")
	for ability in [power, piercing]:
		check(ability.ability_type == AbilityDefinition.AbilityType.RANGED and ability.requires_weapon, "Both shots require ranged equipment")
		check(ability.effect == AbilityDefinition.PrimaryEffect.DAMAGE and ability.damage_type == DamageCalculator.Type.PHYSICAL, "Both shots use standard physical damage")
		check(ability.range == 5.0 and ability.innate_damage == 0 and ability.hit_count == 1, "Both shots have range five, zero innate damage, one hit")
		check(ability.scaling_stat == DamageCalculator.ScalingSource.DEXTERITY and not ability.accepts_weapon_range_bonus, "Both shots scale Dexterity with fixed authored range")
		check(ability.delivery_type == AbilityDefinition.DeliveryType.PROJECTILE and catalog.abilities.has(ability), "Both shots have projectile delivery and developer catalog entries")
		check(ability.get_targeting_configuration_error().is_empty(), "Shipped targeting is valid")
	check(power.scaling_amount == 150.0 and piercing.scaling_amount == 100.0, "Authored scaling percentages match requested values")
	check(power.target_flags == AbilityDefinition.TargetFlags.ENEMY, "Power Shoot targets one enemy")
	check(piercing.target_flags == 10 and piercing.shape == AbilityDefinition.Shape.LINE_TO_MAX_RANGE, "Piercing Shoot uses full-range directional cell targeting")
	check(AbilityDefinition.Shape.LINE_FROM_CASTER == 5 and AbilityDefinition.Shape.LINE_IN_FRONT == 6 and AbilityDefinition.Shape.LINE_TO_MAX_RANGE == 7, "New shape appends without renumbering existing resources")
	var caster := _unit(true, Vector2i(2, 2))
	check(power.calculate_hit_damage(caster) == 22 and piercing.calculate_hit_damage(caster) == 17, "Damage includes weapon plus 150%/100% effective Dexterity")
	check(piercing.get_description(caster).contains("maximum range") and power.get_description(caster).contains("Dexterity x150%"), "Tooltips explain formulas and piercing geometry")
	caster.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, null)
	check(not power.can_be_used_by(caster) and not piercing.can_be_used_by(caster), "Unarmed casters cannot use ranged abilities")
	var melee := ItemDefinition.new()
	melee.weapon_type = ItemDefinition.WeaponType.MELEE
	caster.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, melee)
	check(not power.can_be_used_by(caster) and not piercing.can_be_used_by(caster), "Melee equipment cannot use ranged abilities")
	_clear()
	for property in ["caster_centered", "caster_movement", "hit_targeting", "area_of_effect"]:
		var invalid: AbilityDefinition = piercing.duplicate(true)
		invalid.set(property, true if property == "caster_centered" else (3 if property == "area_of_effect" else 1))
		check(not invalid.get_targeting_configuration_error().is_empty(), "Rejects incompatible full-range authoring: " + property)
	var catalog_script = load("res://addons/ability_balance/catalog.gd").new()
	catalog_script.scan()
	check(power.resource_path in catalog_script.active and piercing.resource_path in catalog_script.active, "Ability Balance discovers both shots")


func _test_geometry() -> void:
	var origin := Vector2i(6, 6)
	for direction in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		var cells := targeting.get_affected_cells(origin, origin + direction, piercing)
		check(cells.size() == 5 and cells.back() == origin + direction * 5, "Cardinal ray extends through nearby aim to full range: " + str(direction))
		check(targeting.get_delivery_endpoint(origin, origin + direction, piercing) == cells.back(), "Cardinal delivery endpoint matches affected line")
	for direction in [Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var cells := targeting.get_affected_cells(origin, origin + direction, piercing)
		check(cells.size() == 3 and cells.back() == origin + direction * 3, "Diagonal rays respect weighted range five")
		check(not cells.has(origin + direction * 4), "Diagonal cells beyond weighted range are excluded")
	var expected: Array[Vector2i] = [Vector2i(7, 6), Vector2i(7, 7), Vector2i(8, 7), Vector2i(9, 7), Vector2i(9, 8), Vector2i(10, 8)]
	var arbitrary := targeting.get_affected_cells(origin, origin + Vector2i(2, 1), piercing)
	check(arbitrary == expected, "Arbitrary direction preserves original slope and line rasterization")
	check(arbitrary == targeting.get_affected_cells(origin, origin + Vector2i(4, 2), piercing), "Collinear aim distances produce the same full-range line")
	check(targeting.get_delivery_endpoint(origin, origin + Vector2i(2, 1), piercing) == expected.back(), "Arbitrary-angle projectile endpoint matches line")
	check(targeting.get_affected_cells(origin, origin, piercing).is_empty(), "Cannot aim a full-range line at caster")
	check(targeting.get_affected_cells(Vector2i(12, 6), Vector2i(13, 6), piercing) == [Vector2i(13, 6)], "Ray clips at map edge")
	check(targeting.get_delivery_endpoint(Vector2i(12, 6), Vector2i(13, 6), piercing) == Vector2i(13, 6), "Map-edge projectile endpoint remains in bounds")
	var walls := {Vector2i(9, 6): true}
	check(targeting.get_affected_cells(origin, origin + Vector2i.RIGHT, piercing, walls) == [Vector2i(7, 6), Vector2i(8, 6)], "Wall stops effects without affecting the wall cell")
	check(targeting.get_delivery_endpoint(origin, origin + Vector2i.RIGHT, piercing, walls) == Vector2i(9, 6), "Projectile visually reaches first blocking wall")
	var beam: AbilityDefinition = load("res://resources/abilities/beam.tres")
	check(not targeting.get_affected_cells(origin, origin + Vector2i.RIGHT, beam).has(origin + Vector2i(2, 0)), "Existing Beam still ends at selected cell")


func _test_power() -> void:
	_clear()
	var caster := _unit(true, Vector2i(1, 3))
	var target := _unit(false, Vector2i(3, 3))
	var behind := _unit(false, Vector2i(5, 3))
	var health := target.current_health
	var other_health := behind.current_health
	check(targeting.get_affected_units(caster, target.grid_cell, power, units) == [target], "Power Shoot affects only selected enemy")
	check(not executor.can_execute(caster, power, Vector2i(2, 3), units, grid, targeting), "Power Shoot cannot select empty ground")
	check(not executor.can_execute(caster, power, Vector2i(7, 3), units, grid, targeting), "Power Shoot respects range limit")
	check(not executor.can_execute(caster, power, target.grid_cell, units, grid, targeting, {Vector2i(2, 3): true}), "Power Shoot respects walls")
	check(await executor.execute(caster, power, target.grid_cell, units, grid, targeting), "Power Shoot executes")
	check(target.current_health == health - 22 and behind.current_health == other_health, "Power Shoot resolves physical formula once on one enemy")
	check(launch_cells == [target.grid_cell] and impact_positions[0].is_equal_approx(grid.grid_to_global(target.grid_cell) + Vector2(0, -18)), "Power Shoot retains ordinary projectile endpoint and aim signal")
	check(not caster.ability_available, "Power Shoot spends one action")


func _test_armor() -> void:
	_clear()
	var caster := _unit(true, Vector2i(1, 3))
	var target := _unit(false, Vector2i(3, 3))
	var armor := ItemDefinition.new()
	armor.slot = ItemDefinition.EquipmentSlot.ARMOR
	armor.armor = 5
	target.set_dev_equipment(ItemDefinition.EquipmentSlot.ARMOR, armor)
	target.current_armor = target.get_max_armor()
	var health := target.current_health
	check(await executor.execute(caster, power, target.grid_cell, units, grid, targeting), "Power Shoot can strike armored enemy")
	check(target.current_armor == 0 and target.current_health == health - 17, "Standard physical armor absorbs five of Power Shoot's 22 damage")


func _test_piercing() -> void:
	_clear()
	var caster := _unit(true, Vector2i(1, 3))
	var before := _unit(false, Vector2i(2, 3))
	var aim := _unit(false, Vector2i(3, 3))
	var beyond := _unit(false, Vector2i(6, 3))
	var outside := _unit(false, Vector2i(7, 3))
	var ally := _unit(true, Vector2i(4, 3))
	var off_line := _unit(false, Vector2i(4, 4))
	var health := before.current_health
	var recipients := targeting.get_affected_units(caster, aim.grid_cell, piercing, units)
	check(recipients == [before, aim, beyond], "Piercing recipients include before/at/beyond aim, exclude allies and off-line/out-of-range units")
	check(not executor.can_execute(caster, piercing, caster.grid_cell, units, grid, targeting), "Piercing rejects caster-cell direction")
	check(executor.can_execute(caster, piercing, Vector2i(5, 3), units, grid, targeting), "Piercing supports empty cell aiming")
	check(await executor.execute(caster, piercing, aim.grid_cell, units, grid, targeting), "Piercing executes one full-range projectile")
	for target in recipients:
		check(target.current_health == health - 17, "Each pierced enemy receives exactly one hit")
	for target in [outside, ally, off_line, caster]:
		check(target.current_health == health, "Excluded unit receives no piercing damage")
	check(launch_cells == [aim.grid_cell], "Piercing emits selected aim in existing projectile signals")
	check(impact_positions.size() == 1 and impact_positions[0].is_equal_approx(grid.grid_to_global(Vector2i(6, 3)) + Vector2(0, -18)), "Projectile travels beyond aim to full-range endpoint")
	check(not caster.ability_available, "Piercing spends a single action")


func _test_walls() -> void:
	_clear()
	var caster := _unit(true, Vector2i(1, 3))
	var near := _unit(false, Vector2i(2, 3))
	var behind_wall := _unit(false, Vector2i(5, 3))
	var walls := {Vector2i(4, 3): true}
	var health := near.current_health
	check(not executor.can_execute(caster, piercing, behind_wall.grid_cell, units, grid, targeting, walls), "Cannot aim through blocking wall")
	check(executor.can_execute(caster, piercing, near.grid_cell, units, grid, targeting, walls), "Aim before wall is legal")
	check(await executor.execute(caster, piercing, near.grid_cell, units, grid, targeting, walls), "Ray can stop at wall beyond legal aim")
	check(near.current_health == health - 17 and behind_wall.current_health == health, "Wall prevents damage to enemies behind it")
	check(impact_positions[0].is_equal_approx(grid.grid_to_global(Vector2i(4, 3)) + Vector2(0, -18)), "Projectile reaches wall rather than stopping at aim")
	var angled_walls := {Vector2i(2, 4): true}
	check(not targeting.is_valid_primary_target(caster, Vector2i(3, 4), piercing, units, angled_walls), "Supercover wall before arbitrary-angle aim blocks cast")
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size, angled_walls)
	check(not EnemyAIPlanner.new()._is_valid_primary_target(caster, caster.grid_cell, Vector2i(3, 4), piercing, snapshot, targeting), "AI rejects same supercover-blocked aim as runtime")


func _test_ai() -> void:
	_clear()
	var caster := _unit(false, Vector2i(1, 3))
	caster.ability_overrides = [piercing]
	var first := _unit(true, Vector2i(2, 3))
	var last := _unit(true, Vector2i(6, 3))
	var outside := _unit(true, Vector2i(7, 3))
	var health := first.current_health
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
	var planner := EnemyAIPlanner.new()
	var profile := EnemyAIProfile.new()
	var plan := planner.choose_plan(caster, units, GridPathfinder.new(grid.grid_size), targeting)
	check(plan.ability == piercing, "AI chooses a legal piercing cast")
	var planned := targeting.get_affected_units(caster, plan.target_cell, piercing, units)
	check(planned.has(first) and planned.has(last), "Chosen AI aim includes multiple aligned enemies")
	var score := planner._forecast_ability(caster, piercing, first.grid_cell, snapshot, targeting, profile)
	check(score > 0 and snapshot.get_health(first) == health - 17 and snapshot.get_health(last) == health - 17, "AI forecasts full-range recipients beyond aim")
	check(snapshot.get_health(outside) == health and first.current_health == health, "AI forecast excludes beyond range and leaves live units unchanged")
	check(await executor.execute(caster, piercing, first.grid_cell, units, grid, targeting), "Enemy can execute forecasted piercing cast")
	check(first.current_health == snapshot.get_health(first) and last.current_health == snapshot.get_health(last), "AI health forecast matches executed piercing damage")


func _test_battle_preview() -> void:
	var battle = load("res://scenes/battle.tscn").instantiate()
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	root.add_child(battle)
	battle.set_process(false)
	await process_frame
	var caster: TacticalCharacter
	var enemies: Array[TacticalCharacter] = []
	for unit in battle._characters:
		if unit.is_friendly() and caster == null:
			caster = unit
		elif not unit.is_friendly():
			enemies.append(unit)
	check(caster != null and not enemies.is_empty(), "Battle fixture has caster and enemies")
	if caster == null or enemies.is_empty():
		battle.shutdown_battle()
		battle.free()
		return
	caster.set_grid_cell_immediate(Vector2i(1, 1))
	var bow := ItemDefinition.new()
	bow.weapon_type = ItemDefinition.WeaponType.RANGED
	bow.weapon_damage = 7
	caster.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, bow)
	caster.set_dev_ability_loadout([piercing])
	caster.reset_ability_action()
	enemies[0].set_grid_cell_immediate(Vector2i(5, 1))
	battle._selected_character = caster
	battle._selected_ability = piercing
	battle._ability_range_cells = battle._ability_targeting.get_cells_in_range(caster, piercing)
	battle._ability_target_cells = battle._ability_targeting.get_valid_target_cells(caster, piercing, battle._characters, battle._get_wall_cells())
	battle.grid.show_ability_targets(caster.grid_cell, battle._ability_range_cells, battle._ability_target_cells)
	battle._update_ability_hover(battle.grid.grid_to_global(Vector2i(2, 1)))
	var expected: Array[Vector2i] = battle._ability_targeting.get_affected_cells(caster.grid_cell, Vector2i(2, 1), piercing, battle._get_wall_cells(), caster)
	check(battle.grid._ability_area_cells == expected and expected.has(Vector2i(5, 1)), "Real hover highlights extend beyond nearby aim")
	var endpoint: Vector2i = battle._ability_targeting.get_delivery_endpoint(caster.grid_cell, Vector2i(2, 1), piercing, battle._get_wall_cells(), caster)
	check(battle.grid._ability_trajectory_cells == [caster.grid_cell, endpoint], "Real hover trajectory uses shared full-range endpoint")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280, 720)
		await process_frame
		await process_frame
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png(DIRECTORY + "/piercing_preview.png")
	battle.shutdown_battle()
	battle.free()
	await process_frame
