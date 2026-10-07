extends SceneTree

const STATS: Array[UnitStat.Type] = [UnitStat.Type.STRENGTH, UnitStat.Type.DEXTERITY, UnitStat.Type.INTELLIGENCE, UnitStat.Type.CONSTITUTION, UnitStat.Type.SPEED, UnitStat.Type.MOVEMENT_RANGE]
const FIELDS: Array[String] = ["default_strength", "default_dexterity", "default_intelligence", "default_constitution", "default_speed", "default_movement_range"]
const OVERRIDES: Array[String] = ["strength_override", "dexterity_override", "intelligence_override", "constitution_override", "speed_override", "movement_range_override"]
var checks := 0
var failures: Array[String] = []
var directory := "res://.godot/class_stat_validation/%d" % Time.get_ticks_usec()


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _class(values: Array) -> CharacterClassDefinition:
	var result := CharacterClassDefinition.new()
	result.class_id = &"stat_test"
	for index in FIELDS.size():
		result.set(FIELDS[index], values[index])
	return result


func _unit(character_class: CharacterClassDefinition) -> TacticalCharacter:
	var unit := TacticalCharacter.new()
	unit.definition = CharacterDefinition.new()
	unit.definition.starting_class = character_class
	return unit


func _modifier(stat: UnitStat.Type, value: float, operation := StatModifierDefinition.Operation.FLAT) -> StatModifierDefinition:
	var result := StatModifierDefinition.new()
	result.stat = stat
	result.value = value
	result.operation = operation
	return result


func _run() -> void:
	create_timer(30.0).timeout.connect(func(): push_error("Class stat tests timed out"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	_test_shipped_defaults()
	_test_precedence_and_fallback()
	_test_multiclass_and_notifications()
	_test_modifiers()
	_test_saved_members()
	await _test_runtime_ui()
	for failure in failures:
		push_error(failure)
	print("CLASS_STAT_TESTS_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_shipped_defaults() -> void:
	var expected := {"warrior": [1, 1, 1, 25, 8, 5.0], "archer": [1, 1, 1, 12, 12, 6.0], "wizard": [1, 1, 1, 6, 10, 6.0], "cleric": [1, 1, 1, 6, 10, 6.0]}
	for id in expected:
		var character_class := load("res://resources/classes/%s.tres" % id) as CharacterClassDefinition
		var unit := (load("res://scenes/friendlies/%s.tscn" % id) as PackedScene).instantiate() as TacticalCharacter
		for index in STATS.size():
			check(is_equal_approx(character_class.get_default_stat(STATS[index]), float(expected[id][index])), "%s authored %s" % [id, FIELDS[index]])
			check(float(unit.get(OVERRIDES[index])) == -1.0, "%s inherits %s" % [id, OVERRIDES[index]])
			var value := float(expected[id][index])
			if STATS[index] == UnitStat.Type.MOVEMENT_RANGE:
				value = UnitStat.get_scaling_rules().calculate_speed_adjusted_base_movement(value, float(expected[id][4]))
			check(is_equal_approx(unit.get_base_stat(STATS[index]), value), "%s resolved %s" % [id, FIELDS[index]])
		check(unit.get_max_health() == int(expected[id][3]) * 4, "%s retains starting HP" % id)
		check(unit.get_initiative() == int(expected[id][4]), "%s retains initiative" % id)
		if id in ["wizard", "cleric"]:
			check(unit.get_effective_stat(UnitStat.Type.INTELLIGENCE) == 3.0, "%s Staff still grants +2 Intelligence" % id)
		unit.free()
	var encounter := (load("res://scenes/maps/goblin_skirmish.tscn") as PackedScene).instantiate()
	var overrides: Array[int] = []
	for node in encounter.find_children("*", "Node2D", true, false):
		if node is TacticalCharacter and node.is_friendly():
			overrides.append(node.constitution_override)
	check(overrides.has(5) and overrides.has(3), "intentional encounter Constitution overrides survive")
	encounter.free()


func _test_precedence_and_fallback() -> void:
	var character_class := _class([3, 4, 5, 6, 10, 7.0])
	var unit := _unit(character_class)
	for index in STATS.size():
		unit.set(OVERRIDES[index], 20)
		var expected := 20.0 if STATS[index] != UnitStat.Type.MOVEMENT_RANGE else 10.0
		check(unit.get_base_stat(STATS[index]) == expected, "individual override wins for %s" % FIELDS[index])
		unit.set(OVERRIDES[index], 0)
		expected = 0.0 if STATS[index] != UnitStat.Type.MOVEMENT_RANGE else 2.0
		check(unit.get_base_stat(STATS[index]) == expected, "zero override is explicit for %s" % FIELDS[index])
		unit.set(OVERRIDES[index], -1)
		character_class.set(FIELDS[index], 0)
		expected = 0.0 if STATS[index] != UnitStat.Type.MOVEMENT_RANGE else 2.0
		check(unit.get_base_stat(STATS[index]) == expected, "zero class default is explicit for %s" % FIELDS[index])
		character_class.set(FIELDS[index], -1)
		var template_values := [10.0, 10.0, 10.0, 25.0, 10.0, 6.0]
		check(unit.get_base_stat(STATS[index]) == template_values[index], "-1 falls back to template for %s" % FIELDS[index])
	check(unit.get_base_stat(UnitStat.Type.NONE) == 0.0, "NONE has no stat")
	unit.definition.starting_class = null
	check(unit.get_max_health() == 100, "classless friendly keeps template stats")
	unit.definition = null
	check(unit.get_base_stat(UnitStat.Type.STRENGTH) == 0.0, "missing template is safe")
	unit.free()
	var legacy := _class([-1, -1, -1, -1, -1, -1])
	var path := directory + "/legacy.tres"
	check(ResourceSaver.save(legacy, path) == OK, "legacy-compatible class saves")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as CharacterClassDefinition
	unit = _unit(loaded)
	check(unit.get_base_stat(UnitStat.Type.STRENGTH) == 10.0 and unit.get_movement_range() == 6.0, "class with omitted default fields retains template values on reload")
	unit.free()
	var enemy := TacticalCharacter.new()
	enemy.definition = CharacterDefinition.new()
	enemy.definition.faction = CharacterDefinition.Faction.ENEMY
	enemy.definition.starting_class = character_class
	enemy.class_level_overrides = [CharacterClassLevel.create(character_class)]
	character_class.default_constitution = 3
	check(enemy.get_max_health() == 100 and enemy.get_base_stat(UnitStat.Type.STRENGTH) == 10.0, "enemies ignore class defaults")
	enemy.free()


func _test_multiclass_and_notifications() -> void:
	var first := _class([3, 4, 5, 10, 10, 6.0])
	var second := _class([8, 9, 10, 3, 8, 3.0])
	second.class_id = &"second"
	var unit := _unit(first)
	root.add_child(unit)
	unit.reset_movement()
	unit.spend_movement(2.0)
	unit.current_health = 35
	unit.class_level_overrides = [CharacterClassLevel.create(first), CharacterClassLevel.create(second, 20)]
	check(unit.get_max_health() == 40 and unit.get_base_stat(UnitStat.Type.STRENGTH) == 3.0, "first allocation wins regardless of invested levels")
	first.default_dexterity = -1
	check(unit.get_base_stat(UnitStat.Type.DEXTERITY) == 10.0, "unset first-class stat falls back to template rather than later classes")
	first.default_dexterity = 4
	unit.set_class_level(first, 15)
	check(unit.current_health == 35 and unit.remaining_movement == 4.0 and unit.get_max_health() == 40, "level changes grant no stat bonus, healing, or movement")
	var events := [0, 0, 0]
	unit.stats_changed.connect(func(): events[0] += 1)
	unit.health_changed.connect(func(_health, _maximum): events[1] += 1)
	unit.movement_remaining_changed.connect(func(_remaining, _maximum): events[2] += 1)
	first.default_constitution = 4
	check(unit.current_health == 16 and unit.get_max_health() == 16 and events[1] > 0, "editing class Constitution clamps health and notifies")
	first.default_constitution = 12
	check(unit.current_health == 16 and unit.get_max_health() == 48, "increasing class Constitution grants no healing")
	first.default_movement_range = 2.0
	check(unit.remaining_movement == 2.0 and events[2] > 0, "editing class movement clamps remaining movement and notifies")
	first.default_movement_range = 8.0
	check(unit.remaining_movement == 2.0, "increasing class movement does not restore spent movement")
	var another := _unit(first)
	another.strength_override = 99
	first.default_strength = 7
	check(unit.get_base_stat(UnitStat.Type.STRENGTH) == 7.0 and another.get_base_stat(UnitStat.Type.STRENGTH) == 99.0, "shared class edits respect independent overrides")
	unit.class_level_overrides = [CharacterClassLevel.create(second), CharacterClassLevel.create(first)]
	check(unit.get_max_health() == 12 and unit.current_health == 12 and unit.get_base_stat(UnitStat.Type.STRENGTH) == 8.0, "reordering changes stat class and clamps health")
	var before: int = events[0]
	first.default_strength = 6
	check(events[0] == before, "former stat class is disconnected")
	second.default_strength = 11
	check(events[0] > before and unit.get_base_stat(UnitStat.Type.STRENGTH) == 11.0, "new first class is watched")
	check(unit.set_class_level(second, 0) and unit.get_max_health() == 48 and unit.current_health == 12, "removing first class selects next without healing")
	unit.class_level_overrides[0].character_class = second
	check(unit.get_max_health() == 12 and unit.get_base_stat(UnitStat.Type.STRENGTH) == 11.0, "editing a nested allocation resource refreshes its stat class")
	unit.class_level_overrides[0].level = 99
	check(unit.get_max_health() == 12 and unit.current_health == 12, "nested level edits do not grant stats or healing")
	unit.class_level_overrides = []
	unit.definition.starting_class = second
	check(unit.get_max_health() == 12, "changing template starting class updates inherited defaults")
	another.free()
	unit.free()


func _test_runtime_ui() -> void:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	root.add_child(battle)
	check(battle.initialization_succeeded, "class-stat battle fixture initializes")
	battle.set_process(false)
	var actor := battle._characters[0]
	var character_class := _class([3, 4, 5, 10, 12, 7.0])
	actor.class_level_overrides = [CharacterClassLevel.create(character_class)]
	actor.clear_dev_stat_override(UnitStat.Type.CONSTITUTION)
	actor.equip_item(load("res://resources/items/weapons/iron_sword.tres"))
	battle.turn_manager.current_unit = actor
	battle.turn_manager.current_index = battle.turn_manager.turn_order.find(actor)
	actor.reset_ability_action()
	battle._on_turn_started(actor)
	var panel := battle.dev_mode_panel
	panel.select_unit(actor)
	check(panel.strength_spin.value == 3 and panel.constitution_spin.value == 10 and panel.speed_spin.value == 12 and panel.movement_spin.value == 7, "developer panel displays class defaults and unadjusted base movement")
	character_class.default_strength = 9
	var strike := actor.get_basic_attack_ability()
	var button := battle.ability_bar.get_node("Margin/HBox").get_child(0) as Button
	check(button.text.contains(strike.get_damage_summary(actor)) and panel.strength_spin.value == 9, "live class edit refreshes battle damage preview and developer panel")
	character_class.default_movement_range = 4.0
	check(panel.movement_spin.value == 4 and actor.get_movement_range() == 4.5, "developer base movement stays distinct from Speed-adjusted movement")
	actor.set_dev_stat_override(UnitStat.Type.STRENGTH, 20)
	check(panel.strength_spin.value == 20, "developer override still takes priority")
	panel._stat_reset(UnitStat.Type.STRENGTH)
	check(panel.strength_spin.value == 9 and actor.strength_override == -1, "developer reset returns to class default")
	actor.spend_action_points(actor.action_points)
	var remaining := actor.remaining_movement
	character_class.default_strength = 10
	check(not actor.ability_available and actor.remaining_movement == remaining, "live default edits do not restore battle actions or movement")
	panel.clear_unit_selection()
	battle.shutdown_battle()
	battle.free()
	await process_frame


func _test_modifiers() -> void:
	var unit := _unit(_class([10, 10, 10, 10, 10, 6.0]))
	root.add_child(unit)
	var item := ItemDefinition.new()
	item.modifiers = [_modifier(UnitStat.Type.STRENGTH, 2.0), _modifier(UnitStat.Type.SPEED, -2.0), _modifier(UnitStat.Type.CONSTITUTION, 2.0)]
	unit.equip_item(item)
	var status := StatusEffectDefinition.new()
	status.status_id = &"class_stats_test"
	status.modifiers = [_modifier(UnitStat.Type.STRENGTH, 0.5, StatModifierDefinition.Operation.PERCENT_ADD), _modifier(UnitStat.Type.SPEED, 4.0)]
	unit.apply_status(status)
	check(unit.get_effective_stat(UnitStat.Type.STRENGTH) == 18.0, "equipment and status modifier ordering is preserved")
	check(unit.get_effective_stat_without_equipment(UnitStat.Type.STRENGTH) == 15.0, "equipment-free preview retains class and statuses")
	check(unit.get_initiative() == 12 and unit.get_movement_range() == 6.5, "effective Speed still drives initiative and movement")
	check(unit.get_max_health() == 48, "equipment Constitution still drives health")
	check(unit.calculate_stat_with_statuses(UnitStat.Type.STRENGTH, [status]) == 18.0, "AI simulation uses class defaults")
	unit.remove_status(status.status_id)
	unit.unequip_item(item.slot)
	check(unit.get_max_health() == 40 and unit.get_movement_range() == 6.0, "removing modifiers restores class defaults")
	unit.free()


func _test_saved_members() -> void:
	var character_class := _class([2, 3, 4, 10, 10, 6.0])
	var path := directory + "/saved_class.tres"
	check(ResourceSaver.save(character_class, path) == OK, "test class saves")
	character_class = load(path) as CharacterClassDefinition
	var item := ItemDefinition.new()
	item.modifiers = [_modifier(UnitStat.Type.CONSTITUTION, 2.0)]
	var item_path := directory + "/saved_item.tres"
	check(ResourceSaver.save(item, item_path) == OK, "test Constitution equipment saves")
	item = load(item_path) as ItemDefinition
	var unit := (load("res://scenes/friendlies/warrior.tscn") as PackedScene).instantiate() as TacticalCharacter
	unit.class_level_overrides = [CharacterClassLevel.create(character_class)]
	unit.use_complete_equipment_override = true
	unit.complete_equipment_overrides = [item]
	unit._runtime_stats_initialized = false
	var member := RunPartyMember.from_character(unit)
	member.health = 45
	var data: Dictionary = JSON.parse_string(JSON.stringify(member.to_data()))
	character_class.default_constitution = 3
	var restored := RunPartyMember.from_data(data)
	check(restored != null and restored.max_health == 20 and restored.health == 20, "saved inherited HP uses current class and saved equipment, clamping health")
	check(data.max_health == 48 and data.health == 45 and data.setup.stat_overrides.constitution == -1, "load does not mutate save input or freeze inherited stats")
	character_class.default_constitution = 20
	restored = RunPartyMember.from_data(data)
	check(restored != null and restored.max_health == 88 and restored.health == 45, "higher class defaults grant no healing on load")
	data.setup.stat_overrides.constitution = 25
	data.max_health = 108
	data.health = 100
	restored = RunPartyMember.from_data(data)
	check(restored != null and restored.max_health == 108 and restored.health == 100, "legacy explicit saved overrides remain authoritative")
	data.setup.stat_overrides.constitution = -1
	data.lost = true
	data.health = 0
	data.equipment = []
	restored = RunPartyMember.from_data(data)
	check(restored != null and restored.lost and restored.health == 0 and restored.max_health == 80 and restored.equipment.is_empty(), "lost members remain lost and do not recover setup equipment")
	data.health = -1
	check(RunPartyMember.from_data(data) == null, "invalid health is rejected before reconciliation")
	unit.free()
