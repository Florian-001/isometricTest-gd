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
const OpportunityAttackSystemScript = preload("res://scripts/opportunity_attack_system.gd")
const AbilityCasterMovementScript = preload("res://scripts/ability_caster_movement.gd")
const StatusCatalogScript = preload("res://addons/tile_painter/status_effect_catalog.gd")
const ItemCatalogScript = preload("res://addons/tile_painter/item_definition_catalog.gd")
const ItemArrayModelScript = preload("res://addons/tile_painter/item_array_editor_model.gd")
const ItemModifierModelScript = preload("res://addons/tile_painter/item_modifier_editor_model.gd")
const AbilityCatalogScript = preload("res://addons/tile_painter/ability_definition_catalog.gd")
const AbilityArrayModelScript = preload("res://addons/tile_painter/ability_array_editor_model.gd")


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
	definition.constitution = 25
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


func test_directional_character_artwork_and_facing() -> void:
	var character = track(TacticalCharacterScript.new()) as TacticalCharacter
	character.facing_left_texture = GradientTexture1D.new()
	character.facing_right_texture = GradientTexture1D.new()
	character.initial_facing = TacticalCharacter.Facing.RIGHT
	character._ready()

	assert_true(character.has_directional_artwork(), "either directional texture should enable character artwork")
	assert_eq(character.current_facing, TacticalCharacter.Facing.RIGHT, "the exported initial facing should initialize presentation")
	character.face_toward_world_position(Vector2(-10.0, 5.0))
	assert_eq(character.current_facing, TacticalCharacter.Facing.LEFT, "a target to screen-left should select the left texture")
	character.face_toward_world_position(Vector2(0.0, 50.0))
	assert_eq(character.current_facing, TacticalCharacter.Facing.LEFT, "purely vertical screen movement should preserve facing")
	character.face_toward_world_position(Vector2(10.0, 5.0))
	assert_eq(character.current_facing, TacticalCharacter.Facing.RIGHT, "a target to screen-right should select the right texture")

	var fallback = track(TacticalCharacterScript.new()) as TacticalCharacter
	assert_false(fallback.has_directional_artwork(), "synthetic units without textures should retain the fallback marker")


func test_character_scenes_assign_game_ready_texture_pairs() -> void:
	var scene_expectations := {
		"res://scenes/friendlies/friend_a.tscn": TacticalCharacter.Facing.RIGHT,
		"res://scenes/friendlies/friend_b.tscn": TacticalCharacter.Facing.RIGHT,
		"res://scenes/enemies/goblin_warrior.tscn": TacticalCharacter.Facing.LEFT,
		"res://scenes/enemies/goblin_warrior_club.tscn": TacticalCharacter.Facing.LEFT,
		"res://scenes/enemies/goblin_archer.tscn": TacticalCharacter.Facing.LEFT,
		"res://scenes/enemies/mage.tscn": TacticalCharacter.Facing.LEFT,
		"res://scenes/enemies/ranger.tscn": TacticalCharacter.Facing.LEFT,
		"res://scenes/enemies/wolf.tscn": TacticalCharacter.Facing.LEFT,
	}
	for scene_path: String in scene_expectations:
		var packed_scene := load(scene_path) as PackedScene
		assert_true(packed_scene != null, "%s should load" % scene_path)
		var character := track(packed_scene.instantiate()) as TacticalCharacter
		assert_true(character.facing_left_texture != null, "%s should assign a left texture" % scene_path)
		assert_true(character.facing_right_texture != null, "%s should assign a right texture" % scene_path)
		assert_eq(character.facing_left_texture.get_size(), Vector2(256.0, 256.0), "%s left texture should be game-ready" % scene_path)
		assert_eq(character.facing_right_texture.get_size(), Vector2(256.0, 256.0), "%s right texture should be game-ready" % scene_path)
		assert_eq(character.initial_facing, scene_expectations[scene_path], "%s should use its faction-facing default" % scene_path)


func test_per_unit_stat_overrides() -> void:
	var definition = CharacterDefinitionScript.new()
	definition.constitution = 25
	definition.movement_range = 6.0
	definition.speed = 9
	var character = track(TacticalCharacterScript.new())
	character.definition = definition
	character.constitution_override = 35
	character.movement_range_override = 7.5
	character.speed_override = 14
	character._ready()

	assert_eq(character.get_max_health(), 140, "unit Constitution override should replace the template value")
	assert_eq(character.current_health, 140, "current health should initialize from the Constitution override")
	assert_true(is_equal_approx(character.get_movement_range(), 8.5), "Speed should modify the overridden base movement")
	assert_eq(character.get_initiative(), 14, "unit Speed override should determine initiative")

	character.constitution_override = -1
	character.movement_range_override = -1.0
	character.speed_override = -1
	assert_eq(character.get_max_health(), 100, "negative Constitution override should fall back to the template")
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


func test_combat_can_stop_during_or_between_turns() -> void:
	var friend := _make_unit(true, Vector2i(1, 1), 6.0, 12)
	var enemy := _make_unit(false, Vector2i(4, 4), 5.0, 10)
	var units: Array[TacticalCharacter] = [friend, enemy]
	var manager = track(TurnManagerScript.new())
	manager.start_combat(units)
	var stopped_round: int = manager.round_number
	manager.stop_combat()
	assert_eq(manager.current_unit, null, "stopping combat should clear the active unit")
	assert_eq(manager.current_index, -1, "stopping combat should clear the active turn index")
	manager.end_current_turn()
	assert_eq(manager.current_unit, null, "ending a turn after combat stops should do nothing")
	assert_eq(manager.round_number, stopped_round, "stopped combat should not advance rounds")

	var reentrant_friend := _make_unit(true, Vector2i(1, 2), 6.0, 12)
	var reentrant_enemy := _make_unit(false, Vector2i(4, 3), 5.0, 10)
	var reentrant_units: Array[TacticalCharacter] = [reentrant_friend, reentrant_enemy]
	var reentrant_manager = track(TurnManagerScript.new())
	var started_units: Array[TacticalCharacter] = []
	reentrant_manager.turn_starting.connect(func(_unit: TacticalCharacter):
		reentrant_manager.stop_combat()
	)
	reentrant_manager.turn_started.connect(func(unit: TacticalCharacter): started_units.append(unit))
	reentrant_manager.start_combat(reentrant_units)
	assert_eq(reentrant_manager.current_unit, null, "combat may stop safely during the turn-start phase")
	assert_true(started_units.is_empty(), "a unit should not begin acting after combat stops during turn start")


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
	assert_eq(ability.ability_type, AbilityDefinition.AbilityType.MAGIC, "new abilities should default to Magic")
	assert_true(_has_editor_property(ability, &"ability_type"), "Ability Type should always be visible in the Inspector")
	ability.area_of_effect = 4
	assert_eq(ability.area_of_effect, 5, "even area sizes should normalize to the next odd span")
	assert_eq(ability.get_effective_area_span(), 5, "normalized area span should be exposed to targeting")

	var friendly_definition = load("res://resources/friendly_spellcaster.tres") as CharacterDefinition
	assert_eq(friendly_definition.abilities.size(), 8, "the friendly template should expose eight sample abilities")
	var names: Array[String] = []
	for sample in friendly_definition.abilities:
		names.append(sample.display_name)
	assert_eq(names, ["Fireball", "Arrow", "Heal", "Beam", "Strike", "Ice Shard", "Charge", "Searing Dagger"], "the friendly template should retain the complete authored sample loadout")
	assert_eq(friendly_definition.abilities[0].innate_damage, 20, "Fireball innate damage should be editable directly on the ability")
	assert_eq(friendly_definition.abilities[4].innate_damage, 0, "Strike should expose zero innate damage directly on the ability")
	var ice_shard := friendly_definition.abilities[5] as AbilityDefinition
	assert_eq(ice_shard.delivery_type, AbilityDefinition.DeliveryType.PROJECTILE, "Ice Shard should use projectile delivery")
	assert_eq(ice_shard.damage_type, DamageCalculator.Type.MAGICAL, "Ice Shard should deal magical damage")
	assert_eq(ice_shard.innate_damage, 15, "Ice Shard should expose 15 innate damage")
	assert_eq(ice_shard.scaling_stat, UnitStat.Type.INTELLIGENCE, "Ice Shard should scale with Intelligence")
	assert_true(is_equal_approx(ice_shard.scaling_amount, 100.0), "Ice Shard should use 100% scaling")
	assert_true(is_equal_approx(ice_shard.range, 5.0), "Ice Shard should have range 5")
	assert_eq(ice_shard.area_of_effect, 0, "Ice Shard should affect one cell")
	assert_eq(ice_shard.target_flags, AbilityDefinition.TargetFlags.ENEMY, "Ice Shard should target one enemy")
	assert_eq(ice_shard.status_effect.status_id, &"slow", "Ice Shard should expose Slow directly")
	var charge := friendly_definition.abilities[6] as AbilityDefinition
	assert_eq(charge.caster_movement, AbilityDefinition.CasterMovement.CHARGE_TO_TARGET, "Charge should expose caster movement directly")
	assert_eq(charge.ability_type, AbilityDefinition.AbilityType.MELEE, "Charge should require a Melee weapon")
	assert_eq(charge.delivery_type, AbilityDefinition.DeliveryType.MELEE, "Charge should resolve through Melee delivery")
	assert_eq(charge.target_flags, AbilityDefinition.TargetFlags.ENEMY, "Charge should require an enemy unit target")
	assert_true(is_equal_approx(charge.range, 5.0), "Charge should have range 5")
	assert_true(_has_editor_property(charge, &"caster_movement"), "Caster Movement should always be visible in the Inspector")
	assert_true(charge.get_description().contains("Charges in a clear straight line"), "Charge descriptions should explain their movement")
	_assert_primary_effect_fields(
		ability,
		AbilityDefinition.PrimaryEffect.NONE,
		["status_effect"]
	)
	_assert_primary_effect_fields(
		ability,
		AbilityDefinition.PrimaryEffect.DAMAGE,
		["damage_type", "innate_damage", "scaling_stat", "scaling_amount", "status_effect"]
	)
	_assert_primary_effect_fields(
		ability,
		AbilityDefinition.PrimaryEffect.HEAL,
		["effect_amount", "scaling_stat", "scaling_amount", "status_effect"]
	)
	_assert_primary_effect_fields(
		ability,
		AbilityDefinition.PrimaryEffect.STATUS,
		["status_effect"]
	)
	assert_eq(DamageCalculator.ScalingSource.NONE, UnitStat.Type.NONE, "ability scaling should preserve the shared stat serialization values")
	assert_eq(DamageCalculator.ScalingSource.MOVEMENT_RANGE, UnitStat.Type.MOVEMENT_RANGE, "all existing ability scaling values should remain stable")
	assert_eq(DamageCalculator.ScalingSource.WEAPON, 6, "Weapon should append one new ability-only scaling value")
	assert_false(UnitStat.Type.keys().has("WEAPON"), "Weapon must not leak into item or status stat modifier dropdowns")
	ability.ability_type = AbilityDefinition.AbilityType.MELEE
	ability.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	assert_true(_get_editor_property_hint(ability, &"scaling_stat").contains("Weapon"), "damaging Melee abilities should offer Weapon scaling")
	ability.ability_type = AbilityDefinition.AbilityType.RANGED
	assert_true(_get_editor_property_hint(ability, &"scaling_stat").contains("Weapon"), "damaging Ranged abilities should offer Weapon scaling")
	ability.scaling_stat = DamageCalculator.ScalingSource.WEAPON
	ability.ability_type = AbilityDefinition.AbilityType.MAGIC
	assert_eq(ability.scaling_stat, DamageCalculator.ScalingSource.NONE, "changing to Magic should clear Weapon scaling")
	assert_false(_get_editor_property_hint(ability, &"scaling_stat").contains("Weapon"), "Magic damage should keep stat-only scaling options")
	ability.ability_type = AbilityDefinition.AbilityType.MELEE
	ability.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	ability.scaling_stat = DamageCalculator.ScalingSource.WEAPON
	ability.effect = AbilityDefinition.PrimaryEffect.HEAL
	assert_eq(ability.scaling_stat, DamageCalculator.ScalingSource.NONE, "changing to Heal should clear Weapon scaling")
	assert_false(_get_editor_property_hint(ability, &"scaling_stat").contains("Weapon"), "Heal should keep stat-only scaling options")
	var legacy_damage_inspector := DamageEffectScript.new() as DamageEffectDefinition
	assert_false(_get_editor_property_hint(legacy_damage_inspector, &"scaling_stat").contains("Weapon"), "legacy damage-effect scaling should remain stat-only")

	var status := StatusEffectDefinition.new()
	_assert_status_effect_fields(status, StatusEffectDefinition.Effect.NONE, null, [])
	_assert_status_effect_fields(
		status,
		StatusEffectDefinition.Effect.DAMAGE_EACH_TURN,
		null,
		["damage_type", "damage_per_turn"]
	)
	_assert_status_effect_fields(
		status,
		StatusEffectDefinition.Effect.STAT_MODIFIER,
		StatusEffectDefinition.ModifierValueType.FLAT,
		["affected_stat", "modifier_direction", "modifier_value_type", "flat_amount", "affected_unit_ai_utility"]
	)
	_assert_status_effect_fields(
		status,
		StatusEffectDefinition.Effect.STAT_MODIFIER,
		StatusEffectDefinition.ModifierValueType.PERCENTAGE,
		["affected_stat", "modifier_direction", "modifier_value_type", "percentage_amount", "affected_unit_ai_utility"]
	)
	_assert_status_effect_fields(
		status,
		StatusEffectDefinition.Effect.STUN,
		null,
		["affected_unit_ai_utility"]
	)

	var item := ItemDefinition.new()
	assert_eq(item.weapon_type, ItemDefinition.WeaponType.MELEE, "new weapons should default to Melee")
	assert_eq(item.status_effect, null, "new weapons should default to no Status Effect")
	assert_true(_has_editor_property(item, &"weapon_type"), "Weapon Type should be visible for Weapon items")
	assert_true(_has_editor_property(item, &"status_effect"), "Status Effect should be visible for Weapon items")
	var status_inspector_source := FileAccess.get_file_as_string("res://addons/tile_painter/tile_status_inspector.gd")
	assert_true(status_inspector_source.contains("object is ItemDefinition"), "the saved-status dropdown should handle ItemDefinition resources")
	assert_eq(
		StatusCatalogScript.get_statuses().map(func(saved_status: StatusEffectDefinition): return saved_status.display_name),
		["Bleeding", "Burning", "Focus", "Slow", "Stun"],
		"the weapon status dropdown should discover every saved status deterministically"
	)
	item.slot = ItemDefinition.EquipmentSlot.ARMOR
	assert_false(_has_editor_property(item, &"weapon_type"), "Weapon Type should be hidden for Armor items")
	assert_false(_has_editor_property(item, &"status_effect"), "Status Effect should be hidden for Armor items")
	item.slot = ItemDefinition.EquipmentSlot.ACCESSORY
	assert_false(_has_editor_property(item, &"weapon_type"), "Weapon Type should be hidden for Accessory items")
	assert_false(_has_editor_property(item, &"status_effect"), "Status Effect should be hidden for Accessory items")


func test_charge_targeting_paths_blockers_and_directions() -> void:
	assert_eq(AbilityDefinition.CasterMovement.NONE, 0, "None caster movement should retain serialization value zero")
	assert_eq(AbilityDefinition.CasterMovement.CHARGE_TO_TARGET, 1, "Charge should append serialization value one")
	var fresh := AbilityDefinitionScript.new() as AbilityDefinition
	assert_eq(fresh.caster_movement, AbilityDefinition.CasterMovement.NONE, "new abilities should not move their caster")
	assert_true(_has_editor_property(fresh, &"caster_movement"), "Caster Movement should always be visible")

	var charge := (load("res://resources/abilities/charge.tres") as AbilityDefinition).duplicate(true) as AbilityDefinition
	var caster := _make_unit(true, Vector2i(5, 5), 6.0)
	var target := _make_unit(false, Vector2i(9, 5), 6.0)
	var weapon := ItemDefinition.new()
	weapon.weapon_type = ItemDefinition.WeaponType.MELEE
	weapon.weapon_damage = 20
	caster.equip_item(weapon)
	var units: Array[TacticalCharacter] = [caster, target]
	var targeting := AbilityTargetingScript.new(Vector2i(11, 11)) as AbilityTargeting
	var directions := [
		Vector2i(4, 0),
		Vector2i(-4, 0),
		Vector2i(0, 4),
		Vector2i(0, -4),
		Vector2i(3, 3),
		Vector2i(-3, 3),
		Vector2i(-3, -3),
		Vector2i(3, -3),
	]
	for difference in directions:
		target.grid_cell = caster.grid_cell + difference
		assert_true(
			targeting.is_valid_primary_target(caster, target.grid_cell, charge, units),
			"Charge should accept straight direction %s" % difference
		)
		var path := targeting.get_caster_movement_path(caster, target.grid_cell, charge, units)
		var direction := Vector2i(signi(difference.x), signi(difference.y))
		assert_eq(
			AbilityCasterMovementScript.get_landing_cell(path),
			target.grid_cell - direction,
			"Charge should stop immediately before its target"
		)

	target.grid_cell = Vector2i(8, 7)
	assert_false(
		targeting.is_valid_primary_target(caster, target.grid_cell, charge, units),
		"Charge should reject a target outside the eight straight directions"
	)
	target.grid_cell = Vector2i(9, 5)
	var blocker := _make_unit(false, Vector2i(7, 5), 6.0)
	var blocked_units: Array[TacticalCharacter] = [caster, target, blocker]
	assert_false(
		targeting.is_valid_primary_target(caster, target.grid_cell, charge, blocked_units),
		"Charge should reject an occupied intermediate cell"
	)
	blocker.grid_cell = Vector2i(8, 5)
	assert_false(
		targeting.is_valid_primary_target(caster, target.grid_cell, charge, blocked_units),
		"Charge should reject an occupied landing cell"
	)
	blocker.grid_cell = Vector2i(0, 0)
	target.grid_cell = Vector2i(8, 8)
	assert_false(
		targeting.is_valid_primary_target(
			caster,
			target.grid_cell,
			charge,
			blocked_units,
			{Vector2i(6, 5): true}
		),
		"Charge should obey diagonal corner blockers"
	)
	target.grid_cell = Vector2i(6, 5)
	assert_eq(
		targeting.get_caster_movement_path(caster, target.grid_cell, charge, units),
		[caster.grid_cell],
		"an adjacent Charge should attack without grid movement"
	)
	target.grid_cell = Vector2i(9, 5)
	assert_false(
		targeting.is_valid_primary_target(caster, Vector2i(9, 4), charge, units),
		"Charge should require a living unit at the selected cell"
	)


func test_inline_item_modifier_inspector_model_and_resources() -> void:
	var strength := StatModifierDefinition.new()
	strength.stat = UnitStat.Type.STRENGTH
	strength.operation = StatModifierDefinition.Operation.FLAT
	strength.value = 2.0
	var initial: Array[StatModifierDefinition] = [strength, null]
	var copied := ItemModifierModelScript.copy_modifiers(initial)
	assert_eq(copied.size(), 2, "the inline editor should preserve every modifier row")
	assert_eq(copied[0], strength, "copying should preserve shared modifier resources")
	assert_eq(copied[1], null, "copying should preserve null modifier positions")
	assert_eq(copied.get_typed_script(), load("res://scripts/stat_modifier_definition.gd"), "modifier edits should retain the typed array element script")

	var appended := ItemModifierModelScript.append_default(initial)
	assert_eq(appended.size(), 3, "Add Modifier should append one row")
	assert_eq(appended[2].stat, UnitStat.Type.STRENGTH, "new modifier rows should default to Strength")
	assert_eq(appended[2].operation, StatModifierDefinition.Operation.FLAT, "new modifier rows should default to Flat")
	assert_true(is_zero_approx(appended[2].value), "new modifier rows should default to zero")
	assert_eq(initial.size(), 2, "editor model operations should not mutate the source array")

	var repaired := ItemModifierModelScript.replace_null(initial, 1)
	assert_true(repaired[1] is StatModifierDefinition, "Create should repair a null modifier row")
	assert_eq(ItemModifierModelScript.remove_entry(repaired, 0).size(), 1, "Remove should delete only the selected modifier row")
	assert_true(
		is_equal_approx(
			ItemModifierModelScript.to_display_value(0.25, StatModifierDefinition.Operation.PERCENT_ADD),
			25.0
		),
		"percentage-add values should display as human percentages"
	)
	assert_true(
		is_equal_approx(
			ItemModifierModelScript.to_stored_value(-30.0, StatModifierDefinition.Operation.PERCENT_MULTIPLY),
			-0.3
		),
		"negative human percentages should convert back to decimal storage"
	)
	assert_true(
		is_equal_approx(
			ItemModifierModelScript.to_display_value(-1.5, StatModifierDefinition.Operation.FLAT),
			-1.5
		),
		"flat values should display without conversion"
	)
	assert_eq(ItemModifierModelScript.get_operation_label(StatModifierDefinition.Operation.FLAT), "Flat", "flat operations should have a concise label")
	assert_eq(ItemModifierModelScript.get_operation_label(StatModifierDefinition.Operation.PERCENT_ADD), "Add %", "additive percentages should have a concise label")
	assert_eq(ItemModifierModelScript.get_operation_label(StatModifierDefinition.Operation.PERCENT_MULTIPLY), "Multiply %", "multiplicative percentages should have a concise label")

	var inspector_source := FileAccess.get_file_as_string("res://addons/tile_painter/item_modifier_inspector.gd")
	var property_source := FileAccess.get_file_as_string("res://addons/tile_painter/item_modifier_editor_property.gd")
	var plugin_source := FileAccess.get_file_as_string("res://addons/tile_painter/tile_painter_plugin.gd")
	assert_true(inspector_source.contains('name != "modifiers"'), "the custom Inspector should replace only ItemDefinition.modifiers")
	assert_true(inspector_source.contains("object is ItemDefinition"), "the modifier Inspector should handle ItemDefinition resources")
	assert_true(property_source.contains("Add Modifier"), "the inline editor should expose Add Modifier")
	assert_true(property_source.contains("add_do_property") and property_source.contains("add_undo_property"), "inline field edits should participate in Inspector undo/redo")
	assert_true(plugin_source.contains("ItemModifierInspector"), "the enabled editor plugin should register the modifier Inspector")

	var iron_sword := load("res://resources/items/iron_sword.tres") as ItemDefinition
	assert_eq(iron_sword.modifiers.size(), 1, "existing item modifier arrays should remain intact")
	assert_eq(iron_sword.modifiers[0].stat, UnitStat.Type.STRENGTH, "Iron Sword should retain its Strength modifier")
	assert_eq(iron_sword.modifiers[0].operation, StatModifierDefinition.Operation.FLAT, "Iron Sword should retain its Flat operation")
	assert_true(is_equal_approx(iron_sword.modifiers[0].value, 2.0), "Iron Sword should retain its +2 value")
	var goblin_club := load("res://resources/items/goblin_club.tres") as ItemDefinition
	assert_eq(goblin_club.modifiers[0].stat, UnitStat.Type.SPEED, "Goblin Club should retain its Speed modifier")
	assert_true(is_equal_approx(goblin_club.modifiers[0].value, -1.0), "Goblin Club should retain its negative value")

	var round_trip_item := ItemDefinition.new()
	var percent_modifier := StatModifierDefinition.new()
	percent_modifier.stat = UnitStat.Type.MOVEMENT_RANGE
	percent_modifier.operation = StatModifierDefinition.Operation.PERCENT_ADD
	percent_modifier.value = -0.3
	var round_trip_modifiers: Array[StatModifierDefinition] = [percent_modifier]
	round_trip_item.modifiers = round_trip_modifiers
	var round_trip_path := "res://Godot/item_modifier_round_trip.tres"
	assert_eq(ResourceSaver.save(round_trip_item, round_trip_path), OK, "item modifiers should save successfully")
	var loaded_item := ResourceLoader.load(round_trip_path, "", ResourceLoader.CACHE_MODE_REPLACE) as ItemDefinition
	assert_true(loaded_item != null, "saved item modifiers should reload successfully")
	if loaded_item != null:
		assert_eq(loaded_item.modifiers.size(), 1, "reloaded items should retain modifier rows")
		assert_eq(loaded_item.modifiers[0].stat, UnitStat.Type.MOVEMENT_RANGE, "reloaded modifiers should retain their stat")
		assert_eq(loaded_item.modifiers[0].operation, StatModifierDefinition.Operation.PERCENT_ADD, "reloaded modifiers should retain their operation")
		assert_true(is_equal_approx(loaded_item.modifiers[0].value, -0.3), "reloaded modifiers should retain decimal percentage storage")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(round_trip_path))


func test_weapon_compatibility_is_independent_from_damage_type_and_delivery() -> void:
	var caster := _make_unit(true, Vector2i(1, 1), 6.0)
	caster.reset_ability_action()
	var target := _make_unit(false, Vector2i(2, 1), 6.0)
	var units: Array[TacticalCharacter] = [caster, target]
	var melee := AbilityDefinition.new()
	melee.display_name = "Arcane Slash"
	melee.ability_type = AbilityDefinition.AbilityType.MELEE
	melee.delivery_type = AbilityDefinition.DeliveryType.PROJECTILE
	melee.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	melee.damage_type = DamageCalculator.Type.MAGICAL
	melee.innate_damage = 3
	melee.scaling_stat = UnitStat.Type.NONE
	melee.range = 2.0
	var ranged := AbilityDefinition.new()
	ranged.display_name = "Physical Shot"
	ranged.ability_type = AbilityDefinition.AbilityType.RANGED
	ranged.delivery_type = AbilityDefinition.DeliveryType.CAST_ON_TARGET
	ranged.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	ranged.damage_type = DamageCalculator.Type.PHYSICAL
	ranged.innate_damage = 4
	ranged.scaling_stat = UnitStat.Type.NONE
	ranged.range = 2.0
	var magic := AbilityDefinition.new()
	magic.display_name = "Physical Magic"
	magic.ability_type = AbilityDefinition.AbilityType.MAGIC
	magic.delivery_type = AbilityDefinition.DeliveryType.MELEE
	magic.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	magic.damage_type = DamageCalculator.Type.PHYSICAL
	magic.innate_damage = 5
	magic.scaling_stat = UnitStat.Type.NONE
	magic.range = 2.0
	var ranged_utility := AbilityDefinition.new()
	ranged_utility.ability_type = AbilityDefinition.AbilityType.RANGED

	assert_false(melee.can_be_used_by(caster), "Melee abilities should require a Melee weapon")
	assert_false(ranged.can_be_used_by(caster), "Ranged abilities should require a Ranged weapon")
	assert_true(magic.can_be_used_by(caster), "Magic abilities should work without a weapon")
	assert_false(ranged_utility.can_be_used_by(caster), "non-damaging Ranged abilities should still require a Ranged weapon")
	assert_eq(melee.get_unavailable_reason(caster), "Requires a Melee weapon", "Melee should expose a clear unavailable reason")
	assert_eq(ranged.get_unavailable_reason(caster), "Requires a Ranged weapon", "Ranged should expose a clear unavailable reason")

	var melee_weapon := ItemDefinition.new()
	melee_weapon.display_name = "Test Blade"
	melee_weapon.weapon_type = ItemDefinition.WeaponType.MELEE
	melee_weapon.weapon_damage = 11
	caster.equip_item(melee_weapon)
	assert_true(melee.can_be_used_by(caster), "a matching Melee weapon should enable a Melee ability")
	assert_false(ranged.can_be_used_by(caster), "a Melee weapon should not enable a Ranged ability")
	assert_eq(melee.calculate_damage(caster), 14, "Melee ability damage should include a matching weapon even when Damage Type is Magical")
	assert_eq(ranged.calculate_damage(caster), 4, "a mismatched weapon should contribute zero damage")
	assert_eq(magic.calculate_damage(caster), 5, "Magic abilities should ignore weapons even when Damage Type is Physical")

	var targeting := AbilityTargetingScript.new(Vector2i(5, 5)) as AbilityTargeting
	var grid := track(IsometricGridScript.new()) as IsometricGrid
	grid.grid_size = Vector2i(5, 5)
	var executor := track(AbilityExecutorScript.new()) as AbilityExecutor
	assert_false(targeting.is_valid_primary_target(caster, target.grid_cell, ranged, units), "targeting should reject an incompatible ability")
	assert_false(executor.can_execute(caster, ranged, target.grid_cell, units, grid, targeting), "execution should reject an incompatible ability")
	assert_true(caster.ability_available, "rejecting an incompatible ability should not spend the action")

	var ranged_weapon := ItemDefinition.new()
	ranged_weapon.display_name = "Test Bow"
	ranged_weapon.weapon_type = ItemDefinition.WeaponType.RANGED
	ranged_weapon.weapon_damage = 7
	caster.equip_item(ranged_weapon)
	assert_false(melee.can_be_used_by(caster), "a Ranged weapon should disable Melee abilities")
	assert_true(ranged.can_be_used_by(caster), "a matching Ranged weapon should enable Ranged abilities")
	assert_true(ranged_utility.can_be_used_by(caster), "a matching weapon should enable non-damaging Ranged abilities")
	assert_eq(ranged.calculate_damage(caster), 11, "Ranged ability damage should include only a matching Ranged weapon")
	assert_eq(magic.calculate_damage(caster), 5, "Magic ability damage should remain unchanged after a weapon swap")

	var legacy_damage := DamageEffectScript.new() as DamageEffectDefinition
	legacy_damage.damage_type = DamageEffectDefinition.DamageType.PHYSICAL
	legacy_damage.innate_damage = 2
	legacy_damage.scaling_stat = UnitStat.Type.NONE
	var magic_legacy := AbilityDefinition.new()
	magic_legacy.ability_type = AbilityDefinition.AbilityType.MAGIC
	var legacy_effects: Array[AbilityEffectDefinition] = [legacy_damage]
	magic_legacy.effects = legacy_effects
	assert_eq(magic_legacy.calculate_damage(caster), 2, "ability-owned legacy damage should inherit the originating Magic type")
	assert_eq(legacy_damage.calculate_amount(caster), 9, "standalone legacy Physical damage should preserve its original weapon behavior")


func test_sample_weapon_and_ability_type_migration() -> void:
	var ability_paths := {
		AbilityDefinition.AbilityType.MELEE: [
			"res://resources/abilities/strike.tres",
			"res://resources/abilities/enemy_slash.tres",
		],
		AbilityDefinition.AbilityType.RANGED: [
			"res://resources/abilities/arrow.tres",
			"res://resources/abilities/enemy_shot.tres",
		],
		AbilityDefinition.AbilityType.MAGIC: [
			"res://resources/abilities/fireball.tres",
			"res://resources/abilities/beam.tres",
			"res://resources/abilities/ice_shard.tres",
			"res://resources/abilities/heal.tres",
			"res://resources/abilities/slow.tres",
			"res://resources/abilities/focus.tres",
		],
	}
	for expected_type in ability_paths:
		for path in ability_paths[expected_type]:
			var ability := load(path) as AbilityDefinition
			assert_eq(ability.ability_type, expected_type, "%s should use its migrated Ability Type" % ability.display_name)

	var weapon_paths := {
		ItemDefinition.WeaponType.MELEE: [
			"res://resources/items/iron_sword.tres",
			"res://resources/items/wooden_sword.tres",
			"res://resources/items/goblin_sword.tres",
			"res://resources/items/goblin_club.tres",
			"res://resources/items/mage_staff.tres",
			"res://resources/items/raider_weapon.tres",
			"res://resources/items/wolf_claws.tres",
		],
		ItemDefinition.WeaponType.RANGED: [
			"res://resources/items/ranger_bow.tres",
			"res://resources/items/goblin_bow.tres",
			"res://resources/items/frost_bow.tres",
		],
	}
	for expected_type in weapon_paths:
		for path in weapon_paths[expected_type]:
			var weapon := load(path) as ItemDefinition
			assert_eq(weapon.slot, ItemDefinition.EquipmentSlot.WEAPON, "%s should remain a Weapon-slot item" % weapon.display_name)
			assert_eq(weapon.weapon_type, expected_type, "%s should use its migrated Weapon Type" % weapon.display_name)


func test_automatic_item_catalog_and_typed_array_editor_model() -> void:
	var catalog := ItemCatalogScript.get_items()
	var names: Array[String] = []
	for item in catalog:
		names.append(item.display_name)
		assert_true(item.resource_path.begins_with("res://resources/items/"), "the item catalog should include only saved item resources")
	assert_eq(names, [
		"Frost Bow",
		"Goblin Bow",
		"Goblin Club",
		"Goblin Sword",
		"Iron Sword",
		"Long Sword",
		"Mage Staff",
		"Raider Weapon",
		"Ranger Armor",
		"Ranger Bow",
		"Sage Charm",
		"Wolf Claws",
		"Wooden Sword",
	], "the automatic item catalog should discover and sort every saved item deterministically")
	assert_eq(ItemCatalogScript.get_labels(catalog), names, "unique item names should appear directly in selector rows")
	var external := ItemDefinition.new()
	external.display_name = "External Relic"
	assert_eq(ItemCatalogScript.get_external_label(external), "External Relic (external)", "out-of-catalog selections should remain visible")

	var iron_sword := load("res://resources/items/iron_sword.tres") as ItemDefinition
	var frost_bow := load("res://resources/items/frost_bow.tres") as ItemDefinition
	var ranger_bow := load("res://resources/items/ranger_bow.tres") as ItemDefinition
	var initial: Array[ItemDefinition] = [iron_sword, null, frost_bow, frost_bow]
	var selected := ItemArrayModelScript.replace_entry(initial, 1, ranger_bow)
	assert_true(selected.is_typed(), "selector edits should preserve a typed array")
	assert_eq(selected.get_typed_script(), load("res://scripts/item_definition.gd"), "selector arrays should retain their ItemDefinition element type")
	assert_eq(selected, [iron_sword, ranger_bow, frost_bow, frost_bow], "selecting an item should replace only its row")
	assert_eq(initial[1], null, "selector operations should not mutate the Inspector source array in place")
	var cleared := ItemArrayModelScript.replace_entry(selected, 1, null)
	assert_eq(cleared[1], null, "the None option should preserve explicit empty entries")
	var appended := ItemArrayModelScript.append_empty(cleared)
	assert_eq(appended.size(), 5, "Add Item should append one empty selector row")
	var moved := ItemArrayModelScript.move_entry(appended, 3, -1)
	assert_eq(moved[2], frost_bow, "reordering should preserve repeated item resources")
	var removed := ItemArrayModelScript.remove_entry(moved, 4)
	assert_eq(removed.size(), 4, "Remove should delete only the selected row")

	var inspector_source := FileAccess.get_file_as_string("res://addons/tile_painter/item_array_inspector.gd")
	for property_name in ["starting_equipment", "starting_equipment_overrides", "starting_items"]:
		assert_true(inspector_source.contains(property_name), "%s should use the automatic item selector" % property_name)
	var editor_source := FileAccess.get_file_as_string("res://addons/tile_painter/item_array_editor_property.gd")
	assert_true(editor_source.contains("filesystem_changed.connect"), "visible item selectors should refresh after filesystem changes")
	assert_true(editor_source.contains("emit_changed"), "selector edits should use Godot Inspector undo/redo changes")


func test_item_granted_ability_catalog_inspector_and_runtime_merge() -> void:
	var catalog := AbilityCatalogScript.get_abilities()
	var names: Array[String] = []
	for ability in catalog:
		names.append(ability.display_name)
		assert_true(ability.resource_path.begins_with("res://resources/abilities/"), "the ability catalog should include only saved ability resources")
	var sorted_names := names.duplicate()
	sorted_names.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	assert_eq(names, sorted_names, "the automatic ability catalog should sort saved abilities by display name")
	assert_true(names.has("Charge"), "the ability picker should discover Charge")
	assert_eq(AbilityCatalogScript.get_labels(catalog), names, "unique ability names should appear directly in selector rows")
	var external := AbilityDefinition.new()
	external.display_name = "External Technique"
	assert_eq(AbilityCatalogScript.get_external_label(external), "External Technique (external)", "out-of-catalog abilities should remain visible")

	var charge := load("res://resources/abilities/charge.tres") as AbilityDefinition
	var strike := load("res://resources/abilities/strike.tres") as AbilityDefinition
	var initial: Array[AbilityDefinition] = [charge, null, strike, charge]
	var selected := AbilityArrayModelScript.replace_entry(initial, 1, strike)
	assert_true(selected.is_typed(), "ability selector edits should preserve a typed array")
	assert_eq(selected.get_typed_script(), load("res://scripts/ability_definition.gd"), "selector arrays should retain their AbilityDefinition element type")
	assert_eq(selected, [charge, strike, strike, charge], "selecting an ability should replace only its row")
	assert_eq(initial[1], null, "ability selector operations should not mutate the Inspector source array")
	var appended := AbilityArrayModelScript.append_empty(selected)
	assert_eq(appended.size(), 5, "Add Ability should append one empty selector row")
	var moved := AbilityArrayModelScript.move_entry(appended, 3, -1)
	assert_eq(moved[2], charge, "reordering should preserve repeated ability resources")
	assert_eq(AbilityArrayModelScript.remove_entry(moved, 4).size(), 4, "Remove should delete only the selected ability row")

	var item := ItemDefinition.new()
	var granted_property: Dictionary = {}
	for property_info in item.get_property_list():
		if StringName(property_info.name) == &"granted_abilities":
			granted_property = property_info
			break
	assert_false(granted_property.is_empty(), "items should expose Granted Abilities")
	assert_true(bool(int(granted_property.usage) & PROPERTY_USAGE_EDITOR), "Granted Abilities should be Inspector-editable")
	assert_true(bool(int(granted_property.usage) & PROPERTY_USAGE_STORAGE), "Granted Abilities should be stored in item resources")
	assert_true(String(granted_property.hint_string).contains("AbilityDefinition"), "Granted Abilities should accept only AbilityDefinition resources")
	var inspector_source := FileAccess.get_file_as_string("res://addons/tile_painter/item_ability_inspector.gd")
	assert_true(inspector_source.contains('name != "granted_abilities"'), "the ability Inspector should replace only ItemDefinition.granted_abilities")
	var property_source := FileAccess.get_file_as_string("res://addons/tile_painter/ability_array_editor_property.gd")
	assert_true(property_source.contains("filesystem_changed.connect"), "visible ability selectors should refresh after filesystem changes")
	assert_true(property_source.contains("emit_changed"), "ability selector edits should participate in Inspector undo/redo")
	var plugin_source := FileAccess.get_file_as_string("res://addons/tile_painter/tile_painter_plugin.gd")
	assert_true(plugin_source.contains("ItemAbilityInspector"), "the enabled editor plugin should register the ability Inspector")

	var innate := AbilityDefinition.new()
	innate.display_name = "Innate"
	var weapon_grant := AbilityDefinition.new()
	weapon_grant.display_name = "Weapon Grant"
	var armor_grant := AbilityDefinition.new()
	armor_grant.display_name = "Armor Grant"
	var accessory_grant := AbilityDefinition.new()
	accessory_grant.display_name = "Accessory Grant"
	var same_name_but_distinct := AbilityDefinition.new()
	same_name_but_distinct.display_name = "Weapon Grant"
	var unit := _make_unit(true, Vector2i.ZERO, 6.0)
	unit.definition.abilities = [innate, charge, null, innate]
	var weapon := ItemDefinition.new()
	weapon.slot = ItemDefinition.EquipmentSlot.WEAPON
	weapon.granted_abilities = [charge, weapon_grant, null]
	var armor := ItemDefinition.new()
	armor.slot = ItemDefinition.EquipmentSlot.ARMOR
	armor.granted_abilities = [armor_grant]
	var accessory := ItemDefinition.new()
	accessory.slot = ItemDefinition.EquipmentSlot.ACCESSORY
	accessory.granted_abilities = [weapon_grant, accessory_grant, same_name_but_distinct]
	unit.equip_item(accessory)
	unit.equip_item(armor)
	unit.equip_item(weapon)
	assert_eq(
		unit.get_abilities(),
		[innate, charge, weapon_grant, armor_grant, accessory_grant, same_name_but_distinct],
		"abilities should keep the first resource occurrence in base, Weapon, Armor, Accessory order"
	)
	var override_ability := AbilityDefinition.new()
	override_ability.display_name = "Override"
	unit.override_template_abilities = true
	unit.ability_overrides = [override_ability, weapon_grant]
	assert_eq(
		unit.get_abilities(),
		[override_ability, weapon_grant, charge, armor_grant, accessory_grant, same_name_but_distinct],
		"equipment grants should append to the active per-unit override while preserving first occurrences"
	)
	unit.unequip_item(ItemDefinition.EquipmentSlot.WEAPON)
	assert_false(unit.get_abilities().has(charge), "unequipping an item should immediately remove its unique granted ability")

	var long_sword := load("res://resources/items/long_sword.tres") as ItemDefinition
	assert_true(long_sword != null, "the reusable Long Sword resource should load")
	var long_sword_uid := ResourceUID.text_to_id("uid://d1ongsw0rd001")
	assert_ne(long_sword_uid, ResourceUID.INVALID_ID, "Long Sword should have a valid stable resource UID")
	assert_eq(ResourceUID.get_id_path(long_sword_uid), "res://resources/items/long_sword.tres", "Long Sword UID should resolve to its saved resource")
	assert_eq(long_sword.display_name, "Long Sword", "the new item should use the corrected display name")
	assert_eq(long_sword.slot, ItemDefinition.EquipmentSlot.WEAPON, "Long Sword should occupy the Weapon slot")
	assert_eq(long_sword.weapon_type, ItemDefinition.WeaponType.MELEE, "Long Sword should be Melee")
	assert_eq(long_sword.weapon_damage, 20, "Long Sword should deal 20 weapon damage")
	assert_true(long_sword.modifiers.is_empty(), "Long Sword should not grant stat modifiers")
	assert_eq(long_sword.status_effect, null, "Long Sword should not apply a status")
	assert_eq(long_sword.granted_abilities, [charge], "Long Sword should grant Charge")
	assert_true(ItemCatalogScript.get_tooltip(long_sword).contains("Grants: Charge"), "item catalog tooltips should identify granted abilities")

	var untrained := _make_unit(true, Vector2i.ONE, 6.0)
	assert_true(untrained.get_abilities().is_empty(), "the grant fixture should start without abilities")
	untrained.equip_item(long_sword)
	assert_eq(untrained.get_abilities(), [charge], "equipping Long Sword should grant Charge to an untrained unit")
	assert_eq(OpportunityAttackSystemScript.get_opportunity_attack_ability(untrained), null, "item-granted Charge should remain excluded from opportunity attacks because it moves the caster")
	untrained.unequip_item(ItemDefinition.EquipmentSlot.WEAPON)
	assert_true(untrained.get_abilities().is_empty(), "unequipping Long Sword should remove Charge from an untrained unit")

	var friendly_definition := load("res://resources/friendly_spellcaster.tres") as CharacterDefinition
	var friendly := track(TacticalCharacterScript.new()) as TacticalCharacter
	friendly.definition = friendly_definition
	friendly._ready()
	friendly.equip_item(long_sword)
	assert_eq(friendly.get_abilities().count(charge), 1, "innate and item-granted Charge should appear only once")
	var controller_source := FileAccess.get_file_as_string("res://scripts/initiative_battle_controller.gd")
	assert_true(controller_source.contains("not character.get_abilities().has(_selected_ability)"), "equipment refresh should cancel targeting when an item-granted ability is removed")


func test_weapon_status_applies_to_every_surviving_weapon_damage_target() -> void:
	var frost_bow := load("res://resources/items/frost_bow.tres") as ItemDefinition
	var slow := load("res://resources/statuses/slow.tres") as StatusEffectDefinition
	assert_eq(frost_bow.display_name, "Frost Bow", "Frost Bow should be reusable")
	assert_eq(frost_bow.weapon_type, ItemDefinition.WeaponType.RANGED, "Frost Bow should be Ranged")
	assert_eq(frost_bow.weapon_damage, 10, "Frost Bow should provide 10 weapon damage")
	assert_eq(frost_bow.status_effect, slow, "Frost Bow should expose reusable Slow in the Inspector")

	var caster := _make_unit(true, Vector2i(1, 1), 6.0)
	caster.equip_item(frost_bow)
	var target_a := _make_unit(false, Vector2i(2, 1), 6.0)
	var target_b := _make_unit(false, Vector2i(2, 2), 6.0)
	var units: Array[TacticalCharacter] = [caster, target_a, target_b]
	var targeting := AbilityTargetingScript.new(Vector2i(6, 6)) as AbilityTargeting
	var executor := track(AbilityExecutorScript.new()) as AbilityExecutor
	var sample_caster := track(TacticalCharacterScript.new()) as TacticalCharacter
	sample_caster.definition = load("res://resources/friendly_spellcaster.tres") as CharacterDefinition
	sample_caster._ready()
	sample_caster.equip_item(frost_bow)
	var sample_target := _make_unit(false, Vector2i(1, 0), 6.0)
	var sample_arrow := load("res://resources/abilities/arrow.tres") as AbilityDefinition
	var sample_units: Array[TacticalCharacter] = [sample_caster, sample_target]
	assert_eq(sample_arrow.calculate_damage(sample_caster), 17, "sample Arrow should deal Frost Bow 10 plus 60% of Dexterity 12")
	executor._apply_effects(sample_caster, sample_target.grid_cell, sample_arrow, sample_units, targeting, {})
	assert_eq(sample_target.current_health, 83, "sample Arrow execution should use its displayed 17 damage")
	assert_eq(sample_target.get_active_statuses()[0].definition, slow, "sample Arrow should apply Frost Bow Slow")
	assert_eq(sample_target.get_active_statuses()[0].source, frost_bow, "sample Arrow Slow should retain Frost Bow as source")
	var volley := AbilityDefinition.new()
	volley.display_name = "Frost Volley"
	volley.ability_type = AbilityDefinition.AbilityType.RANGED
	volley.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	volley.scaling_stat = UnitStat.Type.NONE
	volley.area_of_effect = 3
	volley.target_flags = AbilityDefinition.TargetFlags.ENEMY

	assert_true(volley.uses_weapon_damage(caster), "a damaging Ranged ability should use the matching Frost Bow")
	assert_eq(volley.calculate_damage(caster), 10, "Frost Bow should contribute its exact weapon damage")
	assert_eq(volley.get_weapon_status_effect(caster), slow, "the centralized ability API should expose Frost Bow Slow")
	assert_true(volley.get_description(caster).contains("Weapon applies Slow"), "live ability tooltips should describe the weapon status")
	executor._apply_effects(caster, target_a.grid_cell, volley, units, targeting, {})
	for target in [target_a, target_b]:
		assert_eq(target.current_health, 90, "every affected enemy should take Frost Bow damage")
		assert_eq(target.get_active_statuses().size(), 1, "every surviving damaged enemy should receive Slow once")
		assert_eq(target.get_active_statuses()[0].definition, slow, "Frost Bow should apply the reusable Slow definition")
		assert_eq(target.get_active_statuses()[0].source, frost_bow, "weapon-applied statuses should record the weapon as source")
		assert_eq(target.get_active_statuses()[0].source_unit, caster, "weapon-applied statuses should record the caster")

	var half_weapon_target := _make_unit(false, Vector2i(3, 0), 6.0)
	var half_weapon := AbilityDefinition.new()
	half_weapon.display_name = "Half Weapon Shot"
	half_weapon.ability_type = AbilityDefinition.AbilityType.RANGED
	half_weapon.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	half_weapon.scaling_stat = DamageCalculator.ScalingSource.WEAPON
	half_weapon.scaling_amount = 50.0
	half_weapon.target_flags = AbilityDefinition.TargetFlags.ENEMY
	assert_eq(half_weapon.calculate_damage(caster), 5, "50% Weapon scaling should deal half of Frost Bow's 10 damage")
	assert_true(half_weapon.uses_weapon_damage(caster), "positive Weapon scaling should count as weapon usage")
	var half_weapon_units: Array[TacticalCharacter] = [caster, half_weapon_target]
	executor._apply_effects(caster, half_weapon_target.grid_cell, half_weapon, half_weapon_units, targeting, {})
	assert_eq(half_weapon_target.current_health, 95, "execution should use the centralized half-weapon amount")
	assert_eq(half_weapon_target.get_active_statuses()[0].definition, slow, "positive Weapon scaling should apply the weapon status")

	var zero_weapon_target := _make_unit(false, Vector2i(3, 5), 6.0)
	half_weapon.scaling_amount = 0.0
	assert_eq(half_weapon.calculate_damage(caster), 0, "zero-percent Weapon scaling should contribute no weapon damage")
	assert_false(half_weapon.uses_weapon_damage(caster), "zero-percent Weapon scaling should not count as weapon usage")
	var zero_weapon_units: Array[TacticalCharacter] = [caster, zero_weapon_target]
	executor._apply_effects(caster, zero_weapon_target.grid_cell, half_weapon, zero_weapon_units, targeting, {})
	assert_eq(zero_weapon_target.current_health, 100, "zero-percent Weapon scaling should deal no damage without innate damage")
	assert_true(zero_weapon_target.get_active_statuses().is_empty(), "zero-percent Weapon scaling should not apply the weapon status")

	executor._apply_effects(caster, target_a.grid_cell, volley, units, targeting, {})
	assert_eq(target_a.get_active_statuses().size(), 1, "repeated Frost Bow hits should refresh rather than stack Slow")
	assert_eq(target_a.get_active_statuses()[0].remaining_turns, 2, "a repeated hit should restore Slow's full duration")

	var lethal_target := _make_unit(false, Vector2i(3, 1), 6.0)
	lethal_target.current_health = 10
	var lethal_units: Array[TacticalCharacter] = [caster, lethal_target]
	executor._apply_effects(caster, lethal_target.grid_cell, volley, lethal_units, targeting, {})
	assert_eq(lethal_target.current_health, 0, "Frost Bow damage should still defeat a low-health target")
	assert_true(lethal_target.get_active_statuses().is_empty(), "lethal weapon damage should not apply its status")

	var duplicate_target := _make_unit(false, Vector2i(3, 2), 6.0)
	var duplicate_units: Array[TacticalCharacter] = [caster, duplicate_target]
	var duplicate_slow := AbilityDefinition.new()
	duplicate_slow.ability_type = AbilityDefinition.AbilityType.RANGED
	duplicate_slow.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	duplicate_slow.scaling_stat = UnitStat.Type.NONE
	duplicate_slow.status_effect = slow
	duplicate_slow.target_flags = AbilityDefinition.TargetFlags.ENEMY
	executor._apply_effects(caster, duplicate_target.grid_cell, duplicate_slow, duplicate_units, targeting, {})
	assert_eq(duplicate_target.get_active_statuses().size(), 1, "matching ability and weapon statuses should not duplicate")
	assert_eq(duplicate_target.get_active_statuses()[0].source, duplicate_slow, "the ability-owned copy should keep source precedence")
	var nested_target := _make_unit(false, Vector2i(3, 3), 6.0)
	var nested_units: Array[TacticalCharacter] = [caster, nested_target]
	var nested_slow := AbilityDefinition.new()
	nested_slow.ability_type = AbilityDefinition.AbilityType.RANGED
	nested_slow.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	nested_slow.scaling_stat = UnitStat.Type.NONE
	nested_slow.target_flags = AbilityDefinition.TargetFlags.ENEMY
	var apply_slow := ApplyStatusEffectDefinition.new()
	apply_slow.status_effect = slow
	var nested_effects: Array[AbilityEffectDefinition] = [apply_slow]
	nested_slow.effects = nested_effects
	executor._apply_effects(caster, nested_target.grid_cell, nested_slow, nested_units, targeting, {})
	assert_eq(nested_target.get_active_statuses().size(), 1, "matching Additional Effects and weapon statuses should not duplicate")
	assert_eq(nested_target.get_active_statuses()[0].source, nested_slow, "the Additional Effect copy should keep source precedence")

	var burning_target := _make_unit(false, Vector2i(4, 1), 6.0)
	var burning_units: Array[TacticalCharacter] = [caster, burning_target]
	var burning_shot := AbilityDefinition.new()
	burning_shot.ability_type = AbilityDefinition.AbilityType.RANGED
	burning_shot.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	burning_shot.scaling_stat = UnitStat.Type.NONE
	burning_shot.status_effect = load("res://resources/statuses/burning.tres") as StatusEffectDefinition
	burning_shot.target_flags = AbilityDefinition.TargetFlags.ENEMY
	executor._apply_effects(caster, burning_target.grid_cell, burning_shot, burning_units, targeting, {})
	var applied_ids: Dictionary = {}
	for active_status in burning_target.get_active_statuses():
		applied_ids[active_status.definition.status_id] = true
	assert_true(applied_ids.has(&"burning") and applied_ids.has(&"slow"), "different ability and weapon statuses should both apply")

	var legacy_target := _make_unit(false, Vector2i(4, 2), 6.0)
	var legacy_damage := DamageEffectScript.new() as DamageEffectDefinition
	legacy_damage.innate_damage = 1
	legacy_damage.scaling_stat = UnitStat.Type.NONE
	legacy_damage.apply(caster, legacy_target)
	assert_true(legacy_target.get_active_statuses().is_empty(), "standalone legacy damage should not trigger weapon statuses")
	var legacy_ability := AbilityDefinition.new()
	legacy_ability.ability_type = AbilityDefinition.AbilityType.RANGED
	legacy_ability.target_flags = AbilityDefinition.TargetFlags.ENEMY
	var legacy_effects: Array[AbilityEffectDefinition] = [legacy_damage]
	legacy_ability.effects = legacy_effects
	var ability_legacy_target := _make_unit(false, Vector2i(4, 3), 6.0)
	var legacy_units: Array[TacticalCharacter] = [caster, ability_legacy_target]
	executor._apply_effects(caster, ability_legacy_target.grid_cell, legacy_ability, legacy_units, targeting, {})
	assert_eq(ability_legacy_target.get_active_statuses()[0].definition, slow, "ability-owned legacy damage should trigger its weapon status")

	for ability_type in [AbilityDefinition.AbilityType.MAGIC, AbilityDefinition.AbilityType.MELEE]:
		var excluded_target := _make_unit(false, Vector2i(5, ability_type), 6.0)
		var excluded := AbilityDefinition.new()
		excluded.ability_type = ability_type
		excluded.effect = AbilityDefinition.PrimaryEffect.DAMAGE
		excluded.innate_damage = 5
		excluded.scaling_stat = UnitStat.Type.NONE
		excluded.target_flags = AbilityDefinition.TargetFlags.ENEMY
		var excluded_units: Array[TacticalCharacter] = [caster, excluded_target]
		executor._apply_effects(caster, excluded_target.grid_cell, excluded, excluded_units, targeting, {})
		assert_true(excluded_target.get_active_statuses().is_empty(), "Magic and mismatched Melee abilities should not apply Frost Bow Slow")

	var utility_target := _make_unit(false, Vector2i(5, 3), 6.0)
	var ranged_utility := AbilityDefinition.new()
	ranged_utility.ability_type = AbilityDefinition.AbilityType.RANGED
	ranged_utility.target_flags = AbilityDefinition.TargetFlags.ENEMY
	var utility_units: Array[TacticalCharacter] = [caster, utility_target]
	executor._apply_effects(caster, utility_target.grid_cell, ranged_utility, utility_units, targeting, {})
	assert_true(utility_target.get_active_statuses().is_empty(), "non-damaging weapon abilities should not apply weapon statuses")

	var unarmed_caster := _make_unit(true, Vector2i.ZERO, 6.0)
	var unarmed_target := _make_unit(false, Vector2i(1, 0), 6.0)
	var unarmed_units: Array[TacticalCharacter] = [unarmed_caster, unarmed_target]
	assert_false(volley.uses_weapon_damage(unarmed_caster), "a missing weapon should not count as weapon damage")
	executor._apply_effects(unarmed_caster, unarmed_target.grid_cell, volley, unarmed_units, targeting, {})
	assert_eq(unarmed_target.current_health, 100, "an unavailable weapon ability should not damage an unarmed target")
	assert_true(unarmed_target.get_active_statuses().is_empty(), "a missing weapon should not apply a weapon status")


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
	assert_eq(strike.effect, AbilityDefinition.PrimaryEffect.DAMAGE, "Strike should use the primary Damage effect")
	assert_eq(strike.damage_type, DamageCalculator.Type.PHYSICAL, "Strike should deal physical damage")
	assert_eq(strike.innate_damage, 0, "Strike should have zero innate damage")

	var caster := _make_unit(true, Vector2i(2, 2), 6.0)
	var melee_weapon := ItemDefinition.new()
	melee_weapon.weapon_type = ItemDefinition.WeaponType.MELEE
	caster.equip_item(melee_weapon)
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
	var melee_weapon := ItemDefinition.new()
	melee_weapon.weapon_type = ItemDefinition.WeaponType.MELEE
	caster.equip_item(melee_weapon)
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


func test_opportunity_attack_selection_reach_reaction_and_round_reset() -> void:
	var attacker := _make_unit(true, Vector2i(1, 1), 6.0, 12)
	var mover := _make_unit(false, Vector2i(2, 1), 6.0, 10)
	var ally := _make_unit(true, Vector2i(2, 1), 6.0, 10)
	var strike := load("res://resources/abilities/strike.tres") as AbilityDefinition
	var melee_utility := AbilityDefinitionScript.new() as AbilityDefinition
	melee_utility.ability_type = AbilityDefinition.AbilityType.MELEE
	melee_utility.target_flags = AbilityDefinition.TargetFlags.ENEMY
	var abilities: Array[AbilityDefinition] = [melee_utility, strike]
	attacker.definition.abilities = abilities
	var weapon := ItemDefinition.new()
	weapon.weapon_type = ItemDefinition.WeaponType.MELEE
	attacker.equip_item(weapon)
	attacker.reset_opportunity_reaction()

	assert_eq(
		OpportunityAttackSystemScript.get_opportunity_attack_ability(attacker),
		strike,
		"a unit should use its first compatible single-target damaging Melee ability"
	)
	assert_true(
		OpportunityAttackSystemScript.can_trigger(
			attacker,
			mover,
			Vector2i(2, 1),
			Vector2i(3, 1)
		),
		"leaving orthogonal melee reach should trigger an opportunity attack"
	)
	assert_false(
		OpportunityAttackSystemScript.can_trigger(
			attacker,
			mover,
			Vector2i(2, 1),
			Vector2i(2, 2)
		),
		"moving to another adjacent cell should remain inside melee reach"
	)
	assert_true(
		OpportunityAttackSystemScript.is_leaving_reach(
			attacker.grid_cell,
			Vector2i(2, 2),
			Vector2i(3, 3)
		),
		"leaving diagonal reach should trigger"
	)
	assert_false(
		OpportunityAttackSystemScript.is_leaving_reach(
			attacker.grid_cell,
			Vector2i(2, 2),
			Vector2i(3, 3),
			{Vector2i(2, 1): true}
		),
		"a blocked diagonal corner should not count as melee reach"
	)
	assert_false(
		OpportunityAttackSystemScript.can_trigger(
			attacker,
			ally,
			Vector2i(2, 1),
			Vector2i(3, 1)
		),
		"allies should never trigger opportunity attacks"
	)

	assert_true(attacker.spend_opportunity_reaction(), "an available reaction should be spendable")
	assert_false(
		OpportunityAttackSystemScript.can_trigger(
			attacker,
			mover,
			Vector2i(2, 1),
			Vector2i(3, 1)
		),
		"a spent reaction should not trigger again during the round"
	)
	attacker.reset_ability_action()
	attacker.spend_ability_action()
	attacker.reset_opportunity_reaction()
	assert_false(attacker.ability_available, "resetting a reaction must not restore the normal action")
	assert_true(
		OpportunityAttackSystemScript.can_trigger(
			attacker,
			mover,
			Vector2i(2, 1),
			Vector2i(3, 1)
		),
		"a spent normal ability action should not prevent the separate reaction"
	)
	attacker.current_health = 0
	assert_eq(
		OpportunityAttackSystemScript.get_opportunity_attack_ability(attacker),
		null,
		"defeated units should not provide opportunity attacks"
	)
	attacker.current_health = attacker.get_max_health()

	var manager := track(TurnManagerScript.new()) as TurnManager
	var combatants: Array[TacticalCharacter] = [attacker, mover]
	manager.start_combat(combatants)
	assert_true(attacker.opportunity_reaction_available, "combat round one should initialize reactions")
	attacker.spend_opportunity_reaction()
	manager.end_current_turn()
	manager.end_current_turn()
	assert_eq(manager.round_number, 2, "two living units should wrap into round two")
	assert_true(attacker.opportunity_reaction_available, "a new round should reset spent reactions")

	var enemy_slash := load("res://resources/abilities/enemy_slash.tres") as AbilityDefinition
	var goblin := _make_unit(false, Vector2i(4, 4), 5.0)
	var goblin_abilities: Array[AbilityDefinition] = [enemy_slash]
	goblin.definition.abilities = goblin_abilities
	var goblin_weapon := ItemDefinition.new()
	goblin_weapon.weapon_type = ItemDefinition.WeaponType.MELEE
	goblin.equip_item(goblin_weapon)
	assert_eq(
		OpportunityAttackSystemScript.get_opportunity_attack_ability(goblin),
		enemy_slash,
		"Goblin Warriors should use Enemy Slash without hard-coding Strike"
	)
	goblin.unequip_item(ItemDefinition.EquipmentSlot.WEAPON)
	assert_eq(
		OpportunityAttackSystemScript.get_opportunity_attack_ability(goblin),
		null,
		"a Melee ability without a compatible weapon should not provide a reaction attack"
	)


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
	damage.damage_type = DamageEffectDefinition.DamageType.MAGICAL
	damage.innate_damage = 30
	damage.scaling_stat = UnitStat.Type.NONE
	healing.amount = 10
	damage.apply(caster, target)
	healing.apply(caster, target)
	assert_eq(target.current_health, 80, "multiple effects should apply sequentially")
	target.apply_damage(1000)
	healing.apply(caster, target)
	assert_eq(target.current_health, 0, "ability healing should not revive defeated units")


func test_top_level_damage_executes_once_and_legacy_damage_remains_compatible() -> void:
	var caster := _make_unit(true, Vector2i.ZERO, 6.0)
	var target := _make_unit(false, Vector2i.ONE, 6.0)
	var ability := AbilityDefinitionScript.new() as AbilityDefinition
	ability.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	ability.damage_type = DamageCalculator.Type.MAGICAL
	ability.innate_damage = 10
	ability.scaling_stat = UnitStat.Type.NONE
	var legacy_damage := DamageEffectScript.new() as DamageEffectDefinition
	legacy_damage.damage_type = DamageEffectDefinition.DamageType.MAGICAL
	legacy_damage.innate_damage = 90
	legacy_damage.scaling_stat = UnitStat.Type.NONE
	var effects: Array[AbilityEffectDefinition] = [legacy_damage]
	ability.effects = effects
	var targeting := AbilityTargetingScript.new(Vector2i(4, 4))
	var executor := track(AbilityExecutorScript.new()) as AbilityExecutor
	var units: Array[TacticalCharacter] = [caster, target]
	executor._apply_effects(caster, target.grid_cell, ability, units, targeting, {})
	assert_eq(target.current_health, 90, "top-level damage should execute once and skip a nested legacy damage effect")

	target.current_health = 100
	ability.effect = AbilityDefinition.PrimaryEffect.NONE
	executor._apply_effects(caster, target.grid_cell, ability, units, targeting, {})
	assert_eq(target.current_health, 10, "legacy nested damage should still execute when top-level damage is disabled")


func test_ice_shard_damage_status_refresh_and_lethal_ordering() -> void:
	var caster := _make_unit(true, Vector2i.ZERO, 6.0)
	caster.intelligence_override = 12
	var target := _make_unit(false, Vector2i.ONE, 6.0)
	var ice_shard := load("res://resources/abilities/ice_shard.tres") as AbilityDefinition
	var targeting := AbilityTargetingScript.new(Vector2i(4, 4))
	var executor := track(AbilityExecutorScript.new()) as AbilityExecutor
	var units: Array[TacticalCharacter] = [caster, target]
	assert_eq(ice_shard.calculate_damage(caster), 27, "Ice Shard should deal 15 + 100% of Intelligence 12")
	executor._apply_effects(caster, target.grid_cell, ice_shard, units, targeting, {})
	assert_eq(target.current_health, 73, "Ice Shard execution should use its centralized 27 damage")
	assert_eq(target.get_active_statuses().size(), 1, "a surviving Ice Shard target should receive Slow")
	assert_eq(target.get_active_statuses()[0].source, ice_shard, "Ice Shard should be recorded as the status source")
	assert_eq(target.get_active_statuses()[0].source_unit, caster, "the Ice Shard caster should be recorded as the source unit")
	assert_true(is_equal_approx(target.get_movement_range(), 4.2), "Ice Shard's Slow should reduce movement to 4.2")
	target.get_active_statuses()[0].remaining_turns = 1
	executor._apply_effects(caster, target.grid_cell, ice_shard, units, targeting, {})
	assert_eq(target.get_active_statuses().size(), 1, "repeated Ice Shards should refresh rather than stack Slow")
	assert_eq(target.get_active_statuses()[0].remaining_turns, 2, "repeated Ice Shards should refresh Slow's full duration")

	var lethal_target := _make_unit(false, Vector2i(2, 1), 6.0)
	lethal_target.current_health = 27
	var lethal_units: Array[TacticalCharacter] = [caster, lethal_target]
	executor._apply_effects(caster, lethal_target.grid_cell, ice_shard, lethal_units, targeting, {})
	assert_eq(lethal_target.current_health, 0, "Ice Shard should defeat a target at 27 health")
	assert_true(lethal_target.get_active_statuses().is_empty(), "a target defeated by damage should not receive Slow")


func test_primary_heal_and_direct_slow_skip_only_matching_legacy_effects() -> void:
	var caster := _make_unit(true, Vector2i.ZERO, 6.0)
	var target := _make_unit(false, Vector2i.ONE, 6.0)
	var targeting := AbilityTargetingScript.new(Vector2i(4, 4))
	var executor := track(AbilityExecutorScript.new()) as AbilityExecutor
	var units: Array[TacticalCharacter] = [caster, target]

	var heal_ability := AbilityDefinitionScript.new() as AbilityDefinition
	heal_ability.effect = AbilityDefinition.PrimaryEffect.HEAL
	heal_ability.effect_amount = 10
	heal_ability.scaling_stat = UnitStat.Type.NONE
	var legacy_heal := HealEffectScript.new() as HealEffectDefinition
	legacy_heal.amount = 90
	var heal_effects: Array[AbilityEffectDefinition] = [legacy_heal]
	heal_ability.effects = heal_effects
	target.current_health = 50
	executor._apply_effects(caster, target.grid_cell, heal_ability, units, targeting, {})
	assert_eq(target.current_health, 60, "primary Heal should execute once and skip a nested legacy Heal")
	target.current_health = 50
	heal_ability.effect = AbilityDefinition.PrimaryEffect.NONE
	executor._apply_effects(caster, target.grid_cell, heal_ability, units, targeting, {})
	assert_eq(target.current_health, 100, "legacy nested Heal should remain active when the primary effect is None")

	var legacy_slow_status := StatusEffectDefinition.new()
	legacy_slow_status.status_id = &"slow"
	legacy_slow_status.display_name = "Legacy Slow"
	legacy_slow_status.duration_turns = 9
	var legacy_penalty := StatModifierDefinition.new()
	legacy_penalty.stat = UnitStat.Type.SPEED
	legacy_penalty.value = -9.0
	var legacy_modifiers: Array[StatModifierDefinition] = [legacy_penalty]
	legacy_slow_status.modifiers = legacy_modifiers
	var legacy_slow := ApplyStatusEffectDefinition.new()
	legacy_slow.status_effect = legacy_slow_status
	var slow_ability := AbilityDefinitionScript.new() as AbilityDefinition
	slow_ability.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	slow_ability.damage_type = DamageCalculator.Type.MAGICAL
	slow_ability.innate_damage = 1
	slow_ability.scaling_stat = UnitStat.Type.NONE
	slow_ability.status_effect = load("res://resources/statuses/slow.tres") as StatusEffectDefinition
	var unrelated_heal := HealEffectScript.new() as HealEffectDefinition
	unrelated_heal.amount = 1
	var slow_effects: Array[AbilityEffectDefinition] = [legacy_slow, unrelated_heal]
	slow_ability.effects = slow_effects
	executor._apply_effects(caster, target.grid_cell, slow_ability, units, targeting, {})
	assert_eq(target.current_health, 100, "an unrelated additional Heal should execute after damage and direct Slow")
	assert_eq(target.get_active_statuses().size(), 1, "direct Slow should create one stable status alongside damage")
	assert_eq(target.get_active_statuses()[0].remaining_turns, 2, "matching nested Slow should not replace the direct duration")
	assert_true(is_equal_approx(target.get_movement_range(), 4.2), "matching nested Slow should not replace the direct Movement Range penalty")
	assert_eq(target.get_initiative(), 10, "direct Slow should leave initiative unchanged")
	target.remove_status(&"slow")
	slow_ability.effect = AbilityDefinition.PrimaryEffect.NONE
	slow_ability.status_effect = null
	executor._apply_effects(caster, target.grid_cell, slow_ability, units, targeting, {})
	assert_eq(target.get_active_statuses()[0].remaining_turns, 9, "legacy nested Slow should remain active under None")
	assert_eq(target.get_initiative(), 1, "legacy nested Slow should preserve its own Speed penalty")


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
	assert_eq(entries.get_child_count(), 8, "the ability bar should create one button per configured ability")
	assert_true(entries.get_child(0).text.contains("32 DMG"), "damage buttons should show their caster-scaled total damage")
	assert_true(entries.get_child(1).text.contains("Requires a Ranged weapon"), "the Ability Bar summary should show the incompatible weapon reason")
	assert_true(entries.get_child(1).disabled, "Arrow should remain visible but disabled with a Melee weapon")
	assert_true(entries.get_child(1).tooltip_text.contains("7 physical damage"), "the disabled tooltip should retain the type-aware damage preview")
	assert_true(entries.get_child(1).tooltip_text.contains("Requires a Ranged weapon"), "disabled abilities should explain their weapon requirement")
	assert_false(entries.get_child(2).text.contains("DMG"), "non-damaging ability buttons should remain uncluttered")
	assert_true(entries.get_child(5).text.contains("27 DMG"), "Ice Shard should show its Intelligence-scaled damage")
	assert_true(entries.get_child(5).tooltip_text.contains("Slow"), "Ice Shard's tooltip should include its direct status")
	assert_false(entries.get_child(0).disabled, "ability buttons should be enabled while the action is available")
	assert_false(entries.get_child(4).disabled, "Strike should be enabled by the starting Melee sword")
	assert_true(entries.get_child(6).text.contains("32 DMG"), "Charge should show the shared Melee damage calculation")
	assert_false(entries.get_child(6).disabled, "Charge should be enabled by the starting Melee sword")
	assert_true(entries.get_child(6).tooltip_text.contains("Charges in a clear straight line"), "Charge's tooltip should explain caster movement")

	var ranger_bow := load("res://resources/items/ranger_bow.tres") as ItemDefinition
	unit.equip_item(ranger_bow)
	bar.rebuild(unit, true)
	assert_true(entries.get_child(1).text.contains("17 DMG"), "Arrow should include Ranger Bow damage after a compatible swap")
	assert_false(entries.get_child(1).disabled, "a Ranged weapon should enable Arrow")
	assert_true(entries.get_child(4).disabled, "a Ranged weapon should disable Strike")
	assert_true(entries.get_child(6).disabled, "a Ranged weapon should disable Charge")
	assert_true(entries.get_child(4).tooltip_text.contains("Requires a Melee weapon"), "Strike should explain its Melee requirement")
	unit.spend_ability_action()
	bar.rebuild(unit, true)
	assert_true(entries.get_child(0).disabled, "ability buttons should disable after the action is spent")

	var half_weapon := AbilityDefinition.new()
	half_weapon.display_name = "Half Weapon Shot"
	half_weapon.ability_type = AbilityDefinition.AbilityType.RANGED
	half_weapon.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	half_weapon.scaling_stat = DamageCalculator.ScalingSource.WEAPON
	half_weapon.scaling_amount = 50.0
	var half_weapon_definition := CharacterDefinitionScript.new() as CharacterDefinition
	var half_weapon_abilities: Array[AbilityDefinition] = [half_weapon]
	half_weapon_definition.abilities = half_weapon_abilities
	var half_weapon_unit := track(TacticalCharacterScript.new()) as TacticalCharacter
	half_weapon_unit.definition = half_weapon_definition
	half_weapon_unit._ready()
	half_weapon_unit.equip_item(load("res://resources/items/frost_bow.tres") as ItemDefinition)
	var half_weapon_bar = track(AbilityBarScene.instantiate())
	half_weapon_bar.rebuild(half_weapon_unit, true)
	var half_weapon_entries: HBoxContainer = half_weapon_bar.get_node("Margin/HBox")
	assert_true((half_weapon_entries.get_child(0) as Button).text.contains("5 DMG"), "the Ability Bar should display the centralized half-weapon total")
	assert_true((half_weapon_entries.get_child(0) as Button).tooltip_text.contains("weapon damage x50%"), "the Ability Bar tooltip should show the Weapon scaling formula")


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
	var scene := load("res://scenes/maps/terrain_showcase.tscn") as PackedScene
	var root: Node = track(scene.instantiate())
	var walls: Node = root.get_node("Walls")
	var cells: Array[Vector2i] = []
	for child in walls.get_children():
		assert_true(child is TacticalWall, "sample wall children should use the reusable TacticalWall type")
		cells.append((child as TacticalWall).grid_cell)
	assert_eq(cells, [Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6)], "the sample should include the planned three-cell barrier")


func _assert_primary_effect_fields(
	ability: AbilityDefinition,
	selected_effect: AbilityDefinition.PrimaryEffect,
	expected_visible: Array
) -> void:
	ability.effect = selected_effect
	var configurable_fields := [
		&"damage_type",
		&"innate_damage",
		&"effect_amount",
		&"scaling_stat",
		&"scaling_amount",
		&"status_effect",
	]
	var visible_fields: Dictionary = {}
	for property_info in ability.get_property_list():
		var property_name: StringName = property_info.name
		if property_name in configurable_fields and bool(property_info.usage & PROPERTY_USAGE_EDITOR):
			visible_fields[property_name] = true
	for property_name in configurable_fields:
		assert_eq(
			visible_fields.has(property_name),
			String(property_name) in expected_visible,
			"%s visibility should match primary effect %s" % [
				property_name,
				AbilityDefinition.PrimaryEffect.keys()[selected_effect],
			]
		)


func _assert_status_effect_fields(
	status: StatusEffectDefinition,
	selected_effect: StatusEffectDefinition.Effect,
	selected_value_type,
	expected_visible: Array
) -> void:
	status.effect = selected_effect
	if selected_value_type != null:
		status.modifier_value_type = selected_value_type
	var configurable_fields := [
		&"damage_type",
		&"damage_per_turn",
		&"affected_stat",
		&"modifier_direction",
		&"modifier_value_type",
		&"flat_amount",
		&"percentage_amount",
		&"affected_unit_ai_utility",
	]
	var visible_fields: Dictionary = {}
	for property_info in status.get_property_list():
		var property_name: StringName = property_info.name
		if bool(property_info.usage & PROPERTY_USAGE_EDITOR):
			visible_fields[property_name] = true
	for always_visible in [&"status_id", &"display_name", &"duration_turns", &"icon", &"color", &"modifiers"]:
		assert_true(visible_fields.has(always_visible), "%s should always remain visible in the Status Inspector" % always_visible)
	for property_name in configurable_fields:
		assert_eq(
			visible_fields.has(property_name),
			String(property_name) in expected_visible,
			"%s visibility should match status effect %s" % [
				property_name,
				StatusEffectDefinition.Effect.keys()[selected_effect],
			]
		)


func _has_editor_property(object: Object, property_name: StringName) -> bool:
	for property_info in object.get_property_list():
		if StringName(property_info.name) == property_name:
			return bool(property_info.usage & PROPERTY_USAGE_EDITOR)
	return false


func _get_editor_property_hint(object: Object, property_name: StringName) -> String:
	for property_info in object.get_property_list():
		if StringName(property_info.name) == property_name:
			return String(property_info.get("hint_string", ""))
	return ""


func _make_unit(friendly: bool, cell: Vector2i, movement: float, speed: int = 10) -> TacticalCharacter:
	var definition = CharacterDefinitionScript.new()
	definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	definition.constitution = 25
	definition.movement_range = movement
	var character = track(TacticalCharacterScript.new()) as TacticalCharacter
	character.definition = definition
	character.movement_range_override = movement - (float(speed) - 10.0) * 0.25
	character.speed_override = speed
	character.starting_grid_cell = cell
	character._ready()
	return character
