extends SceneTree

const DIRECTORY := "res://.godot/reassemble_validation"
const PASSIVE := "res://resources/passives/reassemble.tres"
var checks := 0
var failures: Array[String] = []
var arena: Node2D
var grid: IsometricGrid


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func frames(count := 3) -> void:
	for index in range(count):
		await process_frame


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	arena = Node2D.new()
	root.add_child(arena)
	grid = IsometricGrid.new()
	grid.grid_size = Vector2i(12, 12)
	arena.add_child(grid)
	_test_authoring()
	for variant in ["warrior", "archer"]:
		_test_lifecycle(variant)
	await _test_turns()
	await _test_movement()
	await _test_multiple_arrows()
	await _test_caster_collapse()
	_test_ai()
	arena.free()
	await _test_battle_saves()
	await _test_run()
	for failure in failures:
		push_error(failure)
	print("REASSEMBLE_TESTS_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func skeleton(variant := "warrior", cell := Vector2i(2, 2)) -> TacticalCharacter:
	var unit := (load("res://scenes/enemies/skeleton_%s.tscn" % variant) as PackedScene).instantiate() as TacticalCharacter
	unit.starting_grid_cell = cell
	unit.scenario_unit_id = "skeleton_" + variant
	arena.add_child(unit)
	unit.initialize(grid)
	unit.reset_movement()
	unit.reset_ability_action()
	return unit


func friendly() -> TacticalCharacter:
	var unit := (load("res://scenes/friendlies/friend_a.tscn") as PackedScene).instantiate() as TacticalCharacter
	unit.starting_grid_cell = Vector2i(1, 2)
	unit.speed_override = 100
	unit.scenario_unit_id = "friendly"
	arena.add_child(unit)
	unit.initialize(grid)
	return unit


func _test_authoring() -> void:
	var passive := load(PASSIVE) as PassiveAbilityDefinition
	var effect := passive.effects[0] as ReassemblePassiveEffect
	check(passive.validate().is_empty() and effect.pile_health == 1 and effect.restored_health_percentage == 100.0, "shared Reassemble has the authored settings")
	check((load("res://resources/dev_tool_catalog.tres") as DevToolCatalog).passive_abilities.has(passive), "Reassemble is in the developer catalog")
	var artwork := effect.pile_texture.get_image()
	check(artwork.detect_alpha() != Image.ALPHA_NONE and artwork.get_pixel(0, 0).a == 0.0, "bone-pile artwork has actual transparency")
	var custom := effect.duplicate() as ReassemblePassiveEffect
	custom.pile_health = 2
	custom.restored_health_percentage = 50.0
	var inline_passive := PassiveAbilityDefinition.new()
	inline_passive.passive_id = &"custom_reassemble"
	inline_passive.effects = [custom]
	var encoded := PassiveLoadout.to_data([inline_passive])
	check(PassiveLoadout.validate_setup({"override_passives": true, "passives": encoded}).is_empty(), "inline effect settings validate")
	var decoded := PassiveLoadout.from_data(encoded)[0].effects[0] as ReassemblePassiveEffect
	check(decoded.pile_health == 2 and decoded.restored_health_percentage == 50.0 and decoded.pile_texture == effect.pile_texture, "inline effect settings round trip")
	var actor := skeleton()
	actor.set_dev_passive_loadout([inline_passive])
	actor.permanent_defeat = true
	actor.apply_damage(999)
	check(actor.is_bone_pile and actor.current_health == 2, "custom pile health works with permanent-defeat friend rules")
	actor.set_dev_passive_loadout([])
	actor.reform_from_bones()
	check(actor.current_health == 10, "pending reformation uses captured 50% settings even after developer removal")
	actor.apply_damage(999)
	check(actor.current_health == 0 and not actor.is_bone_pile, "removed passive does not trigger on a subsequent defeat")
	actor.free()
	var path := DIRECTORY + "/custom_passive.tres"
	check(ResourceSaver.save(inline_passive, path) == OK, "custom passive saves as an Inspector resource")
	var reloaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PassiveAbilityDefinition
	check(reloaded.effects[0].pile_health == 2 and reloaded.effects[0].restored_health_percentage == 50.0, "resource reload retains edited fields")
	encoded[0].effects[0].pile_health = 0
	check(not PassiveLoadout.validate_setup({"override_passives": true, "passives": encoded}).is_empty(), "invalid pile health is rejected")
	for property in effect.get_property_list():
		if property.name in ["pile_health", "restored_health_percentage", "pile_texture"]:
			check(bool(property.usage & PROPERTY_USAGE_EDITOR) and bool(property.usage & PROPERTY_USAGE_STORAGE), "Inspector exposes and stores " + str(property.name))


func _test_lifecycle(variant: String) -> void:
	var unit := skeleton(variant)
	var maximum := unit.get_max_health()
	var original_cell := unit.grid_cell
	var equipment := unit.get_equipped_items()
	var original_facing := unit.current_facing
	var defeated_events: Array = []
	unit.defeated.connect(func(actor): defeated_events.append(actor))
	unit.apply_status(load("res://resources/statuses/burning.tres"))
	unit.apply_status(load("res://resources/statuses/focus.tres"))
	unit.apply_damage(100000)
	check(unit.is_bone_pile and unit.current_health == 1 and unit.get_max_health() == 1, variant + " collapses with no overkill spill")
	check(defeated_events.is_empty() and unit.is_present_on_map(), "collapse is not final defeat")
	check(unit.grid_cell == original_cell and unit.get_equipped_items() == equipment and unit.current_facing == original_facing, "identity, equipment, cell and facing survive collapse")
	check(unit.get_active_statuses().is_empty(), "collapse clears buffs and debuffs")
	unit.reset_movement()
	unit.reset_ability_action()
	unit.reset_opportunity_reaction()
	check(not unit.can_move() and not unit.ability_available and not unit.opportunity_reaction_available and unit.remaining_movement == 0.0, "pile cannot act even after resets")
	unit.heal(999)
	check(unit.current_health == 1 and unit.is_bone_pile, "healing cannot reform or increase pile HP")
	check(unit.get_combat_display_name() == "Bone Pile" and unit.contains_global_point(unit.global_position + Vector2(0, -20)), "pile presentation and hit area are active")
	unit.reform_from_bones()
	check(not unit.is_bone_pile and unit.current_health == maximum and unit.can_move(), "reformation restores full original maximum health")
	unit.apply_damage(999)
	check(unit.is_bone_pile, "Reassemble repeats")
	var snapshot := unit.capture_runtime_state()
	unit.apply_damage(1)
	check(unit.current_health == 0 and not unit.visible and defeated_events.size() == 1, "destroying pile permanently defeats enemy once")
	unit.heal(999)
	unit.reform_from_bones()
	unit.apply_damage(1)
	check(unit.current_health == 0 and defeated_events.size() == 1, "destroyed pile cannot heal, reform or emit defeat twice")
	var destroyed := unit.capture_runtime_state()
	unit.restore_runtime_state(snapshot, {})
	check(unit.is_bone_pile and unit.current_health == 1 and not unit.can_move(), "runtime restores waiting pile")
	unit.restore_runtime_state(destroyed, {})
	unit.heal(999)
	check(unit.current_health == 0, "runtime preserves permanent destruction")
	unit.restore_runtime_state({"current_health": 0}, {})
	check(not unit.is_bone_pile and unit.current_health == 0, "legacy defeated skeleton stays defeated")
	unit.free()


func _test_turns() -> void:
	var ally := friendly()
	var unit := skeleton()
	var turns := TurnManager.new()
	arena.add_child(turns)
	turns.start_combat([ally, unit])
	unit.apply_damage(999)
	check(turns.get_rotating_order().has(unit), "pile keeps its initiative slot")
	turns.end_current_turn()
	check(turns.current_unit == unit and not unit.is_bone_pile and unit.ability_available and unit.remaining_movement > 0, "next turn reforms before normal movement and ability actions")
	turns.end_current_turn()
	unit.apply_status(load("res://resources/statuses/burning.tres"))
	unit.apply_damage(999)
	turns.end_current_turn()
	check(unit.current_health == unit.get_max_health() and not unit.is_bone_pile, "old Burning is cleared and cannot destroy pile")
	turns.end_current_turn()
	unit.apply_damage(999)
	unit.apply_status(load("res://resources/statuses/burning.tres"))
	turns.end_current_turn()
	check(unit.current_health == 0, "new Burning destroys pile before reformation")
	await frames()
	turns.free()
	unit.free()
	unit = skeleton()
	turns = TurnManager.new()
	arena.add_child(turns)
	turns.start_combat([ally, unit])
	var hazard := func(actor):
		if actor == unit:
			actor.apply_damage(999)
	turns.turn_starting.connect(hazard)
	turns.end_current_turn()
	check(unit.is_bone_pile, "collapse during turn-start hazard cannot immediately reform")
	await frames()
	check(turns.current_unit == ally, "turn-start collapse safely skips remaining actions")
	turns.end_current_turn()
	check(unit.current_health == 0, "next turn hazard destroys surviving pile")
	await frames()
	turns.free()
	unit.free()
	ally.free()


func _test_movement() -> void:
	var unit := skeleton()
	var entered: Array = []
	unit.cell_entered.connect(func(actor, cell):
		entered.append(cell)
		actor.apply_damage(999))
	await unit.move_along([Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2)])
	check(unit.is_bone_pile and unit.grid_cell == Vector2i(3, 2) and entered.size() == 1 and not unit.is_moving, "terrain collapse stops an in-progress movement path")
	unit.free()


func _test_multiple_arrows() -> void:
	var caster := friendly()
	var unit := skeleton("archer")
	var ability := (load("res://resources/abilities/multiple_arrows.tres") as AbilityDefinition).duplicate(true)
	ability.projectile_speed = 10000.0
	caster.set_dev_ability_loadout([ability])
	caster.equip_item(load("res://resources/items/weapons/ranger_bow.tres"))
	caster.reset_ability_action()
	unit.apply_damage(unit.current_health - 1)
	var executor := AbilityExecutor.new()
	arena.add_child(executor)
	var launches: Array = []
	executor.projectile_delivery.projectile_launched.connect(func(_actor, _ability, cell): launches.append(cell))
	var result := await executor.execute_targets(caster, ability, [unit, unit, unit], [caster, unit], grid, AbilityTargeting.new(grid.grid_size))
	check(result and launches.size() == 2 and unit.current_health == 0 and not caster.ability_available, "Multiple Arrows collapses then destroys same identity and skips final arrow for one action")
	executor.free()
	caster.free()
	unit.free()


func _test_ai() -> void:
	var caster := friendly()
	var unit := skeleton()
	unit.apply_status(load("res://resources/statuses/burning.tres"))
	var state := AIBoardSnapshot.from_battle([caster, unit], grid.grid_size)
	var planner := EnemyAIPlanner.new()
	var maximum := state.get_health(unit)
	var score := planner._score_effect_estimate(caster, unit, {"health_delta": -maximum}, null, state)
	check(state.is_living(unit) and state.is_bone_pile(unit) and state.get_health(unit) == 1, "AI forecasts collapse without eliminating target")
	check(score == maximum and state.get_status_ids(unit).is_empty(), "AI clears statuses and grants no final-defeat bonus for collapse")
	check(state.get_blocked_cells().has(unit.grid_cell) and not state.can_use_opportunity_reaction(unit), "AI pile blocks its cell but cannot react")
	check(not planner._can_use_ability_in_snapshot(unit, unit.get_abilities()[0], state), "AI pile cannot cast")
	var copy := state.duplicate_state()
	copy.apply_health_delta(unit, -1)
	check(not copy.is_living(unit) and state.is_living(unit), "AI branches keep independent pile state")
	check(unit.current_health == maximum and not unit.is_bone_pile, "AI forecasting does not mutate live skeleton")
	unit.free()
	caster.free()


func _test_caster_collapse() -> void:
	var caster := skeleton()
	var ability := AbilityDefinition.new()
	ability.target_flags = AbilityDefinition.TargetFlags.SELF
	ability.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	ability.innate_damage = 999
	ability.scaling_amount = 0
	ability.hit_count = 3
	caster.set_dev_ability_loadout([ability])
	var executor := AbilityExecutor.new()
	arena.add_child(executor)
	var result := await executor.execute(caster, ability, caster.grid_cell, [caster], grid, AbilityTargeting.new(grid.grid_size))
	check(result and caster.is_bone_pile and caster.current_health == 1 and not caster.ability_available, "caster collapse stops remaining hits of its own action")
	executor.free()
	caster.free()


func _find(battle: TacticalBattle, id: String) -> TacticalCharacter:
	for unit in battle._characters:
		if unit.scenario_unit_id == id:
			return unit
	return null


func _test_battle_saves() -> void:
	var manager := (load("res://main.tscn") as PackedScene).instantiate() as MapManager
	root.add_child(manager)
	manager.load_level(load("res://resources/maps/goblin_skirmish.tres"))
	await frames()
	var battle := manager.current_battle
	battle._open_dev_mode()
	battle._add_dev_unit(load("res://scenes/enemies/skeleton_warrior.tscn"), Vector2i(0, 0))
	var unit := battle.dev_mode_panel.get_selected_unit()
	var id := unit.scenario_unit_id
	check(manager.reload_battle_from_payload(battle.capture_save_payload(true), battle), "new developer unit enters combat through fresh restart")
	await frames()
	battle = manager.current_battle
	unit = _find(battle, id)
	await _capture(battle, "skeleton_run")
	unit.apply_damage(999)
	var exact := battle.capture_save_payload(false)
	check(ScenarioSaveStore.validate_payload(exact).ok, "exact bone-pile scenario validates")
	var saved := ScenarioSaveStore.save_new(exact, DIRECTORY)
	check(saved.ok, "bone-pile scenario saves to isolated file")
	var loaded := ScenarioSaveStore.load_save(saved.path, DIRECTORY)
	check(loaded.ok and manager.reload_battle_from_payload(loaded.payload, battle), "saved bone-pile scenario loads through manager")
	await frames()
	battle = manager.current_battle
	unit = _find(battle, id)
	check(unit != null and unit.is_bone_pile and battle.turn_manager.get_rotating_order().has(unit), "exact reload preserves pile and its initiative position")
	var enemy: TacticalCharacter
	for other in battle._characters:
		if not other.is_friendly() and other != unit and other.current_health > 0:
			enemy = other
			break
	var friendly_id := battle.turn_manager.current_unit.scenario_unit_id
	battle.turn_manager.current_unit = enemy
	battle.turn_manager.current_index = battle.turn_manager.turn_order.find(enemy)
	battle._set_movement_locked(true)
	var hold := EnemyTurnPlan.new()
	hold.sequence = EnemyTurnPlan.Sequence.HOLD
	hold.end_cell = enemy.grid_cell
	battle._update_ai_debug(enemy, hold)
	unit.apply_damage(1)
	battle._open_dev_mode()
	battle.dev_mode_panel.ai_history_restore_requested.emit(0)
	await frames(5)
	battle = manager.current_battle
	unit = _find(battle, id)
	check(unit.is_bone_pile and unit.current_health == 1 and battle._dev_open and battle._restored_ai_turn_pending, "AI Log rewind restores previously destroyed pile and pauses at captured action boundary")
	battle._restored_ai_turn_pending = false
	battle.turn_manager.current_unit = _find(battle, friendly_id)
	battle.turn_manager.current_index = battle.turn_manager.turn_order.find(battle.turn_manager.current_unit)
	battle._set_movement_locked(false)
	var bad := battle.capture_save_payload(false)
	for state in bad.runtime.units:
		if state.id == id:
			state.current_health = 2
	check(not ScenarioSaveStore.validate_payload(bad).ok, "invalid saved pile HP is rejected")
	battle._open_dev_mode()
	var fresh := battle.capture_save_payload(true)
	check(manager.reload_battle_from_payload(fresh, battle), "Restart & Play accepts bone-pile setup")
	await frames()
	battle = manager.current_battle
	unit = _find(battle, id)
	check(not unit.is_bone_pile and unit.current_health == unit.get_max_health(), "fresh restart returns enemy to full skeleton form")
	unit.set_dev_passive_loadout([])
	unit.apply_damage(999)
	check(unit.current_health == 0 and not unit.is_bone_pile, "developer removal disables future reassembly")
	manager.return_to_level_select()
	manager.queue_free()
	paused = false
	await frames()


func _test_run() -> void:
	var manager := (load("res://main.tscn") as PackedScene).instantiate() as MapManager
	var run := manager.get_node("RunController") as RunController
	run.config = run.config.duplicate()
	run.config.combat_stages = []
	var template := (load("res://resources/maps/spawn_template_demo.tres") as BattleMapTemplateDefinition).duplicate() as BattleMapTemplateDefinition
	template.enemy_pool = [load("res://scenes/enemies/skeleton_warrior.tscn")]
	template.combat_rating = 3
	ResourceSaver.save(template, DIRECTORY + "/skeleton_template.tres")
	var encounter := RunEncounterDefinition.new()
	encounter.battle_map = load(DIRECTORY + "/skeleton_template.tres")
	encounter.enemy_multiplier = 1.5
	ResourceSaver.save(encounter, DIRECTORY + "/skeleton_encounter.tres")
	run.config.normal_encounters = [load(DIRECTORY + "/skeleton_encounter.tres")]
	run.save_path = DIRECTORY + "/run_%d.json" % Time.get_ticks_usec()
	root.add_child(manager)
	check(run.new_run(37), "isolated run starts")
	run.state.party[0].setup.stat_overrides.speed = 1000
	check(run.select_room(run.state.available_rooms()[0]), "run encounter starts: " + run.error_message)
	await frames()
	var battle := manager.current_battle
	var unit: TacticalCharacter
	for other in battle._characters:
		if not other.is_friendly():
			unit = other
			break
	check(unit != null and unit.current_health == 32, "generated run skeleton receives elite scaling exactly once")
	battle._open_dev_mode()
	var id := unit.scenario_unit_id
	var maximum := unit.get_max_health()
	var fresh := battle.capture_save_payload(true)
	check(manager.reload_battle_from_payload(fresh, battle), "edited run reloads with skeleton")
	await frames()
	battle = manager.current_battle
	unit = _find(battle, id)
	unit.apply_damage(999)
	for other in battle._characters:
		if not other.is_friendly() and other != unit:
			other.apply_damage(99999)
			if other.is_bone_pile:
				other.apply_damage(1)
	check(not battle._combat_over and not run.state.pending.resolved, "last enemy pile prevents victory and run rewards")
	var node_id := battle.run_node_id
	battle._open_dev_mode()
	check(manager.reload_battle_from_payload(battle.capture_save_payload(false), battle), "exact run reload accepts the last surviving pile")
	await frames()
	battle = manager.current_battle
	unit = _find(battle, id)
	check(unit.is_bone_pile and unit.current_health == 1 and battle.run_node_id == node_id, "exact run restore preserves pile, room and pending reformation")
	unit.reform_from_bones()
	check(unit.current_health == maximum, "reformation uses adjusted maximum health without multiplying encounter scaling")
	unit.apply_damage(999)
	await _capture(battle, "bone_pile_run")
	var before_gold := run.state.gold
	var reward := int(run.state.pending.gold)
	unit.apply_damage(1)
	await frames(5)
	check(manager.current_battle == null and run.state.pending.resolved and run.state.gold == before_gold + reward, "destroying final pile completes run encounter and records reward once")
	await frames(5)
	check(run.state.gold == before_gold + reward, "no duplicate reward from intermediate collapse")
	manager.return_to_level_select()
	manager.queue_free()
	paused = false
	await frames()


func _capture(battle: TacticalBattle, name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	battle.clear_selection()
	await frames()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(DIRECTORY + "/" + name + ".png") == OK, "render " + name)
