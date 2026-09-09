extends SceneTree

const WEAPON = ItemDefinition.EquipmentSlot.WEAPON
const OFFHAND = ItemDefinition.EquipmentSlot.OFFHAND
var sword: ItemDefinition = load("res://resources/items/weapons/iron_sword.tres")
var shield: ItemDefinition = load("res://resources/items/offhand/wooden_shield.tres")
var bow: ItemDefinition = load("res://resources/items/weapons/frost_bow.tres")
var staff: ItemDefinition = load("res://resources/items/weapons/mage_staff.tres")
var armor: ItemDefinition = load("res://resources/items/armor/ranger_armor.tres")
var failures: Array[String] = []
var checks := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(40.0).timeout.connect(func(): push_error("Offhand tests timed out"); quit(1))
	_test_resources()
	_test_transfers()
	_test_health_and_actions()
	_test_authoring_and_developer()
	await _test_persistence()
	_test_run_equipment_saves()
	await process_frame
	await process_frame
	for failure in failures:
		push_error(failure)
	print("OFFHAND_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _make_unit(items: Array[ItemDefinition] = []) -> TacticalCharacter:
	var unit := TacticalCharacter.new()
	unit.definition = CharacterDefinition.new()
	unit.definition.constitution = 10
	unit.definition.starting_equipment.assign(items)
	root.add_child(unit)
	return unit


func _test_resources() -> void:
	_check(ItemDefinition.EquipmentSlot.values() == [0, 1, 2, 3], "serialized slot values stay compatible")
	_check(not ItemDefinition.new().is_two_handed(), "new weapons default to one hand")
	_check(shield.slot == OFFHAND and shield.icon != null and shield.modifiers.size() == 1, "shield has offhand slot, artwork, and one modifier")
	_check(shield.modifiers[0].stat == UnitStat.Type.CONSTITUTION and shield.modifiers[0].operation == StatModifierDefinition.Operation.FLAT and shield.modifiers[0].value == 3.0, "shield grants exactly flat +3 Constitution")
	_check(shield.get_granted_abilities().is_empty(), "shield grants no weapon attacks")
	var items := ItemDefinitionCatalog.get_items()
	_check(items.size() == 29, "recursive item catalog includes all 29 resources")
	for item in items:
		var file := item.resource_path.get_file()
		_check(item.is_two_handed() == (file.ends_with("_bow.tres") or file in ["mage_staff.tres", "long_sword.tres", "spear.tres"]), "%s handedness" % file)
	_check((load("res://resources/dev_tool_catalog.tres") as DevToolCatalog).items.has(shield), "shield available in developer catalog")
	_check((load("res://resources/run/default_run.tres") as RunConfig).equipment_pool.has(shield), "shield available in merchant/reward pool")
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate()
	_check((battle.get_node("GeneralInventory") as GeneralInventory).starting_items.has(shield), "shield available in sample inventory")
	battle.free()
	var path := "res://.godot/offhand_validation/authored_weapon.tres"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var authored := ItemDefinition.new()
	authored.weapon_handedness = ItemDefinition.WeaponHandedness.TWO_HANDED
	_check(ResourceSaver.save(authored, path) == OK, "save editable handedness")
	_check((ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ItemDefinition).is_two_handed(), "handedness survives resource reload")
	var property := {"name": &"weapon_handedness", "usage": PROPERTY_USAGE_DEFAULT}
	shield._validate_property(property)
	_check((property.usage & PROPERTY_USAGE_EDITOR) == 0, "non-weapons hide handedness in Inspector")


func _test_transfers() -> void:
	# Exercise both transfer directions across all valid hand configurations.
	for equipped in [[], [sword], [shield], [sword, shield], [bow], [staff]]:
		for incoming in [sword, shield, bow, staff, armor]:
			for reverse in [false, true]:
				var setup: Array[ItemDefinition] = []
				setup.assign(equipped)
				var unit := _make_unit(setup)
				var pack := GeneralInventory.new()
				root.add_child(pack)
				# Duplicate incoming resources and an interior vacancy detect copy/index errors.
				pack.initialize_starting_items([incoming, armor, incoming])
				pack.move_or_swap(1, 5)
				var before := _bag(pack.get_items() + unit.get_equipped_items())
				var displaced := unit.get_displaced_items(incoming)
				_check(_bag(pack.get_items() + unit.get_equipped_items()) == before, "preview is read-only")
				var revision := pack.revision
				var events := [0, 0]
				var observed_slots: Array[int] = []
				var old_primary := unit.get_equipped_item(incoming.slot)
				var accepted: bool = not reverse or old_primary != null
				var verify := func():
					_check(_bag(pack.get_items() + unit.get_equipped_items()) == before, "every observer sees all item copies")
					_check(unit.get_equipped_item(incoming.slot) == incoming, "observers see the final item")
					_check(not (unit.get_equipped_weapon() != null and unit.get_equipped_weapon().is_two_handed() and unit.get_equipped_item(OFFHAND) != null), "observers never see conflicting hands")
				unit.stats_changed.connect(func(): events[1] += 1; verify.call())
				unit.equipment_changed.connect(func(slot, _item): observed_slots.append(slot); verify.call())
				pack.items_changed.connect(func(): events[0] += 1; verify.call())
				var result := pack.unequip_to_slot(unit, incoming.slot, 2) if reverse else pack.equip_from_slot(2, unit, incoming.slot)
				_check(result == accepted, "reverse swaps require a real equipped item")
				_check(_bag(pack.get_items() + unit.get_equipped_items()) == before, "transfers conserve every item copy")
				_check(events == ([1, 1] if accepted else [0, 0]), "exactly one inventory and stat notification per accepted transfer")
				_check(pack.revision == revision + (1 if accepted else 0), "exactly one revision increment")
				if accepted:
					_check(pack.get_item_at(0) == incoming, "the undragged duplicate remains in place")
					_check(pack.get_item_at(2) == (null if displaced.is_empty() else displaced[0]), "first displaced item returns to exact source/destination")
					if displaced.size() == 2:
						_check(pack.get_item_at(1) == displaced[1], "extra displaced item fills first vacancy")
					if incoming.is_two_handed():
						_check(observed_slots.has(OFFHAND) or equipped == [incoming], "reservation changes notify Offhand")
				unit.free()
				pack.free()
	var unit := _make_unit([sword, shield])
	var pack := GeneralInventory.new()
	root.add_child(pack)
	pack.initialize_starting_items([bow])
	_check(pack.equip_from_slot(0, unit, WEAPON) and pack.get_slots() == [sword, shield], "inventory grows when both hands return to a full pack")
	var before := pack.capture_state()
	_check(not pack.equip_from_slot(0, unit, OFFHAND) and pack.capture_state() == before, "weapons cannot enter Offhand")
	_check(not pack.unequip_to_slot(unit, OFFHAND, 4), "reserved Offhand cannot be unequipped independently")
	_check(pack.unequip_to_slot(unit, WEAPON, 4) and unit.get_slot_occupant(OFFHAND) == null and pack.get_item_at(4) == bow, "taking the weapon releases both hands and returns one copy")
	unit.free()
	pack.free()
	unit = _make_unit()
	pack = GeneralInventory.new()
	root.add_child(pack)
	pack.initialize_starting_items([shield])
	var notification_snapshot: Array[String] = []
	unit.equipment_changed.connect(func(_slot, _item): notification_snapshot.assign(pack.capture_state()))
	pack.equip_from_slot(0, unit, OFFHAND)
	_check(notification_snapshot == pack.capture_state() and notification_snapshot.is_empty(), "equipment notification sees final trimmed inventory, even when taking its last item")
	unit.free()
	pack.free()


func _test_health_and_actions() -> void:
	var unit := _make_unit([sword])
	var base_max := unit.get_max_health()
	var health := unit.current_health
	unit.spend_ability_action()
	unit.spend_opportunity_reaction()
	_check(unit.equip_item(shield).is_empty(), "shield coexists with a sword")
	_check(unit.get_effective_stat(UnitStat.Type.CONSTITUTION) == 13.0 and unit.get_max_health() == base_max + 12, "shield adds three Constitution and normally twelve max HP")
	_check(unit.current_health == health, "equipping shield does not heal")
	unit.current_health = unit.get_max_health()
	# Equal final Constitution must not momentarily remove the shield and clamp HP.
	var replacement := ItemDefinition.new()
	replacement.weapon_handedness = ItemDefinition.WeaponHandedness.TWO_HANDED
	replacement.modifiers.assign(shield.modifiers)
	_check(unit.equip_item(replacement) == [sword, shield], "API returns both displaced items, destination first")
	_check(unit.current_health == base_max + 12 and unit.get_effective_stat(UnitStat.Type.CONSTITUTION) == 13.0, "atomic replacement avoids intermediate HP clamp and duplicate two-handed modifiers")
	_check(unit.equip_item(shield) == [replacement], "offhand returns the conflicting two-handed weapon")
	_check(unit.get_equipped_weapon() == null and unit.get_abilities().has(load("res://resources/abilities/strike.tres")), "shield without weapon retains unarmed Strike")
	unit.unequip_item(OFFHAND)
	_check(unit.current_health == base_max and unit.get_max_health() == base_max, "shield removal clamps to new maximum")
	unit.current_health = 7
	unit.equip_item(shield)
	unit.equip_item(bow)
	_check(unit.current_health == 7 and not unit.ability_available and not unit.opportunity_reaction_available, "hand swaps preserve wounded HP and spent actions/reactions")
	_check(unit.get_equipped_items() == [bow] and unit.get_abilities().has(load("res://resources/abilities/arrow.tres")), "two-handed bow counts once and grants Shoot")
	unit.free()


func _test_authoring_and_developer() -> void:
	var unit := _make_unit([sword, shield, bow])
	_check(unit.get_equipped_items() == [bow], "last authored two-handed item wins")
	_check(" ".join(unit._get_configuration_warnings()).contains("conflicts"), "conflicting authoring produces a warning")
	unit.set_dev_equipment(OFFHAND, shield)
	_check(unit.get_equipped_items() == [shield] and unit.complete_equipment_overrides == [shield], "developer offhand edit removes two-handed weapon from runtime and setup")
	unit.set_dev_equipment(WEAPON, sword)
	_check(unit.get_equipped_items() == [sword, shield], "developer permits sword and shield")
	unit.set_dev_equipment(WEAPON, staff)
	_check(unit.complete_equipment_overrides == [staff] and unit.get_equipped_items() == [staff], "developer two-handed edit clears both conflicts")
	unit.set_dev_equipment(WEAPON, null)
	_check(unit.get_equipped_items().is_empty() and unit.complete_equipment_overrides.is_empty(), "developer clears weapon and reservation")
	unit.reset_dev_equipment_to_template()
	_check(unit.get_equipped_items() == [bow], "reset uses the same conflict rules")
	unit.free()
	unit = _make_unit([bow, shield])
	_check(unit.get_equipped_items() == [shield], "last authored offhand wins")
	unit.free()
	unit = TacticalCharacter.new()
	unit.definition = CharacterDefinition.new()
	unit.definition.starting_equipment = [bow]
	unit.starting_equipment_overrides = [shield]
	root.add_child(unit)
	_check(unit.get_equipped_items() == [shield], "legacy override removes inherited hand conflict")
	unit.free()


func _test_persistence() -> void:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	root.add_child(battle)
	await process_frame
	var unit: TacticalCharacter = battle.turn_manager.current_unit
	var panel := battle.dev_mode_panel
	panel.select_unit(unit)
	unit.set_dev_equipment(WEAPON, bow)
	panel.select_unit(unit)
	_check(panel.offhand_picker.get_item_text(0).contains("Occupied by Frost Bow") and panel.offhand_picker.is_item_disabled(0), "developer picker shows informational reservation")
	var shield_index := -1
	for index in panel.offhand_picker.item_count:
		if panel.offhand_picker.get_item_metadata(index) == shield:
			shield_index = index
	_check(shield_index > 0, "developer picker offers shield")
	if shield_index > 0:
		panel.offhand_picker.item_selected.emit(shield_index)
		_check(unit.get_equipped_item(OFFHAND) == shield and unit.get_equipped_weapon() == null, "developer picker equips shield and removes bow")
		_check(panel.offhand_picker.get_item_text(0) == "Empty" and not panel.offhand_picker.is_item_disabled(0), "developer picker clears reservation")
	for loadout in [[sword, shield], [bow], [sword]]:
		for slot in ItemDefinition.EquipmentSlot.values():
			unit.set_dev_equipment(slot, null)
		for item in loadout:
			unit.set_dev_equipment(item.slot, item)
		var expected: Array[String] = []
		for item in loadout:
			expected.append(item.resource_path)
		var member := RunPartyMember.from_character(unit)
		var restored := RunPartyMember.from_data(JSON.parse_string(JSON.stringify(member.to_data())))
		_check(restored != null and restored.equipment == expected, "run party round-trip preserves unique equipment including legacy no-offhand loadout")
		var payload := battle.capture_save_payload(false)
		var result := ScenarioSaveStore.save_new(payload, "res://.godot/offhand_validation/scenarios")
		_check(result.ok, "scenario saves hand configuration")
		if result.ok:
			var loaded := ScenarioSaveStore.load_save(result.path, "res://.godot/offhand_validation/scenarios")
			_check(loaded.ok, "scenario reload validates")
			unit.equip_item(staff)
			_check(battle._restore_runtime_state(loaded.payload.runtime), "scenario restores equipment")
			_check(unit.capture_runtime_state().equipped_items == expected, "scenario stores each item once")
			_check((unit.get_slot_occupant(OFFHAND) == bow) == (loadout == [bow]), "restored reservation is derived from weapon")
	var saved := unit.capture_runtime_state()
	saved.equipped_items = [bow.resource_path, shield.resource_path]
	unit.restore_runtime_state(saved, {})
	_check(unit.get_equipped_items() == [shield], "runtime restore normalizes conflicting authored list in order")
	battle.shutdown_battle()
	battle.queue_free()
	await process_frame


func _test_run_equipment_saves() -> void:
	var controller := RunController.new()
	controller.config = load("res://resources/run/default_run.tres")
	controller.save_path = "res://.godot/offhand_validation/run.json"
	root.add_child(controller)
	_check(controller.new_run(10), "create isolated run for equipment saves")
	for loadout in [[sword, shield], [bow], [sword]]:
		var previous := controller.state.party[0]
		var unit := (load(str(previous.setup.scene)) as PackedScene).instantiate() as TacticalCharacter
		unit.apply_setup_state(previous.setup)
		root.add_child(unit)
		for slot in ItemDefinition.EquipmentSlot.values():
			unit.set_dev_equipment(slot, null)
		for item in loadout:
			unit.set_dev_equipment(item.slot, item)
		var member := RunPartyMember.from_character(unit)
		controller.state.party[0] = member
		_check(controller.save_store.save_run(controller.state), "write run checkpoint with hand configuration")
		controller.state = controller.save_store.load_run()
		var saved := controller.state.party[0]
		_check(saved.equipment == member.equipment and saved.max_health == member.max_health, "run disk round-trip preserves equipment and derived max health")
		var restored := (load(str(saved.setup.scene)) as PackedScene).instantiate() as TacticalCharacter
		restored.apply_setup_state(saved.setup)
		root.add_child(restored)
		_check(restored.get_equipped_items() == unit.get_equipped_items() and restored.get_max_health() == unit.get_max_health(), "run saved setup recreates the same loadout and stats")
		restored.queue_free()
		unit.queue_free()
	controller.queue_free()


func _bag(items: Array[ItemDefinition]) -> Dictionary:
	var counts := {}
	for item in items:
		counts[item] = int(counts.get(item, 0)) + 1
	return counts


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
