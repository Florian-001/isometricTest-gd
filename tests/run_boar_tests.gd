extends SceneTree

const SCENE := "res://scenes/enemies/boar.tscn"
const DEFINITION := "res://resources/enemies/boar.tres"
const DIRECTORY := "res://.godot/boar_validation"
var failures: Array[String] = []
var checks := 0


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	_test_content_and_isolation()
	await _test_combat_and_ai()
	await _test_palette_and_saves()
	for failure in failures:
		push_error(failure)
	print("BOAR_TESTS_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_content_and_isolation() -> void:
	var scene := load(SCENE) as PackedScene
	var a := scene.instantiate() as TacticalCharacter
	var b := scene.instantiate() as TacticalCharacter
	root.add_child(a)
	root.add_child(b)
	var definition := a.definition as EnemyDefinition
	check(not a.is_friendly() and definition == load(DEFINITION), "Boar uses a shared enemy definition")
	check(a.current_health == 20 and a.max_health == 20 and definition.max_health == 20, "spawned and Inspector health are 20")
	check(definition.constitution == 5 and definition.base_health_override == 0, "health uses ordinary Constitution scaling")
	check(definition.strength == 2 and definition.dexterity == 1 and definition.intelligence == 1, "Boar has the accepted attributes")
	check(a.get_movement_range() == 6 and a.get_initiative() == 10 and definition.combat_rating == 1, "Boar has movement 6, speed 10 and CR 1")
	check(a.get_enemy_ai_profile() == load("res://resources/ai/general_ai.tres"), "Boar uses General AI")
	check(a.get_passive_abilities().is_empty() and not a.override_template_passives, "Boar starts without passives or a passive override")
	check(not a.override_template_abilities and not a.use_complete_equipment_override and a.starting_equipment_overrides.is_empty(), "Boar inherits its template without developer overrides")
	var abilities: Array[AbilityDefinition] = [load("res://resources/abilities/charge.tres"), load("res://resources/abilities/strike.tres")]
	check(a.get_abilities() == abilities, "ability order is shared Charge then Strike")
	for ability in abilities:
		check(ability.calculate_damage(a) == 8, "%s previews eight damage" % ability.display_name)
	var tusks := a.get_equipped_weapon()
	check(a.get_equipped_items().size() == 1 and tusks == load("res://resources/items/boar_tusks.tres"), "Boar starts with only its Tusks")
	check(tusks.weapon_damage == 6 and tusks.weapon_type == ItemDefinition.WeaponType.MELEE and tusks.modifiers.is_empty() and tusks.status_effect == null and tusks.icon != null, "Tusks provide six melee damage and an icon, with no modifiers or statuses")
	check(a._get_configuration_warnings().is_empty() and a.has_node("UnitNameLabel"), "scene has standard presentation and no configuration warnings")
	for facing in [TacticalCharacter.Facing.LEFT, TacticalCharacter.Facing.RIGHT]:
		a.set_facing(facing)
		var texture := a._get_facing_texture()
		check(texture != null and texture.get_image().detect_alpha() != Image.ALPHA_NONE and texture.get_image().get_pixel(0, 0).a == 0.0, "both facing sprites contain real transparency")
	a.set_dev_stat_override(UnitStat.Type.STRENGTH, 4)
	a.set_dev_stat_override(UnitStat.Type.CONSTITUTION, 6)
	a.set_dev_ability_loadout([abilities[1]])
	check(a.max_health == 24 and abilities[1].calculate_damage(a) == 10, "Boar retains normal health and damage scaling")
	check(b.max_health == 20 and b.get_abilities() == abilities and abilities[0].calculate_damage(b) == 8, "editing one instance leaves another unchanged")
	var packed := PackedScene.new()
	check(packed.pack(a) == OK and ResourceSaver.save(packed, DIRECTORY + "/boar_override.tscn") == OK, "edited Boar scene saves")
	var reloaded := (ResourceLoader.load(DIRECTORY + "/boar_override.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as TacticalCharacter
	check(reloaded.max_health == 24 and reloaded.get_abilities() == [abilities[1]], "scene reload preserves editable overrides")
	reloaded.free()
	a.free()
	b.free()


func _test_combat_and_ai() -> void:
	var field := Node2D.new()
	root.add_child(field)
	var grid := IsometricGrid.new()
	grid.grid_size = Vector2i(10, 8)
	field.add_child(grid)
	var boar := (load(SCENE) as PackedScene).instantiate() as TacticalCharacter
	boar.starting_grid_cell = Vector2i(1, 1)
	boar.movement_animation_speed = 10000
	field.add_child(boar)
	boar.initialize(grid)
	var target := TacticalCharacter.new()
	target.definition = CharacterDefinition.new()
	target.definition.constitution = 50
	target.starting_grid_cell = Vector2i(6, 1)
	field.add_child(target)
	target.initialize(grid)
	var units: Array[TacticalCharacter] = [boar, target]
	var executor := AbilityExecutor.new()
	field.add_child(executor)
	var targeting := AbilityTargeting.new(grid.grid_size)
	var planner := EnemyAIPlanner.new()
	var charge := boar.get_abilities()[0]
	var strike := boar.get_abilities()[1]
	boar.reset_movement()
	boar.reset_ability_action()
	var plan := planner.choose_plan(boar, units, GridPathfinder.new(grid.grid_size), targeting)
	check(plan != null and plan.ability == charge, "General AI selects Charge against a distant aligned target")
	for cell in [Vector2i(6, 1), Vector2i(4, 4), Vector2i(2, 1)]:
		boar.set_grid_cell_immediate(Vector2i(1, 1))
		target.set_grid_cell_immediate(cell)
		boar.reset_ability_action()
		var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
		planner._prepare_decision(boar, snapshot, units)
		planner._forecast_ability(boar, charge, cell, snapshot, targeting, boar.get_enemy_ai_profile())
		var before := target.current_health
		var movement_before := boar.remaining_movement
		check(await executor.execute(boar, charge, cell, units, grid, targeting), "Charge executes at straight, diagonal and adjacent range")
		var direction := Vector2i(signi(cell.x - 1), signi(cell.y - 1))
		check(boar.grid_cell == cell - direction, "Charge lands next to its target")
		check(before - target.current_health == 8 and target.current_health == snapshot.get_health(target), "Charge runtime damage matches preview and AI")
		check(not boar.ability_available and is_equal_approx(boar.remaining_movement, movement_before), "Charge spends its action and preserves ordinary movement")
	boar.set_grid_cell_immediate(Vector2i(1, 1))
	target.set_grid_cell_immediate(Vector2i(5, 1))
	boar.reset_ability_action()
	check(not executor.can_execute(boar, charge, target.grid_cell, units, grid, targeting, {Vector2i(3, 1): true}), "Charge respects blocking walls")
	var blocker := (load(SCENE) as PackedScene).instantiate() as TacticalCharacter
	blocker.starting_grid_cell = Vector2i(4, 1)
	field.add_child(blocker)
	blocker.initialize(grid)
	units.append(blocker)
	check(not executor.can_execute(boar, charge, target.grid_cell, units, grid, targeting), "Charge rejects an occupied landing cell")
	units.erase(blocker)
	blocker.free()
	target.set_grid_cell_immediate(Vector2i(4, 4))
	check(not executor.can_execute(boar, charge, target.grid_cell, units, grid, targeting, {Vector2i(2, 1): true}), "diagonal Charge cannot cut corners")
	target.set_grid_cell_immediate(Vector2i(4, 2))
	check(not executor.can_execute(boar, charge, target.grid_cell, units, grid, targeting), "Charge requires a straight grid direction")
	target.set_grid_cell_immediate(Vector2i(7, 1))
	check(not executor.can_execute(boar, charge, target.grid_cell, units, grid, targeting), "Charge respects its five-unit range")
	target.set_grid_cell_immediate(Vector2i(2, 1))
	boar.set_dev_ability_loadout([strike])
	plan = planner.choose_plan(boar, units, GridPathfinder.new(grid.grid_size), targeting)
	check(plan != null and plan.ability == strike, "General AI supports Strike when the developer loadout selects it")
	boar.reset_dev_ability_loadout()
	var before := target.current_health
	check(await executor.execute(boar, strike, target.grid_cell, units, grid, targeting) and before - target.current_health == 8, "Strike deals eight damage")
	boar.reset_ability_action()
	boar.reset_opportunity_reaction()
	check(OpportunityAttackSystem.get_opportunity_attack_ability(boar) == strike, "Boar uses Strike for opportunity attacks")
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
	planner._forecast_opportunity_attacks(target, target.grid_cell, Vector2i(3, 1), snapshot, targeting, boar.get_enemy_ai_profile())
	before = target.current_health
	check(await executor.execute_opportunity_attack(boar, strike, target.grid_cell, units, grid, targeting), "Boar opportunity attack executes")
	check(before - target.current_health == 8 and target.current_health == snapshot.get_health(target), "reaction damage matches AI forecast")
	check(not boar.opportunity_reaction_available and boar.ability_available, "reaction spends only the reaction")
	var tusks := boar.get_equipped_weapon()
	boar.unequip_item(ItemDefinition.EquipmentSlot.WEAPON)
	check(not charge.can_be_used_by(boar) and not strike.can_be_used_by(boar), "enemy attacks still require equipment")
	var bow := ItemDefinition.new()
	bow.weapon_type = ItemDefinition.WeaponType.RANGED
	boar.equip_item(bow)
	check(not charge.can_be_used_by(boar) and not strike.can_be_used_by(boar), "Boar attacks reject ranged weapons")
	boar.equip_item(tusks)
	var terrain := TacticalTerrain.new()
	field.add_child(terrain)
	var hazard := TileDefinition.new()
	hazard.status_effect = load("res://resources/statuses/burning.tres")
	hazard.status_triggers = TileTriggeredEffectDefinition.Trigger.ENTER
	var tile := TacticalTile.new()
	tile.definition = hazard
	tile.grid_cell = Vector2i(3, 5)
	terrain.add_child(tile)
	terrain.initialize(grid)
	boar.cell_entered.connect(func(unit: TacticalCharacter, _cell: Vector2i): terrain.apply_trigger(unit, TileTriggeredEffectDefinition.Trigger.ENTER))
	boar.set_grid_cell_immediate(Vector2i(1, 5))
	target.set_grid_cell_immediate(Vector2i(5, 5))
	boar.reset_ability_action()
	check(await executor.execute(boar, charge, target.grid_cell, units, grid, targeting), "Boar can Charge across terrain")
	check(not boar.get_active_statuses().is_empty() and boar.get_active_statuses()[0].definition == hazard.status_effect, "grounded Boar receives terrain entry statuses")
	field.queue_free()
	await process_frame


func _battle(payload: Dictionary = {}) -> TacticalBattle:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	battle.pending_restore_payload = payload
	root.add_child(battle)
	check(battle.initialization_succeeded, "Boar-compatible battle initializes")
	return battle


func _dispose(battle: TacticalBattle) -> void:
	paused = false
	battle.shutdown_battle()
	battle.queue_free()


func _test_palette_and_saves() -> void:
	var scene := load(SCENE) as PackedScene
	var catalog := load("res://resources/dev_tool_catalog.tres") as DevToolCatalog
	check(catalog.unit_scenes.back() == scene and catalog.items.back() == load("res://resources/items/boar_tusks.tres"), "Boar and Tusks append to their developer catalogs")
	var demo := load("res://resources/maps/spawn_template_demo.tres") as BattleMapTemplateDefinition
	check(not demo.enemy_pool.has(scene), "Boar is opt-in for existing encounter pools")
	var battle := _battle()
	battle._open_dev_mode()
	battle._add_dev_unit(scene, Vector2i(0, 0))
	var boar := battle.dev_mode_panel.get_selected_unit()
	check(boar.scene_file_path == SCENE and boar.current_health == 20, "developer palette spawns the correct Boar")
	var id := boar.scenario_unit_id
	boar.set_dev_stat_override(UnitStat.Type.CONSTITUTION, 6)
	var setup := battle.capture_save_payload(true)
	check(ScenarioSaveStore.validate_payload(setup).ok, "Boar setup uses the existing scenario schema")
	_dispose(battle)
	await process_frame
	battle = _battle(setup)
	boar = _find(battle, id)
	check(boar != null and boar.current_health == 24, "restart restores the Boar's edited stats")
	battle._open_dev_mode()
	boar.apply_damage(5)
	boar.set_facing(TacticalCharacter.Facing.RIGHT)
	var exact := battle.capture_save_payload(false)
	var saved := ScenarioSaveStore.save_new(exact, DIRECTORY)
	check(saved.ok, "Boar checkpoint saves to disk")
	var loaded := ScenarioSaveStore.load_save(saved.path, DIRECTORY) if saved.ok else {}
	check(loaded.get("ok", false), "Boar checkpoint loads from disk")
	_dispose(battle)
	await process_frame
	if loaded.get("ok", false):
		battle = _battle(loaded.payload)
		boar = _find(battle, id)
		check(boar != null and boar.current_health == 19 and boar.max_health == 24, "checkpoint restores current and maximum health")
		check(boar.grid_cell == Vector2i(0, 0) and boar.current_facing == TacticalCharacter.Facing.RIGHT, "checkpoint restores position and facing")
		check(boar.get_equipped_weapon() == load("res://resources/items/boar_tusks.tres") and boar.get_abilities().size() == 2 and boar.get_abilities()[0].calculate_damage(boar) == 8, "checkpoint restores equipment and both attacks")
		check(not boar.override_template_abilities and not boar.override_template_passives and boar.get_passive_abilities().is_empty(), "checkpoint preserves inherited loadouts")
		_dispose(battle)
		await process_frame


func _find(battle: TacticalBattle, id: String) -> TacticalCharacter:
	for unit in battle._characters:
		if unit.scenario_unit_id == id:
			return unit
	return null
