extends SceneTree

var failures: Array[String] = []
var checks := 0
var pack: PassiveAbilityDefinition
var flight: PassiveAbilityDefinition
var arena: Node2D
var grid: IsometricGrid
var executor: AbilityExecutor
var targeting: AbilityTargeting
var units: Array[TacticalCharacter] = []
const DIRECTORY := "res://.godot/passive_validation"


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	pack = load("res://resources/passives/pack_tactics.tres")
	flight = load("res://resources/passives/flight.tres")
	_test_resources()
	arena = Node2D.new()
	root.add_child(arena)
	grid = IsometricGrid.new()
	grid.grid_size = Vector2i(12, 10)
	arena.add_child(grid)
	executor = AbilityExecutor.new()
	arena.add_child(executor)
	targeting = AbilityTargeting.new(grid.grid_size)
	_test_proximity()
	await _test_damage()
	_test_flight()
	arena.free()
	units.clear()
	await process_frame
	await _test_ui_and_saves()
	await process_frame
	await process_frame
	for failure in failures:
		push_error(failure)
	print("PASSIVE_TESTS_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_resources() -> void:
	check(pack.validate().is_empty() and flight.validate().is_empty(), "shipped passives validate")
	var scene := load("res://scenes/enemies/wolf.tscn") as PackedScene
	var a := scene.instantiate() as TacticalCharacter
	var b := scene.instantiate() as TacticalCharacter
	check(a.get_passive_abilities() == [pack], "wolves inherit Pack Tactics")
	var assignments: Array[PassiveAbilityDefinition] = [flight, flight]
	a.set_dev_passive_loadout(assignments)
	assignments.clear()
	check(a.get_passive_abilities() == [flight] and b.get_passive_abilities() == [pack], "assignment arrays are isolated and duplicates resolve once")
	var changes := [0]
	a.passive_abilities_changed.connect(func(): changes[0] += 1)
	var immunity := flight.effects[0] as GroundImmunityPassiveEffect
	immunity.ignore_movement_modifiers = false
	check(changes[0] > 0 and not PassiveAbilityResolver.ignores_movement_modifiers(a), "shared nested effect edits notify assigned units")
	immunity.ignore_movement_modifiers = true
	a.set_dev_passive_loadout([])
	var empty_setup := a.capture_setup_state()
	b.apply_setup_state(empty_setup)
	check(b.override_template_passives and b.get_passive_abilities().is_empty(), "explicit empty override survives setup")
	b.reset_dev_passive_loadout()
	check(not b.override_template_passives and b.get_passive_abilities() == [pack], "reset restores template")
	var inline := PassiveAbilityDefinition.new()
	inline.passive_id = &"inline_flight"
	inline.effects = [GroundImmunityPassiveEffect.new()]
	a.set_dev_passive_loadout([inline])
	var setup := a.capture_setup_state()
	check(PassiveLoadout.validate_setup(setup).is_empty(), "unsaved inline passive serializes safely")
	b.apply_setup_state(setup)
	check(b.get_passive_abilities()[0].passive_id == &"inline_flight" and PassiveAbilityResolver.ignores_tile_effects(b), "inline passive setup round trip")
	var packed := PackedScene.new()
	check(packed.pack(a) == OK and ResourceSaver.save(packed, DIRECTORY + "/inline.tscn") == OK, "Inspector inline scene saves")
	var reloaded := (ResourceLoader.load(DIRECTORY + "/inline.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as TacticalCharacter
	check(reloaded.get_passive_abilities()[0].effects[0] is GroundImmunityPassiveEffect, "inline typed effect survives scene reload")
	check(PassiveLoadout.validate_setup(reloaded.capture_setup_state()).is_empty(), "saved inline subresource reference validates for developer saves: %s %s" % [reloaded.capture_setup_state().passives, PassiveLoadout.validate_setup(reloaded.capture_setup_state())])
	reloaded.free()
	for malformed in [null, {}, [null], ["res://resources/abilities/bite.tres"], [{"id": "bad", "name": "Bad", "effects": [{"type": "nearby_allies_weapon_damage", "radius": 1.5, "damage_per_ally": 1.5}]}], [{"id": "bad", "name": "Bad", "effects": []}]]:
		check(not PassiveLoadout.validate_setup({"passives": malformed}).is_empty(), "malformed passive data is rejected")
	check(not PassiveLoadout.validate_setup({"override_passives": 1}).is_empty(), "override flag must be boolean")
	var duplicate := pack.duplicate(true) as PassiveAbilityDefinition
	check(not PassiveLoadout.validate([pack, duplicate]).is_empty(), "different resources cannot share a passive ID")
	var legacy := empty_setup.duplicate(true)
	legacy.erase("passives")
	legacy.erase("override_passives")
	var old := scene.instantiate() as TacticalCharacter
	old.apply_setup_state(legacy)
	check(old.get_passive_abilities() == [pack] and not old.override_template_passives, "legacy setup inherits new wolf default")
	a.free()
	b.free()
	old.free()


func _unit(friendly: bool, cell: Vector2i, passives: Array[PassiveAbilityDefinition]) -> TacticalCharacter:
	var unit := TacticalCharacter.new()
	unit.definition = CharacterDefinition.new()
	unit.definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	unit.definition.constitution = 50
	unit.definition.strength = 1
	unit.definition.dexterity = 1
	unit.definition.passive_abilities = passives
	unit.starting_grid_cell = cell
	unit.movement_animation_speed = 10000
	unit.use_complete_equipment_override = true
	unit.complete_equipment_overrides = [load("res://resources/items/weapons/bat_fangs.tres")]
	unit.override_template_abilities = true
	arena.add_child(unit)
	unit.initialize(grid)
	unit.reset_movement()
	unit.reset_ability_action()
	units.append(unit)
	return unit


func _test_proximity() -> void:
	var a := _unit(false, Vector2i(2, 2), [pack])
	var b := _unit(false, Vector2i(3, 3), [pack])
	var c := _unit(false, Vector2i(1, 2), [pack])
	var opponent := _unit(true, Vector2i(2, 1), [pack])
	var ordinary := _unit(false, Vector2i(3, 2), [])
	check(PassiveAbilityResolver.weapon_damage_bonus(a) == 2, "stacking bonus includes diagonal ally and excludes self, opponent, non-pack ally")
	b.grid_cell = Vector2i(4, 2)
	check(PassiveAbilityResolver.weapon_damage_bonus(a) == 1, "distance beyond 1.5 excludes ally immediately")
	c.apply_damage(c.current_health)
	check(PassiveAbilityResolver.weapon_damage_bonus(a) == 0, "defeated ally stops contributing immediately")
	ordinary.set_dev_passive_loadout([pack])
	check(PassiveAbilityResolver.weapon_damage_bonus(a) == 1, "passive edits affect bonus immediately")
	var friend := _unit(true, Vector2i(1, 1), [pack])
	check(PassiveAbilityResolver.weapon_damage_bonus(opponent) == 1, "friendly faction uses same rule")
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
	snapshot.set_cell(b, Vector2i(1, 2))
	snapshot.unit_health[ordinary] = 0
	check(PassiveAbilityResolver.weapon_damage_bonus(a, snapshot) == 1, "AI uses simulated cells and health")
	check(PassiveAbilityResolver.weapon_damage_bonus(a, snapshot, Vector2i(8, 8)) == 0, "explicit predicted caster origin is honored")
	units.erase(friend)
	friend.free()
	for unit in units:
		unit.free()
	units.clear()


func _test_damage() -> void:
	var caster := _unit(false, Vector2i(2, 2), [pack])
	var ally := _unit(false, Vector2i(2, 3), [pack])
	var target := _unit(true, Vector2i(3, 2), [])
	var bite := (load("res://resources/abilities/bite.tres") as AbilityDefinition).duplicate(true) as AbilityDefinition
	bite.delivery_type = AbilityDefinition.DeliveryType.CAST_ON_TARGET
	caster.ability_overrides = [bite]
	check(bite.calculate_damage(caster) == 6, "melee display includes pack after weapon calculation")
	check(bite.get_damage_calculation_description(caster).contains("6 total"), "damage breakdown includes current bonus")
	var before := target.current_health
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
	var planner := EnemyAIPlanner.new()
	var profile := EnemyAIProfile.new()
	planner._prepare_decision(caster, snapshot, units)
	planner._forecast_ability(caster, bite, target.grid_cell, snapshot, targeting, profile)
	check(before - snapshot.get_health(target) == 6, "AI melee forecast includes Pack Tactics")
	check(await executor.execute(caster, bite, target.grid_cell, units, grid, targeting), "melee executes")
	check(before - target.current_health == 6, "runtime melee matches display and AI")
	caster.reset_opportunity_reaction()
	before = target.current_health
	check(await executor.execute_opportunity_attack(caster, bite, target.grid_cell, units, grid, targeting), "opportunity attack executes")
	check(before - target.current_health == 6, "opportunity attack includes pack")
	caster.reset_opportunity_reaction()
	snapshot = AIBoardSnapshot.from_battle(units, grid.grid_size)
	snapshot.set_cell(ally, Vector2i(8, 8))
	planner._forecast_opportunity_attacks(target, target.grid_cell, Vector2i(4, 2), snapshot, targeting, profile)
	check(target.current_health - snapshot.get_health(target) == 5, "AI reactions use simulated pack positions")
	target.set_dev_passive_loadout([flight])
	check(OpportunityAttackSystem.can_trigger(caster, target, target.grid_cell, Vector2i(4, 2), {}), "Flight retains opportunity attacks")
	var multiple := bite.duplicate(true) as AbilityDefinition
	multiple.effect = AbilityDefinition.PrimaryEffect.NONE
	var damage := DamageEffectDefinition.new()
	damage.scaling_percentage = 0
	multiple.effects = [damage, damage]
	check(multiple.calculate_damage(caster) == 11, "repeated damage resource gets one bonus in display")
	before = target.current_health
	executor._apply_effects(caster, target.grid_cell, multiple, units, targeting, {})
	check(before - target.current_health == 11, "multiple damage entries get only one pack bonus")
	caster.ability_overrides = [multiple]
	snapshot = AIBoardSnapshot.from_battle(units, grid.grid_size)
	planner._forecast_ability(caster, multiple, target.grid_cell, snapshot, targeting, profile)
	check(target.current_health - snapshot.get_health(target) == 11, "AI multi-effect forecast matches runtime")
	var ranged := bite.duplicate(true) as AbilityDefinition
	ranged.ability_type = AbilityDefinition.AbilityType.RANGED
	caster.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, load("res://resources/items/weapons/goblin_bow.tres"))
	check(ranged.calculate_damage(caster) == caster.get_weapon_damage() + 1, "ranged weapon damage includes pack")
	caster.ability_overrides = [ranged]
	snapshot = AIBoardSnapshot.from_battle(units, grid.grid_size)
	planner._forecast_ability(caster, ranged, target.grid_cell, snapshot, targeting, profile)
	before = target.current_health
	executor._apply_effects(caster, target.grid_cell, ranged, units, targeting, {})
	check(before - target.current_health == ranged.calculate_damage(caster) and target.current_health == snapshot.get_health(target), "ranged runtime, display and AI agree")
	caster.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, null)
	check(not ranged.can_be_used_by(caster) and ranged.get_passive_damage_bonus(caster) == 0, "passives do not bypass weapon requirements")
	var spell := bite.duplicate(true) as AbilityDefinition
	spell.ability_type = AbilityDefinition.AbilityType.MAGIC
	spell.innate_damage = 7
	check(spell.calculate_damage(caster) == 7, "spells receive no pack bonus")
	spell.effect = AbilityDefinition.PrimaryEffect.HEAL
	spell.effect_amount = 7
	check(spell.calculate_primary_effect_amount(caster) == 7, "healing receives no pack bonus")
	caster.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, load("res://resources/items/weapons/bat_fangs.tres"))
	var charge := (load("res://resources/abilities/charge.tres") as AbilityDefinition).duplicate(true) as AbilityDefinition
	charge.delivery_type = AbilityDefinition.DeliveryType.CAST_ON_TARGET
	caster.ability_overrides = [charge]
	caster.grid_cell = Vector2i(1, 5)
	caster.position = grid.grid_to_world(caster.grid_cell)
	target.grid_cell = Vector2i(6, 5)
	ally.grid_cell = Vector2i(5, 6)
	check(charge.get_passive_damage_bonus(caster) == 0, "Charge begins outside pack range")
	var bar := (load("res://scenes/ability_bar.tscn") as PackedScene).instantiate() as AbilityBar
	arena.add_child(bar)
	bar.rebuild(caster, true)
	bar.set_damage_preview(caster, charge, Vector2i(5, 5))
	check(bar.get_node("Margin/HBox").get_child(0).text.contains("%d DMG" % charge.calculate_damage(caster, null, Vector2i(5, 5))), "Charge ability bar previews damage at landing position")
	bar.set_selected(null)
	check(bar.get_node("Margin/HBox").get_child(0).text.contains("%d DMG" % charge.calculate_damage(caster)), "cancelled targeting resets damage preview")
	bar.free()
	caster.set_dev_passive_loadout([pack, flight])
	var hazard := TileDefinition.new()
	hazard.status_effect = load("res://resources/statuses/burning.tres")
	hazard.status_triggers = TileTriggeredEffectDefinition.Trigger.ENTER
	caster.cell_entered.connect(func(unit: TacticalCharacter, _cell: Vector2i): hazard.apply_trigger(unit, TileTriggeredEffectDefinition.Trigger.ENTER))
	snapshot = AIBoardSnapshot.from_battle(units, grid.grid_size)
	planner._prepare_decision(caster, snapshot, units)
	planner._forecast_ability(caster, charge, target.grid_cell, snapshot, targeting, profile)
	var predicted_damage := target.current_health - snapshot.get_health(target)
	before = target.current_health
	caster.reset_ability_action()
	check(await executor.execute(caster, charge, target.grid_cell, units, grid, targeting), "Charge executes")
	check(charge.get_passive_damage_bonus(caster) == 1 and before - target.current_health == charge.calculate_damage(caster), "Charge resolves bonus at landing cell")
	check(before - target.current_health == predicted_damage, "AI Charge forecast equals runtime")
	check(caster.get_active_statuses().is_empty(), "flying Charge ignores forced-movement terrain triggers")
	for unit in units:
		unit.free()
	units.clear()


func _test_flight() -> void:
	var bat := _unit(false, Vector2i(2, 2), [flight])
	bat.current_health = 30
	var tile := TileDefinition.new()
	tile.status_effect = load("res://resources/statuses/burning.tres")
	tile.status_triggers = 3
	var damage := DamageEffectDefinition.new()
	damage.innate_damage = 3
	var healing := HealEffectDefinition.new()
	healing.amount = 8
	for effect in [damage, healing]:
		var trigger := TileTriggeredEffectDefinition.new()
		trigger.effect = effect
		trigger.triggers = 3
		tile.effects.append(trigger)
	for trigger in [TileTriggeredEffectDefinition.Trigger.ENTER, TileTriggeredEffectDefinition.Trigger.TURN_START]:
		tile.apply_trigger(bat, trigger)
		check(bat.current_health == 30 and bat.get_active_statuses().is_empty(), "Flight ignores tile damage, healing and statuses on both triggers")
		check(tile.estimate_trigger(bat, trigger, 30).health == 30, "Flight terrain estimate matches runtime")
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size, {}, {bat.grid_cell: tile})
	var planner := EnemyAIPlanner.new()
	check(planner._forecast_terrain_trigger(bat, TileTriggeredEffectDefinition.Trigger.ENTER, snapshot, EnemyAIProfile.new()) == 0.0 and snapshot.get_health(bat) == 30, "AI ignores flyer terrain effects")
	var pathfinder := GridPathfinder.new(grid.grid_size)
	pathfinder.set_cell_cost_multipliers({Vector2i(3, 2): 4.0, Vector2i(4, 2): 0.25})
	check(pathfinder.get_step_cost(Vector2i(2, 2), Vector2i(3, 2), true) == 1.0 and pathfinder.get_step_cost(Vector2i(3, 2), Vector2i(4, 2), true) == 1.0, "Flight ignores slow and fast terrain")
	var reach := planner._get_reachability(bat, bat.grid_cell, 2.0, snapshot, pathfinder)
	check(reach.costs.get(Vector2i(4, 2), INF) == 2.0, "AI flyer reachability uses neutral movement costs")
	check(not pathfinder.get_reachable(Vector2i(2, 2), 1.5, {Vector2i(3, 2): true}, true).has(Vector2i(3, 3)), "Flight preserves diagonal collision")
	check(pathfinder.find_path(Vector2i(2, 2), Vector2i(3, 2), 6, {Vector2i(3, 2): true}, {}, true).is_empty(), "Flight preserves occupied/wall cells")
	bat.apply_damage(4)
	check(bat.current_health == 26, "direct damage affects flyers")
	bat.apply_status(tile.status_effect)
	bat.process_status_turn_start()
	check(bat.current_health < 26, "existing ongoing status affects flyers")
	bat.advance_status_durations()
	var content := (load("res://scenes/enemies/bat.tscn") as PackedScene).instantiate() as TacticalCharacter
	arena.add_child(content)
	check(content.current_health == 5 and content.get_movement_range() == 6 and content.get_initiative() == 10 and (content.definition as EnemyDefinition).combat_rating == 1, "Bat matches accepted stats")
	check(content.get_abilities()[0].display_name == "Bite" and content.get_abilities()[0].calculate_damage(content) == 5 and content.get_passive_abilities() == [flight], "Bat starts with Flight and Bite for five")
	for texture in [content.facing_left_texture, content.facing_right_texture]:
		check(texture != null and texture.get_image().detect_alpha() != Image.ALPHA_NONE, "both Bat facings contain real transparent alpha")
	check((load("res://resources/dev_tool_catalog.tres") as DevToolCatalog).unit_scenes.has(load("res://scenes/enemies/bat.tscn")), "Bat is in developer unit catalog")


func _test_ui_and_saves() -> void:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	root.add_child(battle)
	check(battle.initialization_succeeded, "passive-enabled battle initializes")
	battle._on_dev_button_pressed()
	var actor := battle._characters[0]
	var panel := battle.dev_mode_panel
	panel.select_unit(actor)
	check(panel.passive_entries.get_child_count() == 3, "developer passive catalog contains Flight, Pack Tactics and Reassemble")
	(panel.passive_entries.get_child(0) as CheckBox).button_pressed = true
	check(actor.get_passive_abilities() == [flight] and battle._dev_dirty, "developer checkbox assigns passive and marks setup dirty")
	(panel.passive_entries.get_child(0) as CheckBox).button_pressed = false
	check(actor.override_template_passives and actor.get_passive_abilities().is_empty(), "developer removal supports empty override")
	panel.passives_reset.pressed.emit()
	check(not actor.override_template_passives, "developer reset restores inheritance")
	actor.set_dev_passive_loadout([pack, flight])
	var next_cell := actor.grid_cell + Vector2i(1, 0)
	battle._pathfinder.set_cell_cost_multipliers({next_cell: 4.0})
	battle._refresh_reachable_cells()
	check(battle._reachable_cells.get(next_cell, INF) == 1.0, "battle movement preview uses Flight terrain costs")
	var movement_before := actor.remaining_movement
	check(await battle._before_character_movement_step(actor, actor.grid_cell, next_cell) and is_equal_approx(actor.remaining_movement, movement_before - 1.0), "battle movement execution spends neutral Flight cost")
	var context_changes := [0]
	actor.passive_context_changed.connect(func(): context_changes[0] += 1)
	var other := battle._characters[1]
	var previous_cell := other.grid_cell
	other.set_grid_cell_immediate(other.grid_cell + Vector2i(1, 0))
	check(context_changes[0] > 0, "moving other units refreshes passive context")
	other.set_grid_cell_immediate(previous_cell)
	actor.reset_movement()
	battle.inventory_screen.open_for(actor)
	check(battle.inventory_screen.stats_entries.get_node("Passives").text.contains("Pack Tactics"), "inventory displays passive descriptions")
	var payload := battle.capture_save_payload(true)
	check(ScenarioSaveStore.validate_payload(payload).ok, "developer save validates passive setup")
	check(ScenarioSaveStore.save_new(payload, DIRECTORY).ok, "developer passive save writes")
	var malformed := payload.duplicate(true)
	malformed.setup.units[0].passives = [null]
	check(not ScenarioSaveStore.validate_payload(malformed).ok, "developer saves reject malformed passives")
	paused = false
	battle.shutdown_battle()
	battle.free()
	await process_frame
	var restored := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	restored.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	restored.pending_restore_payload = payload
	root.add_child(restored)
	check(restored.initialization_succeeded and restored._characters[0].get_passive_abilities() == [pack, flight], "battle checkpoint restores passive assignments")
	restored.shutdown_battle()
	restored.free()
	var controller := RunController.new()
	controller.config = load("res://resources/run/default_run.tres")
	controller.save_store.path = DIRECTORY + "/run.json"
	check(controller.new_run(123), "new run validates passive defaults")
	controller.state.party[0].setup.override_passives = true
	controller.state.party[0].setup.passives = PassiveLoadout.to_data([pack, flight])
	controller.state.party[1].setup.override_passives = true
	controller.state.party[1].setup.passives = []
	check(controller.save_store.save_run(controller.state), "run writes passive state")
	var state := controller.save_store.load_run()
	check(state != null and state.party[0].setup.passives.size() == 2 and state.party[1].setup.override_passives and state.party[1].setup.passives.is_empty(), "run round trip retains assignments and empty override")
	controller.free()
