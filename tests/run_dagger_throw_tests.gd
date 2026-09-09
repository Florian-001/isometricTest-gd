extends SceneTree

var checks := 0
var failures: Array[String] = []
var arena: Node2D
var grid: IsometricGrid
var targeting: AbilityTargeting
var executor: AbilityExecutor
var units: Array[TacticalCharacter] = []
var ability: AbilityDefinition
var launches := 0


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _unit(friendly: bool, cell: Vector2i) -> TacticalCharacter:
	var unit := TacticalCharacter.new()
	unit.definition = CharacterDefinition.new()
	unit.definition.faction = CharacterDefinition.Faction.FRIENDLY if friendly else CharacterDefinition.Faction.ENEMY
	unit.definition.starting_class = load("res://resources/classes/archer.tres") if friendly else null
	unit.definition.constitution = 50
	unit.definition.dexterity = 10
	unit.starting_grid_cell = cell
	unit.use_complete_equipment_override = true
	arena.add_child(unit)
	unit.initialize(grid)
	unit.reset_ability_action()
	unit.reset_movement()
	units.append(unit)
	return unit


func _run() -> void:
	ability = load("res://resources/abilities/dagger_throw.tres")
	arena = Node2D.new()
	root.add_child(arena)
	grid = IsometricGrid.new()
	grid.grid_size = Vector2i(10, 10)
	arena.add_child(grid)
	targeting = AbilityTargeting.new(grid.grid_size)
	executor = AbilityExecutor.new()
	arena.add_child(executor)
	executor.projectile_delivery.projectile_launched.connect(func(_caster, _ability, _cell): launches += 1)
	var caster := _unit(true, Vector2i(1, 1))
	var target := _unit(false, Vector2i(6, 1))
	var ally := _unit(true, Vector2i(1, 2))
	var archer := load("res://resources/classes/archer.tres") as CharacterClassDefinition
	caster.set_class_level(archer, 3)
	check(not caster.get_abilities().has(ability), "level 3 has no Dagger Throw")
	check(not executor.can_execute(caster, ability, target.grid_cell, units, grid, targeting), "executor rejects locked ability")
	caster.set_class_level(archer, 4)
	check(caster.get_abilities().size() == 4 and caster.get_abilities()[3] == ability, "level 4 unlocks Dagger Throw after Multiple Arrows")
	check((load("res://resources/dev_tool_catalog.tres") as DevToolCatalog).abilities.has(ability), "developer catalog includes Dagger Throw")
	var ranger := load("res://resources/enemies/ranger.tres") as EnemyDefinition
	check(ranger.abilities.size() == 2 and not ranger.abilities.has(ability), "Ranger enemy loadout remains unchanged")
	check(ability.damage_type == DamageCalculator.Type.PHYSICAL and ability.hit_count == 1 and ability.innate_damage == 0, "one hit of physical damage with no innate term")
	check(ability.range == 5.0 and ability.delivery_type == AbilityDefinition.DeliveryType.PROJECTILE, "projectile has range 5")
	check(ability.get_targeting_configuration_error().is_empty(), "single-target configuration validates")

	var pack := load("res://resources/passives/pack_tactics.tres") as PassiveAbilityDefinition
	caster.set_dev_passive_loadout([pack])
	ally.set_dev_passive_loadout([pack])
	check(PassiveAbilityResolver.weapon_damage_bonus(caster) > 0, "fixture has an active nearby passive weapon bonus")
	var bow := ItemDefinition.new()
	bow.weapon_type = ItemDefinition.WeaponType.RANGED
	bow.weapon_damage = 99
	bow.status_effect = load("res://resources/statuses/burning.tres")
	var sword := ItemDefinition.new()
	sword.weapon_type = ItemDefinition.WeaponType.MELEE
	sword.weapon_damage = 80
	sword.status_effect = load("res://resources/statuses/slow.tres")
	for weapon in [null, bow, sword]:
		caster.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, weapon)
		caster.reset_ability_action()
		check(ability.can_be_used_by(caster), "usable with unarmed, bow, and melee equipment")
		check(ability.calculate_damage(caster) == 10, "weapon damage never contributes to Dagger Throw")
		check(ability.get_passive_damage_bonus(caster) == 0 and ability.get_weapon_status_effect(caster) == null, "weapon passive and on-hit status excluded")
		await _check_cast(caster, target, 10)
		check(target.get_active_statuses().is_empty(), "projectile applies no weapon status")

	caster.set_dev_equipment(ItemDefinition.EquipmentSlot.ARMOR, load("res://resources/items/armor/ranger_armor.tres"))
	check(ability.calculate_damage(caster) == 12, "equipment Dexterity modifier contributes")
	var buff := StatusEffectDefinition.new()
	buff.status_id = &"dagger_dex_test"
	buff.effect = StatusEffectDefinition.Effect.STAT_MODIFIER
	buff.affected_stat = UnitStat.Type.DEXTERITY
	buff.modifier_direction = StatusEffectDefinition.ModifierDirection.INCREASE
	buff.modifier_value_type = StatusEffectDefinition.ModifierValueType.FLAT
	buff.flat_amount = 2.5
	caster.apply_status(buff)
	check(is_equal_approx(caster.get_effective_stat(UnitStat.Type.DEXTERITY), 14.5) and ability.calculate_damage(caster) == 15, "effective Dexterity includes statuses and uses normal rounding")
	caster.reset_ability_action()
	await _check_cast(caster, target, 15)
	var bar := (load("res://scenes/ability_bar.tscn") as PackedScene).instantiate() as AbilityBar
	arena.add_child(bar)
	caster.reset_ability_action()
	bar.rebuild(caster, true)
	var button := bar.get_node("Margin/HBox").get_child(3) as Button
	check(button.text.contains("15 DMG") and not button.disabled, "bar displays current damage and permits unarmed-style ability")
	check(button.tooltip_text.contains("15 physical damage") and button.tooltip_text.contains("Dexterity x100%"), "tooltip describes Dexterity-only physical damage")
	bar.set_damage_preview(caster, ability, caster.grid_cell)
	check(button.text.contains("15 DMG") and button.tooltip_text.contains("15 damage"), "hover preview matches cast damage")
	bar.free()
	_test_targeting(caster, target, ally)
	caster.remove_status(buff.status_id)
	check(ability.calculate_damage(caster) == 12, "removing Dexterity status updates damage")

	arena.free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("DAGGER_THROW_TESTS_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check_cast(caster: TacticalCharacter, target: TacticalCharacter, expected: int) -> void:
	var before := target.current_health
	var movement := caster.remaining_movement
	var snapshot := AIBoardSnapshot.from_battle(units, grid.grid_size)
	var planner := EnemyAIPlanner.new()
	planner._prepare_decision(caster, snapshot, units)
	planner._forecast_ability(caster, ability, target.grid_cell, snapshot, targeting, EnemyAIProfile.new())
	var prior_launches := launches
	check(await executor.execute(caster, ability, target.grid_cell, units, grid, targeting), "projectile executes")
	check(before - target.current_health == expected and target.current_health == snapshot.get_health(target), "actual damage matches Dexterity and AI forecast")
	check(launches == prior_launches + 1, "exactly one projectile is launched")
	check(not caster.ability_available and caster.remaining_movement == movement, "one ability action consumed with no movement cost")
	check(not await executor.execute(caster, ability, target.grid_cell, units, grid, targeting), "spent action prevents a second cast")


func _test_targeting(caster: TacticalCharacter, target: TacticalCharacter, ally: TacticalCharacter) -> void:
	caster.reset_ability_action()
	check(targeting.is_valid_primary_target(caster, target.grid_cell, ability, units), "enemy at exactly range 5 is valid")
	check(not targeting.is_valid_primary_target(caster, ally.grid_cell, ability, units), "allies cannot be targeted")
	check(not targeting.is_valid_primary_target(caster, caster.grid_cell, ability, units), "caster cannot be targeted")
	check(not targeting.is_valid_primary_target(caster, Vector2i(2, 1), ability, units), "empty cells cannot be targeted")
	check(targeting.get_affected_units(caster, target.grid_cell, ability, units) == [target], "only one enemy is affected")
	target.set_grid_cell_immediate(Vector2i(7, 1))
	check(not executor.can_execute(caster, ability, target.grid_cell, units, grid, targeting), "range 6 is rejected")
	target.set_grid_cell_immediate(Vector2i(5, 3))
	check(targeting.is_valid_primary_target(caster, target.grid_cell, ability, units), "weighted diagonal distance below 5 is valid")
	target.set_grid_cell_immediate(Vector2i(5, 4))
	check(not targeting.is_valid_primary_target(caster, target.grid_cell, ability, units), "weighted diagonal distance above 5 is rejected")
	target.set_grid_cell_immediate(Vector2i(6, 1))
	var walls := {Vector2i(3, 1): true}
	check(not executor.can_execute(caster, ability, target.grid_cell, units, grid, targeting, walls), "wall blocks projectile targeting")
	check(executor.projectile_delivery.get_preview(caster.grid_cell, target.grid_cell, walls)[1] == Vector2i(3, 1), "blocked trajectory preview stops at wall")
	check(caster.ability_available, "rejected targeting preserves action")
