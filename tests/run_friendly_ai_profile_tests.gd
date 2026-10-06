extends "res://tests/run_ai_profile_tests.gd"

const DIRECTORY := "res://.godot/friendly_ai_validation"
var support: EnemyAIProfile
var aggressive: EnemyAIProfile
var support_class: CharacterClassDefinition
var empty_class: CharacterClassDefinition
var aggressive_class: CharacterClassDefinition


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	fixture = load("res://tests/test_enemy_ai.gd").new()
	support = profile()
	support.display_name = "Class Support"
	support.healing_weight = 10.0
	_save_resource(support, "support.tres")
	aggressive = profile()
	aggressive.display_name = "Unit Aggressive"
	aggressive.damage_weight = 10.0
	_save_resource(aggressive, "aggressive.tres")
	support_class = _class("support", support)
	empty_class = _class("empty", null)
	aggressive_class = _class("aggressive", aggressive)
	fixture._reset()
	fixture.test_profile_resources_and_configuration_warnings()
	check(not fixture._failed, "shared configuration checks accept General AI and friendly overrides: " + fixture._message)
	_test_precedence()
	_test_decisions()
	_test_snapshots_and_legacy_scene()
	await _test_battle_saves_and_automation()
	await _test_run_saves()
	fixture._free_tracked()
	print("FRIENDLY_AI_PROFILE_TESTS_%s: %d checks, %d failures" % [
		"OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _save_resource(resource: Resource, filename: String) -> void:
	var path := DIRECTORY.path_join(filename)
	check(ResourceSaver.save(resource, path) == OK, "save fixture " + filename)
	resource.take_over_path(path)


func _class(id: String, ai: EnemyAIProfile) -> CharacterClassDefinition:
	var result := CharacterClassDefinition.new()
	result.class_id = StringName("ai_test_" + id)
	result.display_name = id.capitalize()
	result.ai_profile = ai
	_save_resource(result, id + "_class.tres")
	return result


func _allocations(actor: TacticalCharacter, classes: Array) -> void:
	var levels: Array[CharacterClassLevel] = []
	for definition in classes:
		levels.append(CharacterClassLevel.create(definition))
	actor.class_level_overrides = levels


func _test_precedence() -> void:
	var actor := unit(true, Vector2i(1, 1))
	actor.definition.starting_class = support_class
	check(actor.get_ai_profile() == support, "template starting class supplies friendly profile")
	_allocations(actor, [empty_class, support_class, aggressive_class])
	check(actor.get_ai_profile() == support, "first configured class wins after skipping empty class")
	check(actor.get_enemy_ai_profile() == support, "legacy getter delegates to common getter")
	actor.ai_profile_override = aggressive
	check(actor.get_ai_profile() == aggressive, "unit override takes precedence over every class")
	check(actor.enemy_ai_profile == aggressive, "legacy property reads the neutral override")
	actor.enemy_ai_profile = support
	check(actor.ai_profile_override == support, "legacy property writes the neutral override")
	actor.ai_profile_override = null
	_allocations(actor, [empty_class, aggressive_class, support_class])
	check(actor.get_ai_profile() == aggressive, "reordering allocations changes inherited profile")
	check(actor.set_class_level(aggressive_class, 0), "remove configured class at runtime")
	check(actor.get_ai_profile() == support, "removed class is reflected in the next decision")
	_allocations(actor, [empty_class])
	check(actor.get_ai_profile() == EnemyAIProfile.get_default(), "all empty classes use General AI")
	empty_class.ai_profile = aggressive
	check(actor.get_ai_profile() == aggressive, "editing class resource affects next resolution")
	empty_class.ai_profile = null
	actor.definition.starting_class = null
	actor.class_level_overrides = []
	check(actor.get_ai_profile() == EnemyAIProfile.get_default(), "missing classes use General AI")
	var enemy := unit(false, Vector2i(3, 1))
	var archetype := EnemyDefinition.new()
	archetype.ai_profile = support
	enemy.definition = archetype
	_allocations(enemy, [aggressive_class])
	check(enemy.get_ai_profile() == support, "enemy archetype inheritance ignores friendly allocations")
	enemy.ai_profile_override = aggressive
	check(enemy.get_ai_profile() == aggressive, "enemy override still takes precedence")
	enemy.enemy_ai_profile = null
	archetype.ai_profile = null
	check(enemy.get_ai_profile() == EnemyAIProfile.get_default(), "empty enemy archetype uses General AI")
	for id in ["warrior", "archer", "wizard", "cleric"]:
		var authored := load("res://resources/classes/%s.tres" % id) as CharacterClassDefinition
		var inherited := unit(true, Vector2i(1, 1))
		inherited.definition.starting_class = authored
		var expected := authored.ai_profile if authored.ai_profile != null else EnemyAIProfile.get_default()
		check(inherited.get_ai_profile() == expected, "authored %s class profile resolves without a unit override" % id)


func _test_decisions() -> void:
	var strike := damage(10)
	var healing := heal(10)
	var actor := unit(true, Vector2i(1, 1), [strike, healing])
	var enemy := unit(false, Vector2i(3, 1))
	var ally := unit(true, Vector2i(1, 3))
	ally.current_health = ally.get_max_health() / 2
	var participants: Array[TacticalCharacter] = [actor, enemy, ally]
	_allocations(actor, [empty_class])
	check(plan(actor, participants).ability == strike, "General AI prefers damage in support fixture")
	_allocations(actor, [empty_class, support_class, aggressive_class])
	check(plan(actor, participants).ability == healing, "healing class changes friendly Auto Battle choice")
	actor.ai_profile_override = aggressive
	check(plan(actor, participants).ability == strike, "unit override changes the chosen action")
	actor.ai_profile_override = null
	_allocations(actor, [aggressive_class, support_class])
	check(plan(actor, participants).ability == strike, "planner resolves reordered classes each action")
	actor.set_class_level(aggressive_class, 0)
	check(plan(actor, participants).ability == healing, "planner resolves class changes each action")
	check(ally.current_health == ally.get_max_health() / 2, "planning does not apply live healing")


func _test_snapshots_and_legacy_scene() -> void:
	var actor := unit(true, Vector2i(1, 1))
	_allocations(actor, [support_class])
	actor.ai_profile_override = aggressive
	var setup: Dictionary = JSON.parse_string(JSON.stringify(actor.capture_setup_state()))
	check(setup.ai_profile_override == aggressive.resource_path, "snapshot stores explicit resource reference")
	check(not setup.has("enemy_ai_profile"), "snapshot uses only canonical field")
	check(EnemyAIProfile.validate_setup(setup).is_empty(), "explicit profile reference validates")
	actor.ai_profile_override = support
	actor.apply_setup_state(setup)
	check(actor.ai_profile_override == aggressive, "JSON snapshot restores override")
	setup.erase("ai_profile_override")
	actor.apply_setup_state(setup)
	check(actor.ai_profile_override == aggressive, "absent snapshot field preserves authored assignment")
	setup.ai_profile_override = ""
	actor.apply_setup_state(setup)
	check(actor.ai_profile_override == null and actor.get_ai_profile() == support,
		"explicit empty snapshot clears override and enables class inheritance")
	var inherited := actor.capture_setup_state()
	check(inherited.ai_profile_override == "", "inherited profile is not copied into override")
	support_class.ai_profile = aggressive
	actor.apply_setup_state(inherited)
	check(actor.get_ai_profile() == aggressive, "restoring inherited snapshot uses current class resource")
	support_class.ai_profile = support
	for bad in [null, 3, {}, "res://missing_ai_profile.tres", "res://resources/classes/warrior.tres"]:
		check(not EnemyAIProfile.validate_setup({"ai_profile_override": bad}).is_empty(),
			"reject invalid saved profile reference %s" % str(bad))
	actor.ai_profile_override = EnemyAIProfile.new()
	check(not EnemyAIProfile.validate_setup(actor.capture_setup_state()).is_empty(),
		"unsaved runtime override cannot be silently lost in a save")
	# Exercise a real old scene property, including an inline profile resource.
	var path := DIRECTORY.path_join("legacy_profile.tscn")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('[gd_scene load_steps=4 format=3]\n\n[ext_resource type="Script" path="res://scripts/initiative_actor.gd" id="actor"]\n[ext_resource type="Script" path="res://scripts/enemy_ai_profile.gd" id="profile"]\n\n[sub_resource type="Resource" id="LegacyAI"]\nscript = ExtResource("profile")\ndisplay_name = "Legacy inline"\nhealing_weight = 7.0\n\n[node name="LegacyUnit" type="Node2D"]\nscript = ExtResource("actor")\nenemy_ai_profile = SubResource("LegacyAI")\n')
	file.close()
	var scene := load(path) as PackedScene
	var legacy := scene.instantiate() as TacticalCharacter
	check(legacy.ai_profile_override != null and legacy.ai_profile_override.healing_weight == 7.0,
		"legacy scene property loads into neutral override")
	var legacy_setup := legacy.capture_setup_state()
	check(EnemyAIProfile.validate_setup(legacy_setup).is_empty(), "saved inline scene reference validates")
	var restored := TacticalCharacter.new()
	restored.apply_setup_state(legacy_setup)
	check(restored.ai_profile_override == legacy.ai_profile_override, "inline legacy reference restores from setup")
	var migrated := PackedScene.new()
	check(migrated.pack(legacy) == OK, "legacy scene can be repacked")
	var migrated_path := DIRECTORY.path_join("migrated_profile.tscn")
	check(ResourceSaver.save(migrated, migrated_path) == OK, "legacy scene resaves")
	var scene_text := FileAccess.get_file_as_string(migrated_path)
	check(scene_text.contains("ai_profile_override =") and not scene_text.contains("enemy_ai_profile ="),
		"resaved scene stores only neutral property")
	legacy.free()
	restored.free()


func _battle(payload: Dictionary = {}) -> TacticalBattle:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres") as BattleMapDefinition
	battle.pending_restore_payload = payload
	root.add_child(battle)
	return battle


func _remove_battle(battle: TacticalBattle) -> void:
	battle.shutdown_battle()
	battle.queue_free()
	await process_frame


func _test_battle_saves_and_automation() -> void:
	var battle := _battle()
	var actor := battle.turn_manager.current_unit
	var ally: TacticalCharacter
	var enemy: TacticalCharacter
	for participant in battle._characters:
		participant.movement_animation_speed = 1000.0
		if participant != actor and participant.is_friendly(): ally = participant
		if not participant.is_friendly(): enemy = participant
	_allocations(actor, [empty_class, support_class])
	var strike := damage(10)
	var healing := heal(10)
	_save_resource(strike, "strike.tres")
	_save_resource(healing, "heal.tres")
	actor.set_dev_ability_loadout([strike, healing])
	actor.spend_movement(actor.remaining_movement)
	ally.apply_damage(ally.current_health / 2)
	check(actor.is_friendly() and not battle._is_ai_controlled(actor), "class profile preserves manual friendly control")
	check(battle._is_ai_controlled(enemy), "enemies are automated while Auto Battle is off")
	var casts: Array[AbilityDefinition] = []
	battle._ability_executor.ability_started.connect(func(caster, chosen, _cell):
		if caster == actor:
			casts.append(chosen)
			battle.set_auto_battle_enabled(false))
	var ally_health := ally.current_health
	var ap := actor.action_points
	battle.set_auto_battle_enabled(true)
	check(battle._is_ai_controlled(actor) and battle.end_turn_button.disabled, "Auto Battle takes over profiled friendly")
	var deadline := Time.get_ticks_msec() + 10000
	while (casts.is_empty() or battle._movement_locked) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(casts == [healing] and ally.current_health > ally_health, "Auto Battle executes class-focused healing")
	check(not battle.auto_battle_enabled and battle.turn_manager.current_unit == actor,
		"toggle off hands the same friendly turn back")
	check(actor.action_points == ap - 1 and not battle.end_turn_button.disabled,
		"profiled handback preserves remaining AP and manual controls")
	check(battle._ai_debug_history[0].contains(support.display_name), "AI log names inherited class profile")
	check(battle._ai_debug_checkpoints.size() == 1, "profiled friendly action creates checkpoint")
	var inherited_checkpoint: Dictionary = battle._ai_debug_checkpoints[0].duplicate(true)
	check(ScenarioSaveStore.validate_payload(inherited_checkpoint).ok, "inherited profile checkpoint validates")
	check(_setup_for(inherited_checkpoint, actor.scenario_unit_id).ai_profile_override == "",
		"checkpoint keeps inheritance enabled")
	actor.ai_profile_override = aggressive
	var actor_id := actor.scenario_unit_id
	battle.set_auto_battle_enabled(true)
	deadline = Time.get_ticks_msec() + 10000
	while (casts.size() < 2 or battle._movement_locked) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(casts == [healing, strike], "next automated action resolves newly assigned unit override")
	check(battle._ai_debug_checkpoints.size() == 2, "override action creates a second checkpoint")
	var override_checkpoint: Dictionary = battle._ai_debug_checkpoints[1].duplicate(true)
	check(_setup_for(override_checkpoint, actor_id).ai_profile_override == aggressive.resource_path,
		"AI checkpoint persists explicit override reference")
	check(ScenarioSaveStore.validate_payload(override_checkpoint).ok, "explicit override checkpoint validates")
	var exact := battle.capture_save_payload(false)
	var saved := ScenarioSaveStore.save_new(exact, DIRECTORY)
	check(saved.ok, "scenario with explicit override saves to disk")
	if saved.ok:
		var loaded := ScenarioSaveStore.load_save(saved.path, DIRECTORY)
		check(loaded.ok, "scenario with explicit override reloads from disk")
		if loaded.ok: exact = loaded.payload
	for bad in [3, "res://missing_ai_profile.tres", "res://resources/classes/warrior.tres"]:
		var corrupt := exact.duplicate(true)
		_setup_for(corrupt, actor_id).ai_profile_override = bad
		check(not ScenarioSaveStore.validate_payload(corrupt).ok, "scenario rejects invalid profile %s" % str(bad))
	var restart_payloads: Array[Dictionary] = []
	battle.battle_reload_requested.connect(func(payload): restart_payloads.append(payload))
	battle._on_restart_button_pressed()
	check(restart_payloads.size() == 1, "restart accepts configured profile")
	await _remove_battle(battle)
	for payload in [exact, restart_payloads[0], inherited_checkpoint, override_checkpoint]:
		var restored := _battle(payload)
		await process_frame
		var character := _character_for(restored, actor_id)
		var expected := aggressive if payload != inherited_checkpoint else support
		check(character.get_ai_profile() == expected, "scenario/restart/checkpoint resolves expected profile")
		check(not restored.auto_battle_enabled and not restored._movement_locked, "restored battle starts with manual control")
		await _remove_battle(restored)


func _setup_for(payload: Dictionary, id: String) -> Dictionary:
	for setup in payload.setup.units:
		if setup.id == id: return setup
	return {}


func _character_for(battle: TacticalBattle, id: String) -> TacticalCharacter:
	for actor in battle._characters:
		if actor.scenario_unit_id == id: return actor
	return null


func _test_run_saves() -> void:
	var controller := RunController.new()
	controller.config = load("res://resources/run/default_run.tres")
	controller.save_path = DIRECTORY.path_join("profile_run.json")
	root.add_child(controller)
	check(controller.new_run(10), "run fixture creates checkpoint")
	var actor := (load("res://scenes/friendlies/cleric.tscn") as PackedScene).instantiate() as TacticalCharacter
	actor.scenario_unit_id = controller.state.party[0].id
	_allocations(actor, [empty_class, support_class])
	actor.ai_profile_override = aggressive
	controller.state.party[0] = RunPartyMember.from_character(actor)
	check(controller.save_store.save_run(controller.state), "run saves explicit profile reference")
	var loaded := controller.save_store.load_run()
	check(loaded != null and loaded.party[0].setup.ai_profile_override == aggressive.resource_path,
		"run reload preserves explicit profile reference")
	if loaded != null:
		actor.ai_profile_override = null
		actor.apply_setup_state(loaded.party[0].setup)
		check(actor.get_ai_profile() == aggressive, "run setup restores unit precedence")
		for bad in [false, "res://missing_ai_profile.tres", "res://resources/classes/warrior.tres"]:
			var data := loaded.to_data()
			data.party[0].setup.ai_profile_override = bad
			check(RunState.from_data(data) == null, "run rejects invalid profile %s" % str(bad))
		actor.ai_profile_override = null
		loaded.party[0] = RunPartyMember.from_character(actor)
		check(controller.save_store.save_run(loaded), "run saves class inheritance")
		loaded = controller.save_store.load_run()
		actor.ai_profile_override = aggressive
		actor.apply_setup_state(loaded.party[0].setup)
		check(actor.ai_profile_override == null and actor.get_ai_profile() == support,
			"run reload clears override and inherits first configured class")
		var legacy := loaded.to_data()
		legacy.party[0].setup.erase("ai_profile_override")
		check(RunState.from_data(legacy) != null, "old run snapshots without profile field still load")
	actor.free()
	controller.queue_free()
	await process_frame
