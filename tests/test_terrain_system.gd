@tool
extends McpTestSuite

const GridPathfinderScript = preload("res://scripts/grid_pathfinder.gd")
const CharacterDefinitionScript = preload("res://scripts/unit_definition.gd")
const TacticalCharacterScript = preload("res://scripts/initiative_actor.gd")
const TileDefinitionScript = preload("res://scripts/tile_definition.gd")
const TileTriggeredEffectScript = preload("res://scripts/tile_triggered_effect_definition.gd")
const DamageEffectScript = preload("res://scripts/damage_effect_definition.gd")
const EnemyAIProfileScript = preload("res://scripts/enemy_ai_profile.gd")
const EnemyAIPlannerScript = preload("res://scripts/enemy_ai_planner.gd")
const AbilityTargetingScript = preload("res://scripts/ability_targeting.gd")
const AbilityDefinitionScript = preload("res://scripts/ability_definition.gd")


func suite_name() -> String:
	return "terrain_system"


func test_editable_mud_fire_and_palette_resources() -> void:
	var mud := load("res://resources/tiles/mud.tres") as TileDefinition
	var fire := load("res://resources/tiles/fire.tres") as TileDefinition
	var palette := load("res://resources/tiles/default_palette.tres") as TilePalette
	assert_eq(mud.display_name, "Mud", "the Mud template should be editable and named")
	assert_true(is_equal_approx(mud.movement_cost_multiplier, 2.0), "Mud should double entry cost")
	assert_eq(fire.display_name, "Fire", "the Fire template should be editable and named")
	assert_true(is_equal_approx(fire.movement_cost_multiplier, 1.0), "Fire should retain normal movement cost")
	assert_eq(fire.effects.size(), 1, "Fire should contain one reusable triggered effect")
	assert_true(
		fire.effects[0].applies_on(TileTriggeredEffectDefinition.Trigger.ENTER),
		"Fire should trigger on entry"
	)
	assert_true(
		fire.effects[0].applies_on(TileTriggeredEffectDefinition.Trigger.TURN_START),
		"Fire should trigger at turn start"
	)
	assert_eq(palette.tiles, [mud, fire], "the default painter palette should expose Mud and Fire")


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


func test_fire_applies_on_every_entry_and_turn_start_with_defeat_clamping() -> void:
	var fire := load("res://resources/tiles/fire.tres") as TileDefinition
	var unit := _make_unit(false, Vector2i.ZERO, 4.0, [])
	fire.apply_trigger(unit, TileTriggeredEffectDefinition.Trigger.ENTER)
	fire.apply_trigger(unit, TileTriggeredEffectDefinition.Trigger.ENTER)
	fire.apply_trigger(unit, TileTriggeredEffectDefinition.Trigger.TURN_START)
	assert_eq(unit.current_health, 97, "Fire should damage on every entry and again at turn start")
	unit.current_health = 1
	fire.apply_trigger(unit, TileTriggeredEffectDefinition.Trigger.ENTER)
	assert_eq(unit.current_health, 0, "Fire should clamp lethal damage at zero health")


func test_multiple_tile_effects_execute_in_order_and_stop_after_defeat() -> void:
	var first_damage := DamageEffectScript.new() as DamageEffectDefinition
	first_damage.amount = 2
	var second_damage := DamageEffectScript.new() as DamageEffectDefinition
	second_damage.amount = 5
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
	profile.counterplay_discount = 1.0
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
	var scene := load("res://main.tscn") as PackedScene
	var root := track(scene.instantiate())
	assert_true(root.has_node("Terrain"), "the battlefield should expose a TacticalTerrain container")
	var terrain := root.get_node("Terrain") as TacticalTerrain
	assert_eq(terrain.get_child_count(), 4, "the sample should include two Mud and two Fire tiles")
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
	profile.behavior_style = EnemyAIProfile.BehaviorStyle.MELEE
	profile.counterplay_discount = 0.0
	return profile


func _damage_ability(range_value: float, amount: int) -> AbilityDefinition:
	var ability := AbilityDefinitionScript.new() as AbilityDefinition
	ability.display_name = "Terrain Test Shot"
	ability.delivery_type = AbilityDefinition.DeliveryType.PROJECTILE
	ability.range = range_value
	ability.target_flags = AbilityDefinition.TargetFlags.ENEMY
	var damage := DamageEffectScript.new() as DamageEffectDefinition
	damage.amount = amount
	ability.effects = [damage]
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
	definition.max_health = 100
	definition.movement_range = movement
	var abilities: Array[AbilityDefinition] = []
	for ability in abilities_value:
		abilities.append(ability as AbilityDefinition)
	definition.abilities = abilities
	var unit := track(TacticalCharacterScript.new()) as TacticalCharacter
	unit.definition = definition
	unit.enemy_ai_profile = profile
	unit.movement_range = movement
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
