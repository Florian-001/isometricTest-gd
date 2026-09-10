extends SceneTree

const ENEMIES := [
	{"id": "skeleton_warrior", "hp": 20, "constitution": 5, "damage": 6, "weapon": "rusty_sword", "attack": "strike", "stat": UnitStat.Type.STRENGTH, "type": ItemDefinition.WeaponType.MELEE},
	{"id": "skeleton_archer", "hp": 12, "constitution": 3, "damage": 5, "weapon": "short_bow", "attack": "enemy_shot", "stat": UnitStat.Type.DEXTERITY, "type": ItemDefinition.WeaponType.RANGED},
]
const DEMO := "res://resources/maps/spawn_template_demo.tres"
var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _run() -> void:
	for entry in ENEMIES:
		await _test_enemy(entry)
	await _test_palette_and_scenarios()
	await _test_templates()
	if _failures.is_empty():
		print("SKELETON_TESTS_OK")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _scene(entry: Dictionary) -> PackedScene:
	return load("res://scenes/enemies/%s.tscn" % entry.id) as PackedScene


func _test_enemy(entry: Dictionary) -> void:
	var field := Node2D.new()
	root.add_child(field)
	var grid := IsometricGrid.new()
	grid.grid_size = Vector2i(8, 8)
	field.add_child(grid)
	var actor := _scene(entry).instantiate() as TacticalCharacter
	actor.starting_grid_cell = Vector2i(1, 1)
	field.add_child(actor)
	actor.initialize(grid)
	var definition := actor.definition as EnemyDefinition
	_check(definition != null and not actor.is_friendly(), "%s is an EnemyDefinition combatant" % entry.id)
	_check(definition.max_health == entry.hp and actor.max_health == entry.hp and actor.current_health == entry.hp, "%s has the expected definition, Inspector, and spawned health" % entry.id)
	_check(definition.base_health_override == 0 and definition.constitution == entry.constitution, "%s retains Constitution-based health" % entry.id)
	_check(definition.combat_rating == 1, "%s has CR 1" % entry.id)
	_check(definition.strength == 1 and definition.dexterity == 1 and definition.intelligence == 1, "%s has the expected attributes" % entry.id)
	_check(definition.speed == 10 and definition.movement_range == 6.0 and actor.get_movement_range() == 6.0, "%s has speed 10 and movement 6" % entry.id)
	_check(actor.get_enemy_ai_profile() == load("res://resources/ai/general_ai.tres"), "%s uses General AI" % entry.id)
	_check(actor._get_configuration_warnings().is_empty(), "%s has no scene configuration warnings" % entry.id)
	_check(actor.has_node("UnitNameLabel"), "%s retains its standard name label" % entry.id)
	for property in definition.get_property_list():
		if property.name in ["combat_rating", "constitution", "starting_equipment", "abilities"]:
			_check(bool(property.usage & PROPERTY_USAGE_EDITOR) and bool(property.usage & PROPERTY_USAGE_STORAGE), "%s exposes editable %s" % [entry.id, property.name])
	for facing in [TacticalCharacter.Facing.LEFT, TacticalCharacter.Facing.RIGHT]:
		actor.set_facing(facing)
		var texture := actor._get_facing_texture()
		_check(texture != null, "%s has both facing textures" % entry.id)
		if texture != null:
			var artwork := texture.get_image()
			_check(artwork.detect_alpha() != Image.ALPHA_NONE and artwork.get_pixel(0, 0).a < 0.05, "%s artwork has a transparent background" % entry.id)
	var weapon := actor.get_equipped_weapon()
	_check(weapon == load("res://resources/items/weapons/%s.tres" % entry.weapon), "%s equips its authored weapon" % entry.id)
	_check(weapon.weapon_damage == entry.damage - 1 and weapon.weapon_type == entry.type and weapon.modifiers.is_empty() and weapon.status_effect == null, "%s weapon adds only its intended damage" % entry.id)
	var attack := load("res://resources/abilities/%s.tres" % entry.attack) as AbilityDefinition
	_check(actor.get_abilities() == [attack], "%s reuses its existing attack resource" % entry.id)
	_check(attack.calculate_damage(actor) == entry.damage, "%s previews the expected damage" % entry.id)
	actor.set_dev_stat_override(entry.stat, 4.0)
	_check(attack.calculate_damage(actor) == entry.damage + 3, "%s attack scales with its normal attribute" % entry.id)
	actor.clear_dev_stat_override(entry.stat)
	actor.set_dev_stat_override(UnitStat.Type.CONSTITUTION, entry.constitution + 1)
	_check(actor.get_max_health() == entry.hp + 4 and actor.get_max_health_without_statuses() == entry.hp + 4, "%s Constitution modifiers retain ordinary health scaling" % entry.id)
	actor.clear_dev_stat_override(UnitStat.Type.CONSTITUTION)

	var target := TacticalCharacter.new()
	target.definition = CharacterDefinition.new()
	target.starting_grid_cell = Vector2i(2, 1)
	field.add_child(target)
	target.initialize(grid)
	var units: Array[TacticalCharacter] = [actor, target]
	var executor := AbilityExecutor.new()
	field.add_child(executor)
	var targeting := AbilityTargeting.new(grid.grid_size)
	actor.reset_movement()
	actor.reset_ability_action()
	var planner := EnemyAIPlanner.new()
	var plan := planner.choose_plan(actor, units, GridPathfinder.new(grid.grid_size), targeting, {})
	_check(plan != null and plan.ability == attack, "%s General AI selects its attack against a reachable enemy" % entry.id)

	var valid_cells: Array[Vector2i] = [Vector2i(2, 1), Vector2i(2, 2)]
	if entry.type == ItemDefinition.WeaponType.RANGED:
		valid_cells = [Vector2i(2, 1), Vector2i(6, 1)]
	for cell in valid_cells:
		target.set_grid_cell_immediate(cell)
		actor.reset_ability_action()
		var health_before := target.current_health
		var succeeded := await executor.execute(actor, attack, cell, units, grid, targeting, {})
		_check(succeeded and health_before - target.current_health == entry.damage, "%s deals exactly %d damage at valid range %s" % [entry.id, entry.damage, cell])
		_check(not actor.ability_available, "%s attack spends its ability action" % entry.id)
	actor.reset_ability_action()
	var outside := Vector2i(3, 1) if entry.type == ItemDefinition.WeaponType.MELEE else Vector2i(7, 1)
	target.set_grid_cell_immediate(outside)
	_check(not executor.can_execute(actor, attack, outside, units, grid, targeting, {}), "%s cannot attack outside its range" % entry.id)
	var blocked_cell := Vector2i(2, 2) if entry.type == ItemDefinition.WeaponType.MELEE else Vector2i(4, 1)
	target.set_grid_cell_immediate(blocked_cell)
	_check(not executor.can_execute(actor, attack, blocked_cell, units, grid, targeting, {Vector2i(2, 1): true}), "%s attacks respect blocking walls" % entry.id)
	actor.unequip_item(ItemDefinition.EquipmentSlot.WEAPON)
	_check(not attack.can_be_used_by(actor), "%s cannot use its attack unarmed" % entry.id)
	var wrong_weapon := ItemDefinition.new()
	wrong_weapon.weapon_type = ItemDefinition.WeaponType.RANGED if entry.type == ItemDefinition.WeaponType.MELEE else ItemDefinition.WeaponType.MELEE
	actor.equip_item(wrong_weapon)
	_check(not attack.can_be_used_by(actor), "%s rejects the wrong weapon type" % entry.id)
	actor.equip_item(weapon)
	_check(attack.can_be_used_by(actor), "%s can attack again after restoring its weapon" % entry.id)
	field.queue_free()
	await process_frame


func _battle(map: BattleMapDefinition, payload: Dictionary = {}) -> TacticalBattle:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = map
	battle.pending_restore_payload = payload
	battle.center_camera_on_start = false
	root.add_child(battle)
	_check(battle.initialization_succeeded, "Battle initializes with skeleton-compatible resources")
	return battle


func _dispose_battle(battle: TacticalBattle) -> void:
	battle.shutdown_battle()
	root.remove_child(battle)
	battle.free()
	paused = false


func _find(battle: TacticalBattle, id: String) -> TacticalCharacter:
	for actor in battle._characters:
		if actor.scenario_unit_id == id:
			return actor
	return null


func _test_palette_and_scenarios() -> void:
	var map := load("res://resources/maps/goblin_skirmish.tres") as BattleMapDefinition
	var battle := _battle(map)
	battle._open_dev_mode()
	var ids: Array[String] = []
	for index in range(ENEMIES.size()):
		var entry: Dictionary = ENEMIES[index]
		_check(battle.dev_tool_catalog.unit_scenes.has(_scene(entry)), "Palette includes %s" % entry.id)
		_check(battle.dev_tool_catalog.items.has(load("res://resources/items/weapons/%s.tres" % entry.weapon)), "Item catalog includes %s" % entry.weapon)
		battle._add_dev_unit(_scene(entry), Vector2i(index, 0))
		var actor := battle.dev_mode_panel.get_selected_unit()
		_check(actor.scene_file_path == _scene(entry).resource_path and actor.current_health == entry.hp, "Palette spawns %s at full health" % entry.id)
		ids.append(actor.scenario_unit_id)
		actor.set_dev_stat_override(UnitStat.Type.CONSTITUTION, entry.constitution + 1)
	var fresh := battle.capture_save_payload(true)
	_check(ScenarioSaveStore.validate_payload(fresh).ok, "Skeleton setup uses the existing scenario schema")
	_dispose_battle(battle)
	await process_frame
	var restored := _battle(map, fresh)
	_check(restored.capture_save_payload(true).setup.units == fresh.setup.units, "Restart preserves skeleton setup, equipment, and stat overrides")
	restored._open_dev_mode()
	for index in range(ids.size()):
		var actor := _find(restored, ids[index])
		_check(actor != null and actor.current_health == ENEMIES[index].hp + 4, "Restart applies the skeleton's authored Constitution override")
		if actor != null:
			actor.apply_damage(3)
			actor.set_facing(TacticalCharacter.Facing.RIGHT)
	var exact := restored.capture_save_payload(false)
	var directory := "res://.godot/skeleton_scenario_tests"
	var saved := ScenarioSaveStore.save_new(exact, directory)
	_check(saved.ok, "Damaged skeleton scenario saves to disk")
	var loaded := ScenarioSaveStore.load_save(saved.path, directory) if saved.ok else {}
	_check(loaded.get("ok", false), "Skeleton scenario reloads from disk")
	_dispose_battle(restored)
	await process_frame
	if loaded.get("ok", false):
		var continued := _battle(map, loaded.payload)
		for index in range(ids.size()):
			var actor := _find(continued, ids[index])
			var entry: Dictionary = ENEMIES[index]
			_check(actor != null, "Saved skeleton stable ID is restored")
			if actor == null:
				continue
			_check(actor.get_max_health() == entry.hp + 4 and actor.current_health == entry.hp + 1, "%s preserves maximum and damaged current HP" % entry.id)
			_check(actor.grid_cell == Vector2i(index, 0) and actor.current_facing == TacticalCharacter.Facing.RIGHT, "%s preserves position and facing" % entry.id)
			_check(actor.get_abilities()[0].calculate_damage(actor) == entry.damage and actor.definition.combat_rating == 1, "%s preserves equipment, attack damage, and CR" % entry.id)
		_dispose_battle(continued)
		await process_frame
		ScenarioSaveStore.delete_save(saved.path, directory)


func _test_templates() -> void:
	var demo := load(DEMO) as BattleMapTemplateDefinition
	var original_pool := demo.enemy_pool.duplicate()
	_check(original_pool.size() == 6, "Demo retains its six original enemies")
	for entry in ENEMIES:
		_check(not original_pool.has(_scene(entry)), "Skeletons are opt-in for existing template pools")
		var custom := demo.duplicate() as BattleMapTemplateDefinition
		custom.enemy_pool = [_scene(entry)]
		var rng := RandomNumberGenerator.new()
		rng.seed = 41
		var selection := EnemyEncounterGenerator.generate(custom, 5, rng)
		_check(selection.error.is_empty() and selection.total_cr == 3 and selection.scenes.size() == 3, "Template can select three CR 1 copies of %s" % entry.id)
		var battle := _battle(custom)
		var count := 0
		for actor in battle._characters:
			if actor.is_friendly():
				continue
			count += 1
			_check(actor.scene_file_path == _scene(entry).resource_path and actor.current_health == entry.hp, "Generated %s retains its authored health and scene" % entry.id)
		_check(count == 3, "CR 3 template populates three skeleton enemies")
		_dispose_battle(battle)
		await process_frame
	_check(demo.enemy_pool == original_pool, "Template tests never modify the demo resource")
