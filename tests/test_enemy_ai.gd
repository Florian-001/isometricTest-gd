@tool
extends McpTestSuite

const CharacterDefinitionScript = preload("res://scripts/unit_definition.gd")
const TacticalCharacterScript = preload("res://scripts/initiative_actor.gd")
const AbilityDefinitionScript = preload("res://scripts/ability_definition.gd")
const AbilityEffectScript = preload("res://scripts/ability_effect_definition.gd")
const DamageEffectScript = preload("res://scripts/damage_effect_definition.gd")
const HealEffectScript = preload("res://scripts/heal_effect_definition.gd")
const EnemyAIProfileScript = preload("res://scripts/enemy_ai_profile.gd")
const EnemyAIPlannerScript = preload("res://scripts/enemy_ai_planner.gd")
const GridPathfinderScript = preload("res://scripts/grid_pathfinder.gd")
const AbilityTargetingScript = preload("res://scripts/ability_targeting.gd")


func suite_name() -> String:
	return "enemy_ai"


func test_profile_defaults_resources_and_configuration_warnings() -> void:
	var profile := EnemyAIProfileScript.new() as EnemyAIProfile
	assert_eq(profile.lookahead_candidate_limit, 32, "AI profiles should default to a 32-plan beam")
	assert_true(is_equal_approx(profile.counterplay_discount, 0.75), "counterplay should be discounted by 0.75")
	assert_true(is_equal_approx(profile.damage_reward, 1.0), "damage should reward effective HP loss")
	assert_true(is_equal_approx(profile.healing_reward, 0.75), "healing should use its planned default weight")

	var melee_profile := load("res://resources/ai/melee_ai.tres") as EnemyAIProfile
	var ranged_profile := load("res://resources/ai/ranged_ai.tres") as EnemyAIProfile
	assert_eq(melee_profile.behavior_style, EnemyAIProfile.BehaviorStyle.MELEE, "melee template should be editable and typed")
	assert_eq(ranged_profile.behavior_style, EnemyAIProfile.BehaviorStyle.RANGED, "ranged template should be editable and typed")

	var enemy := _make_unit(false, Vector2i.ZERO, 4.0, [])
	assert_true(enemy._get_configuration_warnings().size() > 0, "an enemy without an AI profile should warn in the Inspector")
	enemy.enemy_ai_profile = melee_profile
	assert_true(enemy._get_configuration_warnings().is_empty(), "attaching a profile should resolve the enemy warning")
	var friendly := _make_unit(true, Vector2i.ONE, 4.0, [])
	friendly.enemy_ai_profile = melee_profile
	assert_true(friendly._get_configuration_warnings().size() > 0, "friendly units should warn that enemy AI is ignored")
	var bundled_definition := EnemyDefinition.new()
	bundled_definition.ai_profile = melee_profile
	var bundled_enemy := track(TacticalCharacterScript.new()) as TacticalCharacter
	bundled_enemy.definition = bundled_definition
	assert_true(bundled_enemy._get_configuration_warnings().is_empty(), "a bundled archetype AI should satisfy enemy configuration")
	bundled_definition.faction = CharacterDefinition.Faction.FRIENDLY
	assert_true(bundled_enemy._get_configuration_warnings().size() > 0, "warnings should also recognize a bundled AI on an incorrectly friendly archetype")


func test_effect_forecasts_clamp_health_and_support_custom_utility() -> void:
	var caster := _make_unit(false, Vector2i.ZERO, 4.0, [])
	var target := _make_unit(true, Vector2i.ONE, 4.0, [])
	var damage := DamageEffectScript.new() as DamageEffectDefinition
	damage.damage_type = DamageEffectDefinition.DamageType.MAGICAL
	damage.innate_damage = 30
	damage.scaling_stat = UnitStat.Type.NONE
	var damage_estimate := damage.estimate_for_ai(caster, target, 20)
	assert_eq(damage_estimate["health_delta"], -20, "forecast damage should clamp overkill")

	var healing := HealEffectScript.new() as HealEffectDefinition
	healing.amount = 25
	var heal_estimate := healing.estimate_for_ai(caster, caster, 90)
	assert_eq(heal_estimate["health_delta"], 10, "forecast healing should clamp to maximum health")

	var custom := AbilityEffectScript.new() as AbilityEffectDefinition
	custom.ai_utility_hint = 7.5
	var custom_estimate := custom.estimate_for_ai(caster, target, 100)
	assert_true(is_equal_approx(custom_estimate["utility_hint"], 7.5), "custom effects should expose editable AI utility")
	assert_eq(custom_estimate["health_delta"], 0, "unknown effects should not invent health changes")


func test_planner_forecasts_primary_heal_and_slow_from_the_ability_api() -> void:
	var caster := _make_unit(false, Vector2i.ZERO, 4.0, [])
	var ally := _make_unit(false, Vector2i(1, 0), 4.0, [])
	var opponent := _make_unit(true, Vector2i(0, 1), 4.0, [])
	ally.current_health = 50
	var units: Array[TacticalCharacter] = [caster, ally, opponent]
	var targeting := AbilityTargetingScript.new(Vector2i(4, 4)) as AbilityTargeting
	var planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
	var profile := _profile(EnemyAIProfile.BehaviorStyle.MELEE, 0.0)

	var heal := AbilityDefinitionScript.new() as AbilityDefinition
	heal.effect = AbilityDefinition.PrimaryEffect.HEAL
	heal.effect_amount = 25
	heal.scaling_stat = UnitStat.Type.NONE
	heal.target_flags = AbilityDefinition.TargetFlags.FRIEND
	var heal_snapshot := AIBoardSnapshot.from_battle(units, Vector2i(4, 4))
	var heal_score := planner._forecast_ability(
		caster,
		heal,
		ally.grid_cell,
		heal_snapshot,
		targeting,
		profile
	)
	assert_true(is_equal_approx(heal_score, 18.75), "planner healing score should use the primary Heal forecast")
	assert_eq(heal_snapshot.get_health(ally), 75, "planner simulation should apply the forecasted primary healing")

	var slow := AbilityDefinitionScript.new() as AbilityDefinition
	slow.effect = AbilityDefinition.PrimaryEffect.STATUS
	slow.status_effect = load("res://resources/statuses/slow.tres") as StatusEffectDefinition
	slow.target_flags = AbilityDefinition.TargetFlags.ENEMY
	var slow_snapshot := AIBoardSnapshot.from_battle(units, Vector2i(4, 4))
	var slow_score := planner._forecast_ability(
		caster,
		slow,
		opponent.grid_cell,
		slow_snapshot,
		targeting,
		profile
	)
	assert_true(is_equal_approx(slow_score, 8.0), "planner utility should use the primary Slow forecast")
	assert_eq(slow_snapshot.get_health(opponent), 100, "Slow forecasting should leave simulated health unchanged")

	caster.intelligence_override = 12
	var ice_shard := load("res://resources/abilities/ice_shard.tres") as AbilityDefinition
	var ice_snapshot := AIBoardSnapshot.from_battle(units, Vector2i(4, 4))
	var ice_score := planner._forecast_ability(
		caster,
		ice_shard,
		opponent.grid_cell,
		ice_snapshot,
		targeting,
		profile
	)
	assert_true(is_equal_approx(ice_score, 35.0), "Ice Shard AI value should combine 27 damage with Slow's utility 8")
	assert_eq(ice_snapshot.get_health(opponent), 73, "Ice Shard forecasting should apply the exact centralized damage")
	var lethal_estimate := ice_shard.estimate_primary_effect_for_ai(caster, opponent, 27)
	assert_eq(lethal_estimate.health_delta, -27, "lethal Ice Shard forecasting should clamp damage to remaining health")
	assert_true(is_zero_approx(lethal_estimate.utility_hint), "lethal damage should not forecast applying Slow afterward")


func test_virtual_origin_targeting_does_not_move_live_unit() -> void:
	var caster := _make_unit(false, Vector2i.ZERO, 4.0, [])
	var target := _make_unit(true, Vector2i(3, 0), 4.0, [])
	var ability := _make_damage_ability("Short Shot", AbilityDefinition.DeliveryType.PROJECTILE, 1.0, 10)
	var units: Array[TacticalCharacter] = [caster, target]
	var targeting := AbilityTargetingScript.new(Vector2i(6, 6)) as AbilityTargeting
	assert_false(targeting.is_valid_primary_target(caster, target.grid_cell, ability, units), "the live origin should remain out of range")
	assert_true(targeting.is_valid_primary_target_from(caster, Vector2i(2, 0), target.grid_cell, ability, units), "a hypothetical origin should be evaluated without mutation")
	assert_eq(caster.grid_cell, Vector2i.ZERO, "virtual targeting must not move the live caster")


func test_melee_profile_prioritizes_melee_when_adjacent() -> void:
	var slash := load("res://resources/abilities/enemy_slash.tres") as AbilityDefinition
	var shot := load("res://resources/abilities/enemy_shot.tres") as AbilityDefinition
	var profile := _profile(EnemyAIProfile.BehaviorStyle.MELEE, 0.0)
	var enemy := _make_unit(false, Vector2i(2, 2), 3.0, [slash, shot], profile)
	var target := _make_unit(true, Vector2i(3, 2), 3.0, [])
	var plan := _choose(enemy, [enemy, target], Vector2i(7, 7))
	assert_eq(plan.ability, slash, "adjacent melee AI should prefer its melee delivery")
	assert_true(plan.effect_score >= 30.0, "the chosen melee attack should forecast its damage")


func test_melee_profile_closes_and_uses_ranged_fallback() -> void:
	var slash := load("res://resources/abilities/enemy_slash.tres") as AbilityDefinition
	var shot := load("res://resources/abilities/enemy_shot.tres") as AbilityDefinition
	var profile := _profile(EnemyAIProfile.BehaviorStyle.MELEE, 0.0)
	var enemy := _make_unit(false, Vector2i(0, 2), 2.0, [slash, shot], profile)
	var target := _make_unit(true, Vector2i(6, 2), 3.0, [])
	var plan := _choose(enemy, [enemy, target], Vector2i(8, 6))
	assert_eq(plan.ability, shot, "melee AI should use a ranged ability when melee cannot be reached")
	assert_true(plan.get_end_cell(enemy.grid_cell).x > enemy.grid_cell.x, "the fallback shot should still end closer to the opponent")


func test_ranged_profile_shoots_and_retreats_to_standoff() -> void:
	var slash := load("res://resources/abilities/enemy_slash.tres") as AbilityDefinition
	var shot := load("res://resources/abilities/enemy_shot.tres") as AbilityDefinition
	var profile := _profile(EnemyAIProfile.BehaviorStyle.RANGED, 0.0)
	var enemy := _make_unit(false, Vector2i(3, 3), 3.0, [slash, shot], profile)
	var target := _make_unit(true, Vector2i(5, 3), 3.0, [])
	var plan := _choose(enemy, [enemy, target], Vector2i(10, 7))
	assert_eq(plan.ability, shot, "a ranged unit outside melee reach should use its ranged attack")
	assert_true(plan.sequence in [EnemyTurnPlan.Sequence.MOVE_CAST, EnemyTurnPlan.Sequence.CAST_MOVE, EnemyTurnPlan.Sequence.MOVE_CAST_MOVE], "a threatened ranged unit should combine its attack with repositioning")
	var final_distance := AbilityTargetingScript.new(Vector2i(10, 7)).get_weighted_distance(plan.get_end_cell(enemy.grid_cell), target.grid_cell)
	assert_true(final_distance >= 3.0, "the ranged profile should increase separation while retaining a shot")


func test_move_cast_move_candidates_respect_the_shared_budget() -> void:
	var shot := _make_damage_ability("Point Shot", AbilityDefinition.DeliveryType.PROJECTILE, 1.0, 20)
	var profile := _profile(EnemyAIProfile.BehaviorStyle.MELEE, 0.0)
	profile.lookahead_candidate_limit = 256
	profile.post_cast_position_limit = 8
	var enemy := _make_unit(false, Vector2i(0, 1), 2.0, [shot], profile)
	var target := _make_unit(true, Vector2i(2, 1), 0.0, [])
	var pathfinder := GridPathfinderScript.new(Vector2i(4, 3)) as GridPathfinder
	var targeting := AbilityTargetingScript.new(Vector2i(4, 3)) as AbilityTargeting
	var planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
	planner.choose_plan(enemy, _typed_units([enemy, target]), pathfinder, targeting)
	var found_split := false
	for candidate in planner.ranked_candidates:
		if candidate.sequence == EnemyTurnPlan.Sequence.MOVE_CAST_MOVE:
			found_split = true
			assert_true(candidate.movement_cost <= enemy.remaining_movement + GridPathfinder.COST_EPSILON, "split movement must share one exact budget")
	assert_true(found_split, "the tactical search should retain legal move-cast-move candidates")


func test_counterplay_forecast_chooses_safer_plan_without_mutation() -> void:
	var shot := _make_damage_ability("Long Shot", AbilityDefinition.DeliveryType.PROJECTILE, 4.0, 40)
	var counter := _make_damage_ability("Counter Strike", AbilityDefinition.DeliveryType.MELEE, 1.0, 100)
	var enemy := _make_unit(false, Vector2i(0, 1), 3.0, [shot])
	var target := _make_unit(true, Vector2i(4, 1), 0.0, [counter])
	var units: Array[TacticalCharacter] = [enemy, target]

	enemy.enemy_ai_profile = _profile(EnemyAIProfile.BehaviorStyle.MELEE, 0.0)
	var aggressive := _choose(enemy, units, Vector2i(6, 4))
	var aggressive_distance := AbilityTargetingScript.new(Vector2i(6, 4)).get_weighted_distance(aggressive.get_end_cell(enemy.grid_cell), target.grid_cell)

	enemy.enemy_ai_profile = _profile(EnemyAIProfile.BehaviorStyle.MELEE, 1.0)
	var cautious := _choose(enemy, units, Vector2i(6, 4))
	var cautious_distance := AbilityTargetingScript.new(Vector2i(6, 4)).get_weighted_distance(cautious.get_end_cell(enemy.grid_cell), target.grid_cell)
	assert_true(cautious_distance > aggressive_distance, "two-ply scoring should avoid an otherwise lethal adjacent counterattack")
	assert_true(cautious.score_breakdown.has("counterplay"), "counterplay should be represented in the score breakdown")
	assert_eq(enemy.grid_cell, Vector2i(0, 1), "planning must not mutate the enemy position")
	assert_eq(enemy.current_health, 100, "planning must not mutate live health")
	assert_eq(target.current_health, 100, "forecast damage must remain side-effect-free")


func test_walls_block_ai_ability_targeting() -> void:
	var shot := load("res://resources/abilities/enemy_shot.tres") as AbilityDefinition
	var profile := _profile(EnemyAIProfile.BehaviorStyle.RANGED, 0.0)
	var enemy := _make_unit(false, Vector2i.ZERO, 0.0, [shot], profile)
	var target := _make_unit(true, Vector2i(3, 0), 0.0, [])
	var pathfinder := GridPathfinderScript.new(Vector2i(5, 1)) as GridPathfinder
	var targeting := AbilityTargetingScript.new(Vector2i(5, 1)) as AbilityTargeting
	var planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
	var walls := {Vector2i(2, 0): true}
	var plan := planner.choose_plan(enemy, _typed_units([enemy, target]), pathfinder, targeting, walls)
	assert_eq(plan.ability, null, "AI should not select a projectile through a wall")


func test_reusable_enemy_archetypes_equipment_variants_and_scene_isolation() -> void:
	var ranger := _assert_enemy_definition(
		"res://resources/enemies/ranger.tres",
		"Ranger", 90, 6.0, [8, 14, 8, 12],
		EnemyAIProfile.BehaviorStyle.RANGED,
		["Ranger Bow", "Ranger Armor"],
		["Enemy Shot", "Focus"]
	)
	var warrior := _assert_enemy_definition(
		"res://resources/enemies/goblin_warrior.tres",
		"Goblin Warrior", 115, 5.0, [12, 8, 5, 9],
		EnemyAIProfile.BehaviorStyle.MELEE,
		["Goblin Sword"],
		["Enemy Slash"]
	)
	var archer := _assert_enemy_definition(
		"res://resources/enemies/goblin_archer.tres",
		"Goblin Archer", 75, 6.0, [7, 11, 6, 11],
		EnemyAIProfile.BehaviorStyle.RANGED,
		["Goblin Bow"],
		["Enemy Shot", "Slow"]
	)
	var wolf := _assert_enemy_definition(
		"res://resources/enemies/wolf.tres",
		"Wolf", 85, 7.0, [14, 10, 4, 14],
		EnemyAIProfile.BehaviorStyle.MELEE,
		[],
		["Strike"]
	)
	var mage := _assert_enemy_definition(
		"res://resources/enemies/mage.tres",
		"Mage", 70, 5.0, [5, 8, 15, 9],
		EnemyAIProfile.BehaviorStyle.RANGED,
		["Mage Staff"],
		["Fireball", "Ice Shard", "Heal", "Slow"]
	)
	var body_colors := {
		ranger.body_color: true,
		warrior.body_color: true,
		archer.body_color: true,
		wolf.body_color: true,
		mage.body_color: true,
	}
	assert_eq(body_colors.size(), 5, "every starter archetype should have a distinct body color")
	for definition in [ranger, warrior, archer, wolf, mage]:
		assert_eq(definition.health_bar_color, Color(0.96, 0.62, 0.18, 1), "%s should use the standard enemy health-bar color" % definition.display_name)

	var scene_expectations := {
		"res://scenes/enemies/ranger.tscn": "Ranger",
		"res://scenes/enemies/goblin_warrior.tscn": "Goblin Warrior",
		"res://scenes/enemies/goblin_warrior_club.tscn": "Goblin Warrior",
		"res://scenes/enemies/goblin_archer.tscn": "Goblin Archer",
		"res://scenes/enemies/wolf.tscn": "Wolf",
		"res://scenes/enemies/mage.tscn": "Mage",
	}
	for scene_path in scene_expectations:
		var enemy_scene := load(scene_path) as PackedScene
		assert_true(enemy_scene != null, "%s should be a reusable enemy scene" % scene_path)
		var enemy := track(enemy_scene.instantiate()) as TacticalCharacter
		assert_eq(enemy.definition.display_name, scene_expectations[scene_path], "thin scenes should reference their shared archetype")
		assert_eq(enemy.enemy_ai_profile, null, "thin scenes should inherit AI instead of duplicating it")
		assert_true(enemy.get_enemy_ai_profile() != null, "thin scenes should resolve their bundled AI")

	var sword_scene := load("res://scenes/enemies/goblin_warrior.tscn") as PackedScene
	var sword_goblin := track(sword_scene.instantiate()) as TacticalCharacter
	var second_sword_goblin := track(sword_scene.instantiate()) as TacticalCharacter
	sword_goblin._ready()
	second_sword_goblin._ready()
	assert_eq(sword_goblin.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON).display_name, "Goblin Sword", "the base Goblin Warrior should inherit its Sword")
	assert_eq(sword_goblin.get_weapon_damage(), 8, "Goblin Sword should provide 8 weapon damage")
	assert_true(is_equal_approx(sword_goblin.get_effective_stat(UnitStat.Type.STRENGTH), 13.0), "Goblin Sword should add one Strength")
	assert_eq(sword_goblin.get_abilities()[0].calculate_damage(sword_goblin), 34, "Sword Goblin Slash should deal 8 + 200% of Strength 13")
	assert_eq(sword_goblin.get_initiative(), 9, "Sword Goblin should keep Speed 9")
	sword_goblin.apply_damage(20)
	sword_goblin.unequip_item(ItemDefinition.EquipmentSlot.WEAPON)
	assert_eq(second_sword_goblin.current_health, 115, "repeated scene instances should have independent health")
	assert_eq(second_sword_goblin.get_weapon_damage(), 8, "runtime equipment changes should not affect another instance")
	assert_eq(sword_goblin.definition.starting_equipment[0].display_name, "Goblin Sword", "runtime changes should not mutate the shared definition")

	var club_scene := load("res://scenes/enemies/goblin_warrior_club.tscn") as PackedScene
	var club_goblin := track(club_scene.instantiate()) as TacticalCharacter
	club_goblin._ready()
	assert_eq(club_goblin.definition, second_sword_goblin.definition, "Sword and Club Goblins should share one archetype")
	assert_eq(club_goblin.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON).display_name, "Goblin Club", "the Club variant should replace only its inherited weapon")
	assert_eq(club_goblin.get_weapon_damage(), 12, "Goblin Club should provide 12 weapon damage")
	assert_eq(club_goblin.get_abilities()[0].calculate_damage(club_goblin), 36, "Club Goblin Slash should deal 12 + 200% of Strength 12")
	assert_eq(club_goblin.get_initiative(), 8, "Goblin Club should reduce Speed by one")

	var ranger_unit := track((load("res://scenes/enemies/ranger.tscn") as PackedScene).instantiate()) as TacticalCharacter
	ranger_unit._ready()
	assert_eq(ranger_unit.get_weapon_damage(), 10, "Ranger Bow should provide 10 weapon damage")
	assert_true(is_equal_approx(ranger_unit.get_effective_stat(UnitStat.Type.DEXTERITY), 16.0), "Ranger Armor should add two Dexterity")
	assert_eq(ranger_unit.get_abilities()[0].calculate_damage(ranger_unit), 26, "Ranger Shot should use Bow damage and equipped Dexterity")
	var archer_unit := track((load("res://scenes/enemies/goblin_archer.tscn") as PackedScene).instantiate()) as TacticalCharacter
	archer_unit._ready()
	assert_eq(archer_unit.get_weapon_damage(), 7, "Goblin Bow should provide 7 weapon damage")
	assert_true(is_equal_approx(archer_unit.get_effective_stat(UnitStat.Type.DEXTERITY), 12.0), "Goblin Bow should add one Dexterity")
	assert_eq(archer_unit.get_abilities()[0].calculate_damage(archer_unit), 19, "Goblin Archer Shot should use Bow damage and equipped Dexterity")
	var wolf_unit := track((load("res://scenes/enemies/wolf.tscn") as PackedScene).instantiate()) as TacticalCharacter
	wolf_unit._ready()
	assert_true(wolf_unit.get_equipped_items().is_empty(), "Wolf should start without equipment")
	assert_eq(wolf_unit.get_abilities()[0].calculate_damage(wolf_unit), 14, "Wolf Strike should scale from Strength without weapon damage")
	var mage_unit := track((load("res://scenes/enemies/mage.tscn") as PackedScene).instantiate()) as TacticalCharacter
	mage_unit._ready()
	assert_true(is_equal_approx(mage_unit.get_effective_stat(UnitStat.Type.INTELLIGENCE), 17.0), "Mage Staff should add two Intelligence")
	assert_eq(mage_unit.get_abilities()[0].calculate_damage(mage_unit), 37, "Mage Fireball should deal 20 plus effective Intelligence")
	assert_eq(mage_unit.get_abilities()[1].calculate_damage(mage_unit), 32, "Mage Ice Shard should deal 15 plus effective Intelligence")
	assert_eq(mage_unit.get_abilities()[2].calculate_primary_effect_amount(mage_unit), 42, "Mage Heal should restore 25 plus effective Intelligence")

	var ranger_variant := track(TacticalCharacterScript.new()) as TacticalCharacter
	ranger_variant.definition = ranger
	var club := load("res://resources/items/goblin_club.tres") as ItemDefinition
	var equipment_overrides: Array[ItemDefinition] = [club]
	ranger_variant.starting_equipment_overrides = equipment_overrides
	ranger_variant._ready()
	assert_eq(ranger_variant.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON), club, "an override should replace the inherited item in the same slot")
	assert_eq(ranger_variant.get_equipped_item(ItemDefinition.EquipmentSlot.ARMOR).display_name, "Ranger Armor", "an override should retain inherited items in other slots")
	assert_eq(ranger.starting_equipment[0].display_name, "Ranger Bow", "an instance override should leave the shared Ranger equipment unchanged")

	var explicit_ai := load("res://resources/ai/melee_ai.tres") as EnemyAIProfile
	ranger_variant.enemy_ai_profile = explicit_ai
	assert_eq(ranger_variant.get_enemy_ai_profile(), explicit_ai, "an explicit per-instance AI profile should override the bundled profile")
	var legacy := load("res://resources/enemy_raider.tres") as CharacterDefinition
	assert_true(legacy != null, "the legacy Enemy Raider resource should remain loadable")


func test_sample_scene_uses_goblin_archetypes_and_dev_history() -> void:
	var scene := ResourceLoader.load("res://main.tscn", "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var root: Node = track(scene.instantiate())
	var melee := root.get_node("Characters/MeleeEnemy") as TacticalCharacter
	var ranged := root.get_node("Characters/RangedEnemy") as TacticalCharacter
	assert_eq(melee.definition.display_name, "Goblin Warrior", "the sample melee enemy should use the Sword Goblin Warrior")
	assert_eq(ranged.definition.display_name, "Goblin Archer", "the sample ranged enemy should use the Goblin Archer")
	assert_eq(melee.enemy_ai_profile, null, "the sample melee enemy should inherit its bundled AI")
	assert_eq(ranged.enemy_ai_profile, null, "the sample ranged enemy should inherit its bundled AI")
	assert_eq(melee.get_enemy_ai_profile().behavior_style, EnemyAIProfile.BehaviorStyle.MELEE, "the sample melee enemy should resolve the bundled melee profile")
	assert_eq(ranged.get_enemy_ai_profile().behavior_style, EnemyAIProfile.BehaviorStyle.RANGED, "the sample ranged enemy should resolve the bundled ranged profile")
	assert_eq(melee.get_abilities().size(), 1, "the Goblin Warrior should expose only Enemy Slash")
	assert_eq(ranged.get_abilities().size(), 2, "the Goblin Archer should expose Enemy Shot and Slow")
	assert_eq(melee.starting_grid_cell, Vector2i(3, 8), "sample melee placement should stay unchanged")
	assert_eq(ranged.starting_grid_cell, Vector2i(9, 3), "sample ranged placement should match the design")
	assert_true(root.has_node("HUD/DevButton"), "the sample HUD should expose the Dev button")
	assert_eq(root.get_node("HUD/DevButton").text, "Dev", "the developer history button should have a clear compact label")
	assert_true(root.has_node("HUD/DevHistoryPanel"), "the sample HUD should contain an AI score history panel")
	assert_false(root.get_node("HUD/DevHistoryPanel").visible, "AI scores should stay off the battlefield until Dev is pressed")


func _assert_enemy_definition(
	path: String,
	expected_name: String,
	expected_health: int,
	expected_movement: float,
	expected_stats: Array,
	expected_style: EnemyAIProfile.BehaviorStyle,
	expected_items: Array,
	expected_abilities: Array
) -> EnemyDefinition:
	var definition := load(path) as EnemyDefinition
	assert_true(definition != null, "%s should load as an EnemyDefinition" % expected_name)
	assert_eq(definition.display_name, expected_name, "the archetype should keep its display name")
	assert_eq(definition.faction, CharacterDefinition.Faction.ENEMY, "%s should default to the Enemy faction" % expected_name)
	assert_eq(definition.max_health, expected_health, "%s should keep its configured HP" % expected_name)
	assert_true(is_equal_approx(definition.movement_range, expected_movement), "%s should keep its configured base movement" % expected_name)
	assert_eq([definition.strength, definition.dexterity, definition.intelligence, definition.speed], expected_stats, "%s should keep its configured core stats" % expected_name)
	assert_true(definition.ai_profile != null, "%s should bundle an AI profile" % expected_name)
	assert_eq(definition.ai_profile.behavior_style, expected_style, "%s should bundle the expected AI style" % expected_name)
	var item_names: Array[String] = []
	for item in definition.starting_equipment:
		item_names.append(item.display_name)
	assert_eq(item_names, expected_items, "%s should bundle the expected equipment" % expected_name)
	var ability_names: Array[String] = []
	for ability in definition.abilities:
		ability_names.append(ability.display_name)
	assert_eq(ability_names, expected_abilities, "%s should bundle the expected abilities" % expected_name)
	return definition


func test_enemy_controller_has_no_planning_or_preview_delays() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/initiative_battle_controller.gd")
	assert_false(source.contains("is planning..."), "enemy turns should not expose a planning phase")
	assert_false(source.contains("enemy_path_preview_delay"), "enemy path previews should not add an artificial delay")
	assert_false(source.contains("enemy_ability_preview_delay"), "enemy ability previews should not add an artificial delay")
	assert_false(source.contains("_show_enemy_ability_preview"), "enemy abilities should execute without a preview overlay")
	assert_true(source.contains("call_deferred(\"_finish_enemy_turn\", unit)"), "instant enemy turns should advance through a guarded deferred callback")


func _choose(
	actor: TacticalCharacter,
	units_value: Array,
	grid_size: Vector2i
) -> EnemyTurnPlan:
	var pathfinder := GridPathfinderScript.new(grid_size) as GridPathfinder
	var targeting := AbilityTargetingScript.new(grid_size) as AbilityTargeting
	var planner := EnemyAIPlannerScript.new() as EnemyAIPlanner
	return planner.choose_plan(actor, _typed_units(units_value), pathfinder, targeting)


func _profile(style: EnemyAIProfile.BehaviorStyle, counter_discount: float) -> EnemyAIProfile:
	var profile := EnemyAIProfileScript.new() as EnemyAIProfile
	profile.behavior_style = style
	profile.counterplay_discount = counter_discount
	return profile


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
	if not friendly:
		var weapon := ItemDefinition.new()
		weapon.weapon_damage = 10
		var equipment: Array[ItemDefinition] = [weapon]
		definition.starting_equipment = equipment
	var unit := track(TacticalCharacterScript.new()) as TacticalCharacter
	unit.definition = definition
	unit.enemy_ai_profile = profile
	unit.movement_range_override = movement
	unit.starting_grid_cell = cell
	unit._ready()
	unit.reset_movement()
	unit.reset_ability_action()
	return unit


func _make_damage_ability(
	name_value: String,
	delivery: AbilityDefinition.DeliveryType,
	range_value: float,
	amount: int
) -> AbilityDefinition:
	var ability := AbilityDefinitionScript.new() as AbilityDefinition
	ability.display_name = name_value
	ability.delivery_type = delivery
	ability.range = range_value
	ability.target_flags = AbilityDefinition.TargetFlags.ENEMY
	ability.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	ability.damage_type = DamageCalculator.Type.MAGICAL
	ability.innate_damage = amount
	ability.scaling_stat = UnitStat.Type.NONE
	return ability


func _typed_units(values: Array) -> Array[TacticalCharacter]:
	var result: Array[TacticalCharacter] = []
	for value in values:
		result.append(value as TacticalCharacter)
	return result
