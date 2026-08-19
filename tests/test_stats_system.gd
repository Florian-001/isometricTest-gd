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
	assert_true(is_equal_approx(unit.get_effective_stat(UnitStat.Type.STRENGTH), 12.0), "Focus should modify effective Strength")
	unit.advance_status_durations()
	assert_eq(unit.get_active_statuses()[0].remaining_turns, 1, "the owner turn end should decrement duration")
	assert_true(unit.apply_status(focus, unit), "reapplying Focus should succeed")
	assert_eq(unit.get_active_statuses().size(), 1, "the same status id should refresh rather than stack")
	assert_eq(unit.get_active_statuses()[0].remaining_turns, 2, "refresh should restore the full duration")

	assert_true(unit.apply_status(blessing, unit), "a different status id should stack")
	assert_eq(unit.get_active_statuses().size(), 2, "different status ids should coexist")
	assert_true(is_equal_approx(unit.get_effective_stat(UnitStat.Type.STRENGTH), 15.0), "different statuses should combine")
	assert_true(unit.remove_status(&"blessing"), "explicit status removal should report success")
	assert_false(unit.remove_status(&"missing"), "removing an absent status should report failure")
	unit.advance_status_durations()
	unit.advance_status_durations()
	assert_true(unit.get_active_statuses().is_empty(), "Focus should expire after two owner turn endings")
	assert_true(is_equal_approx(unit.get_effective_stat(UnitStat.Type.STRENGTH), 10.0), "expiration should restore the base stat")
	assert_true(status_events[0] >= 6, "application, refresh, duration changes, removal, and expiry should notify observers")

	unit.apply_damage(1000)
	assert_false(unit.apply_status(focus, unit), "defeated units should reject new statuses")


func test_neutral_ten_scaling_damage_healing_descriptions_and_ai_forecasts() -> void:
	var caster := _make_unit(CharacterDefinitionScript.new())
	var target := _make_unit(CharacterDefinitionScript.new())
	var damage := DamageEffectScript.new() as DamageEffectDefinition
	damage.amount = 30
	damage.scaling_stat = UnitStat.Type.INTELLIGENCE
	damage.scaling_ratio = 1.0

	caster.intelligence_override = 14
	assert_eq(damage.calculate_amount(caster), 34, "four Intelligence above neutral should add four damage")
	assert_true(damage.get_description(caster).contains("34 damage"), "the caster tooltip should show calculated damage")
	assert_true(damage.get_description(caster).contains("Intelligence"), "the tooltip should name its scaling stat")
	var estimate := damage.estimate_for_ai(caster, target, 20)
	assert_eq(estimate["health_delta"], -20, "AI forecast should use scaled damage and clamp overkill")
	damage.apply(caster, target)
	assert_eq(target.current_health, 66, "applied damage should use the same scaled amount as forecasting")

	caster.intelligence_override = 6
	assert_eq(damage.calculate_amount(caster), 26, "four Intelligence below neutral should subtract four damage")
	caster.intelligence_override = 0
	damage.amount = 5
	damage.scaling_ratio = 2.0
	assert_eq(damage.calculate_amount(caster), 0, "large negative scaling must clamp damage to zero")

	var healing := HealEffectScript.new() as HealEffectDefinition
	healing.amount = 25
	healing.scaling_stat = UnitStat.Type.INTELLIGENCE
	healing.scaling_ratio = 1.0
	caster.intelligence_override = 14
	target.current_health = 50
	var heal_estimate := healing.estimate_for_ai(caster, target, target.current_health)
	assert_eq(heal_estimate["health_delta"], 29, "AI forecast should include Intelligence-scaled healing")
	healing.apply(caster, target)
	assert_eq(target.current_health, 79, "applied healing should match the forecast")


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


func test_sample_items_scaling_mappings_and_unassigned_status_abilities() -> void:
	var definition := load("res://resources/friendly_spellcaster.tres") as CharacterDefinition
	var unit := _make_unit(definition)
	assert_eq(definition.starting_equipment.size(), 3, "the sample friendly should have three starting items")
	for item in definition.starting_equipment:
		assert_true(item.icon != null, "%s should have an equipment icon" % item.display_name)
	assert_eq(unit.get_equipped_items().size(), 3, "starting equipment should copy into runtime slots")
	assert_true(is_equal_approx(unit.get_effective_stat(UnitStat.Type.STRENGTH), 12.0), "Iron Sword should grant Strength")
	assert_true(is_equal_approx(unit.get_effective_stat(UnitStat.Type.DEXTERITY), 12.0), "Ranger Armor should grant Dexterity")
	assert_true(is_equal_approx(unit.get_effective_stat(UnitStat.Type.INTELLIGENCE), 12.0), "Sage Charm should grant Intelligence")
	assert_eq(unit.get_abilities().size(), 5, "sample statuses must not expand the existing five-button loadout")

	var expected_stats := [
		UnitStat.Type.INTELLIGENCE,
		UnitStat.Type.DEXTERITY,
		UnitStat.Type.INTELLIGENCE,
		UnitStat.Type.INTELLIGENCE,
		UnitStat.Type.STRENGTH,
	]
	var expected_amounts := [32, 27, 27, 22, 32]
	for index in range(unit.get_abilities().size()):
		var effect = unit.get_abilities()[index].effects[0]
		assert_eq(effect.scaling_stat, expected_stats[index], "sample ability should use its configured primary stat")
		assert_eq(effect.calculate_amount(unit), expected_amounts[index], "starting equipment should add two to the relevant amount")

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
