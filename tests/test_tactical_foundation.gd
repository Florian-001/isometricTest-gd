@tool
extends McpTestSuite

const GridPathfinderScript = preload("res://scripts/grid_pathfinder.gd")
const IsometricGridScript = preload("res://scripts/isometric_grid.gd")
const CharacterDefinitionScript = preload("res://scripts/unit_definition.gd")
const TacticalCharacterScript = preload("res://scripts/initiative_actor.gd")
const TurnManagerScript = preload("res://scripts/initiative_turn_manager.gd")
const EnemyMovementPlannerScript = preload("res://scripts/enemy_turn_planner.gd")
const TurnOrderBarScene = preload("res://scenes/turn_order_bar.tscn")
const AbilityDefinitionScript = preload("res://scripts/ability_definition.gd")
const DamageEffectScript = preload("res://scripts/damage_effect_definition.gd")
const HealEffectScript = preload("res://scripts/heal_effect_definition.gd")
const AbilityTargetingScript = preload("res://scripts/ability_targeting.gd")
const AbilityBarScene = preload("res://scenes/ability_bar.tscn")
const GridLineOfSightScript = preload("res://scripts/grid_line_of_sight.gd")
const TacticalWallScript = preload("res://scripts/tactical_wall.gd")
const WallPainterPluginScript = preload("res://addons/wall_painter/wall_painter_plugin.gd")
const ProjectileDeliveryScript = preload("res://scripts/projectile_delivery.gd")
const AbilityExecutorScript = preload("res://scripts/ability_executor.gd")
const MeleeDeliveryScript = preload("res://scripts/melee_delivery.gd")


func suite_name() -> String:
	return "tactical_foundation"


func test_grid_coordinates_and_bounds() -> void:
	var grid = track(IsometricGridScript.new())
	grid.grid_size = Vector2i(8, 6)
	grid.cell_size = Vector2(96.0, 48.0)
	for y in range(grid.grid_size.y):
		for x in range(grid.grid_size.x):
			var cell := Vector2i(x, y)
			assert_eq(grid.world_to_grid(grid.grid_to_world(cell)), cell, "grid/world round trip")
	assert_true(grid.is_in_bounds(Vector2i(7, 5)), "last configured cell should be in bounds")
	assert_false(grid.is_in_bounds(Vector2i(8, 5)), "cell beyond width should be out of bounds")


func test_path_costs_and_budget_boundaries() -> void:
	var pathfinder = GridPathfinderScript.new(Vector2i(5, 5))
	var orthogonal_path: Array[Vector2i] = pathfinder.find_path(Vector2i.ZERO, Vector2i(2, 0))
	var diagonal_path: Array[Vector2i] = pathfinder.find_path(Vector2i.ZERO, Vector2i(2, 2))
	assert_true(is_equal_approx(pathfinder.get_path_cost(orthogonal_path), 2.0), "orthogonal steps should cost 1")
	assert_true(is_equal_approx(pathfinder.get_path_cost(diagonal_path), 2.828), "diagonal steps should cost 1.414")

	var below_diagonal := pathfinder.get_reachable(Vector2i.ZERO, 1.413)
	var exact_diagonal := pathfinder.get_reachable(Vector2i.ZERO, 1.414)
	assert_false(below_diagonal.has(Vector2i.ONE), "diagonal should be excluded below its cost")
	assert_true(exact_diagonal.has(Vector2i.ONE), "diagonal should be included at its exact cost")
	assert_true(pathfinder.find_path(Vector2i.ZERO, Vector2i(2, 2), 2.827).is_empty(), "over-budget path should be rejected")


func test_occupied_cells_and_corner_cutting() -> void:
	var pathfinder = GridPathfinderScript.new(Vector2i(5, 5))
	var occupied := {Vector2i(2, 2): true}
	assert_true(pathfinder.find_path(Vector2i.ZERO, Vector2i(2, 2), INF, occupied).is_empty(), "occupied destination should be rejected")

	var tight_corner := {
		Vector2i(1, 0): true,
		Vector2i(0, 1): true,
	}
	assert_true(pathfinder.find_path(Vector2i.ZERO, Vector2i.ONE, 1.414, tight_corner).is_empty(), "diagonal corner cutting should be rejected")


func test_character_health_and_defeat_signal() -> void:
	var definition = CharacterDefinitionScript.new()
	definition.max_health = 100
	var character = track(TacticalCharacterScript.new())
	character.definition = definition
	character._ready()

	assert_eq(character.current_health, 100, "health should initialize from the definition")
	var defeated_calls := [0]
	character.defeated.connect(func(_character): defeated_calls[0] += 1)
	character.apply_damage(35)
	assert_eq(character.current_health, 65, "damage should reduce current health")
	character.heal(500)
	assert_eq(character.current_health, 100, "healing should clamp to maximum health")
	character.apply_damage(150)
	assert_eq(character.current_health, 0, "damage should clamp to zero")
	assert_eq(defeated_calls[0], 1, "defeat should emit once on reaching zero")
	character.apply_damage(1)
	assert_eq(defeated_calls[0], 1, "defeat should not repeat while already defeated")


func test_per_unit_stat_overrides() -> void:
	var definition = CharacterDefinitionScript.new()
	definition.max_health = 100
	definition.movement_range = 6.0
	definition.speed = 9
	var character = track(TacticalCharacterScript.new())
	character.definition = definition
	character.max_health_override = 140
	character.movement_range = 7.5
	character.speed_override = 14
	character._ready()

	assert_eq(character.get_max_health(), 140, "unit health override should replace the template value")
	assert_eq(character.current_health, 140, "current health should initialize from the unit override")
	assert_true(is_equal_approx(character.get_movement_range(), 8.5), "Speed should modify the overridden base movement")
	assert_eq(character.get_initiative(), 14, "unit Speed override should determine initiative")

	character.max_health_override = 0
	character.movement_range = -1.0
	character.speed_override = -1
	assert_eq(character.get_max_health(), 100, "zero health override should fall back to the template")
	assert_true(is_equal_approx(character.get_movement_range(), 5.75), "inherited Speed should modify inherited base movement")
	assert_eq(character.get_initiative(), 9, "negative Speed override should fall back to the template")


func test_split_movement_budget_and_reset() -> void:
	var character := _make_unit(true, Vector2i.ZERO, 8.0)
	character.reset_movement()
	assert_true(is_equal_approx(character.remaining_movement, 8.0), "movement should reset to the configured range")
	assert_true(character.spend_movement(3.0), "an affordable first move should be accepted")
	assert_true(is_equal_approx(character.remaining_movement, 5.0), "unused movement should remain available")
	assert_true(character.spend_movement(1.414), "a diagonal move should spend its fractional cost")
	assert_true(is_equal_approx(character.remaining_movement, 3.586), "fractional movement should be retained")
	assert_false(character.spend_movement(4.0), "movement beyond the remaining budget should be rejected")
	assert_true(is_equal_approx(character.remaining_movement, 3.586), "rejected movement should not change the budget")
	assert_true(character.spend_movement(3.586), "the exact remaining budget should be spendable")
	assert_true(is_zero_approx(character.remaining_movement), "movement should clamp to zero")


func test_initiative_sorting_and_scene_order_ties() -> void:
	var friend_a := _make_unit(true, Vector2i(1, 1), 6.0, 12)
	var enemy := _make_unit(false, Vector2i(4, 4), 5.0, 10)
	var friend_b := _make_unit(true, Vector2i(2, 2), 3.0, 8)
	friend_a.name = "FriendA"
	enemy.name = "Enemy"
	friend_b.name = "FriendB"
	var units: Array[TacticalCharacter] = [friend_a, friend_b, enemy]
	var manager = track(TurnManagerScript.new())
	manager.start_combat(units)

	assert_eq(manager.turn_order, [friend_a, enemy, friend_b], "units should sort by descending initiative")
	assert_eq(manager.current_unit, friend_a, "the highest-initiative unit should begin combat")
	assert_eq(manager.round_number, 1, "combat should begin on round one")

	friend_a.speed_override = 10
	friend_b.speed_override = 10
	manager.start_combat(units)
	assert_eq(manager.turn_order, [friend_a, friend_b, enemy], "initiative ties should retain the supplied scene order")


func test_individual_turn_sequence_and_movement_reset() -> void:
	var friend_a := _make_unit(true, Vector2i(1, 1), 6.0, 12)
	var enemy := _make_unit(false, Vector2i(4, 4), 5.0, 10)
	var friend_b := _make_unit(true, Vector2i(2, 2), 3.0, 8)
	var units: Array[TacticalCharacter] = [friend_a, friend_b, enemy]
	var manager = track(TurnManagerScript.new())
	manager.start_combat(units)

	assert_true(is_equal_approx(friend_a.remaining_movement, 6.0), "only the first active unit should reset at combat start")
	assert_true(is_zero_approx(enemy.remaining_movement), "upcoming enemies should not reset early")
	assert_true(is_zero_approx(friend_b.remaining_movement), "upcoming friendlies should not reset early")
	friend_a.spend_movement(4.0)
	manager.end_current_turn()
	assert_eq(manager.current_unit, enemy, "the enemy should follow FriendA")
	assert_true(is_equal_approx(friend_a.remaining_movement, 2.0), "ending a turn should preserve that unit's spent budget")
	assert_true(is_equal_approx(enemy.remaining_movement, 5.0), "the enemy should reset when its own turn begins")
	manager.end_current_turn()
	assert_eq(manager.current_unit, friend_b, "FriendB should follow the enemy")
	assert_true(is_equal_approx(friend_b.remaining_movement, 3.0), "FriendB should use its Inspector-configured movement range")
	manager.end_current_turn()
	assert_eq(manager.current_unit, friend_a, "the order should rotate back to FriendA")
	assert_eq(manager.round_number, 2, "the round should increment only after every unit acts")
	assert_true(is_equal_approx(friend_a.remaining_movement, 6.0), "FriendA should reset at the start of its next turn")


func test_rotating_order_and_dead_unit_skip() -> void:
	var friend_a := _make_unit(true, Vector2i(1, 1), 6.0, 12)
	var enemy := _make_unit(false, Vector2i(4, 4), 5.0, 10)
	var friend_b := _make_unit(true, Vector2i(2, 2), 3.0, 8)
	var units: Array[TacticalCharacter] = [friend_a, friend_b, enemy]
	var manager = track(TurnManagerScript.new())
	manager.start_combat(units)
	manager.end_current_turn()
	assert_eq(manager.get_rotating_order(), [enemy, friend_b, friend_a], "the active unit should be first in the rotating queue")

	friend_b.apply_damage(100)
	manager.notify_unit_state_changed()
	assert_eq(manager.get_rotating_order(), [enemy, friend_a], "defeated units should disappear from the visible queue")
	manager.end_current_turn()
	assert_eq(manager.current_unit, friend_a, "turn advancement should skip defeated units")
	assert_eq(manager.round_number, 2, "skipping a defeated final slot should still wrap the round")


func test_turn_order_bar_uses_fallback_and_portrait_visuals() -> void:
	var friend_a := _make_unit(true, Vector2i(1, 1), 6.0, 12)
	var enemy := _make_unit(false, Vector2i(4, 4), 5.0, 10)
	friend_a.name = "FriendA"
	enemy.name = "Enemy"
	var order: Array[TacticalCharacter] = [friend_a, enemy]
	var bar = track(TurnOrderBarScene.instantiate())
	bar.rebuild(order, friend_a)
	var entries: HBoxContainer = bar.get_node("Margin/HBox")

	assert_eq(entries.get_child_count(), 2, "the queue should create one square per living unit")
	assert_eq(entries.get_child(0).get_meta("unit"), friend_a, "the current unit should occupy the first square")
	assert_true(entries.get_child(0).get_meta("is_current"), "the current square should be marked active")
	assert_false(entries.get_child(0).get_meta("uses_portrait"), "units without portraits should use the initial fallback")

	enemy.definition.portrait = GradientTexture1D.new()
	bar.rebuild(order, friend_a)
	assert_true(entries.get_child(1).get_meta("uses_portrait"), "a template portrait should replace the fallback visual")


func test_ability_resources_and_sample_assignment() -> void:
	var ability = AbilityDefinitionScript.new()
	ability.area_of_effect = 4
	assert_eq(ability.area_of_effect, 5, "even area sizes should normalize to the next odd span")
	assert_eq(ability.get_effective_area_span(), 5, "normalized area span should be exposed to targeting")

	var friendly_definition = load("res://resources/friendly_spellcaster.tres") as CharacterDefinition
	assert_eq(friendly_definition.abilities.size(), 5, "the friendly template should expose five sample abilities")
	var names: Array[String] = []
	for sample in friendly_definition.abilities:
		names.append(sample.display_name)
	assert_eq(names, ["Fireball", "Arrow", "Heal", "Beam", "Strike"], "sample abilities should retain their configured order")
	assert_eq(friendly_definition.abilities[0].effects[0].amount, 30, "Fireball damage should be editable through its effect resource")
	assert_eq(friendly_definition.abilities[4].effects[0].amount, 30, "Strike damage should be editable through its effect resource")


func test_unit_ability_loadout_override() -> void:
	var unit := _make_unit(true, Vector2i.ZERO, 6.0)
	var template_ability = AbilityDefinitionScript.new()
	template_ability.display_name = "Template Ability"
	var override_ability = AbilityDefinitionScript.new()
	override_ability.display_name = "Unit Ability"
	unit.definition.abilities = [template_ability]

	assert_eq(unit.get_abilities(), [template_ability], "units should inherit their editable template loadout by default")
	unit.override_template_abilities = true
	unit.ability_overrides = [override_ability]
	assert_eq(unit.get_abilities(), [override_ability], "Inspector overrides should replace the template loadout for one unit")
	unit.ability_overrides.clear()
	assert_true(unit.get_abilities().is_empty(), "an enabled empty override should allow a unit to have no abilities")


func test_ability_weighted_range_flags_and_projectile_blockers() -> void:
	var caster := _make_unit(true, Vector2i.ZERO, 6.0)
	var diagonal_enemy := _make_unit(false, Vector2i.ONE, 5.0)
	var friendly := _make_unit(true, Vector2i(2, 0), 5.0)
	var blocker := _make_unit(true, Vector2i(1, 0), 5.0)
	var units: Array[TacticalCharacter] = [caster, diagonal_enemy, friendly, blocker]
	var targeting = AbilityTargetingScript.new(Vector2i(8, 8))
	var ability = AbilityDefinitionScript.new()
	ability.range = 1.414
	ability.target_flags = AbilityDefinition.TargetFlags.ENEMY

	assert_true(is_equal_approx(targeting.get_weighted_distance(Vector2i.ZERO, Vector2i(2, 2)), 2.828), "ability range should use 1.414 diagonals")
	var visible_range := targeting.get_cells_in_range(caster, ability)
	assert_true(visible_range.has(Vector2i(0, 1)), "unit-targeted abilities should still expose empty cells in their cast range")
	assert_true(visible_range.has(blocker.grid_cell), "units should not hide cells from the visible cast range")
	assert_true(targeting.is_valid_primary_target(caster, diagonal_enemy.grid_cell, ability, units), "an enemy at the exact diagonal boundary should be targetable")
	ability.range = 1.413
	assert_false(targeting.is_valid_primary_target(caster, diagonal_enemy.grid_cell, ability, units), "a target beyond the fractional range should be rejected")
	ability.range = 5.0
	assert_false(targeting.is_valid_primary_target(caster, friendly.grid_cell, ability, units), "enemy-only abilities should reject friendly primary targets")

	ability.target_flags = AbilityDefinition.TargetFlags.CELL | AbilityDefinition.TargetFlags.ENEMY
	assert_true(targeting.is_valid_primary_target(caster, Vector2i(3, 0), ability, units), "cell targeting should ignore an intervening occupied cell")


func test_grid_separates_cast_range_from_valid_targets() -> void:
	var grid = track(IsometricGridScript.new())
	grid.grid_size = Vector2i(6, 6)
	var range_cells := {
		Vector2i(1, 1): 0.0,
		Vector2i(2, 1): 1.0,
		Vector2i(1, 2): 1.0,
	}
	var valid_targets := {Vector2i(2, 1): 1.0}
	grid.show_ability_targets(Vector2i(1, 1), range_cells, valid_targets)

	assert_eq(grid._ability_range_cells.size(), 3, "the overlay should retain every cell within cast range")
	assert_eq(grid._ability_target_cells.size(), 1, "valid click targets should remain a separate highlighted subset")


func test_ability_shapes_and_grid_clipping() -> void:
	var targeting = AbilityTargetingScript.new(Vector2i(7, 7))
	var ability = AbilityDefinitionScript.new()
	ability.area_of_effect = 3
	var center := Vector2i(3, 3)

	ability.shape = AbilityDefinition.Shape.SQUARE
	assert_eq(targeting.get_affected_cells(Vector2i.ZERO, center, ability).size(), 9, "a square span of three should cover 3x3 cells")
	assert_eq(targeting.get_affected_cells(Vector2i.ZERO, Vector2i.ZERO, ability).size(), 4, "centered shapes should clip at grid edges")

	ability.shape = AbilityDefinition.Shape.CIRCLE
	assert_eq(targeting.get_affected_cells(Vector2i.ZERO, center, ability).size(), 5, "a circle span of three should cover the center and four orthogonal neighbors")

	ability.area_of_effect = 5
	ability.shape = AbilityDefinition.Shape.PLUS
	assert_eq(targeting.get_affected_cells(Vector2i.ZERO, center, ability).size(), 9, "a plus span of five should have two-cell arms")
	ability.shape = AbilityDefinition.Shape.LINE_VERTICAL
	var vertical := targeting.get_affected_cells(Vector2i.ZERO, center, ability)
	assert_eq(vertical.size(), 5, "vertical lines should use the configured span")
	assert_true(vertical.all(func(cell): return cell.x == center.x), "vertical line cells should share their x coordinate")
	ability.shape = AbilityDefinition.Shape.LINE_HORIZONTAL
	var horizontal := targeting.get_affected_cells(Vector2i.ZERO, center, ability)
	assert_eq(horizontal.size(), 5, "horizontal lines should use the configured span")
	assert_true(horizontal.all(func(cell): return cell.y == center.y), "horizontal line cells should share their y coordinate")

	ability.shape = AbilityDefinition.Shape.LINE_FROM_CASTER
	ability.area_of_effect = 1
	var narrow_beam := targeting.get_affected_cells(Vector2i(1, 3), Vector2i(5, 3), ability)
	assert_eq(narrow_beam, [Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3)], "a narrow beam should run from caster through the selected cell")
	ability.area_of_effect = 3
	var wide_beam := targeting.get_affected_cells(Vector2i(1, 3), Vector2i(5, 3), ability)
	assert_true(wide_beam.has(Vector2i(3, 2)) and wide_beam.has(Vector2i(3, 4)), "beam AoE should control perpendicular width")


func test_all_projectile_abilities_share_delivery_geometry() -> void:
	var fireball := load("res://resources/abilities/fireball.tres") as AbilityDefinition
	var arrow := load("res://resources/abilities/arrow.tres") as AbilityDefinition
	var delivery = track(ProjectileDeliveryScript.new()) as ProjectileDelivery
	var caster_cell := Vector2i(2, 3)
	var target_cell := Vector2i(8, 6)
	var walls := {Vector2i(5, 5): true}

	assert_eq(fireball.delivery_type, AbilityDefinition.DeliveryType.PROJECTILE, "Fireball should use shared projectile delivery")
	assert_eq(arrow.delivery_type, AbilityDefinition.DeliveryType.PROJECTILE, "Arrow should use shared projectile delivery")
	var fireball_preview := delivery.get_preview(caster_cell, target_cell, walls)
	var arrow_preview := delivery.get_preview(caster_cell, target_cell, walls)
	assert_eq(arrow_preview, fireball_preview, "Arrow and Fireball should use identical projectile geometry")
	assert_eq(fireball_preview, [caster_cell, Vector2i(5, 5)], "blocked projectile previews should clip at the first wall")
	assert_false(delivery.has_clear_trajectory(caster_cell, target_cell, walls), "the shared delivery should reject a wall obstruction")
	assert_true(delivery.has_clear_trajectory(caster_cell, target_cell, {}), "the shared delivery should accept a clear straight trajectory")


func test_projectile_target_filters_remain_ability_specific() -> void:
	var caster := _make_unit(true, Vector2i.ZERO, 6.0)
	var enemy := _make_unit(false, Vector2i(3, 0), 6.0)
	var units: Array[TacticalCharacter] = [caster, enemy]
	var targeting = AbilityTargetingScript.new(Vector2i(8, 8))
	var fireball := load("res://resources/abilities/fireball.tres") as AbilityDefinition
	var enemy_only_projectile = AbilityDefinitionScript.new()
	enemy_only_projectile.delivery_type = AbilityDefinition.DeliveryType.PROJECTILE
	enemy_only_projectile.range = 5.0
	enemy_only_projectile.target_flags = AbilityDefinition.TargetFlags.ENEMY

	assert_true(targeting.is_valid_primary_target(caster, Vector2i(2, 0), fireball, units), "Fireball should retain visible cell targeting")
	assert_false(targeting.is_valid_primary_target(caster, Vector2i(2, 0), enemy_only_projectile, units), "enemy-only projectiles should reject empty cells")
	assert_true(targeting.is_valid_primary_target(caster, enemy.grid_cell, enemy_only_projectile, units), "enemy-only projectiles should accept a visible enemy")


func test_blocked_projectile_does_not_spend_action() -> void:
	var caster := _make_unit(true, Vector2i.ZERO, 6.0)
	var enemy := _make_unit(false, Vector2i(3, 0), 6.0)
	var units: Array[TacticalCharacter] = [caster, enemy]
	var grid = track(IsometricGridScript.new()) as IsometricGrid
	grid.grid_size = Vector2i(8, 8)
	var targeting = AbilityTargetingScript.new(grid.grid_size)
	var executor = track(AbilityExecutorScript.new()) as AbilityExecutor
	var blocked_projectile = AbilityDefinitionScript.new()
	blocked_projectile.delivery_type = AbilityDefinition.DeliveryType.PROJECTILE
	blocked_projectile.range = 5.0
	blocked_projectile.target_flags = AbilityDefinition.TargetFlags.ENEMY
	caster.reset_ability_action()

	var can_execute := executor.can_execute(
		caster,
		blocked_projectile,
		enemy.grid_cell,
		units,
		grid,
		targeting,
		{Vector2i(2, 0): true}
	)
	assert_false(can_execute, "a wall-blocked projectile should be rejected before launch")
	assert_true(caster.ability_available, "a rejected projectile should not spend the caster's action")


func test_future_projectile_uses_shared_delivery_without_special_case() -> void:
	var future_projectile = AbilityDefinitionScript.new()
	future_projectile.display_name = "Future Projectile"
	future_projectile.delivery_type = AbilityDefinition.DeliveryType.PROJECTILE
	future_projectile.projectile_speed = 900.0
	future_projectile.placeholder_color = Color.CYAN
	var delivery = track(ProjectileDeliveryScript.new()) as ProjectileDelivery

	assert_eq(
		delivery.get_preview(Vector2i(1, 1), Vector2i(4, 2), {}),
		[Vector2i(1, 1), Vector2i(4, 2)],
		"future projectile abilities should receive the same straight preview without controller changes"
	)
	assert_true(delivery.has_clear_trajectory(Vector2i(1, 1), Vector2i(4, 2), {}), "future projectiles should use the shared clear-trajectory check")


func test_melee_delivery_values_targeting_and_corner_walls() -> void:
	assert_eq(AbilityDefinition.DeliveryType.PROJECTILE, 0, "Projectile serialization value should remain stable")
	assert_eq(AbilityDefinition.DeliveryType.CAST_ON_TARGET, 1, "Cast serialization value should remain stable")
	assert_eq(AbilityDefinition.DeliveryType.MELEE, 2, "Melee should append a new serialization value")

	var strike := load("res://resources/abilities/strike.tres") as AbilityDefinition
	assert_eq(strike.delivery_type, AbilityDefinition.DeliveryType.MELEE, "Strike should use melee delivery")
	assert_true(is_equal_approx(strike.range, 1.414), "Strike should reach all adjacent cells")
	assert_true(strike.has_target_flag(AbilityDefinition.TargetFlags.ENEMY), "Strike should retain enemy targeting")
	assert_eq(strike.effects[0].amount, 30, "Strike should deal its editable 30 damage")

	var caster := _make_unit(true, Vector2i(2, 2), 6.0)
	var orthogonal_enemy := _make_unit(false, Vector2i(3, 2), 6.0)
	var diagonal_enemy := _make_unit(false, Vector2i(3, 3), 6.0)
	var distant_enemy := _make_unit(false, Vector2i(4, 2), 6.0)
	var friendly := _make_unit(true, Vector2i(2, 3), 6.0)
	var units: Array[TacticalCharacter] = [caster, orthogonal_enemy, diagonal_enemy, distant_enemy, friendly]
	var targeting = AbilityTargetingScript.new(Vector2i(8, 8))

	assert_true(targeting.is_valid_primary_target(caster, orthogonal_enemy.grid_cell, strike, units), "Strike should target an orthogonally adjacent enemy")
	assert_true(targeting.is_valid_primary_target(caster, diagonal_enemy.grid_cell, strike, units), "Strike should target an exact-cost diagonal enemy")
	assert_false(targeting.is_valid_primary_target(caster, distant_enemy.grid_cell, strike, units), "Strike should reject enemies beyond adjacent range")
	var allows_cells := strike.has_target_flag(AbilityDefinition.TargetFlags.CELL)
	assert_eq(targeting.is_valid_primary_target(caster, friendly.grid_cell, strike, units), allows_cells, "CELL-enabled melee can select an occupied cell without affecting an unconfigured faction")
	assert_eq(targeting.is_valid_primary_target(caster, Vector2i(1, 2), strike, units), allows_cells, "empty-cell validity should follow the editable CELL flag")
	assert_false(
		targeting.is_valid_primary_target(caster, diagonal_enemy.grid_cell, strike, units, {Vector2i(3, 2): true}),
		"a side wall should block a diagonal melee attack"
	)


func test_melee_preflight_rejects_invalid_attacks_without_spending_action() -> void:
	var caster := _make_unit(true, Vector2i(2, 2), 6.0)
	var enemy := _make_unit(false, Vector2i(3, 3), 6.0)
	var units: Array[TacticalCharacter] = [caster, enemy]
	var grid = track(IsometricGridScript.new()) as IsometricGrid
	grid.grid_size = Vector2i(8, 8)
	var targeting = AbilityTargetingScript.new(grid.grid_size)
	var executor = track(AbilityExecutorScript.new()) as AbilityExecutor
	var strike := load("res://resources/abilities/strike.tres") as AbilityDefinition
	caster.reset_ability_action()

	assert_true(MeleeDeliveryScript.can_reach(caster.grid_cell, enemy.grid_cell, {}), "shared melee delivery should accept an open diagonal")
	assert_false(MeleeDeliveryScript.can_reach(caster.grid_cell, enemy.grid_cell, {Vector2i(3, 2): true}), "shared melee delivery should reject a diagonal wall corner")
	assert_false(
		executor.can_execute(caster, strike, enemy.grid_cell, units, grid, targeting, {Vector2i(3, 2): true}),
		"the executor should reject blocked melee before starting"
	)
	assert_true(caster.ability_available, "an invalid melee attack should not spend the ability action")


func test_ability_recipient_filtering_and_mass_heal_shape() -> void:
	var caster := _make_unit(true, Vector2i(3, 3), 6.0)
	var friendly := _make_unit(true, Vector2i(4, 4), 6.0)
	var enemy := _make_unit(false, Vector2i(4, 3), 6.0)
	var units: Array[TacticalCharacter] = [caster, friendly, enemy]
	var targeting = AbilityTargetingScript.new(Vector2i(8, 8))
	var ability = AbilityDefinitionScript.new()
	ability.range = 0.0
	ability.area_of_effect = 5
	ability.shape = AbilityDefinition.Shape.SQUARE
	ability.target_flags = AbilityDefinition.TargetFlags.SELF | AbilityDefinition.TargetFlags.FRIEND
	var recipients := targeting.get_affected_units(caster, caster.grid_cell, ability, units)

	assert_true(recipients.has(caster), "SELF should include the caster in an area effect")
	assert_true(recipients.has(friendly), "FRIEND should include allied units in the area")
	assert_false(recipients.has(enemy), "unconfigured factions should be filtered out of the area")
	assert_true(targeting.is_valid_primary_target(caster, caster.grid_cell, ability, units), "SELF should permit selecting the caster")


func test_damage_heal_effects_and_no_revive() -> void:
	var caster := _make_unit(true, Vector2i.ZERO, 6.0)
	var target := _make_unit(false, Vector2i.ONE, 6.0)
	var damage = DamageEffectScript.new()
	var healing = HealEffectScript.new()
	damage.amount = 30
	healing.amount = 10
	damage.apply(caster, target)
	healing.apply(caster, target)
	assert_eq(target.current_health, 80, "multiple effects should apply sequentially")
	target.apply_damage(1000)
	healing.apply(caster, target)
	assert_eq(target.current_health, 0, "ability healing should not revive defeated units")


func test_ability_action_resets_only_on_active_turn() -> void:
	var friend_a := _make_unit(true, Vector2i(1, 1), 6.0, 12)
	var enemy := _make_unit(false, Vector2i(4, 4), 5.0, 10)
	var friend_b := _make_unit(true, Vector2i(2, 2), 3.0, 8)
	var units: Array[TacticalCharacter] = [friend_a, friend_b, enemy]
	var manager = track(TurnManagerScript.new())
	manager.start_combat(units)

	assert_true(friend_a.ability_available, "the active unit should receive its ability action")
	assert_false(enemy.ability_available, "upcoming enemies should not reset early")
	assert_false(friend_b.ability_available, "upcoming friendlies should not reset early")
	assert_true(friend_a.spend_ability_action(), "the first cast should consume the action")
	assert_false(friend_a.spend_ability_action(), "a second cast in the same turn should be rejected")
	friend_a.spend_movement(2.0)
	assert_true(is_equal_approx(friend_a.remaining_movement, 4.0), "casting should not consume movement")
	manager.end_current_turn()
	assert_true(enemy.ability_available, "the next unit should reset its own ability action")
	manager.end_current_turn()
	manager.end_current_turn()
	assert_true(friend_a.ability_available, "the ability action should reset on the unit's next turn")


func test_ability_bar_populates_and_disables_after_cast() -> void:
	var friendly_definition = load("res://resources/friendly_spellcaster.tres") as CharacterDefinition
	var unit = track(TacticalCharacterScript.new()) as TacticalCharacter
	unit.definition = friendly_definition
	unit._ready()
	unit.reset_ability_action()
	var bar = track(AbilityBarScene.instantiate())
	bar.rebuild(unit, true)
	var entries: HBoxContainer = bar.get_node("Margin/HBox")
	assert_eq(entries.get_child_count(), 5, "the ability bar should create one button per configured ability")
	assert_true(entries.get_child(0).text.contains("32 DMG"), "damage buttons should show their caster-scaled total damage")
	assert_true(entries.get_child(1).text.contains("27 DMG"), "Dexterity-scaled damage should show on its button")
	assert_false(entries.get_child(2).text.contains("DMG"), "non-damaging ability buttons should remain uncluttered")
	assert_false(entries.get_child(0).disabled, "ability buttons should be enabled while the action is available")
	unit.spend_ability_action()
	bar.rebuild(unit, true)
	assert_true(entries.get_child(0).disabled, "ability buttons should disable after the action is spent")


func test_enemy_planner_approaches_without_overspending() -> void:
	var enemy := _make_unit(false, Vector2i(0, 0), 2.0)
	var friendly := _make_unit(true, Vector2i(4, 0), 6.0)
	enemy.reset_movement()
	var friendlies: Array[TacticalCharacter] = [friendly]
	var units: Array[TacticalCharacter] = [enemy, friendly]
	var pathfinder = GridPathfinderScript.new(Vector2i(8, 8))
	var planner = EnemyMovementPlannerScript.new()
	var path: Array[Vector2i] = planner.choose_path(enemy, friendlies, units, pathfinder)

	assert_eq(path[0], Vector2i(0, 0), "enemy path should begin at its current cell")
	assert_eq(path[path.size() - 1], Vector2i(2, 0), "enemy should use its budget moving toward an adjacent target cell")
	assert_true(pathfinder.get_path_cost(path) <= enemy.remaining_movement, "enemy path should remain within its movement budget")


func test_enemy_planner_respects_blocked_corner() -> void:
	var enemy := _make_unit(false, Vector2i(0, 0), 5.0)
	var friendly := _make_unit(true, Vector2i(2, 2), 6.0)
	var blocker_a := _make_unit(false, Vector2i(1, 0), 0.0)
	var blocker_b := _make_unit(false, Vector2i(0, 1), 0.0)
	enemy.reset_movement()
	var friendlies: Array[TacticalCharacter] = [friendly]
	var units: Array[TacticalCharacter] = [enemy, friendly, blocker_a, blocker_b]
	var pathfinder = GridPathfinderScript.new(Vector2i(5, 5))
	var planner = EnemyMovementPlannerScript.new()

	assert_true(planner.choose_path(enemy, friendlies, units, pathfinder).is_empty(), "enemy should skip when units block every legal exit")


func test_enemy_planner_returns_typed_empty_path_when_adjacent() -> void:
	var enemy := _make_unit(false, Vector2i(1, 1), 5.0)
	var friendly := _make_unit(true, Vector2i(2, 1), 6.0)
	enemy.reset_movement()
	var friendlies: Array[TacticalCharacter] = [friendly]
	var units: Array[TacticalCharacter] = [enemy, friendly]
	var pathfinder = GridPathfinderScript.new(Vector2i(5, 5))
	var planner = EnemyMovementPlannerScript.new()
	var path: Array[Vector2i] = planner.choose_path(enemy, friendlies, units, pathfinder)

	assert_true(path.is_empty(), "an enemy already adjacent to a friendly should return a typed no-move path")


func test_wall_cells_block_movement_and_enemy_routes() -> void:
	var pathfinder = GridPathfinderScript.new(Vector2i(6, 6))
	var walls := {
		Vector2i(1, 0): true,
		Vector2i(1, 1): true,
	}
	var path := pathfinder.find_path(Vector2i.ZERO, Vector2i(3, 0), INF, walls)
	assert_false(path.is_empty(), "movement should find a route around a finite wall")
	assert_false(path.has(Vector2i(1, 0)) or path.has(Vector2i(1, 1)), "movement paths must never enter a wall")

	var enemy := _make_unit(false, Vector2i.ZERO, 3.0)
	var friendly := _make_unit(true, Vector2i(4, 0), 6.0)
	enemy.reset_movement()
	var friendlies: Array[TacticalCharacter] = [friendly]
	var units: Array[TacticalCharacter] = [enemy, friendly]
	var planner = EnemyMovementPlannerScript.new()
	var enemy_path: Array[Vector2i] = planner.choose_path(enemy, friendlies, units, pathfinder, walls)
	assert_false(enemy_path.has(Vector2i(1, 0)) or enemy_path.has(Vector2i(1, 1)), "enemy planning should merge static walls with unit blockers")


func test_center_crossing_line_of_sight_and_corner_grazing() -> void:
	var sight = GridLineOfSightScript.new()
	var direct_wall := {Vector2i(1, 1): true}
	assert_eq(
		sight.get_line_cells(Vector2i.ZERO, Vector2i(2, 2)),
		[Vector2i.ZERO, Vector2i(1, 1), Vector2i(2, 2)],
		"line of sight should rasterize cell centers"
	)
	assert_false(sight.has_line_of_sight(Vector2i.ZERO, Vector2i(2, 2), direct_wall), "a crossed wall should block sight")
	assert_eq(sight.get_first_blocking_wall(Vector2i.ZERO, Vector2i(2, 2), direct_wall), Vector2i(1, 1), "the first obstruction should be reported")
	assert_true(
		sight.has_line_of_sight(Vector2i.ZERO, Vector2i(2, 1), {Vector2i(1, 0): true}),
		"a wall touched only at a corner should not block center-crossing sight"
	)


func test_ability_targets_require_clear_sight_and_reject_walls() -> void:
	var caster := _make_unit(true, Vector2i.ZERO, 6.0)
	var enemy := _make_unit(false, Vector2i(3, 0), 6.0)
	var unit_blocker := _make_unit(true, Vector2i(1, 0), 6.0)
	var units: Array[TacticalCharacter] = [caster, enemy, unit_blocker]
	var targeting = AbilityTargetingScript.new(Vector2i(8, 8))
	var ability = AbilityDefinitionScript.new()
	ability.range = 5.0
	ability.target_flags = AbilityDefinition.TargetFlags.CELL | AbilityDefinition.TargetFlags.ENEMY

	assert_true(targeting.is_valid_primary_target(caster, enemy.grid_cell, ability, units), "units should not block ability sight")
	var walls := {Vector2i(2, 0): true}
	assert_false(targeting.is_valid_primary_target(caster, enemy.grid_cell, ability, units, walls), "a target behind a wall should be invalid")
	assert_false(targeting.is_valid_primary_target(caster, Vector2i(2, 0), ability, units, walls), "a wall cell should never be a valid destination")
	assert_true(targeting.get_cells_in_range(caster, ability).has(enemy.grid_cell), "occluded cells should remain present in the raw range overlay")
	var projectile_delivery = track(ProjectileDeliveryScript.new()) as ProjectileDelivery
	assert_eq(projectile_delivery.get_preview(caster.grid_cell, enemy.grid_cell, walls), [caster.grid_cell, Vector2i(2, 0)], "an invalid projectile preview should clip at the first wall")


func test_walls_block_area_effects_and_beams() -> void:
	var targeting = AbilityTargetingScript.new(Vector2i(8, 8))
	var ability = AbilityDefinitionScript.new()
	ability.area_of_effect = 5
	ability.shape = AbilityDefinition.Shape.SQUARE
	var walls := {Vector2i(4, 3): true}
	var explosion := targeting.get_affected_cells(Vector2i.ZERO, Vector2i(3, 3), ability, walls)
	assert_true(explosion.has(Vector2i(3, 4)), "cells with clear sight from an impact should remain affected")
	assert_false(explosion.has(Vector2i(4, 3)), "wall cells should not be affected")
	assert_false(explosion.has(Vector2i(5, 3)), "an explosion should not propagate through a wall")

	ability.shape = AbilityDefinition.Shape.LINE_FROM_CASTER
	ability.area_of_effect = 1
	var beam := targeting.get_affected_cells(Vector2i(1, 3), Vector2i(6, 3), ability, walls)
	assert_true(beam.has(Vector2i(3, 3)), "a beam should include cells before a wall")
	assert_false(beam.has(Vector2i(4, 3)), "a beam should exclude the wall itself")
	assert_false(beam.has(Vector2i(5, 3)), "a beam should not continue through a wall")


func test_sample_scene_contains_editable_wall_barrier() -> void:
	var scene := load("res://main.tscn") as PackedScene
	var root: Node = track(scene.instantiate())
	var walls: Node = root.get_node("Walls")
	var cells: Array[Vector2i] = []
	for child in walls.get_children():
		assert_true(child is TacticalWall, "sample wall children should use the reusable TacticalWall type")
		cells.append((child as TacticalWall).grid_cell)
	assert_eq(cells, [Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6)], "the sample should include the planned three-cell barrier")


func _make_unit(friendly: bool, cell: Vector2i, movement: float, speed: int = 10) -> TacticalCharacter:
	var definition = CharacterDefinitionScript.new()
	definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	definition.max_health = 100
	definition.movement_range = movement
	var character = track(TacticalCharacterScript.new()) as TacticalCharacter
	character.definition = definition
	character.movement_range = movement - (float(speed) - 10.0) * 0.25
	character.speed_override = speed
	character.starting_grid_cell = cell
	character._ready()
	return character
