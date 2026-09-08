extends SceneTree

const CAPTURE_DIR := "res://.godot/spear_validation"
var spear: ItemDefinition = load("res://resources/items/spear.tres")
var long_sword: ItemDefinition = load("res://resources/items/long_sword.tres")
var sword: ItemDefinition = load("res://resources/items/iron_sword.tres")
var shield: ItemDefinition = load("res://resources/items/wooden_shield.tres")
var strike: AbilityDefinition = load("res://resources/abilities/strike.tres")
var arena: Node2D
var grid: IsometricGrid
var targeting: AbilityTargeting
var executor: AbilityExecutor
var caster: TacticalCharacter
var target: TacticalCharacter
var units: Array[TacticalCharacter] = []
var checks := 0
var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(50.0).timeout.connect(func(): push_error("Spear tests timed out"); quit(1))
	_test_resources()
	arena = Node2D.new()
	root.add_child(arena)
	grid = IsometricGrid.new()
	grid.grid_size = Vector2i(10, 10)
	arena.add_child(grid)
	targeting = AbilityTargeting.new(grid.grid_size)
	executor = AbilityExecutor.new()
	arena.add_child(executor)
	caster = _unit(true, Vector2i(4, 4))
	target = _unit(false, Vector2i(6, 4))
	_test_range_resolution()
	_test_grid_boundaries()
	await _test_delivery_and_ai()
	await _test_reactions()
	arena.queue_free()
	await process_frame
	await _test_battle_and_saves()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("SPEAR_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _unit(friendly: bool, cell: Vector2i) -> TacticalCharacter:
	var unit := TacticalCharacter.new()
	unit.definition = CharacterDefinition.new()
	unit.definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	unit.definition.constitution = 100
	unit.definition.strength = 10
	unit.use_complete_equipment_override = true
	unit.starting_grid_cell = cell
	arena.add_child(unit)
	unit.initialize(grid)
	unit.reset_ability_action()
	unit.reset_opportunity_reaction()
	unit.reset_movement()
	units.append(unit)
	return unit


func _test_resources() -> void:
	check(ItemDefinition.new().weapon_range_bonus == 0.0 and not AbilityDefinition.new().accepts_weapon_range_bonus, "new resources preserve default range behavior")
	var catalog := load("res://resources/dev_tool_catalog.tres") as DevToolCatalog
	var config := load("res://resources/run/default_run.tres") as RunConfig
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate()
	for item in [long_sword, spear]:
		check(item.is_two_handed() and item.slot == ItemDefinition.EquipmentSlot.WEAPON and item.weapon_type == ItemDefinition.WeaponType.MELEE, "both new weapons use two melee hands")
		check(item.icon != null and item.modifiers.is_empty() and item.status_effect == null, "each weapon has artwork and no extra stats/status")
		check(item.get_granted_abilities() == [strike], "both grant canonical Strike")
		check(catalog.items.count(item) == 1 and config.equipment_pool.count(item) == 1 and battle.get_node("GeneralInventory").starting_items.count(item) == 1, "each weapon appears once in developer, reward/shop, and sample inventories")
	check(long_sword.weapon_damage == 10 and long_sword.weapon_range_bonus == 0.0, "Long Sword gives ten weapon damage")
	check(spear.weapon_damage == 5 and spear.weapon_range_bonus == 1.0, "Spear gives five weapon damage and one range")
	battle.free()
	for file in DirAccess.get_files_at("res://resources/abilities"):
		if file.ends_with(".tres"):
			var ability := load("res://resources/abilities/" + file) as AbilityDefinition
			check(ability.accepts_weapon_range_bonus == (ability == strike), "only Strike opts into weapon range: " + file)
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	var authored := spear.duplicate() as ItemDefinition
	authored.weapon_range_bonus = 2.0
	var path := CAPTURE_DIR.path_join("authored_spear.tres")
	check(ResourceSaver.save(authored, path) == OK, "range bonus saves as an editable resource property")
	check((ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ItemDefinition).weapon_range_bonus == 2.0, "edited range bonus reloads")
	var hidden := {"name": &"weapon_range_bonus", "usage": PROPERTY_USAGE_DEFAULT}
	shield._validate_property(hidden)
	check((hidden.usage & PROPERTY_USAGE_EDITOR) == 0, "non-weapons hide weapon range bonus")


func _test_range_resolution() -> void:
	check(is_equal_approx(strike.get_effective_range(), 1.414), "missing caster returns authored range")
	caster.equip_item(spear)
	check(is_equal_approx(strike.get_effective_range(caster), 2.414) and is_equal_approx(strike.range, 1.414), "spear adds one without mutating shared Strike")
	target.set_dev_ability_loadout([strike])
	target.equip_item(sword)
	check(is_equal_approx(strike.get_effective_range(target), 1.414), "other caster sharing Strike keeps normal range")
	for path in ["battle_stomp", "multi_attack", "charge", "arrow"]:
		var ability := load("res://resources/abilities/" + path + ".tres") as AbilityDefinition
		check(is_equal_approx(ability.get_effective_range(caster), ability.range) and is_equal_approx(ability.get_effective_melee_reach(caster), 1.414), "%s ignores spear range" % path)
	check(strike.get_description(caster).contains("Range 2.41") and strike.get_description(caster).contains("normal attacks only"), "ability descriptions expose effective range and reaction exception")
	caster.equip_item(long_sword)
	check(is_equal_approx(strike.get_effective_range(caster), 1.414), "Long Sword restores normal Strike range")
	caster.equip_item(spear)
	caster.equip_item(shield)
	check(caster.get_equipped_weapon() == null and is_equal_approx(strike.get_effective_range(caster), 1.414), "offhand conflict removes spear bonus")
	caster.equip_item(load("res://resources/items/ranger_bow.tres"))
	check(strike.get_weapon_range_bonus(caster) == 0.0, "incompatible weapon gives no range bonus")
	caster.equip_item(spear)
	var pack := GeneralInventory.new()
	arena.add_child(pack)
	pack.initialize_starting_items([sword, shield, long_sword])
	pack.equip_from_slot(0, caster, 0)
	pack.equip_from_slot(1, caster, 3)
	check(pack.equip_from_slot(2, caster, 0) and caster.get_equipped_items() == [long_sword], "Long Sword displaces sword and shield")
	check(pack.get_items().has(sword) and pack.get_items().has(shield) and pack.get_items().has(spear), "hand conflicts conserve all weapons and shield")
	pack.equip_from_slot(pack.get_slots().find(spear), caster, 0)
	check(caster.get_slot_occupant(3) == spear and caster.get_equipped_items() == [spear], "Spear reserves Offhand and is counted once")


func _test_grid_boundaries() -> void:
	var planner := EnemyAIPlanner.new()
	for weapon in [spear, long_sword, sword]:
		caster.equip_item(weapon)
		var range_cells := targeting.get_cells_in_range(caster, strike)
		for dx in range(-3, 4):
			for dy in range(-3, 4):
				var cell := caster.grid_cell + Vector2i(dx, dy)
				var diagonal := mini(absi(dx), absi(dy))
				var distance := maxi(absi(dx), absi(dy)) - diagonal + diagonal * 1.414
				var within_range: bool = distance <= (2.4141 if weapon == spear else 1.4141)
				var valid: bool = within_range and Vector2i(dx, dy) != Vector2i.ZERO
				check(range_cells.has(cell) == within_range, "range highlight matches expected weighted distance")
				check(targeting.is_valid_primary_target(caster, cell, strike, units) == valid, "targeting honors distance and excludes caster")
				check(executor.can_execute(caster, strike, cell, units, grid, targeting) == valid, "runtime cast validator matches targeting")
				var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
				check(planner._is_valid_primary_target(caster, caster.grid_cell, cell, strike, snapshot, targeting) == valid, "AI primary target validator matches runtime")
	caster.equip_item(spear)
	for fixture in [
		{"offset": Vector2i(2, 0), "walls": {Vector2i(5, 4): true}},
		{"offset": Vector2i(2, 0), "walls": {Vector2i(6, 4): true}},
		{"offset": Vector2i(2, 1), "walls": {Vector2i(5, 4): true}},
		{"offset": Vector2i(2, 1), "walls": {Vector2i(4, 5): true}},
		{"offset": Vector2i(1, 1), "walls": {Vector2i(5, 4): true}},
	]:
		var cell: Vector2i = caster.grid_cell + fixture.offset
		var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size, fixture.walls)
		check(not targeting.is_valid_primary_target(caster, cell, strike, units, fixture.walls), "walls and corner walls block spear targeting")
		check(not executor.can_execute(caster, strike, cell, units, grid, targeting, fixture.walls), "walls and corner walls block execution")
		check(not planner._is_valid_primary_target(caster, caster.grid_cell, cell, strike, snapshot, targeting), "AI respects the same spear wall rules")
	check(not MeleeDelivery.can_reach(caster.grid_cell, caster.grid_cell + Vector2i(2, 0)), "default melee reach remains adjacent")


func _test_delivery_and_ai() -> void:
	target.set_dev_ability_loadout([])
	caster.spend_movement(caster.remaining_movement)
	var planner := EnemyAIPlanner.new()
	for offset in [Vector2i(2, 0), Vector2i(2, 1)]:
		target.set_grid_cell_immediate(caster.grid_cell + offset)
		caster.reset_ability_action()
		var plan := planner.choose_plan(caster, units, GridPathfinder.new(grid.grid_size), targeting)
		check(plan.ability == strike and plan.target_cell == target.grid_cell and plan.get_cast_cell(caster.grid_cell) == caster.grid_cell, "AI chooses extended Strike without moving")
		var old_health := target.current_health
		var old_position := caster.global_position
		check(await executor.execute(caster, strike, target.grid_cell, units, grid, targeting), "extended Strike completes real melee delivery")
		check(target.current_health == old_health - 15 and caster.global_position.is_equal_approx(old_position), "spear applies Strength plus five damage and returns from lunge")
		check(not caster.ability_available and caster.opportunity_reaction_available, "normal spear attack spends action only")
	caster.equip_item(long_sword)
	caster.reset_ability_action()
	check(not executor.can_execute(caster, strike, target.grid_cell, units, grid, targeting), "Long Sword cannot attack extended target")
	var plan := planner.choose_plan(caster, units, GridPathfinder.new(grid.grid_size), targeting)
	check(plan.ability == null, "AI cannot attack beyond Long Sword reach without movement")
	target.set_grid_cell_immediate(caster.grid_cell + Vector2i(1, 0))
	var health := target.current_health
	check(await executor.execute(caster, strike, target.grid_cell, units, grid, targeting) and target.current_health == health - 20, "Long Sword uses Strength plus ten weapon damage")
	caster.equip_item(spear)
	caster.reset_ability_action()
	var blocked := {caster.grid_cell + Vector2i(1, 0): true}
	target.set_grid_cell_immediate(caster.grid_cell + Vector2i(2, 0))
	check(not await executor.execute(caster, strike, target.grid_cell, units, grid, targeting, blocked) and caster.ability_available, "blocked spear attacks preserve the action")
	var impacts := [0]
	check(not await executor.melee_delivery.perform(caster, strike, target.grid_cell, grid, func(): impacts[0] += 1, blocked) and impacts[0] == 0, "delivery itself rejects a spear through a wall")


func _test_reactions() -> void:
	caster.spend_ability_action()
	caster.reset_opportunity_reaction()
	var adjacent := caster.grid_cell + Vector2i(1, 0)
	var farther := caster.grid_cell + Vector2i(2, 0)
	target.set_grid_cell_immediate(farther)
	check(not OpportunityAttackSystem.can_trigger(caster, target, farther, farther + Vector2i(1, 0)), "leaving extended spear reach triggers no reaction")
	check(not executor.can_execute_opportunity_attack(caster, strike, farther, units, grid, targeting), "direct reaction validation rejects distant targets")
	check(not await executor.execute_opportunity_attack(caster, strike, farther, units, grid, targeting) and caster.opportunity_reaction_available, "rejected distant reaction spends nothing")
	var planner := EnemyAIPlanner.new()
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
	var old_health := target.current_health
	planner._forecast_opportunity_attacks(target, farther, farther + Vector2i(1, 0), snapshot, targeting, EnemyAIProfile.new())
	check(snapshot.get_health(target) == old_health and snapshot.can_use_opportunity_reaction(caster), "AI does not forecast distant spear reactions")
	target.set_grid_cell_immediate(adjacent)
	check(OpportunityAttackSystem.can_trigger(caster, target, adjacent, farther), "leaving adjacency still triggers even inside normal spear range")
	snapshot = AIBoardSnapshot.from_battle(units, grid.grid_size)
	planner._forecast_opportunity_attacks(target, adjacent, farther, snapshot, targeting, EnemyAIProfile.new())
	check(await executor.execute_opportunity_attack(caster, strike, adjacent, units, grid, targeting), "adjacent opportunity Strike executes")
	check(target.current_health == old_health - 15 and snapshot.get_health(target) == target.current_health, "reaction forecast matches actual damage")
	check(not caster.opportunity_reaction_available and not caster.ability_available, "reaction preserves the spent normal action")


func _test_battle_and_saves() -> void:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	root.add_child(battle)
	battle.set_process(false)
	var actor := battle._characters[0]
	var victim: TacticalCharacter
	for unit in battle._characters:
		if not unit.is_friendly():
			victim = unit
			break
	actor.set_grid_cell_immediate(Vector2i(4, 6))
	victim.set_grid_cell_immediate(Vector2i(6, 7))
	battle.turn_manager.current_unit = actor
	battle.turn_manager.current_index = battle.turn_manager.turn_order.find(actor)
	actor.reset_ability_action()
	battle._on_turn_started(actor)
	actor.equip_item(spear)
	battle._on_ability_selected(strike)
	check(battle._ability_target_cells.has(victim.grid_cell) and battle._ability_range_cells.has(victim.grid_cell), "battle highlights extended spear target")
	battle._update_ability_hover(battle.grid.grid_to_global(victim.grid_cell))
	await _capture("spear_targeting")
	actor.equip_item(long_sword)
	check(battle._selected_ability == strike and not battle._ability_target_cells.has(victim.grid_cell), "swapping to Long Sword immediately contracts active targeting")
	actor.equip_item(spear)
	check(battle._ability_target_cells.has(victim.grid_cell), "swapping back immediately restores targeting")
	var screen := battle.inventory_screen
	for item in [long_sword, spear]:
		actor.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, item)
		screen.open_for(actor)
		await process_frame
		var cell := screen.equipment_entries.get_child(0).get_node("Slot") as InventoryItemSlot
		screen.request_details(cell)
		screen._on_hover_timeout()
		await process_frame
		await process_frame
		screen.item_details.place_next_to(cell)
		check(screen.item_details.category.text.contains("Two-handed") and screen.item_details.body.text.contains("%d weapon damage" % item.weapon_damage), "weapon details show handedness and damage")
		check(screen.item_details.body.text.contains("+1 Strike range (normal attacks only)") == (item == spear), "only spear details show Strike reach bonus")
		check(root.get_visible_rect().encloses(screen.item_details.get_global_rect()), "weapon details stay in viewport")
		await _capture("spear_details" if item == spear else "long_sword_details")
		screen.close_screen()
		var payload := battle.capture_save_payload(false)
		var result := ScenarioSaveStore.save_new(payload, CAPTURE_DIR.path_join("scenarios"))
		check(result.ok, "scenario saves new weapon")
		if result.ok:
			var loaded := ScenarioSaveStore.load_save(result.path, CAPTURE_DIR.path_join("scenarios"))
			actor.equip_item(sword)
			check(loaded.ok and battle._restore_runtime_state(loaded.payload.runtime), "scenario reload restores new weapon")
			check(actor.get_equipped_weapon() == item and actor.get_slot_occupant(3) == item and is_equal_approx(strike.get_effective_range(actor), 2.414 if item == spear else 1.414), "restored equipment restores hand reservation and range")
		var member := RunPartyMember.from_character(actor)
		var restored := RunPartyMember.from_data(JSON.parse_string(JSON.stringify(member.to_data())))
		check(restored != null and restored.equipment.has(item.resource_path), "run party serialization preserves new weapon path")
		var rebuilt := (load(str(restored.setup.scene)) as PackedScene).instantiate() as TacticalCharacter
		rebuilt.apply_setup_state(restored.setup)
		root.add_child(rebuilt)
		check(rebuilt.get_equipped_weapon() == item and is_equal_approx(strike.get_effective_range(rebuilt), strike.get_effective_range(actor)), "saved run setup derives the same range")
		rebuilt.queue_free()
	battle.shutdown_battle()
	battle.queue_free()
	await process_frame


func _capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture") or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(CAPTURE_DIR.path_join(label + ".png")) == OK, "save rendered capture")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
