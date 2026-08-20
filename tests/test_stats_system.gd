@tool
extends McpTestSuite

const CharacterDefinitionScript = preload("res://scripts/unit_definition.gd")
const TacticalCharacterScript = preload("res://scripts/initiative_actor.gd")
const TurnManagerScript = preload("res://scripts/initiative_turn_manager.gd")
const StatModifierScript = preload("res://scripts/stat_modifier_definition.gd")
const ItemDefinitionScript = preload("res://scripts/item_definition.gd")
const StatusEffectScript = preload("res://scripts/status_effect_definition.gd")
const DamageEffectScript = preload("res://scripts/damage_effect_definition.gd")
const HealEffectScript = preload("res://scripts/heal_effect_definition.gd")


func suite_name() -> String:
	return "stats_system"


func test_equipment_modifier_order_replacement_and_shared_template_isolation() -> void:
	var definition := CharacterDefinitionScript.new() as CharacterDefinition
	var first := _make_unit(definition)
	var second := _make_unit(definition)
	var equipment_events := [0]
	var stats_events := [0]
	first.equipment_changed.connect(func(_slot, _item): equipment_events[0] += 1)
	first.stats_changed.connect(func(): stats_events[0] += 1)

	var flat := _make_modifier(
		UnitStat.Type.STRENGTH,
		StatModifierDefinition.Operation.FLAT,
		2.0
	)
	var percent_add := _make_modifier(
		UnitStat.Type.STRENGTH,
		StatModifierDefinition.Operation.PERCENT_ADD,
		0.5
	)
	var percent_multiply := _make_modifier(
		UnitStat.Type.STRENGTH,
		StatModifierDefinition.Operation.PERCENT_MULTIPLY,
		0.25
	)
	var sword := ItemDefinitionScript.new() as ItemDefinition
	sword.display_name = "Test Sword"
	sword.slot = ItemDefinition.EquipmentSlot.WEAPON
	var sword_modifiers: Array[StatModifierDefinition] = [flat, percent_add, percent_multiply]
	sword.modifiers = sword_modifiers

	assert_eq(first.equip_item(sword), null, "equipping an empty slot should not replace an item")
	assert_true(
		is_equal_approx(first.get_effective_stat(UnitStat.Type.STRENGTH), 22.5),
		"modifier order should be (10 + 2) x 1.5 x 1.25"
	)
	assert_true(
		is_equal_approx(second.get_effective_stat(UnitStat.Type.STRENGTH), 10.0),
		"runtime equipment must not mutate another unit sharing the template"
	)

	var replacement := ItemDefinitionScript.new() as ItemDefinition
	replacement.display_name = "Replacement Sword"
	replacement.slot = ItemDefinition.EquipmentSlot.WEAPON
	var replacement_modifiers: Array[StatModifierDefinition] = [
		_make_modifier(UnitStat.Type.STRENGTH, StatModifierDefinition.Operation.FLAT, 1.0)
	]
	replacement.modifiers = replacement_modifiers
	assert_eq(first.equip_item(replacement), sword, "equipping the same slot should return the replaced item")
	assert_true(is_equal_approx(first.get_effective_stat(UnitStat.Type.STRENGTH), 11.0), "replacement modifiers should take effect")
	assert_eq(first.unequip_item(ItemDefinition.EquipmentSlot.WEAPON), replacement, "unequip should return the removed item")
	assert_true(is_equal_approx(first.get_effective_stat(UnitStat.Type.STRENGTH), 10.0), "unequip should restore the base stat")
	assert_eq(equipment_events[0], 3, "equip, replace, and unequip should each emit equipment_changed")
	assert_eq(stats_events[0], 3, "every equipment change should emit stats_changed")


func test_effective_stats_without_equipment_keep_statuses_and_speed_movement_rules() -> void:
	var definition := CharacterDefinitionScript.new() as CharacterDefinition
	definition.movement_range = 6.0
	definition.strength = 10
	definition.speed = 10
	var unit := _make_unit(definition)
	var equipment := ItemDefinitionScript.new() as ItemDefinition
	var equipment_modifiers: Array[StatModifierDefinition] = [
		_make_modifier(UnitStat.Type.STRENGTH, StatModifierDefinition.Operation.FLAT, 2.0),
		_make_modifier(UnitStat.Type.SPEED, StatModifierDefinition.Operation.FLAT, -2.0),
	]
	equipment.modifiers = equipment_modifiers
	unit.equip_item(equipment)
	var status := _make_status(
		&"comparison_buff",
		2,
		[
			_make_modifier(UnitStat.Type.STRENGTH, StatModifierDefinition.Operation.FLAT, 3.0),
			_make_modifier(UnitStat.Type.SPEED, StatModifierDefinition.Operation.FLAT, 4.0),
		]
	)
	unit.apply_status(status, unit)

	assert_true(is_equal_approx(unit.get_effective_stat(UnitStat.Type.STRENGTH), 15.0), "live totals should include equipment and statuses")
	assert_true(is_equal_approx(unit.get_effective_stat_without_equipment(UnitStat.Type.STRENGTH), 13.0), "equipment-free totals should retain status Strength")
	assert_true(is_equal_approx(unit.get_effective_stat(UnitStat.Type.SPEED), 12.0), "live Speed should combine equipment and status modifiers")
	assert_true(is_equal_approx(unit.get_effective_stat_without_equipment(UnitStat.Type.SPEED), 14.0), "equipment-free Speed should remove only the item penalty")
	assert_true(is_equal_approx(unit.get_effective_stat(UnitStat.Type.MOVEMENT_RANGE), 6.5), "live Movement should use fully effective Speed")
	assert_true(is_equal_approx(unit.get_effective_stat_without_equipment(UnitStat.Type.MOVEMENT_RANGE), 7.0), "equipment-free Movement should recalculate from Speed without equipment")


func test_constitution_drives_health_modifiers_inspector_and_ai_snapshots() -> void:
	assert_eq(
		[
			UnitStat.Type.NONE,
			UnitStat.Type.STRENGTH,
			UnitStat.Type.DEXTERITY,
			UnitStat.Type.INTELLIGENCE,
			UnitStat.Type.SPEED,
			UnitStat.Type.MOVEMENT_RANGE,
		],
		[0, 1, 2, 3, 4, 5],
		"existing unit-stat serialization ids should remain unchanged"
	)
	assert_eq(UnitStat.Type.CONSTITUTION, 7, "Constitution should use the new serialization-safe stat id")
	assert_eq(DamageCalculator.ScalingSource.WEAPON, 6, "Weapon scaling must retain its serialized id")
	assert_eq(DamageCalculator.ScalingSource.CONSTITUTION, 7, "ability scaling should share Constitution's stat id")
	assert_eq(UnitStat.get_display_name(UnitStat.Type.CONSTITUTION), "Constitution", "Constitution should have an Inspector-facing name")
	assert_true(DamageCalculator.UNIT_STAT_SCALING_OPTIONS.contains("Constitution:7"), "ability scaling should expose Constitution")

	var definition := CharacterDefinitionScript.new() as CharacterDefinition
	definition.constitution = 25
	assert_eq(definition.max_health, 100, "definition Max Health should be Constitution x4")
	var constitution_property := _get_property_info(definition, &"constitution")
	var definition_health_property := _get_property_info(definition, &"max_health")
	assert_true(bool(int(constitution_property.usage) & PROPERTY_USAGE_EDITOR), "Constitution should be editable in the definition Inspector")
	assert_true(bool(int(constitution_property.usage) & PROPERTY_USAGE_STORAGE), "Constitution should be stored in resources")
	assert_true(bool(int(definition_health_property.usage) & PROPERTY_USAGE_EDITOR), "derived Max Health should remain visible in the definition Inspector")
	assert_true(bool(int(definition_health_property.usage) & PROPERTY_USAGE_READ_ONLY), "definition Max Health should be Inspector-read-only")
	assert_false(bool(int(definition_health_property.usage) & PROPERTY_USAGE_STORAGE), "derived Max Health should not be serialized")

	var unit := _make_unit(definition)
	assert_eq(unit.current_health, 100, "units should initialize at their Constitution-derived maximum")
	assert_eq(unit.get_max_health(), 100, "runtime Max Health should start from effective Constitution")
	var unit_health_property := _get_property_info(unit, &"max_health")
	assert_true(bool(int(unit_health_property.usage) & PROPERTY_USAGE_READ_ONLY), "unit Max Health should be Inspector-read-only")
	assert_false(bool(int(unit_health_property.usage) & PROPERTY_USAGE_STORAGE), "unit Max Health should not be serialized")
	assert_false(_get_property_info(unit, &"constitution_override").is_empty(), "units should expose Constitution Override")
	assert_true(_get_property_info(unit, &"max_health_override").is_empty(), "the legacy health override should be removed")

	var health_events: Array[Vector2i] = []
	var stat_events := [0]
	unit.health_changed.connect(func(current: int, maximum: int): health_events.append(Vector2i(current, maximum)))
	unit.stats_changed.connect(func(): stat_events[0] += 1)
	var constitution_item := ItemDefinitionScript.new() as ItemDefinition
	constitution_item.modifiers = [
		_make_modifier(UnitStat.Type.CONSTITUTION, StatModifierDefinition.Operation.FLAT, 5.0),
		_make_modifier(UnitStat.Type.CONSTITUTION, StatModifierDefinition.Operation.PERCENT_ADD, 0.2),
		_make_modifier(UnitStat.Type.CONSTITUTION, StatModifierDefinition.Operation.PERCENT_MULTIPLY, 0.5),
	]
	unit.equip_item(constitution_item)
	assert_true(is_equal_approx(unit.get_effective_stat(UnitStat.Type.CONSTITUTION), 54.0), "Constitution should use the shared flat/additive/multiplicative order")
	assert_eq(unit.get_max_health(), 216, "fractional stat operations should round only after multiplying Constitution by four")
	assert_eq(unit.current_health, 100, "raising Max Health should not grant current HP")
	assert_eq(health_events[-1], Vector2i(100, 216), "Max Health changes should emit health_changed")

	var crushing_item := ItemDefinitionScript.new() as ItemDefinition
	crushing_item.modifiers = [
		_make_modifier(UnitStat.Type.CONSTITUTION, StatModifierDefinition.Operation.FLAT, -100.0)
	]
	unit.equip_item(crushing_item)
	assert_eq(unit.get_effective_stat(UnitStat.Type.CONSTITUTION), 0.0, "the generic effective stat should retain its zero floor")
	assert_eq(unit.get_max_health(), 4, "Max Health should use a minimum effective Constitution of one")
	assert_eq(unit.current_health, 4, "lowering Max Health should clamp current HP")
	unit.unequip_item(ItemDefinition.EquipmentSlot.WEAPON)
	assert_eq(unit.get_max_health(), 100, "removing a Constitution penalty should restore Max Health")
	assert_eq(unit.current_health, 4, "restoring Max Health should not restore current HP")
	assert_eq(stat_events[0], 3, "each Constitution equipment change should emit stats_changed")

	var status_unit := _make_unit(definition)
	var constitution_penalty := _make_status(
		&"frail",
		2,
		[_make_modifier(UnitStat.Type.CONSTITUTION, StatModifierDefinition.Operation.FLAT, -10.0)]
	)
	assert_true(status_unit.apply_status(constitution_penalty, status_unit), "living units should accept Constitution statuses")
	assert_eq(status_unit.get_max_health(), 60, "Constitution status penalties should reduce Max Health")
	assert_eq(status_unit.current_health, 60, "Constitution status penalties should clamp current HP")
	status_unit.remove_status(&"frail")
	assert_eq(status_unit.get_max_health(), 100, "removing a Constitution status should restore Max Health")
	assert_eq(status_unit.current_health, 60, "removing the status should not heal the previous clamp")

	var scaling_amount := DamageCalculator.calculate_amount(
		status_unit,
		DamageCalculator.Type.MAGICAL,
		0,
		DamageCalculator.ScalingSource.CONSTITUTION,
		100.0,
		DamageCalculator.NO_WEAPON_REQUIRED
	)
	assert_eq(scaling_amount, 25, "abilities should be able to scale from effective Constitution")
	status_unit.current_health = 100
	var snapshot := AIBoardSnapshot.from_battle([status_unit], Vector2i(4, 4))
	var forecast := snapshot.forecast_status_application(status_unit, status_unit, constitution_penalty)
	assert_eq(snapshot.get_max_health(status_unit), 60, "AI snapshots should simulate Constitution-derived Max Health")
	assert_eq(forecast.health_delta, -40, "AI forecasts should report HP clamped by a Constitution penalty")


func test_status_refresh_stacking_expiration_removal_and_dead_rejection() -> void:
	var unit := _make_unit(CharacterDefinitionScript.new())
	var focus := _make_status(
		&"focus",
		2,
		[_make_modifier(UnitStat.Type.STRENGTH, StatModifierDefinition.Operation.FLAT, 2.0)]
	)
	var blessing := _make_status(
		&"blessing",
		3,
		[_make_modifier(UnitStat.Type.STRENGTH, StatModifierDefinition.Operation.FLAT, 3.0)]
	)
	var status_events := [0]
	unit.statuses_changed.connect(func(): status_events[0] += 1)

	assert_true(unit.apply_status(focus, unit), "a living unit should accept a configured status")
	assert_eq(unit.get_active_statuses().size(), 1, "first application should create one runtime status")
	assert_eq(unit.get_active_statuses()[0].source, unit, "direct status application should retain its source object")
	assert_eq(unit.get_active_statuses()[0].source_unit, unit, "a unit source should be inferred as the source unit")
	var one_icon := unit._get_status_icon_entries()
	assert_eq(one_icon.size(), 1, "one active status should create one health-bar icon entry")
	assert_true(
		(one_icon[0].rect as Rect2).end.y < -57.0,
		"status icons should sit above the health bar"
	)
	assert_true(
		is_zero_approx((one_icon[0].rect as Rect2).get_center().x),
		"a single status icon should be centered over the unit"
	)
	assert_true(is_equal_approx(unit.get_effective_stat(UnitStat.Type.STRENGTH), 12.0), "Focus should modify effective Strength")
	unit.process_status_turn_start()
	unit.advance_status_durations()
	assert_eq(unit.get_active_statuses()[0].remaining_turns, 1, "the owner turn end should decrement duration")
	assert_true(unit.apply_status(focus, unit), "reapplying Focus should succeed")
	assert_eq(unit.get_active_statuses().size(), 1, "the same status id should refresh rather than stack")
	assert_eq(unit.get_active_statuses()[0].remaining_turns, 2, "refresh should restore the full duration")

	assert_true(unit.apply_status(blessing, unit), "a different status id should stack")
	assert_eq(unit.get_active_statuses().size(), 2, "different status ids should coexist")
	var two_icons := unit._get_status_icon_entries()
	assert_eq(two_icons.size(), 2, "different active statuses should each receive an icon entry")
	assert_true(
		is_zero_approx(
			(two_icons[0].rect as Rect2).get_center().x
			+ (two_icons[1].rect as Rect2).get_center().x
		),
		"multiple status icons should remain centered as a row"
	)
	assert_true(is_equal_approx(unit.get_effective_stat(UnitStat.Type.STRENGTH), 15.0), "different statuses should combine")
	assert_true(unit.remove_status(&"blessing"), "explicit status removal should report success")
	assert_false(unit.remove_status(&"missing"), "removing an absent status should report failure")
	unit.process_status_turn_start()
	unit.advance_status_durations()
	unit.process_status_turn_start()
	unit.advance_status_durations()
	assert_true(unit.get_active_statuses().is_empty(), "Focus should expire after two owner turn endings")
	assert_true(unit._get_status_icon_entries().is_empty(), "expired statuses should disappear from the icon row")
	assert_true(is_equal_approx(unit.get_effective_stat(UnitStat.Type.STRENGTH), 10.0), "expiration should restore the base stat")
	assert_true(status_events[0] >= 6, "application, refresh, duration changes, removal, and expiry should notify observers")

	unit.apply_damage(1000)
	assert_false(unit.apply_status(focus, unit), "defeated units should reject new statuses")


func test_central_physical_magical_damage_scaling_descriptions_and_ai_forecasts() -> void:
	var caster := _make_unit(CharacterDefinitionScript.new())
	var target := _make_unit(CharacterDefinitionScript.new())
	var strength_buff := _make_modifier(
		UnitStat.Type.STRENGTH,
		StatModifierDefinition.Operation.FLAT,
		2.0
	)
	var weapon := ItemDefinitionScript.new() as ItemDefinition
	weapon.weapon_damage = 10
	var weapon_modifiers: Array[StatModifierDefinition] = [strength_buff]
	weapon.modifiers = weapon_modifiers
	caster.strength_override = 14
	caster.equip_item(weapon)

	var physical := AbilityDefinition.new()
	physical.ability_type = AbilityDefinition.AbilityType.MELEE
	physical.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	physical.innate_damage = 5
	physical.scaling_stat = UnitStat.Type.STRENGTH
	physical.scaling_amount = 150.0
	assert_eq(physical.calculate_damage(caster), 39, "physical damage should be innate 5 + weapon 10 + 150% of buffed Strength 16")
	assert_true(physical.get_description(caster).contains("39 physical damage"), "the tooltip should show centralized physical damage")
	assert_true(physical.get_description(caster).contains("Strength x150%"), "the tooltip should show the configured scaling")

	var weapon_scaled := AbilityDefinition.new()
	weapon_scaled.ability_type = AbilityDefinition.AbilityType.MELEE
	weapon_scaled.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	weapon_scaled.innate_damage = 5
	weapon_scaled.scaling_stat = DamageCalculator.ScalingSource.WEAPON
	weapon_scaled.scaling_amount = 50.0
	assert_eq(weapon_scaled.calculate_damage(caster), 10, "50% Weapon scaling should add only 5 of a 10-damage weapon, not the automatic full weapon term")
	assert_true(weapon_scaled.get_description(caster).contains("weapon damage x50%"), "damage descriptions should expose the selected Weapon percentage")
	var weapon_estimate := weapon_scaled.estimate_primary_effect_for_ai(caster, target, target.current_health)
	assert_eq(weapon_estimate["health_delta"], -10, "AI forecasting should use the same Weapon-scaled amount")
	weapon_scaled.scaling_amount = 150.0
	assert_eq(weapon_scaled.calculate_damage(caster), 20, "Weapon scaling above 100% should multiply the weapon without adding another full copy")
	weapon.weapon_damage = 7
	weapon_scaled.scaling_amount = 50.0
	assert_eq(weapon_scaled.calculate_damage(caster), roundi(5.0 + 7.0 * 0.5), "Weapon percentage results should retain nearest-integer rounding")
	weapon.weapon_damage = 10

	var ranged_weapon := ItemDefinitionScript.new() as ItemDefinition
	ranged_weapon.weapon_type = ItemDefinition.WeaponType.RANGED
	ranged_weapon.weapon_damage = 12
	caster.equip_item(ranged_weapon)
	assert_false(weapon_scaled.can_be_used_by(caster), "a mismatched weapon should leave a Weapon-scaled ability unavailable")
	assert_eq(weapon_scaled.calculate_damage(caster), 5, "a mismatched weapon should contribute zero to Weapon scaling")
	caster.equip_item(weapon)

	weapon_scaled.scaling_stat = DamageCalculator.ScalingSource.WEAPON
	weapon_scaled.ability_type = AbilityDefinition.AbilityType.MAGIC
	assert_eq(weapon_scaled.scaling_stat, DamageCalculator.ScalingSource.NONE, "changing a Weapon-scaled ability to Magic should reset scaling to None")
	assert_eq(weapon_scaled.calculate_damage(caster), 5, "Magic abilities should never use equipped weapon damage")

	var damage := AbilityDefinition.new()
	damage.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	damage.damage_type = DamageCalculator.Type.MAGICAL
	damage.innate_damage = 30
	damage.scaling_stat = UnitStat.Type.INTELLIGENCE
	damage.scaling_amount = 150.0
	caster.intelligence_override = 14
	assert_eq(damage.calculate_damage(caster), 51, "magical damage should be innate 30 + 150% of Intelligence 14")
	assert_true(damage.get_description(caster).contains("51 magical damage"), "the caster tooltip should show centralized magical damage")
	assert_true(damage.get_description(caster).contains("Intelligence x150%"), "the tooltip should name magical scaling")
	var legacy_damage := DamageEffectScript.new() as DamageEffectDefinition
	legacy_damage.damage_type = DamageEffectDefinition.DamageType.MAGICAL
	legacy_damage.innate_damage = 30
	legacy_damage.scaling_stat = UnitStat.Type.INTELLIGENCE
	legacy_damage.scaling_percentage = 150.0
	assert_eq(legacy_damage.calculate_amount(caster), damage.calculate_damage(caster), "legacy effects and direct abilities should share one calculator")
	var estimate := legacy_damage.estimate_for_ai(caster, target, 20)
	assert_eq(estimate["health_delta"], -20, "AI forecast should use scaled damage and clamp overkill")
	legacy_damage.apply(caster, target)
	assert_eq(target.current_health, 49, "applied damage should use the same centralized amount as forecasting")

	var healing := AbilityDefinition.new()
	healing.effect = AbilityDefinition.PrimaryEffect.HEAL
	healing.effect_amount = 25
	healing.scaling_stat = UnitStat.Type.INTELLIGENCE
	healing.scaling_amount = 150.0
	caster.intelligence_override = 14
	target.current_health = 50
	assert_eq(healing.calculate_primary_effect_amount(caster), 46, "healing should be base 25 + 150% of effective Intelligence 14")
	assert_true(healing.get_description(caster).contains("46 healing"), "the tooltip should use the centralized healing amount")
	assert_true(healing.get_description(caster).contains("Intelligence x150%"), "the tooltip should show healing scaling")
	var heal_estimate := healing.estimate_primary_effect_for_ai(caster, target, target.current_health)
	assert_eq(heal_estimate["health_delta"], 46, "AI forecast should include full effective-stat healing")
	healing.apply_primary_effect(caster, target)
	assert_eq(target.current_health, 96, "applied healing should match the forecast")
	healing.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	healing.ability_type = AbilityDefinition.AbilityType.MELEE
	healing.scaling_stat = DamageCalculator.ScalingSource.WEAPON
	healing.effect = AbilityDefinition.PrimaryEffect.HEAL
	assert_eq(healing.scaling_stat, DamageCalculator.ScalingSource.NONE, "changing a Weapon-scaled ability to Heal should reset scaling to None")
	assert_eq(healing.calculate_primary_effect_amount(caster), 25, "Heal should ignore invalid Weapon scaling and retain only its base amount")

	var slow_status := load("res://resources/statuses/slow.tres") as StatusEffectDefinition
	var slow := AbilityDefinition.new()
	slow.effect = AbilityDefinition.PrimaryEffect.STATUS
	slow.status_effect = slow_status
	assert_true(slow.get_description(caster).contains("Reduce Movement Range by 30%"), "the tooltip should describe the reusable Slow status")
	var slow_estimate := slow.estimate_primary_effect_for_ai(caster, target, target.current_health)
	assert_eq(slow_estimate["health_delta"], 0, "Slow forecasting should not invent a health change")
	assert_true(is_equal_approx(slow_estimate["utility_hint"], -8.0), "a harmful status should be negative from an allied target's perspective")
	slow.apply_primary_effect(caster, target)
	assert_eq(target.get_active_statuses().size(), 1, "primary Slow should create one status")
	assert_eq(target.get_active_statuses()[0].source, slow, "an ability-applied status should retain the ability as its source")
	assert_eq(target.get_active_statuses()[0].source_unit, caster, "an ability-applied status should retain its caster")
	assert_true(is_equal_approx(target.get_movement_range(), 4.2), "Slow should reduce final Movement Range by 30%")
	assert_true(is_equal_approx(target.get_effective_stat(UnitStat.Type.SPEED), 10.0), "Slow should not change Speed")
	assert_eq(target.get_initiative(), 10, "Slow should not change initiative")
	target.process_status_turn_start()
	target.advance_status_durations()
	slow.apply_primary_effect(caster, target)
	assert_eq(target.get_active_statuses().size(), 1, "reapplying primary Slow should refresh instead of stacking")
	assert_eq(target.get_active_statuses()[0].remaining_turns, 2, "refreshing primary Slow should restore its duration")
	target.advance_status_durations()
	assert_eq(target.get_active_statuses()[0].remaining_turns, 2, "a refreshed mid-turn status should not immediately lose duration")
	target.process_status_turn_start()
	target.advance_status_durations()
	target.process_status_turn_start()
	target.advance_status_durations()
	assert_true(target.get_active_statuses().is_empty(), "primary Slow should expire after its configured duration")
	assert_true(is_equal_approx(target.get_movement_range(), 6.0), "Slow expiration should restore Movement Range")

	var burning := load("res://resources/statuses/burning.tres") as StatusEffectDefinition
	var burning_ability := AbilityDefinition.new()
	burning_ability.effect = AbilityDefinition.PrimaryEffect.STATUS
	burning_ability.status_effect = burning
	target.current_health = 100
	var burning_estimate := burning_ability.estimate_primary_effect_for_ai(caster, target, 100)
	assert_eq(burning_estimate["health_delta"], -2, "Burning should forecast its two fixed future damage ticks")
	burning_ability.apply_primary_effect(caster, target)
	target.process_status_turn_start()
	assert_eq(target.current_health, 99, "status damage should ignore the caster's weapon and stats")

	var bleeding := load("res://resources/statuses/bleeding.tres") as StatusEffectDefinition
	assert_eq(bleeding.status_id, &"bleeding", "Bleeding should expose its stable status id")
	assert_eq(bleeding.display_name, "Bleeding", "Bleeding should expose its display name")
	assert_eq(bleeding.effect, StatusEffectDefinition.Effect.DAMAGE_EACH_TURN, "Bleeding should deal damage each turn")
	assert_eq(bleeding.damage_type, DamageCalculator.Type.PHYSICAL, "Bleeding should be classified as Physical damage")
	assert_eq(bleeding.damage_per_turn, 2, "Bleeding should deal two fixed damage per tick")
	assert_eq(bleeding.duration_turns, 2, "Bleeding should last for two processed turns")
	assert_eq(
		bleeding.get_description(),
		"Bleeding: 2 physical damage at turn start for 2 turns",
		"Bleeding should describe its complete tick behavior"
	)
	assert_true(bleeding.icon != null, "Bleeding should provide a status icon")
	for existing_status_path in [
		"res://resources/statuses/burning.tres",
		"res://resources/statuses/focus.tres",
		"res://resources/statuses/slow.tres",
		"res://resources/statuses/stun.tres",
	]:
		var existing_status := load(existing_status_path) as StatusEffectDefinition
		assert_ne(
			bleeding.icon.resource_path,
			existing_status.icon.resource_path,
			"Bleeding should use an icon distinct from %s" % existing_status.display_name
		)
	assert_eq(bleeding.color, Color(0.72, 0.06, 0.12, 1), "Bleeding should use its dark-red presentation color")
	assert_true(
		ResourceLoader.get_resource_uid("res://resources/statuses/bleeding.tres")
		!= ResourceUID.INVALID_ID,
		"Bleeding should have a stable resource UID"
	)
	var bleeding_target := _make_unit(CharacterDefinitionScript.new())
	assert_true(bleeding_target.apply_status(bleeding, caster, caster), "Bleeding should apply to a living unit")
	assert_eq(bleeding_target.current_health, 100, "Bleeding should not deal immediate damage")
	bleeding_target.process_status_turn_start()
	assert_eq(bleeding_target.current_health, 98, "Bleeding should deal two damage on its first tick")
	bleeding_target.advance_status_durations()
	bleeding_target.process_status_turn_start()
	assert_eq(bleeding_target.current_health, 96, "Bleeding should deal two damage on its second tick")
	bleeding_target.advance_status_durations()
	assert_true(bleeding_target.get_active_statuses().is_empty(), "Bleeding should expire after two processed turns")
	bleeding_target.process_status_turn_start()
	assert_eq(bleeding_target.current_health, 96, "expired Bleeding should not deal a third tick")
	var refresh_target := _make_unit(CharacterDefinitionScript.new())
	assert_true(refresh_target.apply_status(bleeding, caster, caster), "Bleeding should apply before refresh")
	refresh_target.get_active_statuses()[0].remaining_turns = 1
	assert_true(refresh_target.apply_status(bleeding, caster, caster), "Bleeding should refresh successfully")
	assert_eq(refresh_target.get_active_statuses().size(), 1, "reapplying Bleeding should not create a second stack")
	assert_eq(refresh_target.get_active_statuses()[0].remaining_turns, 2, "reapplying Bleeding should restore its full duration")


func test_status_flat_percentage_direction_and_different_id_stacking() -> void:
	var unit := _make_unit(CharacterDefinitionScript.new())
	var flat_reduction := StatusEffectScript.new() as StatusEffectDefinition
	flat_reduction.status_id = &"flat_reduction"
	flat_reduction.effect = StatusEffectDefinition.Effect.STAT_MODIFIER
	flat_reduction.affected_stat = UnitStat.Type.MOVEMENT_RANGE
	flat_reduction.modifier_direction = StatusEffectDefinition.ModifierDirection.REDUCE
	flat_reduction.modifier_value_type = StatusEffectDefinition.ModifierValueType.FLAT
	flat_reduction.flat_amount = 1.0
	var percentage_increase := StatusEffectScript.new() as StatusEffectDefinition
	percentage_increase.status_id = &"percentage_increase"
	percentage_increase.effect = StatusEffectDefinition.Effect.STAT_MODIFIER
	percentage_increase.affected_stat = UnitStat.Type.MOVEMENT_RANGE
	percentage_increase.modifier_direction = StatusEffectDefinition.ModifierDirection.INCREASE
	percentage_increase.modifier_value_type = StatusEffectDefinition.ModifierValueType.PERCENTAGE
	percentage_increase.percentage_amount = 20.0

	unit.apply_status(flat_reduction, unit)
	assert_true(is_equal_approx(unit.get_movement_range(), 5.0), "a positive Reduce flat amount should subtract from Movement Range")
	unit.apply_status(percentage_increase, unit)
	assert_eq(unit.get_active_statuses().size(), 2, "different status IDs should stack")
	assert_true(is_equal_approx(unit.get_movement_range(), 6.0), "flat modifiers should apply before additive percentage modifiers")
	unit.remove_status(&"flat_reduction")
	assert_true(is_equal_approx(unit.get_movement_range(), 7.2), "a positive Increase percentage should raise Movement Range")


func test_speed_movement_reconciliation_and_next_round_resort() -> void:
	var fast_definition := CharacterDefinitionScript.new() as CharacterDefinition
	fast_definition.movement_range = 6.0
	fast_definition.speed = 12
	var fast := _make_unit(fast_definition)
	var normal_definition := CharacterDefinitionScript.new() as CharacterDefinition
	normal_definition.movement_range = 6.0
	normal_definition.speed = 10
	var normal := _make_unit(normal_definition)

	assert_true(is_equal_approx(fast.get_movement_range(), 6.5), "Speed 12 should add 0.5 movement")
	fast.reset_movement()
	fast.spend_movement(1.0)
	var haste := _make_status(
		&"haste",
		2,
		[_make_modifier(UnitStat.Type.SPEED, StatModifierDefinition.Operation.FLAT, 4.0)]
	)
	assert_true(fast.apply_status(haste, fast), "Haste should apply")
	assert_true(is_equal_approx(fast.get_movement_range(), 7.5), "Haste should increase maximum movement")
	assert_true(is_equal_approx(fast.remaining_movement, 5.5), "a Speed increase must not restore spent movement")
	fast.reset_movement()
	fast.spend_movement(1.0)
	var drag := _make_status(
		&"drag",
		2,
		[_make_modifier(UnitStat.Type.SPEED, StatModifierDefinition.Operation.FLAT, -8.0)]
	)
	assert_true(fast.apply_status(drag, normal), "a separate Speed penalty should stack")
	assert_true(is_equal_approx(fast.get_movement_range(), 5.5), "combined Speed modifiers should update movement")
	assert_true(is_equal_approx(fast.remaining_movement, 5.5), "a Speed decrease should clamp remaining movement")

	fast.remove_status(&"haste")
	fast.remove_status(&"drag")
	var round_slow := _make_status(
		&"round_slow",
		2,
		[_make_modifier(UnitStat.Type.SPEED, StatModifierDefinition.Operation.FLAT, -4.0)]
	)
	var manager := track(TurnManagerScript.new()) as TurnManager
	var units: Array[TacticalCharacter] = [fast, normal]
	manager.start_combat(units)
	assert_eq(manager.turn_order, [fast, normal], "the faster unit should start combat")
	fast.apply_status(round_slow, normal)
	assert_eq(manager.turn_order, [fast, normal], "mid-round Speed changes must not reorder the active round")
	manager.end_current_turn()
	assert_eq(manager.current_unit, normal, "the existing round order should continue after the Speed change")
	manager.end_current_turn()
	assert_eq(manager.round_number, 2, "both units ending turns should begin round two")
	assert_eq(manager.turn_order, [normal, fast], "the next round should re-sort by current effective Speed")


func test_stun_blocks_one_activation_and_preserves_unspent_reaction() -> void:
	assert_eq(StatusEffectDefinition.Effect.NONE, 0, "None status effects should retain value zero")
	assert_eq(StatusEffectDefinition.Effect.DAMAGE_EACH_TURN, 1, "periodic damage should retain value one")
	assert_eq(StatusEffectDefinition.Effect.STAT_MODIFIER, 2, "stat modifiers should retain value two")
	assert_eq(StatusEffectDefinition.Effect.STUN, 3, "Stun should append serialized value three")
	var stun := load("res://resources/statuses/stun.tres") as StatusEffectDefinition
	assert_eq(stun.status_id, &"stun", "Stun should use a stable reusable status id")
	assert_eq(stun.display_name, "Stun", "Stun should expose its display name")
	assert_eq(stun.duration_turns, 1, "Stun should last one affected-unit activation")
	assert_true(stun.blocks_actions(), "the centralized status query should identify Stun")
	assert_true(is_equal_approx(stun.affected_unit_ai_utility, -20.0), "Stun should expose its editable AI utility")
	assert_true(stun.icon != null, "Stun should provide a status-bar icon")
	assert_true(stun.get_description().contains("Cannot move, use abilities, or make opportunity attacks"), "Stun descriptions should explain every blocked action")

	var ability := AbilityDefinition.new()
	ability.display_name = "Test Spell"
	var definition := CharacterDefinitionScript.new() as CharacterDefinition
	definition.movement_range = 6.0
	var abilities: Array[AbilityDefinition] = [ability]
	definition.abilities = abilities
	var unit := _make_unit(definition)
	var source := _make_unit(CharacterDefinitionScript.new())
	unit.reset_movement()
	unit.reset_ability_action()
	unit.reset_opportunity_reaction()
	assert_true(unit.apply_status(stun, ability, source), "a living unit should accept Stun from an ability source")
	assert_true(unit.apply_status(stun, stun, source), "reapplying Stun should refresh it")
	assert_eq(unit.get_active_statuses().size(), 1, "Stun should refresh instead of stacking")
	assert_eq(unit.get_active_statuses()[0].source, stun, "a refreshed Stun should replace its source object")
	assert_eq(unit.get_active_statuses()[0].source_unit, source, "a refreshed Stun should replace its source unit")
	assert_true(unit.is_stunned(), "the unit should report its centralized stunned state")
	assert_false(unit.can_move(), "Stun should block movement")
	assert_false(unit.can_use_abilities(), "Stun should block all abilities")
	assert_false(unit.can_use_opportunity_reactions(), "Stun should block reactions")
	assert_true(is_zero_approx(unit.remaining_movement), "Stun should expose zero usable movement")
	assert_false(unit.ability_available, "Stun should hide an otherwise unused ability action")
	assert_false(unit.opportunity_reaction_available, "Stun should hide an unspent reaction token")
	assert_true(is_equal_approx(unit.get_movement_range(), 6.0), "Stun should not modify the underlying Movement stat")
	assert_eq(ability.get_unavailable_reason(unit), "Stunned", "ability availability should prioritize the Stunned reason")
	assert_eq(unit._get_status_icon_entries()[0].definition, stun, "Stun should appear in the existing status-icon row")

	var other := _make_unit(CharacterDefinitionScript.new())
	var manager := track(TurnManagerScript.new()) as TurnManager
	manager.start_combat([unit, other])
	assert_eq(manager.current_unit, unit, "a friendly stunned activation should remain current until End Turn")
	assert_true(unit.get_active_statuses()[0].processed_this_turn, "Stun should be processed on its owner's activation")
	assert_true(is_zero_approx(unit.remaining_movement), "turn reset must not grant movement through Stun")
	assert_false(unit.ability_available, "turn reset must not grant an ability through Stun")
	assert_false(unit.opportunity_reaction_available, "round reset must not expose a reaction through Stun")
	manager.end_current_turn()
	assert_eq(manager.current_unit, other, "ending the stunned activation should advance combat normally")
	assert_false(unit.is_stunned(), "one-turn Stun should expire at the end of the processed activation")
	assert_true(unit.ability_available, "the unused raw ability token should become visible after Stun expires")
	assert_true(unit.opportunity_reaction_available, "an unspent reaction should return after Stun expires")
	assert_true(is_equal_approx(unit.remaining_movement, 6.0), "the unit's normal movement should return after Stun expires")

	unit.reset_opportunity_reaction()
	assert_true(unit.spend_opportunity_reaction(), "the separate spent-reaction case should consume its token")
	unit.apply_status(stun, source, source)
	unit.process_status_turn_start()
	unit.advance_status_durations()
	assert_false(unit.opportunity_reaction_available, "Stun expiry must not restore a reaction spent before application")


func test_sample_items_scaling_mappings_and_unassigned_status_abilities() -> void:
	var definition := load("res://resources/friendly_spellcaster.tres") as CharacterDefinition
	var unit := _make_unit(definition)
	assert_eq(definition.starting_equipment.size(), 3, "the sample friendly should have three starting items")
	assert_eq(unit.get_equipped_items().size(), 3, "starting equipment should copy into runtime slots")
	assert_true(is_equal_approx(unit.get_effective_stat(UnitStat.Type.STRENGTH), 12.0), "Iron Sword should grant Strength")
	assert_true(is_equal_approx(unit.get_effective_stat(UnitStat.Type.DEXTERITY), 12.0), "Ranger Armor should grant Dexterity")
	assert_true(is_equal_approx(unit.get_effective_stat(UnitStat.Type.INTELLIGENCE), 12.0), "Sage Charm should grant Intelligence")
	assert_eq(unit.get_weapon_damage(), 20, "Iron Sword should provide the physical weapon-damage contribution")
	assert_eq(unit.get_abilities().size(), 8, "Charge and Searing Dagger should expand the sample loadout to eight abilities")

	var expected_stats := [
		UnitStat.Type.INTELLIGENCE,
		UnitStat.Type.DEXTERITY,
		UnitStat.Type.INTELLIGENCE,
		UnitStat.Type.INTELLIGENCE,
		UnitStat.Type.STRENGTH,
		UnitStat.Type.INTELLIGENCE,
		UnitStat.Type.STRENGTH,
		UnitStat.Type.INTELLIGENCE,
	]
	var expected_amounts := [32, 7, 37, 22, 32, 27, 32, 27]
	for index in range(unit.get_abilities().size()):
		var ability := unit.get_abilities()[index]
		if index == 2:
			assert_eq(ability.effect, AbilityDefinition.PrimaryEffect.HEAL, "Heal should expose its primary effect directly")
			assert_eq(ability.scaling_stat, expected_stats[index], "Heal should expose its scaling stat directly")
			assert_eq(ability.calculate_primary_effect_amount(unit), 37, "Heal should be 25 base + the full equipped Intelligence 12")
		else:
			assert_eq(ability.scaling_stat, expected_stats[index], "sample damage should expose its scaling stat directly")
			assert_eq(ability.calculate_damage(unit), expected_amounts[index], "top-level damage should preserve the expected amount")
	assert_eq(unit.get_abilities()[0].damage_type, DamageCalculator.Type.MAGICAL, "Fireball should be magical")
	assert_eq(unit.get_abilities()[1].damage_type, DamageCalculator.Type.PHYSICAL, "Arrow should be physical")
	assert_eq(unit.get_abilities()[3].damage_type, DamageCalculator.Type.MAGICAL, "Beam should be magical")
	assert_eq(unit.get_abilities()[4].damage_type, DamageCalculator.Type.PHYSICAL, "Strike should be physical")
	assert_eq(unit.get_abilities()[5].damage_type, DamageCalculator.Type.MAGICAL, "Ice Shard should be magical")
	assert_eq(unit.get_abilities()[6].damage_type, DamageCalculator.Type.PHYSICAL, "Charge should be physical")
	assert_eq(unit.get_abilities()[7].damage_type, DamageCalculator.Type.MAGICAL, "Searing Dagger should be magical")
	var expected_ability_types := [
		AbilityDefinition.AbilityType.MAGIC,
		AbilityDefinition.AbilityType.RANGED,
		AbilityDefinition.AbilityType.MAGIC,
		AbilityDefinition.AbilityType.MAGIC,
		AbilityDefinition.AbilityType.MELEE,
		AbilityDefinition.AbilityType.MAGIC,
		AbilityDefinition.AbilityType.MELEE,
		AbilityDefinition.AbilityType.MAGIC,
	]
	for index in range(expected_ability_types.size()):
		assert_eq(unit.get_abilities()[index].ability_type, expected_ability_types[index], "sample ability type should match its migrated role")
	assert_false(unit.get_abilities()[1].can_be_used_by(unit), "Arrow should be unavailable with the starting Melee sword")
	assert_true(unit.get_abilities()[4].can_be_used_by(unit), "Strike should be available with the starting Melee sword")
	assert_true(unit.get_abilities()[6].can_be_used_by(unit), "Charge should be available with the starting Melee sword")
	var ranger_bow := load("res://resources/items/ranger_bow.tres") as ItemDefinition
	unit.equip_item(ranger_bow)
	assert_eq(unit.get_abilities()[1].calculate_damage(unit), 17, "Arrow should deal Ranger Bow 10 plus 60% of Dexterity 12")
	assert_true(unit.get_abilities()[1].can_be_used_by(unit), "Arrow should become available with a Ranged weapon")
	assert_eq(unit.get_abilities()[4].calculate_damage(unit), 10, "Strike preview should omit mismatched weapon damage and lost Sword Strength")
	assert_false(unit.get_abilities()[4].can_be_used_by(unit), "Strike should become unavailable with a Ranged weapon")
	assert_false(unit.get_abilities()[6].can_be_used_by(unit), "Charge should become unavailable with a Ranged weapon")
	assert_eq(unit.get_abilities()[0].calculate_damage(unit), 32, "Magic damage should remain unchanged across weapon types")
	assert_eq(unit.get_abilities()[5].status_effect.status_id, &"slow", "Ice Shard should apply Slow")
	var status_icon_paths: Array[String] = []
	var unique_status_icon_paths: Dictionary = {}
	for status_path in [
		"res://resources/statuses/bleeding.tres",
		"res://resources/statuses/burning.tres",
		"res://resources/statuses/slow.tres",
		"res://resources/statuses/focus.tres",
		"res://resources/statuses/stun.tres",
	]:
		var status := load(status_path) as StatusEffectDefinition
		assert_true(status.icon != null, "%s should provide its own status icon" % status.display_name)
		status_icon_paths.append(status.icon.resource_path)
		unique_status_icon_paths[status.icon.resource_path] = true
	assert_eq(unique_status_icon_paths.size(), status_icon_paths.size(), "every reusable status should use a distinct icon asset")

	var focus := load("res://resources/abilities/focus.tres") as AbilityDefinition
	var slow := load("res://resources/abilities/slow.tres") as AbilityDefinition
	assert_eq(focus.display_name, "Focus", "the reusable Focus ability should load")
	assert_eq(slow.display_name, "Slow", "the reusable Slow ability should load")
	assert_false(unit.get_abilities().has(focus), "Focus should remain available without occupying the current ability bar")
	assert_false(unit.get_abilities().has(slow), "Slow should remain available without occupying the current ability bar")


func _make_unit(definition: CharacterDefinition) -> TacticalCharacter:
	var unit := track(TacticalCharacterScript.new()) as TacticalCharacter
	unit.definition = definition
	unit._ready()
	return unit


func _make_modifier(
	stat: UnitStat.Type,
	operation: StatModifierDefinition.Operation,
	value: float
) -> StatModifierDefinition:
	var modifier := StatModifierScript.new() as StatModifierDefinition
	modifier.stat = stat
	modifier.operation = operation
	modifier.value = value
	return modifier


func _make_status(
	status_id: StringName,
	duration: int,
	modifier_values: Array
) -> StatusEffectDefinition:
	var status := StatusEffectScript.new() as StatusEffectDefinition
	status.status_id = status_id
	status.display_name = String(status_id).capitalize()
	status.duration_turns = duration
	var modifiers: Array[StatModifierDefinition] = []
	for modifier in modifier_values:
		modifiers.append(modifier as StatModifierDefinition)
	status.modifiers = modifiers
	return status


func _get_property_info(object: Object, property_name: StringName) -> Dictionary:
	for property_info in object.get_property_list():
		if StringName(property_info.name) == property_name:
			return property_info
	return {}
