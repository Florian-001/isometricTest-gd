extends SceneTree

const DIRECTORY := "res://.godot/armor_validation"
var checks := 0
var failures: Array[String] = []
var arena: Node2D
var grid: IsometricGrid
var shield: ItemDefinition = load("res://resources/items/offhand/wooden_shield.tres")


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count := 3) -> void:
	for index in range(count):
		await process_frame


func _run() -> void:
	root.size = Vector2i(1280, 720)
	create_timer(60.0).timeout.connect(func(): push_error("Armor tests timed out"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	arena = Node2D.new()
	root.add_child(arena)
	grid = IsometricGrid.new()
	grid.grid_size = Vector2i(12, 12)
	arena.add_child(grid)
	_test_authored_armor()
	_test_pools_and_equipment()
	await _test_ai()
	arena.free()
	await _test_saves_and_ui()
	await _test_finalization()
	await _test_run_encounters()
	print("ARMOR_TESTS_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func unit(enemy := false, cell := Vector2i(2, 2), items: Array[ItemDefinition] = []) -> TacticalCharacter:
	var actor := TacticalCharacter.new()
	actor.definition = CharacterDefinition.new()
	actor.definition.faction = CharacterDefinition.Faction.ENEMY if enemy else CharacterDefinition.Faction.FRIENDLY
	actor.definition.starting_equipment = items
	actor.starting_grid_cell = cell
	arena.add_child(actor)
	actor.initialize(grid)
	actor.reset_ability_action()
	return actor


func spell(amount: int) -> AbilityDefinition:
	var ability := AbilityDefinition.new()
	ability.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	ability.ability_type = AbilityDefinition.AbilityType.MAGIC
	ability.innate_damage = amount
	ability.scaling_stat = UnitStat.Type.NONE
	ability.scaling_amount = 0.0
	ability.range = 20.0
	return ability


func _test_authored_armor() -> void:
	var cases := [
		{"id": "leather_armor", "armor": 5, "bonuses": {UnitStat.Type.STRENGTH: 1.0, UnitStat.Type.DEXTERITY: 1.0}, "details": "+5 Armor\n\n+1 Strength\n\n+1 Dexterity"},
		{"id": "plate_armor", "armor": 10, "bonuses": {}, "details": "+10 Armor"},
		{"id": "robe", "armor": 3, "bonuses": {UnitStat.Type.INTELLIGENCE: 3.0}, "details": "+3 Armor\n\n+3 Intelligence"},
	]
	var catalog := ItemDefinitionCatalog.get_items()
	var developer_catalog := load("res://resources/dev_tool_catalog.tres") as DevToolCatalog
	var details := (load("res://scenes/inventory_item_details.tscn") as PackedScene).instantiate() as InventoryItemDetails
	root.add_child(details)
	for entry in cases:
		var item := load("res://resources/items/armor/%s.tres" % entry.id) as ItemDefinition
		check(item != null, "%s loads as an item" % entry.id)
		if item == null:
			continue
		check(item.slot == ItemDefinition.EquipmentSlot.ARMOR, "%s uses the Armor slot" % entry.id)
		check(item.icon != null and item.icon.get_size() == Vector2(64, 64), "%s has a 64x64 icon" % entry.id)
		check(catalog.has(item) and developer_catalog.items.has(item), "%s is available in both editor catalogs" % entry.id)
		var actor := unit()
		var base_stats: Dictionary = {}
		for stat in [UnitStat.Type.STRENGTH, UnitStat.Type.DEXTERITY, UnitStat.Type.INTELLIGENCE]:
			base_stats[stat] = actor.get_effective_stat(stat)
		actor.equip_item(item)
		check(actor.get_equipped_item(ItemDefinition.EquipmentSlot.ARMOR) == item, "%s equips into Armor" % entry.id)
		check(actor.get_max_armor() == entry.armor and actor.current_armor == entry.armor, "%s applies its armor contribution" % entry.id)
		for stat in base_stats:
			check(is_equal_approx(actor.get_effective_stat(stat), base_stats[stat] + float(entry.bonuses.get(stat, 0.0))), "%s applies the exact %s bonus" % [entry.id, UnitStat.get_display_name(stat)])
		details.show_item(item, true)
		check(details.title.text == item.display_name and details.category.text == "Armor" and details.body.text == entry.details, "%s item details show its exact bonuses" % entry.id)
		actor.unequip_item(ItemDefinition.EquipmentSlot.ARMOR)
		check(actor.get_max_armor() == 0 and actor.current_armor == 0, "%s unequip removes its armor contribution" % entry.id)
		for stat in base_stats:
			check(is_equal_approx(actor.get_effective_stat(stat), base_stats[stat]), "%s unequip restores %s" % [entry.id, UnitStat.get_display_name(stat)])
		actor.free()
	details.free()


func _test_pools_and_equipment() -> void:
	check(shield.armor == 10 and shield.modifiers[0].value == 3.0, "shield grants 10 armor and retains +3 Constitution")
	var item := ItemDefinition.new()
	check(item.armor == 0, "other items default to zero armor")
	item.armor = -4
	check(item.armor == 0, "item armor is nonnegative")
	item.slot = ItemDefinition.EquipmentSlot.ARMOR
	item.armor = 5
	check(ResourceSaver.save(item, DIRECTORY + "/armor_item.tres") == OK, "armor item saves")
	check((load(DIRECTORY + "/armor_item.tres") as ItemDefinition).armor == 5, "authored armor survives resource reload")
	var a := unit(false, Vector2i(2, 2), [shield])
	var b := unit(true, Vector2i(3, 2), [shield])
	var hp := a.current_health
	var changes: Array[Vector2i] = []
	a.armor_changed.connect(func(current: int, maximum: int): changes.append(Vector2i(current, maximum)))
	check(a.current_armor == 10 and b.current_armor == 10, "both factions spawn at full armor")
	a.apply_damage(6)
	check(a.current_armor == 4 and a.current_health == hp and b.current_armor == 10, "armor absorbs damage independently for each unit")
	check(changes[-1] == Vector2i(4, 10), "armor damage emits updated values")
	a.heal(99)
	check(a.current_armor == 4, "health healing does not restore armor")
	a.unequip_item(ItemDefinition.EquipmentSlot.OFFHAND)
	var saved := a.capture_runtime_state()
	check(saved.armor_damage_spent == 6 and a.current_armor == 0, "unequipped armor retains spent damage")
	a.restore_runtime_state(saved, {})
	a.equip_item(shield)
	check(a.current_armor == 4, "save and restore while unequipped prevents armor refill by re-equipping")
	a.equip_item(item)
	check(a.get_max_armor() == 15 and a.current_armor == 9, "equipped armor contributions stack against spent damage")
	var two_handed := ItemDefinition.new()
	two_handed.weapon_handedness = ItemDefinition.WeaponHandedness.TWO_HANDED
	two_handed.armor = 7
	a.equip_item(two_handed)
	check(a.get_max_armor() == 12 and a.current_armor == 6, "two-handed item displaces shield and counts its armor only once")
	a.equip_item(shield)
	check(a.get_max_armor() == 15 and a.current_armor == 9, "offhand replacement retains armor damage")
	a.unequip_item(ItemDefinition.EquipmentSlot.ARMOR)
	a.restore_armor()
	hp = a.current_health
	a.apply_damage(10)
	check(a.current_armor == 0 and a.current_health == hp, "exact armor depletion leaves health unchanged")
	a.restore_armor()
	a.apply_damage(14)
	check(a.current_armor == 0 and a.current_health == hp - 4, "overflow reaches health")
	a.current_health = 2
	a.restore_armor()
	a.apply_damage(11)
	check(a.current_health == 1 and a.current_armor == 0, "damage is split before low-health clamping")
	a.apply_damage(1)
	check(a.current_health == 0, "health depletion defeats after armor")
	a.apply_damage(100)
	check(a.current_health == 0 and a.current_armor == 0, "defeated units do not take further damage")
	a = unit()
	hp = a.current_health
	a.apply_damage(4)
	check(a.current_health == hp - 4 and a.current_armor == 0, "unarmored damage remains unchanged")
	a.equip_item(shield)
	a.apply_damage(0)
	a.apply_damage(-3)
	check(a.current_armor == 10, "nonpositive damage does not consume armor")
	saved = a.capture_runtime_state()
	saved.erase("armor_damage_spent")
	a.apply_damage(9)
	a.restore_runtime_state(saved, {})
	check(a.current_armor == 10, "legacy runtime snapshots default to full armor")
	for child in arena.get_children():
		if child is TacticalCharacter:
			child.free()


func _test_ai() -> void:
	var caster := unit(false, Vector2i(1, 2))
	var target := unit(true, Vector2i(2, 2), [shield])
	var units: Array[TacticalCharacter] = [caster, target]
	var planner := EnemyAIPlanner.new()
	var targeting := AbilityTargeting.new()
	targeting.set_grid_size(grid.grid_size)
	for hp in [2, 20]:
		for amount in [4, 10, 14, 25]:
			target.current_health = hp
			target.restore_armor()
			var ability := spell(amount)
			var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
			var estimate := ability.estimate_primary_effect_for_ai(caster, target, hp, false, snapshot)
			var score := planner._score_effect_estimate(caster, target, estimate, null, snapshot)
			check(score > 0.0 and target.current_health == hp and target.current_armor == 10, "forecast values armor damage without changing live state")
			target.apply_damage(amount)
			check(snapshot.get_health(target) == target.current_health and snapshot.get_armor(target) == target.current_armor, "primary forecast agrees with both pools at HP %d damage %d" % [hp, amount])
	target.current_health = 20
	target.restore_armor()
	var multi := spell(6)
	multi.hit_count = 3
	caster.set_dev_ability_loadout([multi])
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
	var copied := snapshot.duplicate_state()
	var before_key := planner._get_snapshot_key(snapshot)
	var executor := AbilityExecutor.new()
	arena.add_child(executor)
	planner._forecast_ability(caster, multi, target.grid_cell, snapshot, targeting, EnemyAIProfile.new())
	check(await executor.execute(caster, multi, target.grid_cell, units, grid, targeting), "multi-hit cast executes")
	check(target.current_health == 12 and target.current_armor == 0 and snapshot.get_health(target) == 12 and snapshot.get_armor(target) == 0, "repeated hits consume armor exactly once per hit")
	check(copied.get_armor(target) == 10 and planner._get_snapshot_key(snapshot) != before_key, "snapshot copies and cache keys include armor")
	var key_probe := copied.duplicate_state()
	key_probe.unit_armor[target] = 9
	check(planner._get_snapshot_key(key_probe) != planner._get_snapshot_key(copied), "armor-only changes invalidate cached forecasts")
	target.current_health = 20
	target.restore_armor()
	var nested := spell(0)
	nested.effect = AbilityDefinition.PrimaryEffect.NONE
	for amount in [8, 6]:
		var effect := DamageEffectDefinition.new()
		effect.damage_type = DamageEffectDefinition.DamageType.MAGICAL
		effect.innate_damage = amount
		effect.scaling_stat = UnitStat.Type.NONE
		nested.effects.append(effect)
	caster.set_dev_ability_loadout([nested])
	caster.reset_ability_action()
	snapshot = AIBoardSnapshot.from_battle(units, grid.grid_size)
	planner._forecast_ability(caster, nested, target.grid_cell, snapshot, targeting, EnemyAIProfile.new())
	check(await executor.execute(caster, nested, target.grid_cell, units, grid, targeting), "additional damage effects execute")
	check(target.current_health == 16 and target.current_armor == 0 and snapshot.get_health(target) == 16 and snapshot.get_armor(target) == 0, "additional effects agree with armor forecast")
	target.current_health = 20
	target.restore_armor()
	var burning := (load("res://resources/statuses/burning.tres") as StatusEffectDefinition).duplicate() as StatusEffectDefinition
	burning.damage_per_turn = 4
	burning.duration_turns = 3
	snapshot = AIBoardSnapshot.from_battle(units, grid.grid_size)
	var estimated := snapshot.forecast_status_application(caster, target, burning)
	snapshot.apply_effect_estimate(target, estimated)
	for index in range(3):
		burning.apply_turn_start(target)
	check(target.current_health == 18 and target.current_armor == 0 and snapshot.get_health(target) == 18 and snapshot.get_armor(target) == 0, "damage-over-time forecast consumes armor before health across its duration")
	target.current_health = 20
	target.restore_armor()
	var tile := TileDefinition.new()
	var trigger := TileTriggeredEffectDefinition.new()
	trigger.effect = nested.effects[0]
	tile.effects = [trigger]
	snapshot = AIBoardSnapshot.from_battle(units, grid.grid_size, {}, {target.grid_cell: tile})
	var tile_estimate := tile.estimate_trigger(target, TileTriggeredEffectDefinition.Trigger.ENTER, 20, 10)
	planner._forecast_terrain_trigger(target, TileTriggeredEffectDefinition.Trigger.ENTER, snapshot, EnemyAIProfile.new())
	tile.apply_trigger(target, TileTriggeredEffectDefinition.Trigger.ENTER)
	check(target.current_health == 20 and target.current_armor == 2 and snapshot.get_armor(target) == 2 and int(tile_estimate.armor_delta) == -8, "terrain and tile estimates absorb damage in armor")
	# Selected per-hit casts use a separate executor entry point.
	target.current_health = 20
	target.restore_armor()
	var selected := spell(6)
	selected.hit_count = 2
	selected.hit_targeting = AbilityDefinition.HitTargeting.SELECT_PER_HIT
	caster.set_dev_ability_loadout([selected])
	caster.reset_ability_action()
	check(await executor.execute_targets(caster, selected, [target, target], units, grid, targeting), "selected repeated-target cast executes")
	check(target.current_armor == 0 and target.current_health == 18 and not executor.is_resolving(), "selected hits share armor and settle their resolution")
	target.current_health = 20
	target.restore_armor()
	var healing := spell(0)
	healing.effect = AbilityDefinition.PrimaryEffect.HEAL
	healing.effect_amount = 8
	target.apply_damage(14)
	snapshot = AIBoardSnapshot.from_battle(units, grid.grid_size)
	snapshot.apply_effect_estimate(target, healing.estimate_primary_effect_for_ai(caster, target, target.current_health, false, snapshot))
	healing.apply_primary_effect(caster, target)
	check(snapshot.get_health(target) == target.current_health and snapshot.get_armor(target) == 0 and target.current_armor == 0, "healing estimates and runtime restore only HP")
	# A normal weapon attack forecast also underlies opportunity reactions.
	var strike := load("res://resources/abilities/strike.tres") as AbilityDefinition
	var sword := load("res://resources/items/weapons/iron_sword.tres") as ItemDefinition
	caster.equip_item(sword)
	caster.set_dev_ability_loadout([strike])
	caster.reset_opportunity_reaction()
	target.current_health = 30
	target.restore_armor()
	snapshot = AIBoardSnapshot.from_battle(units, grid.grid_size)
	planner._forecast_opportunity_attacks(target, target.grid_cell, Vector2i(3, 2), snapshot, targeting, EnemyAIProfile.new())
	check(await executor.execute_opportunity_attack(caster, strike, target.grid_cell, units, grid, targeting), "opportunity attack executes")
	check(snapshot.get_health(target) == target.current_health and snapshot.get_armor(target) == target.current_armor, "opportunity forecast agrees with armor runtime")
	var skeleton := (load("res://scenes/enemies/skeleton_warrior.tscn") as PackedScene).instantiate() as TacticalCharacter
	arena.add_child(skeleton)
	skeleton.equip_item(shield)
	snapshot = AIBoardSnapshot.from_battle([skeleton], grid.grid_size)
	var fatal := spell(999)
	snapshot.apply_effect_estimate(skeleton, fatal.estimate_primary_effect_for_ai(caster, skeleton, skeleton.current_health, false, snapshot))
	skeleton.apply_damage(999)
	check(skeleton.is_bone_pile and skeleton.current_armor == 0 and snapshot.is_bone_pile(skeleton) and snapshot.get_armor(skeleton) == 0, "Reassemble starts only after armor and health are depleted")
	skeleton.reform_from_bones()
	check(skeleton.current_armor == 0, "reformation does not restore spent armor")
	for child in arena.get_children():
		if child is TacticalCharacter or child is AbilityExecutor:
			child.free()


func battle() -> TacticalBattle:
	var result := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	result.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	root.add_child(result)
	return result


func close_battle(value: TacticalBattle) -> void:
	value.shutdown_battle()
	value.queue_free()
	paused = false
	await frames()


func _test_saves_and_ui() -> void:
	var value := battle()
	await frames()
	var actor := value.turn_manager.current_unit
	actor.set_dev_equipment(ItemDefinition.EquipmentSlot.OFFHAND, shield)
	actor.apply_damage(6)
	value.inventory_screen.open_for(actor)
	await frames()
	var row := value.inventory_screen.stats_entries.get_node("Armor")
	check(row.get_meta("value_text") == "4 / 10", "inventory displays current and maximum armor")
	value.inventory_screen.item_details.show_item(shield, true)
	check(value.inventory_screen.item_details.body.text.contains("+10 Armor") and value.inventory_screen.item_details.body.text.contains("+3 Constitution"), "shield tooltip describes both bonuses")
	value.inventory_screen.item_details.hide()
	value.inventory_screen.close_screen()
	var payload := value.capture_save_payload(false)
	check(ScenarioSaveStore.validate_payload(payload).ok, "armor runtime snapshot validates")
	var saved := ScenarioSaveStore.save_new(payload, DIRECTORY + "/scenarios")
	check(saved.ok, "armor snapshot saves")
	if saved.ok:
		var loaded := ScenarioSaveStore.load_save(saved.path, DIRECTORY + "/scenarios")
		actor.apply_damage(999)
		check(loaded.ok and value._restore_runtime_state(loaded.payload.runtime), "armor snapshot reloads")
		check(actor.current_armor == 4 and actor.current_health > 0, "checkpoint restores both damaged armor and health")
	value.inventory_screen.setup(value.general_inventory, value._get_living_friendlies())
	for bad_value in [-1, 1.5, "6", true]:
		var bad := payload.duplicate(true)
		bad.runtime.units[0].armor_damage_spent = bad_value
		check(not ScenarioSaveStore.validate_payload(bad).ok, "invalid spent armor is rejected")
	var legacy := payload.duplicate(true)
	for runtime in legacy.runtime.units:
		runtime.erase("armor_damage_spent")
	check(ScenarioSaveStore.validate_payload(legacy).ok, "legacy scenarios without armor remain valid")
	# Freeze combat for deterministic UI captures, keeping the armored unit selected.
	paused = true
	for character in value._characters:
		for child in character.get_children():
			if child.has_meta("damage_number"):
				child.hide()
	await _capture(value, "armor_battle", false)
	await _capture(value, "armor_inventory", true)
	var fresh_payload := value.capture_save_payload(true)
	var actor_id := actor.scenario_unit_id
	await close_battle(value)
	value = (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	value.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	value.pending_restore_payload = fresh_payload
	root.add_child(value)
	await frames()
	for candidate in value._characters:
		if candidate.scenario_unit_id == actor_id:
			check(candidate.current_armor == 10 and candidate.current_health == candidate.get_max_health(), "fresh developer restart resets spent armor and health")
	await close_battle(value)


func _test_finalization() -> void:
	var value := battle()
	await frames()
	var caster := value.turn_manager.current_unit
	caster.equip_item(shield)
	caster.current_health = 60
	caster.apply_damage(6)
	# An animated area attack kills the last enemy on hit one, then still hits
	# surviving allies on hit two. Refilling between those hits would hide HP loss.
	var attack := spell(7)
	attack.hit_count = 2
	attack.delivery_type = AbilityDefinition.DeliveryType.PROJECTILE
	attack.projectile_speed = 300.0
	attack.area_of_effect = 21
	attack.target_flags = AbilityDefinition.TargetFlags.ENEMY | AbilityDefinition.TargetFlags.FRIEND | AbilityDefinition.TargetFlags.SELF
	caster.set_dev_ability_loadout([attack])
	caster.reset_ability_action()
	value._dev_open_pending = true
	for actor in value._characters:
		if not actor.is_friendly():
			actor.current_health = 1
	var during: Array[int] = []
	caster.armor_changed.connect(func(current: int, _maximum: int):
		if value._ability_executor.is_resolving():
			during.append(current))
	check(await value._ability_executor.execute(caster, attack, caster.grid_cell, value._characters, value.grid, value._ability_targeting, value._get_wall_cells()), "final multi-hit area attack executes")
	check(not during.has(10) and caster.current_health == 50, "final hits preserve depleted armor (HP %d, armor events %s)" % [caster.current_health, during])
	await frames()
	check(value._combat_over and value._combat_finalized and caster.current_armor == 10 and caster.current_health == 50, "standalone victory restores armor after damage resolves and leaves health unchanged")
	check(value._dev_open and paused, "queued Dev panel opens only after the final action and armor restoration")
	caster.apply_damage(2)
	value._queue_run_result()
	await frames()
	check(caster.current_armor == 8, "repeated finalization does not refill armor twice")
	await close_battle(value)
	value = battle()
	await frames()
	var survivor: TacticalCharacter
	for actor in value._characters:
		if not actor.is_friendly():
			survivor = actor
			break
	survivor.equip_item(shield)
	survivor.apply_damage(6)
	var hp := survivor.current_health
	caster = value.turn_manager.current_unit
	for actor in value._characters:
		if actor.is_friendly() and actor != caster:
			actor.apply_damage(9999)
	caster.set_grid_cell_immediate(Vector2i(0, 0))
	survivor.set_grid_cell_immediate(Vector2i(2, 0))
	var charge := spell(2)
	charge.caster_movement = AbilityDefinition.CasterMovement.CHARGE_TO_TARGET
	caster.set_dev_ability_loadout([charge])
	caster.reset_ability_action()
	caster.reset_movement()
	var abort_step := func(_moving: TacticalCharacter, _from: Vector2i, _to: Vector2i) -> bool:
		caster.apply_damage(99999)
		return false
	var succeeded := await value._ability_executor.execute(caster, charge, survivor.grid_cell, value._characters, value.grid, value._ability_targeting, {}, abort_step)
	check(not succeeded and not value._ability_executor.is_resolving(), "an aborted charge releases its resolution after the caster dies")
	await frames()
	check(value._combat_finalized and survivor.current_armor == 10 and survivor.current_health == hp, "defeat restores surviving enemy armor without healing")
	await close_battle(value)


func _test_run_encounters() -> void:
	var manager := (load("res://main.tscn") as PackedScene).instantiate() as MapManager
	var run := manager.get_node("RunController") as RunController
	run.save_path = DIRECTORY + "/run_%d.json" % Time.get_ticks_usec()
	root.add_child(manager)
	check(run.new_run(37), "isolated armor run starts")
	var member := run.state.party[0]
	member.equipment.append(shield.resource_path)
	member.setup.stat_overrides.speed = 1000
	check(run.select_room(run.state.available_rooms()[0]), "run encounter starts")
	await frames()
	var value := manager.current_battle
	var actor: TacticalCharacter
	for candidate in value._characters:
		if candidate.scenario_unit_id == member.id:
			actor = candidate
	check(actor != null and actor.current_armor == 10, "run starts with armor derived from equipment")
	actor.apply_damage(14)
	var hp := actor.current_health
	var finalized: Array[int] = []
	value.battle_finished.connect(func(_victory: bool, _results: Array[Dictionary], _items: Array[String]):
		finalized.append(actor.current_armor))
	for enemy in value._characters:
		if not enemy.is_friendly():
			enemy.apply_damage(99999)
			if enemy.is_bone_pile:
				enemy.apply_damage(99999)
	await frames(5)
	check(finalized == [10] and manager.current_battle == null, "run result emits once after armor restoration")
	check(member.health == hp, "run result retains health damage")
	# Reconstruct a subsequent encounter from the persisted member loadout.
	var next := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	next.map_definition = load("res://resources/run/goblin_skirmish_map.tres")
	next.run_encounter = load("res://resources/run/goblin_skirmish_normal.tres")
	for party_member in run.state.party:
		next.run_party_input.append(party_member.to_data())
	root.add_child(next)
	await frames()
	for candidate in next._characters:
		if candidate.scenario_unit_id == member.id:
			check(candidate.current_armor == 10 and candidate.current_health == hp, "next encounter has full armor and persistent damaged health")
	await close_battle(next)
	manager.return_to_level_select()
	manager.queue_free()
	await frames()


func _capture(value: TacticalBattle, filename: String, inventory: bool) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	value.clear_selection()
	var actor: TacticalCharacter
	for candidate in value._characters:
		if candidate.is_friendly() and candidate.get_max_armor() > 0:
			actor = candidate
			break
	for dimensions in [Vector2i(1280, 720), Vector2i(800, 600)]:
		root.size = dimensions
		if inventory:
			value.inventory_screen.open_for(actor)
			check(value.inventory_screen.stats_entries.get_node("Armor").get_meta("value_text") == "4 / 10", "capture shows the armored character")
		await frames()
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(DIRECTORY + "/%s_%dx%d.png" % [filename, dimensions.x, dimensions.y]) == OK, "render armor at " + str(dimensions))
	if inventory:
		value.inventory_screen.close_screen()
	root.size = Vector2i(1280, 720)
