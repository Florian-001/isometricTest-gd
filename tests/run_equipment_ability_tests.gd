extends SceneTree

var checks := 0
var failures: Array[String] = []
var arena: Node2D
var grid: IsometricGrid
var targeting: AbilityTargeting
var executor: AbilityExecutor
var units: Array[TacticalCharacter] = []
var strike: AbilityDefinition = load("res://resources/abilities/strike.tres")
var shoot: AbilityDefinition = load("res://resources/abilities/arrow.tres")
var sword: ItemDefinition = load("res://resources/items/weapons/iron_sword.tres")
var bow: ItemDefinition = load("res://resources/items/weapons/frost_bow.tres")
var impacts := 0
var launches := 0
const CAPTURE_DIR := "res://.godot/equipment_ability_validation"


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _run() -> void:
	create_timer(45.0).timeout.connect(func(): push_error("Equipment ability tests timed out"); quit(1))
	arena = Node2D.new()
	root.add_child(arena)
	grid = IsometricGrid.new()
	grid.grid_size = Vector2i(10, 10)
	arena.add_child(grid)
	targeting = AbilityTargeting.new(grid.grid_size)
	executor = AbilityExecutor.new()
	arena.add_child(executor)
	executor.melee_delivery.melee_impact.connect(func(_caster, _ability, _cell): impacts += 1)
	executor.projectile_delivery.projectile_launched.connect(func(_caster, _ability, _cell): launches += 1)
	_test_loadouts()
	await _test_damage_and_reactions()
	_test_saves()
	arena.free()
	await process_frame
	await _test_battle_ui()
	for failure in failures:
		push_error(failure)
	print("EQUIPMENT_ABILITY_TESTS_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _unit(friendly: bool, cell: Vector2i) -> TacticalCharacter:
	var unit := TacticalCharacter.new()
	unit.definition = CharacterDefinition.new()
	unit.definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	unit.definition.starting_class = load("res://resources/classes/warrior.tres") if friendly else null
	unit.definition.constitution = 100
	unit.definition.strength = 10
	unit.definition.dexterity = 10
	unit.use_complete_equipment_override = true
	unit.starting_grid_cell = cell
	arena.add_child(unit)
	unit.initialize(grid)
	unit.reset_ability_action()
	unit.reset_movement()
	unit.reset_opportunity_reaction()
	units.append(unit)
	return unit


func _test_loadouts() -> void:
	check(shoot.display_name == "Shoot" and shoot.resource_path == "res://resources/abilities/arrow.tres", "Shoot retains the legacy resource path")
	check(strike.allow_unarmed_for_friendlies and strike.requires_weapon and not AbilityDefinition.new().allow_unarmed_for_friendlies, "only Strike opts into unarmed friendly use")
	check(strike.get_targeting_configuration_error().is_empty() and strike.hit_count == 1, "normalized Strike configuration validates")
	check(sword.get_granted_abilities() == [strike] and bow.get_granted_abilities() == [shoot], "weapon types grant canonical basic attacks")
	for item in [load("res://resources/items/armor/ranger_armor.tres"), load("res://resources/items/accessory/sage_charm.tres")]:
		check(item.get_granted_abilities().is_empty(), "non-weapons grant no attack")
	var inline := ItemDefinition.new()
	check(inline.get_granted_abilities() == [strike], "new inline melee weapons grant Strike automatically")
	inline.weapon_type = ItemDefinition.WeaponType.RANGED
	check(inline.get_granted_abilities() == [shoot], "changing inline weapon type changes its grant")
	for id in ["warrior", "archer", "wizard", "cleric"]:
		var definition := load("res://resources/classes/%s.tres" % id) as CharacterClassDefinition
		var unit := TacticalCharacter.new()
		unit.definition = CharacterDefinition.new()
		unit.definition.starting_class = definition
		unit.use_complete_equipment_override = true
		for unlock in definition.ability_unlocks:
			check(unlock.ability != strike and unlock.ability != shoot, "basic attacks are absent from %s class unlocks" % id)
		for level in [1, 2, 3, 4, 5, 150]:
			unit.set_class_level(definition, level)
			for weapon in [null, sword, bow]:
				unit.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, weapon)
				var basic := shoot if weapon == bow else strike
				var abilities := unit.get_abilities()
				check(abilities[0] == basic and abilities.count(basic) == 1 and not abilities.has(strike if basic == shoot else shoot), "%s %d has exactly its equipment basic attack before ready" % [id, level])
				var expected_count := 1
				for unlock in definition.ability_unlocks:
					if level >= unlock.required_level:
						expected_count += 1
						check(abilities.has(unlock.ability), "equipment retains unlocked class skills")
				check(abilities.size() == expected_count, "no additional class or equipment skills leak")
		unit.set_dev_ability_loadout([])
		check(unit.get_abilities().is_empty(), "explicit empty developer override remains empty")
		unit.set_dev_ability_loadout([strike, shoot])
		unit.unequip_item(ItemDefinition.EquipmentSlot.WEAPON)
		check(unit.get_abilities() == [strike, shoot], "equipment changes preserve explicit developer loadouts")
		unit.reset_dev_ability_loadout()
		check(unit.get_abilities()[0] == strike, "reset restores normal unarmed loadout")
		unit.free()
	var catalog := load("res://resources/dev_tool_catalog.tres") as DevToolCatalog
	check(catalog.abilities.count(strike) == 1 and catalog.abilities.count(shoot) == 1, "catalog retains one canonical entry per basic attack")
	var enemy := _unit(false, Vector2i(9, 9))
	check(enemy.get_abilities().is_empty(), "unarmed enemies receive no automatic attack")
	enemy.equip_item(bow)
	check(enemy.get_abilities().is_empty(), "enemy equipment does not grant abilities")
	enemy.set_dev_ability_loadout([strike])
	enemy.unequip_item(ItemDefinition.EquipmentSlot.WEAPON)
	check(not strike.can_be_used_by(enemy), "enemy Strike still requires a melee weapon")
	enemy.equip_item(sword)
	check(strike.can_be_used_by(enemy), "armed enemy Strike keeps working")
	enemy.free()
	units.clear()


func _test_damage_and_reactions() -> void:
	var caster := _unit(true, Vector2i(1, 1))
	var target := _unit(false, Vector2i(2, 1))
	var ally := _unit(true, Vector2i(1, 2))
	var pack := load("res://resources/passives/pack_tactics.tres") as PassiveAbilityDefinition
	caster.set_dev_passive_loadout([pack])
	ally.set_dev_passive_loadout([pack])
	check(PassiveAbilityResolver.weapon_damage_bonus(caster) > 0, "fixture activates passive weapon damage")
	var buff := StatusEffectDefinition.new()
	buff.status_id = &"equipment_strength_test"
	buff.effect = StatusEffectDefinition.Effect.STAT_MODIFIER
	buff.affected_stat = UnitStat.Type.STRENGTH
	buff.modifier_value_type = StatusEffectDefinition.ModifierValueType.FLAT
	buff.modifier_direction = StatusEffectDefinition.ModifierDirection.INCREASE
	buff.flat_amount = 2.5
	caster.apply_status(buff)
	check(strike.calculate_damage(caster) == 13 and strike.get_passive_damage_bonus(caster) == 0 and strike.get_weapon_status_effect(caster) == null, "unarmed damage is rounded effective Strength without weapon effects")
	check(not strike.get_description(caster).contains("weapon damage") and strike.get_description(caster).contains("Strength x100%"), "unarmed tooltip describes Strength-only damage")
	check(targeting.is_valid_primary_target(caster, target.grid_cell, strike, units), "unarmed Strike retains adjacent reach")
	target.set_grid_cell_immediate(Vector2i(2, 2))
	check(targeting.is_valid_primary_target(caster, target.grid_cell, strike, units), "unarmed Strike retains diagonal reach")
	target.set_grid_cell_immediate(Vector2i(3, 1))
	check(not executor.can_execute(caster, strike, target.grid_cell, units, grid, targeting), "unarmed Strike cannot reach two tiles")
	target.set_grid_cell_immediate(Vector2i(2, 1))
	check(not executor.can_execute(caster, strike, target.grid_cell, units, grid, targeting, {target.grid_cell: true}), "wall blocks unarmed melee")
	check(targeting.get_affected_units(caster, ally.grid_cell, strike, units).is_empty() and targeting.get_affected_units(caster, caster.grid_cell, strike, units).is_empty(), "Strike's existing cell targeting never affects friendly units or caster")
	await _cast_and_compare(caster, target, strike, 13)
	check(impacts == 1 and launches == 0, "unarmed Strike has exactly one melee impact")
	check(OpportunityAttackSystem.get_opportunity_attack_ability(caster) == strike, "spent ability action retains unarmed opportunity attack")
	check(OpportunityAttackSystem.can_trigger(caster, target, target.grid_cell, Vector2i(3, 1)), "leaving unarmed reach triggers a reaction")
	ally.spend_opportunity_reaction()
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
	var planner := EnemyAIPlanner.new()
	planner._forecast_opportunity_attacks(target, target.grid_cell, Vector2i(3, 1), snapshot, targeting, EnemyAIProfile.new())
	check(await executor.execute_opportunity_attack(caster, strike, target.grid_cell, units, grid, targeting), "unarmed opportunity attack executes after spent action")
	check(snapshot.get_health(target) == target.current_health and not caster.opportunity_reaction_available, "unarmed reaction forecast matches actual damage and spending")
	caster.equip_item(sword)
	check(not caster.ability_available and not caster.opportunity_reaction_available, "equipping never restores action or reaction")
	var weapon_bonus := strike.get_passive_damage_bonus(caster)
	check(weapon_bonus > 0, "armed Strike includes applicable passive bonuses")
	await _cast_and_compare(caster, target, strike, roundi(caster.get_effective_stat(UnitStat.Type.STRENGTH) + sword.weapon_damage) + weapon_bonus)
	caster.equip_item(bow)
	check(not caster.get_abilities().has(strike) and not strike.can_be_used_by(caster), "ranged weapon replaces Strike and prevents unarmed fallback")
	check(OpportunityAttackSystem.get_opportunity_attack_ability(caster) == null, "Shoot grants no melee reaction")
	target.set_grid_cell_immediate(Vector2i(6, 1))
	caster.equip_item(load("res://resources/items/armor/ranger_armor.tres"))
	check(caster.get_abilities() == [shoot], "armor preserves the weapon attack")
	var expected := roundi(bow.weapon_damage + caster.get_effective_stat(UnitStat.Type.DEXTERITY) * 0.6) + shoot.get_passive_damage_bonus(caster)
	await _cast_and_compare(caster, target, shoot, expected)
	check(launches == 1 and target.get_active_statuses().size() == 1 and target.get_active_statuses()[0].definition == bow.status_effect, "Shoot launches once and applies its weapon status")
	caster.reset_ability_action()
	check(not executor.can_execute(caster, shoot, target.grid_cell, units, grid, targeting, {Vector2i(3, 1): true}), "Shoot respects projectile-blocking walls")
	target.set_grid_cell_immediate(Vector2i(7, 1))
	check(not executor.can_execute(caster, shoot, target.grid_cell, units, grid, targeting), "Shoot retains range five")
	caster.spend_ability_action()
	caster.unequip_item(ItemDefinition.EquipmentSlot.WEAPON)
	check(caster.get_abilities() == [strike] and not caster.ability_available and not caster.opportunity_reaction_available, "unequipping restores only the default attack")
	check(strike.get_weapon_status_effect(caster) == null and strike.get_passive_damage_bonus(caster) == 0, "unequipping removes weapon status and passive contribution")
	for unit in units:
		unit.free()
	units.clear()


func _cast_and_compare(caster: TacticalCharacter, target: TacticalCharacter, ability: AbilityDefinition, expected: int) -> void:
	caster.reset_ability_action()
	var before := target.current_health
	var movement := caster.remaining_movement
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
	var planner := EnemyAIPlanner.new()
	check(planner._can_use_ability_in_snapshot(caster, ability, snapshot), "AI shares runtime equipment eligibility")
	planner._prepare_decision(caster, snapshot, units)
	planner._forecast_ability(caster, ability, target.grid_cell, snapshot, targeting, EnemyAIProfile.new())
	check(ability.calculate_damage(caster) == expected and ability.get_damage_summary(caster) == "%d DMG" % expected, "damage summary matches expected formula")
	check(await executor.execute(caster, ability, target.grid_cell, units, grid, targeting), "normal equipment ability executes")
	check(before - target.current_health == expected and target.current_health == snapshot.get_health(target), "runtime impact and AI forecast agree with preview")
	check(not caster.ability_available and caster.remaining_movement == movement, "cast spends one action without movement cost")
	check(not await executor.execute(caster, ability, target.grid_cell, units, grid, targeting), "spent action prevents another cast")


func _test_saves() -> void:
	var scene := load("res://scenes/friendlies/friend_a.tscn") as PackedScene
	var unit := scene.instantiate() as TacticalCharacter
	unit.scenario_unit_id = "equipment_save"
	arena.add_child(unit)
	unit.initialize(grid)
	for weapon in [null, sword, bow]:
		unit.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, weapon)
		unit.spend_ability_action()
		var setup: Dictionary = JSON.parse_string(JSON.stringify(unit.capture_setup_state()))
		var state: Dictionary = JSON.parse_string(JSON.stringify(unit.capture_runtime_state()))
		var restored := scene.instantiate() as TacticalCharacter
		restored.apply_setup_state(setup)
		check(restored.get_abilities() == unit.get_abilities(), "setup recomputes equipment attacks before ready")
		arena.add_child(restored)
		restored.initialize(grid)
		restored.restore_runtime_state(state, {})
		check(restored.get_abilities() == unit.get_abilities() and not restored.ability_available, "runtime restore recomputes attacks and retains spent action")
		var member := RunPartyMember.from_data(JSON.parse_string(JSON.stringify(RunPartyMember.from_character(unit).to_data())))
		check(member != null and member.equipment == state.equipped_items, "run save preserves the equipment that determines basic attacks")
		restored.free()
	unit.set_dev_ability_loadout([shoot])
	var legacy := scene.instantiate() as TacticalCharacter
	legacy.apply_setup_state(JSON.parse_string(JSON.stringify(unit.capture_setup_state())))
	check(legacy.get_abilities() == [shoot] and legacy.get_abilities()[0].display_name == "Shoot", "legacy Arrow override path loads as Shoot")
	legacy.free()
	unit.free()


func _test_battle_ui() -> void:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	root.add_child(battle)
	check(battle.initialization_succeeded, "battle initializes with equipment attacks")
	battle.set_process(false)
	var actor := battle._characters[0]
	battle.turn_manager.current_unit = actor
	battle.turn_manager.current_index = battle.turn_manager.turn_order.find(actor)
	actor.reset_ability_action()
	battle._on_turn_started(actor)
	actor.equip_item(sword)
	battle._on_ability_selected(strike)
	check(battle._selected_ability == strike, "equipped Strike can enter targeting")
	actor.unequip_item(ItemDefinition.EquipmentSlot.WEAPON)
	var button := battle.ability_bar.get_node("Margin/HBox").get_child(0) as Button
	check(battle._selected_ability == strike and not battle._ability_target_cells.is_empty(), "melee-to-unarmed swap retains valid Strike targeting")
	check(button.text.contains(strike.get_damage_summary(actor)) and button.tooltip_text.contains("Unarmed") and not button.disabled, "unarmed bar shows current damage and source")
	await _capture("unarmed_strike")
	actor.equip_item(bow)
	button = battle.ability_bar.get_node("Margin/HBox").get_child(0) as Button
	check(battle._selected_ability == null and button.get_meta("ability") == shoot, "ranged swap cancels Strike and refreshes the first shortcut")
	check(button.text.contains("Shoot") and button.tooltip_text.contains("Equipped: Frost Bow"), "Shoot bar labels the equipment source")
	battle._on_ability_selected(shoot)
	check(battle._selected_ability == shoot, "Shoot enters battle targeting")
	await _capture("equipped_shoot")
	actor.unequip_item(ItemDefinition.EquipmentSlot.WEAPON)
	check(battle._selected_ability == null, "unequipping cancels removed Shoot targeting")
	actor.spend_ability_action()
	actor.spend_opportunity_reaction()
	actor.equip_item(bow)
	check(not actor.ability_available and not actor.opportunity_reaction_available and battle.ability_bar.get_node("Margin/HBox").get_child(0).disabled, "battle equipment changes preserve spent actions and disabled bar")
	battle.inventory_screen.open_for(actor)
	await process_frame
	var screen := battle.inventory_screen
	check(screen.ability_entries.get_child(0).get_meta("ability") == shoot and screen.ability_entries.get_child(0).tooltip_text.contains("Equipped: Frost Bow"), "inventory shows the equipment attack and source")
	var details := screen.item_details
	for equipped in [false, true]:
		details.show_item(sword, equipped)
		check(details.body.text.contains("Grants while equipped: Strike"), "bag and equipped sword descriptions show Strike")
		details.show_item(bow, equipped)
		check(details.body.text.contains("Grants while equipped: Shoot"), "bag and equipped bow descriptions show Shoot")
	details.show_item(load("res://resources/items/armor/ranger_armor.tres"), false)
	check(not details.body.text.contains("Grants while equipped"), "non-weapon descriptions show no ability grant")
	screen.request_details(screen.equipment_entries.get_child(0).get_node("Slot"))
	screen._on_hover_timeout()
	await process_frame
	await process_frame
	details.place_next_to(screen._detail_cell)
	check(root.get_visible_rect().encloses(details.get_global_rect()), "weapon grant detail card stays inside the canvas viewport")
	await _capture("inventory_weapon_grant")
	screen.close_screen()
	battle._on_dev_button_pressed()
	battle.dev_mode_panel.select_unit(actor)
	var entry := battle.dev_mode_panel.ability_entries.get_child(0)
	check(entry.get_meta("ability") == shoot and entry.get_child(0).text == "Shoot · Equipped: Frost Bow", "developer preview labels equipment instead of class level")
	check(battle.dev_mode_panel.abilities_reset.text == "Use Default Abilities", "developer reset names the equipment and class defaults")
	await process_frame
	(battle.dev_mode_panel.tabs.get_child(DevModePanel.UNIT_TAB) as ScrollContainer).ensure_control_visible(entry)
	await _capture("developer_equipment_attack")
	var payload := battle.capture_save_payload(true)
	check(ScenarioSaveStore.validate_payload(payload).ok, "battle snapshot validates without new ability save fields")
	paused = false
	battle.shutdown_battle()
	battle.free()
	await process_frame
	var config := load("res://resources/run/default_run.tres") as RunConfig
	for roster_entry in config.inspect_starting_roster().entries:
		check(str(roster_entry.abilities).contains("Equipped:") or str(roster_entry.abilities).contains("Unarmed"), "party preview includes each basic attack's equipment or unarmed source")
	var hub := (load("res://scenes/starting_hub.tscn") as PackedScene).instantiate() as StartingHub
	root.add_child(hub)
	hub.open_hub(config)
	await _capture("party_equipment_attacks")
	hub.free()


func _capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture") or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
	var was_paused := paused
	paused = false
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(CAPTURE_DIR.path_join(name + ".png")) == OK, "visual capture saves")
	paused = was_paused
