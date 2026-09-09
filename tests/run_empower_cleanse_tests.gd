extends SceneTree

const StatusCatalog = preload("res://addons/tile_painter/status_effect_catalog.gd")
const DIRECTORY := "res://.godot/empower_validation"
var failures: Array[String] = []
var checks := 0
var arena: Node2D
var grid: IsometricGrid
var targeting: AbilityTargeting
var executor: AbilityExecutor
var units: Array[TacticalCharacter] = []
var empower: AbilityDefinition
var cleanse: AbilityDefinition
var empowered: StatusEffectDefinition
var focus: StatusEffectDefinition
var negatives: Array[StatusEffectDefinition] = []


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	empower = load("res://resources/abilities/empower.tres")
	cleanse = load("res://resources/abilities/cleanse.tres")
	empowered = load("res://resources/statuses/empowered.tres")
	focus = load("res://resources/statuses/focus.tres")
	for id in ["burning", "slow", "stun", "taunted"]:
		negatives.append(load("res://resources/statuses/%s.tres" % id))
	arena = Node2D.new()
	root.add_child(arena)
	grid = IsometricGrid.new()
	grid.grid_size = Vector2i(12, 12)
	arena.add_child(grid)
	targeting = AbilityTargeting.new(grid.grid_size)
	executor = AbilityExecutor.new()
	arena.add_child(executor)
	_test_resources()
	_test_empower_lifecycle()
	_test_cleanse()
	_test_forecasts()
	await _test_execution()
	_test_ai_selection()
	await _test_ui()
	_clear()
	arena.free()
	for failure in failures:
		push_error(failure)
	print("EMPOWER_CLEANSE_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _unit(friendly := true, cell := Vector2i(1, 1)) -> TacticalCharacter:
	var unit := TacticalCharacter.new()
	unit.name = "EmpowerTest%d" % units.size()
	unit.scenario_unit_id = unit.name
	unit.definition = CharacterDefinition.new()
	unit.definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	unit.definition.strength = 10
	unit.definition.dexterity = 10
	unit.definition.intelligence = 10
	unit.definition.constitution = 25
	unit.definition.speed = 10
	unit.definition.movement_range = 4.0
	unit.starting_grid_cell = cell
	unit.use_complete_equipment_override = true
	unit.override_template_abilities = true
	unit.ability_overrides = [empower, cleanse]
	arena.add_child(unit)
	unit.initialize(grid)
	unit.reset_movement()
	unit.reset_ability_action()
	units.append(unit)
	return unit


func _clear() -> void:
	for unit in units:
		unit.free()
	units.clear()


func _test_resources() -> void:
	check(StatusEffectDefinition.new().is_negative(), "new statuses default to negative")
	var custom_status := StatusEffectDefinition.new()
	var multiplier := StatModifierDefinition.new()
	multiplier.operation = StatModifierDefinition.Operation.PERCENT_MULTIPLY
	multiplier.value = 0.25
	custom_status.modifiers = [multiplier]
	check(custom_status.get_description().contains("1.25 Strength"), "multiplicative modifiers have a valid tooltip")
	check(AbilityDefinition.PrimaryEffect.STATUS == 3 and AbilityDefinition.PrimaryEffect.CLEANSE == 4, "primary effect serialization remains compatible")
	for ability in [empower, cleanse]:
		check(ability.ability_type == AbilityDefinition.AbilityType.MAGIC and not ability.requires_weapon, "support spells require no weapon")
		check(ability.range == 5.0 and ability.target_flags == 5 and ability.delivery_type == AbilityDefinition.DeliveryType.CAST_ON_TARGET, "support targeting matches Heal")
		check(not ability.has_damage() and ability.get_hit_count() == 1, "support spells do not damage or repeat")
	check(empower.status_effect == empowered and empowered.duration_turns == 3, "Empower applies the reusable three-turn status")
	check(not empowered.is_negative() and not focus.is_negative(), "both buffs are positive")
	check(empowered.affected_unit_ai_utility == 12.0, "Empowered provides configured positive AI utility")
	check(empowered.icon != null and empowered.icon != focus.icon, "Empowered has a distinct icon")
	var stats: Array[int] = []
	for modifier in empowered.get_stat_modifiers():
		check(modifier.operation == StatModifierDefinition.Operation.FLAT and modifier.value == 1.0, "Empowered uses flat +1 modifiers")
		stats.append(modifier.stat)
	for stat in UnitStat.Type.values():
		if stat != UnitStat.Type.NONE:
			check(stats.count(stat) == 1, "each configurable stat is included exactly once")
			check(empower.get_description().contains("+1 " + UnitStat.get_display_name(stat)), "ability description includes each stat bonus")
	check(empower.get_description().contains("3 turns") and empower.get_description().contains("Positive status"), "Empower describes duration and polarity")
	for status in negatives:
		check(status.is_negative() and status.get_description().contains("Negative status"), "every debuff is explicitly negative")
	check(StatusCatalog.get_labels(StatusCatalog.get_statuses()) == ["Burning", "Empowered", "Focus", "Slow", "Stun", "Taunted"], "status catalog discovers and sorts all definitions")
	var catalog := load("res://resources/dev_tool_catalog.tres") as DevToolCatalog
	check(catalog.abilities.count(empower) == 1 and catalog.abilities.count(cleanse) == 1, "developer catalog includes both spells once")
	var cleric := load("res://resources/classes/cleric.tres") as CharacterClassDefinition
	var unit := _unit()
	unit.override_template_abilities = false
	unit.definition.starting_class = cleric
	for level in [1, 2, 3, 4, 5]:
		unit.set_class_level(cleric, level)
		check(unit.get_abilities().has(empower) == (level >= 3), "Empower unlocks at Cleric 3")
		check(unit.get_abilities().has(cleanse) == (level >= 4), "Cleanse unlocks at Cleric 4")
	_clear()


func _test_empower_lifecycle() -> void:
	var unit := _unit()
	unit.current_health = 70
	unit.process_status_turn_start()
	empower.apply_primary_effect(unit, unit)
	for stat in [UnitStat.Type.STRENGTH, UnitStat.Type.DEXTERITY, UnitStat.Type.INTELLIGENCE, UnitStat.Type.SPEED]:
		check(unit.get_effective_stat(stat) == 11.0, "Empowered increases an effective stat by one")
	check(unit.get_effective_stat(UnitStat.Type.CONSTITUTION) == 26.0 and unit.get_max_health() == 104, "Constitution increases max health")
	check(unit.current_health == 70, "increasing maximum health does not heal")
	check(is_equal_approx(unit.get_movement_range(), 5.25), "Speed and direct movement bonuses both contribute")
	check(unit.remaining_movement == 4.0, "Empower does not refill movement")
	check(unit.get_initiative() == 11, "Speed bonus changes initiative")
	unit.advance_status_durations()
	check(unit.get_active_statuses()[0].remaining_turns == 3, "application mid-turn does not consume duration")
	unit.process_status_turn_start()
	unit.advance_status_durations()
	check(unit.get_active_statuses()[0].remaining_turns == 2, "first full turn decrements duration")
	empower.apply_primary_effect(unit, unit)
	check(unit.get_active_statuses().size() == 1 and unit.get_active_statuses()[0].remaining_turns == 3, "reapplication refreshes without stacking")
	unit.apply_status(focus, unit)
	check(unit.get_effective_stat(UnitStat.Type.STRENGTH) == 13, "Focus stacks with Empowered")
	var state := unit.capture_runtime_state()
	var restored := _unit(true, Vector2i(2, 1))
	restored.restore_runtime_state(state, {unit.scenario_unit_id: unit})
	check(restored.get_active_statuses().size() == 2 and restored.get_active_statuses()[0].remaining_turns == 3, "save/restore preserves duration and positive statuses")
	check(restored.get_active_statuses()[0].source_unit == unit and restored.get_movement_range() == unit.get_movement_range(), "save/restore preserves source and derived values")
	for turn in range(3):
		unit.process_status_turn_start()
		check(unit.get_effective_stat(UnitStat.Type.SPEED) == 11.0, "buff remains active throughout each full turn")
		unit.advance_status_durations()
	check(unit.get_active_statuses().is_empty() and unit.get_max_health() == 100, "statuses expire and health limit returns")
	check(unit.get_movement_range() == 4.0 and unit.current_health == 70, "expiry restores movement without healing")
	empower.apply_primary_effect(unit, unit)
	unit.heal(999)
	unit.remove_status(&"empowered")
	check(unit.current_health == 100, "expiry/removal clamps health above restored maximum")
	var slow := negatives[1]
	unit.apply_status(slow, unit)
	empower.apply_primary_effect(unit, unit)
	check(is_equal_approx(unit.get_movement_range(), 5.25 * 0.7), "flat buffs respect existing percentage modifiers")
	unit.movement_range_override = 10.0
	check(unit.get_movement_range() <= 10.0, "existing movement cap remains enforced")
	_clear()


func _test_cleanse() -> void:
	var unit := _unit()
	var opponent := _unit(false, Vector2i(3, 1))
	unit.current_health = 75
	unit.apply_status(empowered, unit)
	unit.apply_status(focus, unit)
	unit.process_status_turn_start()
	unit.advance_status_durations()
	for status in negatives:
		unit.apply_status(status, cleanse, opponent)
	check(unit.is_stunned() and unit.get_taunt_target() == opponent, "debuffs suppress actions and record taunt source")
	var events := [0, 0]
	unit.statuses_changed.connect(func(): events[0] += 1)
	unit.stats_changed.connect(func(): events[1] += 1)
	check(unit.remove_negative_statuses() == 4, "Cleanse removes every bundled negative status")
	check(events == [1, 1], "batch removal sends one status and stat notification")
	check(unit.get_active_statuses().size() == 2 and unit.get_active_statuses()[0].remaining_turns == 2 and unit.get_active_statuses()[1].remaining_turns == 1, "positive statuses and their durations remain intact")
	check(unit.current_health == 75 and unit.get_effective_stat(UnitStat.Type.STRENGTH) == 13.0, "Cleanse preserves health and buffs")
	check(not unit.is_stunned() and unit.get_taunt_target() == null and unit.ability_available, "Cleanse clears Stun and Taunt and exposes an unspent action")
	check(unit._get_status_icon_entries().size() == 2, "only positive status icons remain")
	check(unit.remove_negative_statuses() == 0 and events == [1, 1], "repeated empty cleansing emits no spurious changes")
	unit.spend_ability_action()
	unit.spend_opportunity_reaction()
	unit.spend_movement(1.0)
	var movement := unit.remaining_movement
	unit.apply_status(negatives[2], opponent)
	unit.remove_negative_statuses()
	check(not unit.ability_available and not unit.opportunity_reaction_available and unit.remaining_movement == movement, "cleansing preserves spent resources")
	unit.apply_status(negatives[0], opponent)
	unit.process_status_turn_start()
	var damaged_health := unit.current_health
	unit.remove_negative_statuses()
	unit.process_status_turn_start()
	check(unit.current_health == damaged_health, "Cleanse prevents later burning ticks without reversing prior damage")
	check(unit.apply_status(negatives[0], opponent), "cleansing grants no immunity to reapplication")
	var positive_burning := negatives[0].duplicate() as StatusEffectDefinition
	positive_burning.status_id = &"positive_burning"
	positive_burning.polarity = StatusEffectDefinition.Polarity.POSITIVE
	unit.apply_status(positive_burning, opponent)
	unit.remove_negative_statuses()
	check(unit.get_active_statuses().any(func(active: ActiveStatus): return active.definition == positive_burning), "explicit positive polarity is retained even for a damage effect")
	unit.current_health = 0
	check(unit.remove_negative_statuses() == 0, "dead units reject cleansing")
	_clear()


func _test_forecasts() -> void:
	var unit := _unit()
	var caster := _unit(true, Vector2i(2, 1))
	var opponent := _unit(false, Vector2i(3, 1))
	unit.apply_status(negatives[1], opponent)
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
	var live_before := unit.capture_runtime_state()
	var bonus := snapshot.forecast_status_application(caster, unit, empowered)
	check(bonus.utility_hint == 12.0 and bonus.health_delta == 0, "Empower forecast rewards the buff without healing")
	empower.apply_primary_effect(caster, unit)
	check(is_equal_approx(snapshot.get_movement_range(unit), unit.get_movement_range()) and snapshot.get_max_health(unit) == unit.get_max_health(), "Empower forecast matches combined Speed/movement and Constitution")
	check(snapshot.forecast_status_application(caster, unit, empowered).utility_hint == 0, "refresh at full duration earns no duplicate reward")
	unit.restore_runtime_state(live_before, {opponent.scenario_unit_id: opponent})
	for status in [negatives[0], negatives[2], negatives[3]]:
		unit.apply_status(status, opponent)
	var before_cleanse := unit.capture_runtime_state()
	var original := AIBoardSnapshot.from_battle(units, grid.grid_size)
	var preview := original.duplicate_state()
	var predicted := preview.forecast_cleanse(caster, unit)
	check(predicted.removed_count == 4 and predicted.utility_hint > 0 and predicted.health_delta == 0 and predicted.armor_delta == 0, "forecast values removal without refunding damage")
	check(original.get_status_ids(unit).size() == 4 and unit.capture_runtime_state() == before_cleanse, "forecast preserves source snapshot and live units")
	check(not preview.is_stunned(unit) and preview.get_taunt_target(unit) == null, "snapshot clears Stun and Taunt")
	cleanse.apply_primary_effect(caster, unit)
	check(preview.get_movement_range(unit) == unit.get_movement_range() and preview.get_remaining_movement(unit) == unit.remaining_movement, "cleansing forecast restores exact movement without refilling it")
	check(preview.can_use_opportunity_reaction(unit) == unit.opportunity_reaction_available, "forecast retains reactions suppressed by Stun")
	check(preview.forecast_cleanse(caster, unit).utility_hint == 0, "repeated forecast cleanse has no benefit")
	var direct := cleanse.estimate_primary_effect_for_ai(caster, unit, unit.current_health)
	check(direct.utility_hint == 0 and direct.health_delta == 0, "empty direct estimate has zero benefit")
	unit.apply_status(negatives[1], opponent)
	var full := AIBoardSnapshot.from_battle(units, grid.grid_size)
	var full_benefit: float = full.estimate_cleanse(caster, unit).utility_hint
	unit.process_status_turn_start()
	unit.advance_status_durations()
	var partial := AIBoardSnapshot.from_battle(units, grid.grid_size)
	check(partial.estimate_cleanse(caster, unit).utility_hint == full_benefit * 0.5, "cleansing utility scales with remaining duration")
	check(partial.estimate_cleanse(opponent, unit).utility_hint < 0, "cleansing an opponent is scored against the caster")
	var weakness := StatusEffectDefinition.new()
	weakness.status_id = &"weakness"
	weakness.effect = StatusEffectDefinition.Effect.STAT_MODIFIER
	weakness.affected_stat = UnitStat.Type.CONSTITUTION
	weakness.percentage_amount = 40
	unit.apply_status(weakness, opponent)
	var weak_snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
	var hp := unit.current_health
	var estimate := weak_snapshot.forecast_cleanse(caster, unit)
	cleanse.apply_primary_effect(caster, unit)
	check(weak_snapshot.get_max_health(unit) == unit.get_max_health() and estimate.health_delta == 0 and unit.current_health == hp, "removing a Constitution penalty restores max health without healing")
	unit.apply_status(negatives[0], opponent)
	unit.process_status_turn_start()
	var burning_snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
	check(burning_snapshot.estimate_cleanse(caster, unit).utility_hint == 1.0, "cleansing only values Burning ticks that have not already happened")
	_clear()


func _test_execution() -> void:
	var caster := _unit()
	var ally := _unit(true, Vector2i(2, 1))
	var enemy := _unit(false, Vector2i(3, 1))
	var distant := _unit(true, Vector2i(10, 10))
	for ability in [empower, cleanse]:
		check(targeting.is_valid_primary_target(caster, caster.grid_cell, ability, units), "caster is a valid support target")
		check(targeting.is_valid_primary_target(caster, ally.grid_cell, ability, units), "ally is a valid support target")
		check(not targeting.is_valid_primary_target(caster, enemy.grid_cell, ability, units), "enemies are invalid support targets")
		check(not targeting.is_valid_primary_target(caster, distant.grid_cell, ability, units), "out-of-range allies are rejected")
		ally.current_health = 0
		check(not targeting.is_valid_primary_target(caster, ally.grid_cell, ability, units), "dead targets are rejected")
		ally.current_health = 100
	check(await executor.execute(caster, empower, ally.grid_cell, units, grid, targeting), "Empower executes on an ally")
	check(not caster.ability_available and ally.get_active_statuses().size() == 1, "Empower spends one action and applies one buff")
	caster.reset_ability_action()
	ally.apply_status(negatives[2], enemy)
	check(await executor.execute(caster, cleanse, ally.grid_cell, units, grid, targeting), "ally can cleanse a stunned unit")
	check(not ally.is_stunned() and ally.get_active_statuses().size() == 1, "executor removes Stun and keeps Empowered")
	caster.reset_ability_action()
	check(await executor.execute(caster, cleanse, caster.grid_cell, units, grid, targeting), "empty self Cleanse still executes")
	check(not caster.ability_available, "empty Cleanse spends the action")
	caster.reset_ability_action()
	caster.apply_status(negatives[2], enemy)
	check(not await executor.execute(caster, cleanse, caster.grid_cell, units, grid, targeting), "stunned caster cannot self-cleanse")
	_clear()


func _test_ai_selection() -> void:
	var caster := _unit(false)
	caster.ability_overrides = [cleanse]
	var ally := _unit(false, Vector2i(2, 1))
	var enemy := _unit(true, Vector2i(7, 1))
	ally.apply_status(negatives[2], enemy)
	var planner := EnemyAIPlanner.new()
	var pathfinder := GridPathfinder.new(grid.grid_size)
	var state := ally.capture_runtime_state()
	var plan := planner.choose_plan(caster, units, pathfinder, targeting)
	check(plan.ability == cleanse and plan.target_cell == ally.grid_cell, "AI chooses to cleanse a stunned ally")
	check(ally.capture_runtime_state() == state, "AI planning does not alter a live debuff")
	ally.remove_negative_statuses()
	plan = planner.choose_plan(caster, units, pathfinder, targeting)
	check(plan.ability == null, "AI does not spend an action on an empty cleanse")
	_clear()


func _test_ui() -> void:
	var unit := _unit()
	unit.apply_status(empowered, unit)
	var bar := (load("res://scenes/ability_bar.tscn") as PackedScene).instantiate() as AbilityBar
	arena.add_child(bar)
	bar.rebuild(unit, true)
	check(bar._get_entries().get_child_count() == 2, "ability bar shows both support spells")
	check(bar._get_entries().get_child(0).tooltip_text.contains("Positive status") and bar._get_entries().get_child(1).tooltip_text.contains("negative statuses"), "ability tooltips describe polarity and cleansing")
	check(unit._get_status_icon_entries()[0].definition == empowered, "Empowered uses the existing status icon row")
	if "--capture" in OS.get_cmdline_user_args():
		unit.position = Vector2(300, 280)
		bar.position = Vector2(60, 350)
		var description := Label.new()
		description.position = Vector2(60, 40)
		description.text = "Empower and Cleanse — Cleric support abilities\n\n" + empower.get_description(unit) + "\n\n" + cleanse.get_description(unit)
		description.size = Vector2(900, 140)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		arena.add_child(description)
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		check(image.save_png(DIRECTORY + "/abilities.png") == OK, "visual capture saves")
	bar.free()
