extends SceneTree

const WAND := "res://resources/items/weapons/wand.tres"
const DIRECTORY := "res://.godot/wand_validation"
const DraftStore = preload("res://addons/unit_balance/draft_store.gd")
var checks := 0
var failures: Array[String] = []
var wand: ItemDefinition = load(WAND)
var shot: AbilityDefinition = load("res://resources/abilities/wand_shot.tres")
var shoot: AbilityDefinition = load("res://resources/abilities/arrow.tres")
var strike: AbilityDefinition = load("res://resources/abilities/strike.tres")
var grid: IsometricGrid
var arena: Node2D
var units: Array[TacticalCharacter] = []


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _unit(friendly: bool, cell: Vector2i) -> TacticalCharacter:
	var actor := TacticalCharacter.new()
	actor.definition = CharacterDefinition.new()
	actor.definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	if friendly:
		actor.definition.starting_class = CharacterClassDefinition.new()
		actor.definition.starting_class.class_id = &"wand_test"
	actor.constitution_override = 100
	actor.intelligence_override = 10
	actor.dexterity_override = 10
	actor.use_complete_equipment_override = true
	actor.starting_grid_cell = cell
	arena.add_child(actor)
	actor.initialize(grid)
	actor.reset_ability_action()
	units.append(actor)
	return actor


func _run() -> void:
	create_timer(45.0).timeout.connect(func(): push_error("Wand tests timed out"); quit(1))
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	_test_resources()
	arena = Node2D.new()
	root.add_child(arena)
	grid = IsometricGrid.new()
	grid.grid_size = Vector2i(10, 10)
	arena.add_child(grid)
	await _test_combat()
	_test_saves_and_balance()
	arena.free()
	await _test_battle_ui()
	_test_pool()
	for failure in failures:
		push_error(failure)
	print("WAND_TESTS_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_resources() -> void:
	check(wand.weapon_type == ItemDefinition.WeaponType.RANGED and wand.weapon_damage == 5, "Wand is a five-damage ranged weapon")
	check(wand.get_occupied_slots() == [ItemDefinition.EquipmentSlot.WEAPON] and not wand.is_two_handed(), "Wand occupies only its weapon hand")
	check(wand.modifiers.is_empty() and wand.status_effect == null and wand.weapon_range_bonus == 0, "Wand adds no bonuses or on-hit status")
	check(wand.icon != null and wand.icon.get_size() == Vector2(64, 64), "Wand inventory icon loads at 64x64")
	check(wand.get_granted_abilities() == [shot], "Wand grants only Wand Shot")
	check(shot.ability_type == AbilityDefinition.AbilityType.RANGED and shot.requires_weapon, "Wand Shot requires a ranged weapon and uses its damage")
	check(shot.damage_type == DamageCalculator.Type.MAGICAL and shot.innate_damage == 0, "Wand Shot classifies damage as magical with no innate damage")
	check(shot.scaling_stat == DamageCalculator.ScalingSource.INTELLIGENCE and shot.scaling_amount == 100, "Wand Shot uses 100 percent Intelligence")
	check(shot.range == 5 and not shot.accepts_weapon_range_bonus and shot.hit_count == 1, "Wand Shot has fixed range five and a single hit")
	check(shot.ap_cost == shoot.ap_cost and shot.cooldown_turns == shoot.cooldown_turns and shot.target_flags == shoot.target_flags and shot.delivery_type == shoot.delivery_type and shot.projectile_speed == shoot.projectile_speed, "Wand Shot shares Shoot costs, targeting and delivery")
	check(shot.get_targeting_configuration_error().is_empty(), "Wand Shot configuration validates")
	for path in ["iron_sword", "staff", "short_bow", "frost_bow", "spear"]:
		var existing := load("res://resources/items/weapons/%s.tres" % path) as ItemDefinition
		check(existing.basic_attack_override == null and existing.get_granted_abilities() == [shoot if existing.weapon_type == ItemDefinition.WeaponType.RANGED else strike], "%s retains its original attack" % path)
	var inline := wand.duplicate() as ItemDefinition
	inline.basic_attack_override = null
	check(inline.get_granted_abilities() == [shoot], "Empty override restores generic ranged attack")
	inline.basic_attack_override = shot
	inline.slot = ItemDefinition.EquipmentSlot.ARMOR
	check(inline.get_granted_abilities().is_empty(), "Non-weapons never grant basic attacks")
	var catalog := load("res://resources/dev_tool_catalog.tres") as DevToolCatalog
	check(catalog.items.count(wand) == 1 and catalog.abilities.count(shot) == 1, "Developer catalog registers item and attack once")


func _test_combat() -> void:
	var caster := _unit(true, Vector2i(1, 1))
	var target := _unit(false, Vector2i(6, 1))
	var other := _unit(true, Vector2i(1, 2))
	check(not shot.can_be_used_by(caster), "Unarmed unit cannot use Wand Shot")
	caster.equip_item(wand)
	check(caster.get_abilities() == [shot] and caster.get_basic_attack_ability() == shot, "Wand Shot is the first and only synthetic-class basic attack")
	check(other.get_abilities() == [strike], "Equipping one unit leaves another isolated")
	check(shot.calculate_damage(caster) == 15 and shot.get_damage_summary(caster) == "15 DMG", "Intelligence ten produces fifteen damage and preview")
	caster.dexterity_override = 100
	check(shot.calculate_damage(caster) == 15, "Dexterity has no effect")
	var charm := ItemDefinition.new()
	charm.slot = ItemDefinition.EquipmentSlot.ACCESSORY
	var modifier := StatModifierDefinition.new()
	modifier.stat = UnitStat.Type.INTELLIGENCE
	modifier.value = 2.5
	charm.modifiers = [modifier]
	caster.equip_item(charm)
	check(shot.calculate_damage(caster) == 18, "Equipment Intelligence modifiers use rounded final damage")
	var buff := StatusEffectDefinition.new()
	buff.status_id = &"wand_intelligence"
	buff.modifiers = [modifier]
	caster.apply_status(buff)
	check(shot.calculate_damage(caster) == 20 and shot.get_damage_summary(caster) == "20 DMG", "Status and equipment Intelligence stack in damage previews")
	var shield := ItemDefinition.new()
	shield.slot = ItemDefinition.EquipmentSlot.OFFHAND
	caster.equip_item(shield)
	check(caster.get_slot_occupant(ItemDefinition.EquipmentSlot.OFFHAND) == shield and caster.get_equipped_weapon() == wand, "Wand allows an offhand item")
	var extended := wand.duplicate() as ItemDefinition
	extended.weapon_range_bonus = 10
	caster.equip_item(extended)
	check(shot.get_effective_range(caster) == 5, "Weapon bonuses cannot extend Wand Shot")
	var targeting := AbilityTargeting.new(grid.grid_size)
	var executor := AbilityExecutor.new()
	arena.add_child(executor)
	check(executor.can_execute(caster, shot, target.grid_cell, units, grid, targeting), "Wand targeting accepts distance five")
	target.set_grid_cell_immediate(Vector2i(7, 1))
	check(not executor.can_execute(caster, shot, target.grid_cell, units, grid, targeting), "Wand targeting rejects distance six")
	target.set_grid_cell_immediate(Vector2i(6, 1))
	check(not executor.can_execute(caster, shot, target.grid_cell, units, grid, targeting, {Vector2i(3, 1): true}), "Wand projectile respects walls")
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
	var planner := EnemyAIPlanner.new()
	planner._prepare_decision(caster, snapshot, units)
	planner._forecast_ability(caster, shot, target.grid_cell, snapshot, targeting, EnemyAIProfile.new())
	var before := target.current_health
	var launches := [0]
	executor.projectile_delivery.projectile_launched.connect(func(_caster, _ability, _cell): launches[0] += 1)
	check(await executor.execute(caster, shot, target.grid_cell, units, grid, targeting), "Wand Shot executes")
	check(before - target.current_health == 20 and snapshot.get_health(target) == target.current_health and launches[0] == 1, "Runtime damage, AI forecast and single projectile agree")
	caster.spend_action_points(caster.action_points)
	caster.spend_opportunity_reaction()
	var bow := load("res://resources/items/weapons/short_bow.tres") as ItemDefinition
	caster.equip_item(bow)
	check(caster.get_abilities() == [shoot] and caster.get_slot_occupant(ItemDefinition.EquipmentSlot.OFFHAND) == bow, "Bow swap restores Shoot and two-handed occupancy")
	caster.equip_item(wand)
	check(caster.get_abilities() == [shot] and not caster.ability_available and not caster.opportunity_reaction_available, "Wand swap grants no action or reaction")
	caster.unequip_item(ItemDefinition.EquipmentSlot.WEAPON)
	check(caster.get_abilities() == [strike] and not caster.ability_available, "Unequipping restores unarmed Strike without actions")
	target.equip_item(wand)
	check(target.get_abilities().is_empty(), "Enemies retain explicit ability loadouts")


func _test_saves_and_balance() -> void:
	var scene := load("res://scenes/friendlies/wizard.tscn") as PackedScene
	var actor := scene.instantiate() as TacticalCharacter
	arena.add_child(actor)
	actor.initialize(grid)
	actor.intelligence_override = 10
	actor.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, wand)
	actor.spend_action_points(actor.action_points)
	var setup: Dictionary = JSON.parse_string(JSON.stringify(actor.capture_setup_state()))
	var runtime: Dictionary = JSON.parse_string(JSON.stringify(actor.capture_runtime_state()))
	var restored := scene.instantiate() as TacticalCharacter
	restored.apply_setup_state(setup)
	check(restored.get_abilities()[0] == shot, "Setup restoration resolves Wand Shot before ready")
	arena.add_child(restored)
	restored.initialize(grid)
	restored.restore_runtime_state(runtime, {})
	check(restored.get_equipped_weapon() == wand and restored.get_abilities()[0] == shot and shot.calculate_damage(restored) == 15 and not restored.ability_available, "Runtime save restores Wand, Intelligence, damage and spent actions")
	var member := RunPartyMember.from_data(JSON.parse_string(JSON.stringify(RunPartyMember.from_character(actor).to_data())))
	check(member != null and member.equipment == [WAND], "Run party save retains canonical Wand reference")
	var inventory := GeneralInventory.new()
	arena.add_child(inventory)
	inventory.restore_state([WAND])
	check(inventory.capture_state() == [WAND], "Inventory save restores Wand")
	var path := DIRECTORY + "/balance_wand.tres"
	check(ResourceSaver.save(wand.duplicate(), path) == OK, "Temporary Wand resource saves")
	var store := DraftStore.new()
	store.recovery_path = ""
	store.add_resource(path)
	store.set_field(path, "weapon_damage", 7)
	check((store.draft(path) as ItemDefinition).basic_attack_override == shot, "Unit Balance draft preserves attack override")
	var result := store.save_all()
	check(result.saved.has(path) and result.failed.is_empty(), "Unit Balance saves edited Wand")
	var edited := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ItemDefinition
	check(edited.weapon_damage == 7 and edited.get_granted_abilities() == [shot], "Unit Balance save/reload preserves Wand Shot")
	check(wand.weapon_damage == 5, "Temporary balance edits leave shipped Wand unchanged")
	store.history.clear_history()


func _test_battle_ui() -> void:
	var battle := load("res://scenes/battle.tscn").instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	root.add_child(battle)
	check(battle.initialization_succeeded, "Battle initializes")
	battle.set_process(false)
	var actor := battle._characters[0]
	battle.turn_manager.current_unit = actor
	battle.turn_manager.current_index = battle.turn_manager.turn_order.find(actor)
	actor.intelligence_override = 10
	actor.reset_ability_action()
	battle._on_turn_started(actor)
	actor.equip_item(wand)
	var button := battle.ability_bar.get_node("Margin/HBox").get_child(0) as Button
	check(button.get_meta("ability") == shot and button.text.contains("15 DMG") and button.tooltip_text.contains("Equipped: Wand"), "Battle first shortcut shows Wand Shot damage and source")
	battle.inventory_screen.open_for(actor)
	await process_frame
	check(battle.inventory_screen.ability_entries.get_child(0).get_meta("ability") == shot, "Inventory ability preview shows Wand Shot first")
	actor.equip_item(load("res://resources/items/accessory/sage_charm.tres"))
	var equipment_damage := shot.calculate_damage(actor)
	check(equipment_damage > 15 and battle.ability_bar.get_node("Margin/HBox").get_child(0).text.contains("%d DMG" % equipment_damage), "Intelligence equipment updates live battle preview")
	var buff := StatusEffectDefinition.new()
	buff.status_id = &"wand_preview_intelligence"
	buff.effect = StatusEffectDefinition.Effect.STAT_MODIFIER
	buff.affected_stat = UnitStat.Type.INTELLIGENCE
	buff.modifier_direction = StatusEffectDefinition.ModifierDirection.INCREASE
	buff.modifier_value_type = StatusEffectDefinition.ModifierValueType.FLAT
	buff.flat_amount = 3
	actor.apply_status(buff)
	check(shot.calculate_damage(actor) == equipment_damage + 3 and battle.ability_bar.get_node("Margin/HBox").get_child(0).text.contains("%d DMG" % (equipment_damage + 3)), "Intelligence status updates live battle preview")
	check(battle.inventory_screen.ability_entries.get_child(0).tooltip_text.contains("%d" % (equipment_damage + 3)), "Inventory preview refreshes modified damage")
	for equipped in [false, true]:
		battle.inventory_screen.item_details.show_item(wand, equipped)
		var text := battle.inventory_screen.item_details.body.text
		check(text.contains("5 weapon damage") and text.contains("Wand Shot") and text.contains("Intelligence") and text.contains("Magical") and text.contains("5.00"), "Wand item description shows damage, attack, Intelligence, magic and range")
	battle.inventory_screen.close_screen()
	battle._on_ability_selected(shot)
	actor.equip_item(load("res://resources/items/weapons/short_bow.tres"))
	check(battle._selected_ability == null and battle.ability_bar.get_node("Margin/HBox").get_child(0).get_meta("ability") == shoot, "Swapping to bow clears removed Wand targeting and shows Shoot")
	actor.equip_item(wand)
	var payload := battle.capture_save_payload(true)
	check(ScenarioSaveStore.validate_payload(payload).ok, "Wand battle snapshot validates with existing save format")
	paused = false
	battle.shutdown_battle()
	battle.free()
	await process_frame


func _test_pool() -> void:
	var controller := RunController.new()
	controller.config = load("res://resources/run/default_run.tres")
	controller.save_path = DIRECTORY + "/pool_run.json"
	root.add_child(controller)
	check(controller.config.equipment_pool.count(wand) == 1, "Default run equipment pool includes Wand once")
	check(controller.new_run_with_party(["wizard", "cleric"], 37), "Default run starts")
	var node := controller.state.graph.get_node_by_id(controller.state.available_rooms()[0])
	var found_drop := false
	var found_shop := false
	for seed_value in range(100):
		controller.state.graph.seed_value = seed_value
		node.type = RunMapGraph.NodeType.CHEST
		found_drop = found_drop or controller._prepare_room(node).reward_item == WAND
		node.type = RunMapGraph.NodeType.SHOP
		found_shop = found_shop or controller._prepare_room(node).offers.has(WAND)
	check(found_drop and found_shop, "Real default-run reward and shop generation can select Wand")
	for member in controller.state.party:
		check(not member.equipment.has(WAND), "Starting party equipment does not change")
	controller.free()
