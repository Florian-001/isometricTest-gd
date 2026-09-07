extends SceneTree

const RAT := "res://scenes/enemies/rat.tscn"
const DEFINITION := "res://resources/enemies/rat.tres"
const DEMO := "res://resources/maps/spawn_template_demo.tres"
var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _run() -> void:
	var sections := OS.get_cmdline_user_args()
	if sections.is_empty() or sections.has("health"):
		_test_definition_and_health()
	if sections.is_empty() or sections.has("bite"):
		await _test_bite()
	if sections.is_empty() or sections.has("persistence"):
		await _test_palette_save_and_template()
	if _failures.is_empty():
		print("RAT_TESTS_OK")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _modifier(operation: StatModifierDefinition.Operation, value: float) -> StatModifierDefinition:
	var modifier := StatModifierDefinition.new()
	modifier.stat = UnitStat.Type.CONSTITUTION
	modifier.operation = operation
	modifier.value = value
	return modifier


func _test_definition_and_health() -> void:
	var definition := load(DEFINITION) as EnemyDefinition
	_check(definition != null, "Rat definition loads as EnemyDefinition")
	if definition == null:
		return
	_check(definition.max_health == 5 and definition.combat_rating == 1, "Inspector-derived HP is 5 and CR is 1")
	_check([definition.strength, definition.dexterity, definition.intelligence, definition.constitution] == [1, 1, 1, 1], "Rat attributes are all 1")
	_check(definition.speed == 10 and definition.movement_range == 6.0, "Rat speed is 10 and movement is 6")
	_check(definition.ai_profile == load("res://resources/ai/general_ai.tres"), "Rat uses General AI")
	for property in definition.get_property_list():
		if property.name in ["base_health_override", "combat_rating"]:
			_check(bool(property.usage & PROPERTY_USAGE_EDITOR) and bool(property.usage & PROPERTY_USAGE_STORAGE), "%s is editable and saved" % property.name)
			_check(not bool(property.usage & PROPERTY_USAGE_READ_ONLY), "%s is not read-only" % property.name)
		if property.name == "max_health":
			_check(bool(property.usage & PROPERTY_USAGE_EDITOR) and bool(property.usage & PROPERTY_USAGE_READ_ONLY), "Derived HP is shown read-only in the Inspector")
	var fresh := EnemyDefinition.new()
	_check(fresh.base_health_override == 0 and fresh.combat_rating == 1, "New enemy definitions retain legacy health and CR 1")
	var edited := definition.duplicate() as EnemyDefinition
	edited.base_health_override = 7
	edited.combat_rating = 1001
	var path := "res://.godot/rat_definition_test.tres"
	_check(ResourceSaver.save(edited, path) == OK, "Edited enemy resource saves")
	var reloaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as EnemyDefinition
	_check(reloaded.max_health == 7 and reloaded.combat_rating == 1001, "Health override and CR above 999 survive resource reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var rat := (load(RAT) as PackedScene).instantiate() as TacticalCharacter
	root.add_child(rat)
	_check(rat.current_health == 5 and rat.get_max_health() == 5 and rat.get_max_health_without_statuses() == 5, "Spawned rat has 5 HP in both runtime getters")
	_check(rat.max_health == 5 and rat.has_node("UnitNameLabel"), "Scene Inspector HP and standard name label remain available")
	for facing in [TacticalCharacter.Facing.LEFT, TacticalCharacter.Facing.RIGHT]:
		rat.set_facing(facing)
		var texture := rat._get_facing_texture()
		_check(texture != null, "Both facing textures are assigned")
		if texture != null:
			var sprite := texture.get_image()
			_check(sprite.detect_alpha() != Image.ALPHA_NONE, "Rat artwork has transparent alpha")
			_check(sprite.get_pixel(sprite.get_width() / 2, sprite.get_height() / 4).a < 0.05, "Rat artwork preserves transparent space above the small sprite")
	var item := ItemDefinition.new()
	item.slot = ItemDefinition.EquipmentSlot.ARMOR
	item.modifiers = [_modifier(StatModifierDefinition.Operation.FLAT, 1.0), _modifier(StatModifierDefinition.Operation.PERCENT_ADD, 0.5)]
	rat.equip_item(item)
	_check(rat.get_max_health() == 15 and rat.get_max_health_without_statuses() == 15, "Equipment scales the 5-HP override proportionally")
	_check(rat.current_health == 5, "Extra Constitution does not grant current HP")
	var status := StatusEffectDefinition.new()
	status.status_id = &"rat_health_test"
	status.modifiers = [_modifier(StatModifierDefinition.Operation.PERCENT_MULTIPLY, 1.0)]
	var snapshot := AIBoardSnapshot.from_battle([rat], Vector2i(4, 4))
	snapshot.forecast_status_application(rat, rat, status)
	_check(snapshot.get_max_health(rat) == 30, "AI forecasts respect definition health overrides")
	rat.apply_status(status, rat)
	_check(rat.get_max_health() == 30 and rat.get_max_health_without_statuses() == 15, "Only the status-aware health getter includes statuses")
	rat.remove_status(status.status_id)
	rat.unequip_item(ItemDefinition.EquipmentSlot.ARMOR)
	_check(rat.get_max_health() == 5, "Removing Constitution modifiers restores 5 max HP")
	_check(definition.calculate_max_health(-10.0) == 5, "Rat respects the existing minimum Constitution of one")
	edited.constitution = 4
	edited.base_health_override = 5
	_check(edited.calculate_max_health(4.0) == 5 and edited.calculate_max_health(2.0) == 3, "Override anchors at authored Constitution and rounds proportional HP")
	edited.base_health_override = 1
	_check(edited.calculate_max_health(1.0) == 1, "An override never results in less than 1 HP")
	rat.free()
	var paths: Array[String] = ["res://resources/enemy_raider.tres"]
	for file in DirAccess.get_files_at("res://resources/enemies"):
		if file.ends_with(".tres") and file != "rat.tres":
			paths.append("res://resources/enemies/" + file)
	for enemy_path in paths:
		var existing := load(enemy_path) as EnemyDefinition
		_check(existing != null and existing.base_health_override == 0, "Existing enemy keeps legacy health: %s" % enemy_path)
		if existing != null:
			_check(existing.max_health == UnitStat.get_scaling_rules().calculate_max_health(existing.constitution), "Existing authored HP stays unchanged: %s" % enemy_path)
			for constitution in [0.0, 1.0, 2.5, 25.0]:
				_check(existing.calculate_max_health(constitution) == UnitStat.get_scaling_rules().calculate_max_health(constitution), "Existing modified HP stays unchanged: %s" % enemy_path)
	var suite = load("res://tests/test_stats_system.gd").new()
	suite._reset()
	suite.setup()
	suite.test_constitution_drives_health_modifiers_inspector_and_ai_snapshots()
	suite.teardown()
	suite._free_tracked()
	_check(not suite._failed, "Existing Constitution regression: %s" % suite._message)


func _test_bite() -> void:
	var field := Node2D.new()
	root.add_child(field)
	var grid := IsometricGrid.new()
	grid.grid_size = Vector2i(6, 6)
	field.add_child(grid)
	var rat := (load(RAT) as PackedScene).instantiate() as TacticalCharacter
	rat.starting_grid_cell = Vector2i(1, 1)
	field.add_child(rat)
	rat.initialize(grid)
	var target := TacticalCharacter.new()
	target.definition = CharacterDefinition.new()
	target.starting_grid_cell = Vector2i(2, 1)
	field.add_child(target)
	target.initialize(grid)
	var bite := load("res://resources/abilities/bite.tres") as AbilityDefinition
	var teeth := load("res://resources/items/rat_teeth.tres") as ItemDefinition
	_check(teeth.weapon_damage == 5 and teeth.modifiers.is_empty(), "Rat Teeth provide 5 weapon damage and no stat modifiers")
	_check(bite.calculate_damage(rat) == 5, "Bite previews exactly 5 damage")
	rat.set_dev_stat_override(UnitStat.Type.STRENGTH, 99.0)
	_check(bite.calculate_damage(rat) == 5, "Bite has no Strength scaling")
	var executor := AbilityExecutor.new()
	field.add_child(executor)
	var units: Array[TacticalCharacter] = [rat, target]
	var targeting := AbilityTargeting.new(grid.grid_size)
	for cell in [Vector2i(2, 1), Vector2i(2, 2)]:
		target.set_grid_cell_immediate(cell)
		rat.reset_movement()
		rat.reset_ability_action()
		var health_before := target.current_health
		var succeeded := await executor.execute(rat, bite, cell, units, grid, targeting, {})
		_check(succeeded, "Bite is usable at adjacent and diagonal melee range")
		_check(health_before - target.current_health == 5, "Bite removes exactly 5 HP from an unmodified target")
		_check(not rat.ability_available, "Bite spends the normal ability action")
	field.queue_free()
	await process_frame


func _battle(template: BattleMapDefinition, payload: Dictionary = {}) -> TacticalBattle:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = template
	battle.pending_restore_payload = payload
	battle.center_camera_on_start = false
	root.add_child(battle)
	return battle


func _test_palette_save_and_template() -> void:
	var catalog := load("res://resources/dev_tool_catalog.tres") as DevToolCatalog
	var rat_scene := load(RAT) as PackedScene
	_check(catalog.unit_scenes.has(rat_scene), "Developer unit palette contains Rat")
	_check(catalog.abilities.has(load("res://resources/abilities/bite.tres")), "Developer ability catalog contains Bite")
	_check(catalog.items.has(load("res://resources/items/rat_teeth.tres")), "Developer item catalog contains Rat Teeth")
	var authored := load("res://resources/maps/goblin_skirmish.tres") as BattleMapDefinition
	var battle := _battle(authored)
	_check(battle.initialization_succeeded, "Existing authored battle loads")
	battle._open_dev_mode()
	battle._add_dev_unit(catalog.unit_scenes[catalog.unit_scenes.find(rat_scene)], Vector2i(0, 0))
	var rat := battle.dev_mode_panel.get_selected_unit()
	_check(rat.definition == load(DEFINITION) and rat.current_health == 5, "Developer palette spawns a full-health Rat")
	rat.set_facing(TacticalCharacter.Facing.RIGHT)
	var rat_id := rat.scenario_unit_id
	var fresh_payload := battle.capture_save_payload(true)
	var directory := "res://.godot/rat_scenario_test"
	var saved := ScenarioSaveStore.save_new(fresh_payload, directory)
	_check(saved.ok, "Scenario containing the Rat saves with the existing schema")
	var loaded := ScenarioSaveStore.load_save(saved.path, directory) if saved.ok else {}
	_check(loaded.get("ok", false), "Rat scenario reloads from disk")
	paused = false
	battle.shutdown_battle()
	battle.queue_free()
	await process_frame
	if loaded.get("ok", false):
		var restored := _battle(authored, loaded.payload)
		_check(restored.initialization_succeeded, "Saved Rat scenario initializes")
		var found := false
		for actor in restored._characters:
			if actor.scenario_unit_id != rat_id:
				continue
			found = true
			_check(actor.get_max_health() == 5 and actor.current_health == 5 and actor.definition.combat_rating == 1, "Rat health and CR survive scenario reload")
			_check(actor.starting_grid_cell == Vector2i(0, 0), "Rat placement survives scenario reload")
			_check((load("res://resources/abilities/bite.tres") as AbilityDefinition).calculate_damage(actor) == 5, "Rat equipment and damage survive scenario reload")
		_check(found, "Scenario restores the Rat stable ID")
		_check(restored.capture_save_payload(true).setup.units == fresh_payload.setup.units, "Restart preserves the full configured roster")
		restored.shutdown_battle()
		restored.queue_free()
		await process_frame
		ScenarioSaveStore.delete_save(saved.path, directory)
	var demo := load(DEMO) as BattleMapTemplateDefinition
	_check(demo.enemy_pool.size() == 6 and not demo.enemy_pool.has(rat_scene), "Demo enemy pool remains the original six scenes")
	var custom := demo.duplicate() as BattleMapTemplateDefinition
	custom.enemy_pool = [rat_scene]
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	var composition := EnemyEncounterGenerator.generate(custom, 5, rng)
	_check(composition.error.is_empty() and composition.total_cr == 3 and composition.scenes.size() == 3, "Rat works when manually assigned to a CR 3 template")
	var generated := _battle(custom)
	_check(generated.initialization_succeeded, "Rat-only template battle initializes")
	var rat_count := 0
	for actor in generated._characters:
		if not actor.is_friendly():
			rat_count += 1
			_check(actor.definition == load(DEFINITION) and actor.get_max_health() == 5, "Generated rats retain their definition and exact health")
	_check(rat_count == 3, "CR 3 template spawns three CR 1 rats")
	generated.shutdown_battle()
	# Remove this temporary map and its duplicated resource before the runner exits.
	root.remove_child(generated)
	generated.free()
	await process_frame
