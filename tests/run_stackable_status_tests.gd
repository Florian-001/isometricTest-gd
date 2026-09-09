extends SceneTree

const IDS := ["strength_up", "dexterity_up", "constitution_up", "intelligence_up"]
const STATS := [UnitStat.Type.STRENGTH, UnitStat.Type.DEXTERITY, UnitStat.Type.CONSTITUTION, UnitStat.Type.INTELLIGENCE]
const DIRECTORY := "res://.godot/stack_buffs_validation"
var failures: Array[String] = []
var checks := 0
var arena: Node2D
var grid: IsometricGrid
var serial := 0


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _frames() -> void:
	for index in range(5):
		await process_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	arena = Node2D.new()
	root.add_child(arena)
	grid = IsometricGrid.new()
	grid.grid_size = Vector2i(12, 12)
	arena.add_child(grid)
	_test_resources_and_stacks()
	_test_modifiers_and_health()
	_test_lifetimes()
	_test_saves_and_ai()
	await _test_battle_end()
	await _test_presentation()
	arena.free()
	for failure in failures:
		push_error(failure)
	print("STACKABLE_STATUS_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _buff(index: int) -> StatusEffectDefinition:
	return load("res://resources/statuses/%s.tres" % IDS[index]) as StatusEffectDefinition


func _unit(friendly := true) -> TacticalCharacter:
	var unit := TacticalCharacter.new()
	serial += 1
	unit.name = "StackTest%d" % serial
	unit.scenario_unit_id = unit.name
	unit.definition = CharacterDefinition.new()
	unit.definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	unit.definition.strength = 10
	unit.definition.dexterity = 10
	unit.definition.constitution = 10
	unit.definition.intelligence = 10
	unit.use_complete_equipment_override = true
	unit.starting_grid_cell = Vector2i(1, 1)
	arena.add_child(unit)
	unit.initialize(grid)
	return unit


func _test_resources_and_stacks() -> void:
	var unit := _unit()
	var source := _unit()
	var defaults := StatusEffectDefinition.new()
	check(not defaults.stackable and not defaults.lasts_until_battle_end, "existing resource defaults remain timed and nonstacking")
	var icons: Array[Texture2D] = []
	for index in range(IDS.size()):
		var buff := _buff(index)
		check(buff.stackable and buff.lasts_until_battle_end and not buff.is_negative(), "%s is an unlimited encounter buff" % IDS[index])
		check(buff.affected_stat == STATS[index] and buff.flat_amount == 1 and buff.affected_unit_ai_utility == 2, "%s has the correct stat, amount and AI utility" % IDS[index])
		check(buff.icon != null and not icons.has(buff.icon), "%s has its own icon" % IDS[index])
		icons.append(buff.icon)
		check(buff.get_description().contains("+1 %s per stack" % UnitStat.get_display_name(STATS[index])) and buff.get_description().contains("Until battle ends") and not buff.get_description().contains("for 1 turn"), "%s describes stacks and lifetime" % IDS[index])
		for count in range(1, 13):
			check(unit.apply_status(buff, source), "application %d of %s succeeds" % [count, IDS[index]])
			check(unit.get_effective_stat(STATS[index]) == 10 + count, "%s stack %d grants exactly +%d" % [IDS[index], count, count])
		var active := unit.get_active_statuses()[index]
		check(active.stack_count == 12 and unit.get_active_statuses().size() == index + 1, "stacks share one entry and stat buffs remain independent")
		unit.apply_status(buff, unit)
		check(active.stack_count == 13 and active.source_unit == unit and active.source == unit, "sources combine and newest application owns metadata")
		check(buff.get_stat_modifiers()[0].value == 1.0, "stacking preserves shared definition modifiers")
	var other := _unit()
	other.apply_status(_buff(0))
	check(other.get_effective_stat(STATS[0]) == 11, "stack counts are local to each unit")
	unit.apply_status(load("res://resources/statuses/focus.tres"))
	unit.apply_status(load("res://resources/statuses/empowered.tres"))
	check(unit.get_effective_stat(STATS[0]) == 26 and unit.get_effective_stat(STATS[2]) == 24, "stacks coexist with Focus and Empowered")
	unit.apply_status(load("res://resources/statuses/burning.tres"))
	check(unit.remove_negative_statuses() == 1 and unit.get_active_statuses().size() == 6, "Cleanse preserves every positive stack")
	unit.free()
	source.free()
	other.free()


func _test_modifiers_and_health() -> void:
	var unit := _unit()
	var status := _buff(0).duplicate() as StatusEffectDefinition
	var additive := StatModifierDefinition.new()
	additive.stat = UnitStat.Type.STRENGTH
	additive.operation = StatModifierDefinition.Operation.PERCENT_ADD
	additive.value = 0.1
	var multiplier := additive.duplicate() as StatModifierDefinition
	multiplier.operation = StatModifierDefinition.Operation.PERCENT_MULTIPLY
	multiplier.value = 0.2
	status.modifiers = [additive, multiplier]
	unit.apply_status(status)
	unit.apply_status(status)
	check(is_equal_approx(unit.get_effective_stat(STATS[0]), 12.0 * 1.2 * 1.2 * 1.2), "flat, additive and multiplicative modifiers apply once per stack in the normal order")
	check(additive.value == 0.1 and multiplier.value == 0.2 and status.flat_amount == 1, "modifier evaluation never edits authored resources")
	var maximum := unit.get_max_health()
	unit.apply_damage(5)
	var health := unit.current_health
	unit.apply_status(_buff(2))
	unit.apply_status(_buff(2))
	check(unit.get_max_health() == maximum + 8 and unit.current_health == health, "two Constitution stacks grant eight max HP without healing")
	unit.heal(999)
	check(unit.remove_status(&"constitution_up") and unit.current_health == maximum and unit.get_max_health() == maximum, "removing Constitution removes all stacks and clamps healed HP")
	unit.free()


func _test_lifetimes() -> void:
	var unit := _unit()
	for index in range(IDS.size()):
		unit.apply_status(_buff(index))
		unit.apply_status(_buff(index))
	unit.apply_status(load("res://resources/statuses/stun.tres"))
	check(unit.is_stunned(), "lifetime fixture includes a stunned turn")
	for turn in range(20):
		unit.expire_turn_start_statuses()
		unit.process_status_turn_start()
		unit.advance_status_durations()
	check(unit.get_active_statuses().size() == 4 and not unit.is_stunned(), "battle buffs survive twenty turns while Stun expires")
	for active in unit.get_active_statuses():
		check(active.stack_count == 2 and active.remaining_turns == 1, "untimed stacks retain their active marker")
	# Battle lifetime takes precedence over either countdown setting.
	var turn_start := _buff(0).duplicate() as StatusEffectDefinition
	turn_start.expires_at_turn_start = true
	unit.apply_status(turn_start)
	unit.expire_turn_start_statuses()
	check(unit.get_active_statuses()[0].stack_count == 3, "battle-end lifetime overrides turn-start expiry")
	var burning := load("res://resources/statuses/burning.tres") as StatusEffectDefinition
	unit.apply_status(burning)
	var health := unit.current_health
	unit.process_status_turn_start()
	unit.advance_status_durations()
	unit.apply_status(burning)
	var burn := unit.get_active_statuses().back() as ActiveStatus
	check(burn.stack_count == 1 and burn.remaining_turns == 2, "Burning still refreshes without stacking")
	for turn in range(2):
		unit.process_status_turn_start()
		unit.advance_status_durations()
	check(unit.current_health == health - 3 and unit.get_active_statuses().size() == 4, "Burning damage and expiration remain unchanged")
	unit.apply_status(load("res://resources/statuses/focus.tres"))
	check(unit.remove_battle_end_statuses() == 4 and unit.get_active_statuses().size() == 1, "battle cleanup removes encounter buffs and retains ordinary statuses")
	check(unit.remove_battle_end_statuses() == 0, "battle cleanup is idempotent")
	unit.free()
	var skeleton := (load("res://scenes/enemies/skeleton_warrior.tscn") as PackedScene).instantiate() as TacticalCharacter
	arena.add_child(skeleton)
	skeleton.initialize(grid)
	skeleton.apply_status(_buff(2))
	skeleton.apply_status(_buff(2))
	skeleton.apply_damage(9999)
	check(skeleton.is_bone_pile and skeleton.get_active_statuses().is_empty(), "Reassemble clears encounter buffs using existing collapse rules")
	skeleton.reform_from_bones()
	check(skeleton.get_active_statuses().is_empty(), "reformation does not restore old stacks")
	skeleton.free()


func _test_saves_and_ai() -> void:
	var unit := _unit()
	var source := _unit()
	for index in range(IDS.size()):
		for count in range(index + 1):
			unit.apply_status(_buff(index), _buff(index), source)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(unit.capture_runtime_state()))
	var restored := _unit()
	restored.restore_runtime_state(saved, {source.scenario_unit_id: source})
	for index in range(IDS.size()):
		var active := restored.get_active_statuses()[index]
		check(active.stack_count == index + 1 and active.source_unit == source and active.source == _buff(index), "save restores counts, resources and sources")
		check(restored.get_effective_stat(STATS[index]) == unit.get_effective_stat(STATS[index]), "restored stats match live stacks")
	for status in saved.statuses:
		status.erase("stack_count")
	restored.restore_runtime_state(saved, {})
	check(restored.get_active_statuses().all(func(active: ActiveStatus): return active.stack_count == 1), "legacy saves default to one stack")
	var units: Array[TacticalCharacter] = [unit, source]
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
	var original := snapshot.duplicate_state()
	var live_before := unit.capture_runtime_state()
	var planner := EnemyAIPlanner.new()
	for index in range(IDS.size()):
		var key_before := planner._get_snapshot_key(snapshot)
		var estimate := snapshot.forecast_status_application(source, unit, _buff(index))
		check(estimate.utility_hint == 2 and estimate.health_delta == 0, "each extra stack retains utility and never heals")
		check(snapshot.get_effective_stat(unit, STATS[index]) == unit.get_effective_stat(STATS[index]) + 1, "forecast includes one additional stat point")
		check(snapshot.get_status_state(unit, _buff(index).status_id).stack_count == index + 2, "forecast increments count")
		check(planner._get_snapshot_key(snapshot) != key_before, "stack count changes invalidate planner cache keys")
		check(original.get_status_state(unit, _buff(index).status_id).stack_count == index + 1, "snapshot mutation preserves copied counts")
	check(snapshot.get_max_health(unit) == unit.get_max_health() + 4 and snapshot.get_health(unit) == unit.current_health, "AI Constitution raises maximum without healing")
	check(unit.capture_runtime_state() == live_before, "forecasting never mutates live state")
	snapshot.expire_turn_start_statuses(unit)
	snapshot.forecast_cleanse(source, unit)
	check(snapshot.get_status_ids(unit).size() == 4, "AI duration processing and Cleanse preserve buffs")
	for index in range(IDS.size()):
		unit.apply_status(_buff(index), source)
		check(snapshot.get_effective_stat(unit, STATS[index]) == unit.get_effective_stat(STATS[index]), "live applications agree with AI for every stat")
	var key_probe := original.duplicate_state()
	key_probe.unit_statuses[unit][&"strength_up"].stack_count += 1
	check(planner._get_snapshot_key(original) != planner._get_snapshot_key(key_probe), "count alone changes the cache key")
	var ability := AbilityDefinition.new()
	ability.effect = AbilityDefinition.PrimaryEffect.STATUS
	ability.status_effect = _buff(0)
	ability.apply_primary_effect(source, unit)
	var nested := ApplyStatusEffectDefinition.new()
	nested.status_effect = _buff(0)
	nested.apply(source, unit)
	check(unit.get_active_statuses()[0].stack_count == 4, "primary and additional-effect status application each add one stack")
	unit.free()
	source.free()
	restored.free()


func _test_battle_end() -> void:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	root.add_child(battle)
	await _frames()
	var unit := battle.turn_manager.current_unit
	check(unit != null and unit.is_friendly(), "battle starts with a friendly fixture")
	if unit == null:
		battle.free()
		return
	var maximum := unit.get_max_health()
	unit.apply_status(_buff(2))
	unit.apply_status(_buff(2))
	unit.heal(999)
	unit.apply_status(_buff(0))
	var payload := battle.capture_save_payload(false)
	check(ScenarioSaveStore.validate_payload(payload).ok, "scenario validator accepts stacked runtime state")
	var saved := ScenarioSaveStore.save_new(payload, DIRECTORY + "/scenarios")
	check(saved.ok, "exact-state scenario writes successfully")
	var fresh := battle.capture_save_payload(true)
	check(fresh.runtime.fresh_start and not fresh.runtime.has("units"), "fresh restart payload excludes runtime stacks")
	for enemy in battle._characters:
		if not enemy.is_friendly():
			enemy.apply_damage(99999)
	# Simulate a final synchronous effect after lethal damage but before deferred cleanup.
	unit.apply_status(_buff(1))
	check(not unit.get_active_statuses().is_empty(), "cleanup waits until synchronous effects finish")
	await _frames()
	check(battle._combat_finalized and unit.get_active_statuses().is_empty(), "normal combat finalization clears encounter stacks")
	check(unit.get_max_health() == maximum and unit.current_health == maximum, "battle completion removes Constitution and clamps HP")
	for member in battle.capture_run_party():
		if member.id == unit.scenario_unit_id:
			check(member.max_health == unit.get_max_health_without_statuses() and member.health <= member.max_health, "run results exclude battle-only health bonuses")
	battle.shutdown_battle()
	battle.free()
	await _frames()


func _test_presentation() -> void:
	var unit := _unit()
	for index in range(IDS.size()):
		for count in range([1, 3, 12, 99][index]):
			unit.apply_status(_buff(index))
	var entries := unit._get_status_icon_entries()
	check(entries.size() == 4, "each buff has one icon regardless of stack count")
	for index in range(4):
		check(entries[index].stack_count == [1, 3, 12, 99][index], "icon entry supplies the exact stack count")
		check(entries[index].stack_badge_rect.end.y < TacticalCharacter.FALLBACK_HEALTH_BAR_RECT.position.y, "stack badges stay above the health bar")
	unit.get_active_statuses()[0].stack_count = 123456
	var large_entries := unit._get_status_icon_entries()
	check(large_entries[0].stack_badge_rect.end.x < large_entries[1].stack_badge_rect.position.x, "large stack counts reserve enough row width")
	unit.get_active_statuses()[0].stack_count = 1
	if "--capture" in OS.get_cmdline_user_args():
		grid.visible = false
		unit.position = Vector2(520, 560)
		unit.scale = Vector2(3, 3)
		var title := Label.new()
		title.position = Vector2(50, 40)
		title.text = "Stackable stat buffs\n+1 per stack | Unlimited stacks | Until battle ends\n\nStrength x1   Dexterity x3   Constitution x12   Intelligence x99"
		title.add_theme_font_size_override("font_size", 22)
		arena.add_child(title)
		await _frames()
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(DIRECTORY + "/stacks.png") == OK, "stack badge visual capture saves")
	unit.free()
