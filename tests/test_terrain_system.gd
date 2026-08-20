@tool
extends McpTestSuite

const GridPathfinderScript = preload("res://scripts/grid_pathfinder.gd")
const CharacterDefinitionScript = preload("res://scripts/unit_definition.gd")
const TacticalCharacterScript = preload("res://scripts/initiative_actor.gd")
const TileDefinitionScript = preload("res://scripts/tile_definition.gd")
const TileTriggeredEffectScript = preload("res://scripts/tile_triggered_effect_definition.gd")
const DamageEffectScript = preload("res://scripts/damage_effect_definition.gd")
const ApplyStatusEffectScript = preload("res://scripts/apply_status_effect_definition.gd")
const StatusCatalogScript = preload("res://addons/tile_painter/status_effect_catalog.gd")
const EnemyAIProfileScript = preload("res://scripts/enemy_ai_profile.gd")
const EnemyAIPlannerScript = preload("res://scripts/enemy_ai_planner.gd")
const AbilityTargetingScript = preload("res://scripts/ability_targeting.gd")
const AbilityDefinitionScript = preload("res://scripts/ability_definition.gd")


func suite_name() -> String:
	return "terrain_system"


func test_editable_mud_fire_ice_and_palette_resources() -> void:
	var mud := load("res://resources/tiles/mud.tres") as TileDefinition
	var fire := load("res://resources/tiles/fire.tres") as TileDefinition
	var ice := load("res://resources/tiles/ice.tres") as TileDefinition
	var palette := load("res://resources/tiles/default_palette.tres") as TilePalette
	assert_eq(mud.display_name, "Mud", "the Mud template should be editable and named")
	assert_true(is_equal_approx(mud.movement_cost_multiplier, 2.0), "Mud should double entry cost")
	assert_eq(fire.display_name, "Fire", "the Fire template should be editable and named")
	assert_true(is_equal_approx(fire.movement_cost_multiplier, 1.0), "Fire should retain normal movement cost")
	assert_eq(fire.effects.size(), 0, "Fire should use the direct status field")
	var burning := fire.status_effect
	assert_eq(burning.status_id, &"burning", "Fire should reference the Burning status")
	assert_eq(burning.effect, StatusEffectDefinition.Effect.DAMAGE_EACH_TURN, "Burning should deal damage each turn")
	assert_eq(burning.damage_per_turn, 1, "Burning damage should be editable in its Inspector resource")
	assert_eq(burning.duration_turns, 2, "Burning should last two processed turns")
	assert_true(
		fire.status_applies_on(TileTriggeredEffectDefinition.Trigger.ENTER),
		"Fire should trigger on entry"
	)
	assert_true(
		fire.status_applies_on(TileTriggeredEffectDefinition.Trigger.TURN_START),
		"Fire should trigger at turn start"
	)
	assert_eq(ice.display_name, "Ice", "the Ice template should be editable and named")
	assert_true(is_equal_approx(ice.movement_cost_multiplier, 2.0), "Ice should double entry cost")
	assert_eq(ice.status_effect.status_id, &"slow", "Ice should reference the reusable Slow status")
	assert_eq(
		ice.status_effect.affected_stat,
		UnitStat.Type.MOVEMENT_RANGE,
		"Ice's Slow should affect Movement Range"
	)
	assert_true(
		is_equal_approx(ice.status_effect.percentage_amount, 30.0),
		"Ice's Slow should reduce Movement Range by 30%"
	)
	assert_true(ice.status_applies_on(TileTriggeredEffectDefinition.Trigger.ENTER), "Ice should trigger on entry")
	assert_true(
		ice.status_applies_on(TileTriggeredEffectDefinition.Trigger.TURN_START),
		"Ice should trigger at turn start"
	)
	assert_true(
		ice.get_description().contains("Reduce Movement Range by 30%"),
		"tile descriptions should include the direct Slow status"
	)
	assert_eq(palette.tiles, [mud, fire, ice], "the default painter palette should expose Mud, Fire, and Ice")


func test_tile_status_inspector_defaults_visibility_and_catalog() -> void:
	var tile := TileDefinitionScript.new() as TileDefinition
	assert_eq(tile.status_effect, null, "new tiles should default to Status Effect None")
	assert_false(_tile_property_is_visible(tile, &"status_triggers"), "None should hide tile status triggers")
	assert_eq(
		tile.status_triggers,
		TileTriggeredEffectDefinition.Trigger.ENTER | TileTriggeredEffectDefinition.Trigger.TURN_START,
		"new direct statuses should default to both triggers"
	)
	tile.status_effect = load("res://resources/statuses/slow.tres") as StatusEffectDefinition
	assert_true(_tile_property_is_visible(tile, &"status_triggers"), "selecting a status should expose its triggers")
	var statuses := StatusCatalogScript.get_statuses()
	var names: Array[String] = []
	for status in statuses:
		names.append(status.display_name)
	assert_eq(names, ["Bleeding", "Burning", "Focus", "Slow", "Stun"], "saved status choices should be discovered recursively and sorted")
	for path in [
		"res://resources/statuses/bleeding.tres",
		"res://resources/statuses/burning.tres",
		"res://resources/statuses/focus.tres",
		"res://resources/statuses/slow.tres",
		"res://resources/statuses/stun.tres",
	]:
		assert_true(
			ResourceLoader.get_resource_uid(path) != ResourceUID.INVALID_ID,
			"%s should have a valid UID so Godot's standard resource picker can list it" % path
		)
	assert_eq(
		StatusCatalogScript.get_labels(statuses),
		["Bleeding", "Burning", "Focus", "Slow", "Stun"],
		"unique status choices should use their display names"
	)


func test_mud_costs_use_destination_and_choose_a_cheaper_route() -> void:
	var pathfinder := GridPathfinderScript.new(Vector2i(4, 3)) as GridPathfinder
	pathfinder.set_cell_cost_multipliers({Vector2i(1, 1): 2.0})
	assert_true(
		is_equal_approx(pathfinder.get_step_cost(Vector2i(0, 1), Vector2i(1, 1)), 2.0),
		"orthogonal entry into Mud should cost 2"
	)
	assert_true(
		is_equal_approx(pathfinder.get_step_cost(Vector2i(0, 0), Vector2i(1, 1)), 2.828),
		"diagonal entry into Mud should cost 2.828"
	)
	assert_true(
		is_equal_approx(pathfinder.get_step_cost(Vector2i(1, 1), Vector2i(2, 1)), 1.0),
		"leaving Mud for a normal destination should use normal cost"
	)
	var path := pathfinder.find_path(Vector2i(0, 1), Vector2i(2, 1), 2.828)
	assert_false(path.has(Vector2i(1, 1)), "the cheapest exact-budget path should route around Mud")
	assert_true(is_equal_approx(pathfinder.get_path_cost(path), 2.828), "the alternate path should use exact diagonal costs")
	assert_true(
		pathfinder.get_reachable(Vector2i(0, 1), 2.827).has(Vector2i(2, 1)) == false,
		"the destination should be unreachable immediately below its exact terrain-weighted cost"
	)


func test_fire_applies_refreshes_and_ticks_burning_for_two_turns() -> void:
	var fire := load("res://resources/tiles/fire.tres") as TileDefinition
	var unit := _make_unit(false, Vector2i.ZERO, 4.0, [])
	fire.apply_trigger(unit, TileTriggeredEffectDefinition.Trigger.ENTER)
	assert_eq(unit.current_health, 100, "entering Fire should apply Burning without immediate damage")
	assert_eq(unit.get_active_statuses().size(), 1, "entering Fire should add Burning")
	assert_eq(unit.get_active_statuses()[0].source, fire, "a tile-applied status should retain the Tile Definition as its source")
	assert_eq(unit.get_active_statuses()[0].source_unit, null, "terrain should not invent a source unit")
	unit.get_active_statuses()[0].remaining_turns = 1
	fire.apply_trigger(unit, TileTriggeredEffectDefinition.Trigger.ENTER)
	assert_eq(unit.get_active_statuses().size(), 1, "re-entering Fire should refresh rather than stack Burning")
	assert_eq(unit.get_active_statuses()[0].remaining_turns, 2, "Fire should refresh Burning to its full duration")
	unit.process_status_turn_start()
	assert_eq(unit.current_health, 99, "Burning should deal one damage at the first turn start")
	unit.advance_status_durations()
	assert_eq(unit.get_active_statuses()[0].remaining_turns, 1, "one processed turn should consume one duration")
	unit.process_status_turn_start()
	assert_eq(unit.current_health, 98, "Burning should deal one damage at the second turn start")
	unit.advance_status_durations()
	assert_true(unit.get_active_statuses().is_empty(), "Burning should expire after two processed turns")
	unit.current_health = 1
	fire.apply_trigger(unit, TileTriggeredEffectDefinition.Trigger.ENTER)
	unit.process_status_turn_start()
	assert_eq(unit.current_health, 0, "Fire should clamp lethal damage at zero health")


func test_ice_applies_refreshes_slow_and_forecasts_its_cost() -> void:
	var ice := load("res://resources/tiles/ice.tres") as TileDefinition
	var unit := _make_unit(false, Vector2i.ZERO, 6.0, [])
	ice.apply_trigger(unit, TileTriggeredEffectDefinition.Trigger.ENTER)
	assert_eq(unit.get_active_statuses().size(), 1, "entering Ice should apply one Slow status")
	assert_eq(unit.get_active_statuses()[0].source, ice, "Ice should be recorded as the status source")
	assert_eq(unit.get_active_statuses()[0].source_unit, null, "Ice should not invent a source unit")
	assert_true(is_equal_approx(unit.get_movement_range(), 4.2), "Ice should reduce movement from 6 to 4.2")
	unit.get_active_statuses()[0].remaining_turns = 1
	ice.apply_trigger(unit, TileTriggeredEffectDefinition.Trigger.TURN_START)
	assert_eq(unit.get_active_statuses().size(), 1, "Ice should refresh Slow instead of stacking it")
	assert_eq(unit.get_active_statuses()[0].remaining_turns, 2, "turn-start Ice should restore Slow's full duration")
	var estimate := ice.estimate_trigger(unit, TileTriggeredEffectDefinition.Trigger.ENTER, unit.current_health)
	assert_eq(estimate.health_delta, 0, "Ice should not forecast health damage")
	assert_true(is_equal_approx(estimate.utility_hint, -8.0), "Ice should expose Slow's terrain utility penalty to AI")
	var pathfinder := GridPathfinderScript.new(Vector2i(3, 3)) as GridPathfinder
	pathfinder.set_cell_cost_multipliers({Vector2i(1, 1): ice.movement_cost_multiplier})
	assert_true(
		is_equal_approx(pathfinder.get_step_cost(Vector2i(0, 1), Vector2i(1, 1)), 2.0),
		"AI path costs should include Ice's movement multiplier"
	)


func test_direct_status_skips_a_matching_additional_status() -> void:
	var slow := load("res://resources/statuses/slow.tres") as StatusEffectDefinition
	var legacy_slow := slow.duplicate(true) as StatusEffectDefinition
	legacy_slow.duration_turns = 9
	var apply_status := ApplyStatusEffectScript.new() as ApplyStatusEffectDefinition
	apply_status.status_effect = legacy_slow
	var triggered := TileTriggeredEffectScript.new() as TileTriggeredEffectDefinition
	triggered.effect = apply_status
	var tile := TileDefinitionScript.new() as TileDefinition
	tile.status_effect = slow
	tile.effects = [triggered]
	var unit := _make_unit(false, Vector2i.ZERO, 6.0, [])
	tile.apply_trigger(unit, TileTriggeredEffectDefinition.Trigger.ENTER)
	assert_eq(unit.get_active_statuses().size(), 1, "matching direct and nested statuses should not stack")
	assert_eq(
		unit.get_active_statuses()[0].remaining_turns,
		2,
		"the matching nested status should be skipped after the direct status"
	)


func test_multiple_tile_effects_execute_in_order_and_stop_after_defeat() -> void:
	var first_damage := DamageEffectScript.new() as DamageEffectDefinition
	first_damage.damage_type = DamageEffectDefinition.DamageType.MAGICAL
	first_damage.innate_damage = 2
	first_damage.scaling_stat = UnitStat.Type.NONE
	var second_damage := DamageEffectScript.new() as DamageEffectDefinition
	second_damage.damage_type = DamageEffectDefinition.DamageType.MAGICAL
	second_damage.innate_damage = 5
	second_damage.scaling_stat = UnitStat.Type.NONE
	var first_trigger := TileTriggeredEffectScript.new() as TileTriggeredEffectDefinition
	first_trigger.effect = first_damage
	var second_trigger := TileTriggeredEffectScript.new() as TileTriggeredEffectDefinition
	second_trigger.effect = second_damage
	var tile := TileDefinitionScript.new() as TileDefinition
	tile.effects = [first_trigger, second_trigger]
	var unit := _make_unit(false, Vector2i.ZERO, 4.0, [])
	unit.current_health = 2
	tile.apply_trigger(unit, TileTriggeredEffectDefinition.Trigger.ENTER)
	assert_eq(unit.current_health, 0, "the first lethal effect should defeat the occupant")
	assert_true(unit._defeat_emitted, "later effects should not revive or continue after defeat")


func test_ai_avoids_fire_when_safe_positioning_is_better() -> void:
	var profile := _profile()
	var actor := _make_unit(false, Vector2i(0, 1), 1.414, [], profile)
	var target := _make_unit(true, Vector2i(2, 1), 0.0, [])
	var fire := load("res://resources/tiles/fire.tres") as TileDefinition
	var terrain := {Vector2i(1, 1): fire}
	var plan := _choose(actor, [actor, target], Vector2i(4, 3), terrain)
	assert_false(
		plan.pre_cast_path.has(Vector2i(1, 1)),
		"AI should choose an equally useful safe route around Fire: %s" % plan.get_debug_summary()
	)
	assert_true(plan.terrain_score >= 0.0, "the selected safe route should not include terrain damage")


func test_ai_accepts_fire_when_the_attack_reward_is_greater() -> void:
	var shot := _damage_ability(1.0, 100)
	var profile := _profile()
	var actor := _make_unit(false, Vector2i(0, 0), 1.0, [shot], profile)
	var target := _make_unit(true, Vector2i(2, 0), 0.0, [])
	var fire := load("res://resources/tiles/fire.tres") as TileDefinition
	var terrain := {Vector2i(1, 0): fire}
	var plan := _choose(actor, [actor, target], Vector2i(3, 1), terrain)
	assert_eq(plan.ability, shot, "AI should cross Fire when doing so enables a decisive attack")
	assert_true(plan.pre_cast_path.has(Vector2i(1, 0)), "the rewarded plan should forecast the Fire entry")
	assert_true(plan.terrain_score < 0.0, "Fire damage should be visible in the selected plan score")


func test_lethal_fire_plan_is_rejected_when_holding_is_safer() -> void:
	var profile := _profile()
	var actor := _make_unit(false, Vector2i(0, 0), 2.0, [], profile)
	actor.current_health = 1
	var target := _make_unit(true, Vector2i(2, 0), 0.0, [])
	var fire := load("res://resources/tiles/fire.tres") as TileDefinition
	var plan := _choose(
		actor,
		[actor, target],
		Vector2i(3, 1),
		{Vector2i(1, 0): fire}
	)
	assert_eq(plan.sequence, EnemyTurnPlan.Sequence.HOLD, "AI should not enter lethal Fire for positioning alone")


func test_counterplay_forecast_applies_responder_turn_start_fire() -> void:
	var counter := _damage_ability(1.0, 20)
	var profile := _profile()
	profile.risk_aversion = 1.0
	var actor := _make_unit(false, Vector2i(0, 0), 0.0, [], profile)
	var responder := _make_unit(true, Vector2i(0, 1), 0.0, [counter])
	responder.current_health = 1
	var without_fire := _choose(actor, [actor, responder], Vector2i(1, 2), {})
	var fire := load("res://resources/tiles/fire.tres") as TileDefinition
	var with_fire := _choose(
		actor,
		[actor, responder],
		Vector2i(1, 2),
		{Vector2i(0, 1): fire}
	)
	assert_true(without_fire.counterplay_score > 0.0, "a living responder should forecast its counterattack")
	assert_true(
		is_zero_approx(with_fire.counterplay_score),
		"lethal turn-start Fire should remove the responder from counterplay"
	)


func test_sample_scene_and_tile_painter_are_configured() -> void:
	var scene := load("res://scenes/maps/terrain_showcase.tscn") as PackedScene
	var root := track(scene.instantiate())
	assert_true(root.has_node("Terrain"), "the battlefield should expose a TacticalTerrain container")
	var terrain := root.get_node("Terrain") as TacticalTerrain
	assert_eq(terrain.get_child_count(), 6, "the sample should include two Mud, two Fire, and two Ice tiles")
	assert_eq(
		(root.get_node("Terrain/Ice_8_4") as TacticalTile).grid_cell,
		Vector2i(8, 4),
		"the sample should place Ice at (8,4)"
	)
	assert_eq(
		(root.get_node("Terrain/Ice_9_4") as TacticalTile).grid_cell,
		Vector2i(9, 4),
		"the sample should place Ice at (9,4)"
	)
	assert_true(
		FileAccess.file_exists("res://addons/tile_painter/plugin.cfg"),
		"the editable Tile Paint plugin should be installed"
	)
	assert_true(
		load("res://addons/tile_painter/tile_painter_plugin.gd") != null,
		"the Tile Paint editor plugin should parse successfully"
	)
	var project_text := FileAccess.get_file_as_string("res://project.godot")
	assert_true(
		project_text.contains("res://addons/tile_painter/plugin.cfg"),
		"Tile Paint should be enabled for the Godot editor"
	)


func _choose(
	actor: TacticalCharacter,
	units_value: Array,
	grid_size: Vector2i,
	terrain: Dictionary
) -> EnemyTurnPlan:
	var pathfinder := GridPathfinderScript.new(grid_size) as GridPathfinder
	var costs: Dictionary = {}
	for cell: Vector2i in terrain:
		costs[cell] = (terrain[cell] as TileDefinition).movement_cost_multiplier
	pathfinder.set_cell_cost_multipliers(costs)
	var targeting := AbilityTargetingScript.new(grid_size) as AbilityTargeting
	var planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
	return planner.choose_plan(
		actor,
		_typed_units(units_value),
		pathfinder,
		targeting,
		{},
		terrain
	)


func _profile() -> EnemyAIProfile:
	var profile := EnemyAIProfileScript.new() as EnemyAIProfile
	profile.risk_aversion = 0.0
	return profile


func _damage_ability(range_value: float, amount: int) -> AbilityDefinition:
	var ability := AbilityDefinitionScript.new() as AbilityDefinition
	ability.display_name = "Terrain Test Shot"
	ability.delivery_type = AbilityDefinition.DeliveryType.PROJECTILE
	ability.range = range_value
	ability.target_flags = AbilityDefinition.TargetFlags.ENEMY
	ability.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	ability.damage_type = DamageCalculator.Type.MAGICAL
	ability.innate_damage = amount
	ability.scaling_stat = UnitStat.Type.NONE
	return ability


func _make_unit(
	friendly: bool,
	cell: Vector2i,
	movement: float,
	abilities_value: Array,
	profile: EnemyAIProfile = null
) -> TacticalCharacter:
	var definition := CharacterDefinitionScript.new() as CharacterDefinition
	definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	definition.constitution = 25
	definition.movement_range = movement
	var abilities: Array[AbilityDefinition] = []
	for ability in abilities_value:
		abilities.append(ability as AbilityDefinition)
	definition.abilities = abilities
	var unit := track(TacticalCharacterScript.new()) as TacticalCharacter
	unit.definition = definition
	unit.enemy_ai_profile = profile
	unit.movement_range_override = movement
	unit.starting_grid_cell = cell
	unit._ready()
	unit.reset_movement()
	unit.reset_ability_action()
	return unit


func _typed_units(values: Array) -> Array[TacticalCharacter]:
	var result: Array[TacticalCharacter] = []
	for value in values:
		result.append(value as TacticalCharacter)
	return result


func _tile_property_is_visible(tile: TileDefinition, property_name: StringName) -> bool:
	for property_info in tile.get_property_list():
		if property_info.name == property_name:
			return bool(property_info.usage & PROPERTY_USAGE_EDITOR)
	return false
