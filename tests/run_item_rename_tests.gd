extends SceneTree

const STAFF := "res://resources/items/weapons/staff.tres"
const BOW := "res://resources/items/weapons/short_bow.tres"
const OLD_STAFF := "res://resources/items/weapons/mage_staff.tres"
const OLD_BOW := "res://resources/items/weapons/weathered_bow.tres"
const DIRECTORY := "res://.godot/item_rename_validation"
var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	_test_resources_and_defaults()
	await _test_scenario()
	await _test_run()
	for failure in failures:
		push_error(failure)
	print("ITEM_RENAME_TESTS: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _test_resources_and_defaults() -> void:
	var staff := load(STAFF) as ItemDefinition
	var bow := load(BOW) as ItemDefinition
	_check(staff.display_name == "Staff" and staff.is_two_handed(), "Staff name and handedness")
	_check(staff.modifiers.size() == 1 and staff.modifiers[0].stat == UnitStat.Type.INTELLIGENCE
		and staff.modifiers[0].value == 2.0 and staff.weapon_damage == 0, "Staff keeps existing stats")
	_check(bow.display_name == "Short Bow" and bow.weapon_damage == 4
		and bow.weapon_type == ItemDefinition.WeaponType.RANGED and bow.is_two_handed(), "Short Bow keeps existing stats")
	_check(staff.icon.resource_path == "res://assets/item_icons/staff.svg"
		and bow.icon.resource_path == "res://assets/item_icons/short_bow.svg", "renamed icons load")
	_check(ResourceUID.id_to_text(ResourceLoader.get_resource_uid(STAFF)) == "uid://rp1xdm4agyqo", "Staff retains its resource UID")
	var catalog := load("res://resources/dev_tool_catalog.tres") as DevToolCatalog
	_check(catalog.items.count(staff) == 1 and catalog.items.count(bow) == 1, "catalog lists each renamed item once")
	for id in ["wizard", "cleric"]:
		var actor := load("res://scenes/friendlies/%s.tscn" % id).instantiate() as TacticalCharacter
		root.add_child(actor)
		_check(actor.get_equipped_items() == [staff], "%s starts with Staff" % id)
		_check(actor.get_slot_occupant(ItemDefinition.EquipmentSlot.OFFHAND) == staff, "%s reserves both hands" % id)
		# Saved empty loadouts must override the newly authored starting weapon.
		var old_setup := actor.capture_setup_state()
		old_setup.equipment = []
		actor.apply_setup_state(old_setup)
		_check(actor.get_equipped_items().is_empty(), "%s saved empty loadout remains empty" % id)
		actor.free()
	var mage := load("res://scenes/enemies/mage.tscn").instantiate() as TacticalCharacter
	root.add_child(mage)
	_check(mage.get_equipped_weapon() == staff, "enemy Mage still has Staff")
	mage.free()
	var pack := GeneralInventory.new()
	root.add_child(pack)
	var old_paths := [OLD_STAFF, "", OLD_BOW]
	pack.restore_state(old_paths)
	_check(pack.capture_state() == [STAFF, "", BOW] and old_paths == [OLD_STAFF, "", OLD_BOW],
		"direct inventory restore normalizes copies and preserves empty slots")
	pack.free()


func _test_scenario() -> void:
	var battle := load("res://scenes/battle.tscn").instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	root.add_child(battle)
	await process_frame
	var actor := battle.turn_manager.current_unit
	actor.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, load(STAFF))
	actor.apply_status(load("res://resources/statuses/focus.tres"), load(BOW), actor)
	battle.general_inventory.restore_state([STAFF, "", BOW])
	var canonical := battle.capture_save_payload(false)
	var legacy := _legacy(canonical)
	legacy.setup.units[0].legacy_equipment = [OLD_STAFF]
	var before := JSON.stringify(legacy)
	var checked := ScenarioSaveStore.validate_payload(legacy)
	_check(checked.ok, "legacy scenario validates: %s" % [checked.errors])
	_check(JSON.stringify(legacy) == before, "scenario validation leaves input untouched")
	if checked.ok:
		_check(_canonical(checked.payload), "all nested scenario paths are normalized")
		_check(checked.payload.setup.units[0].legacy_equipment == [STAFF], "legacy equipment override paths normalize")
		_check(battle._restore_runtime_state(legacy.runtime), "direct runtime restoration accepts old paths")
		_check(actor.get_equipped_weapon().resource_path == STAFF, "restored equipment uses canonical resource")
		_check(actor.capture_runtime_state().statuses[0].source_resource == BOW, "status source is restored through renamed item")
		_check(_canonical(battle.capture_save_payload(false)), "restored scenario captures canonical paths")
	var disk_path := DIRECTORY + "/legacy_scenario.json"
	_write(disk_path, legacy)
	var loaded := ScenarioSaveStore.load_save(disk_path, DIRECTORY)
	_check(loaded.ok and FileAccess.get_file_as_string(disk_path) == before, "loading legacy scenario does not rewrite its file")
	if loaded.ok:
		var saved := ScenarioSaveStore.save_new(loaded.payload, DIRECTORY)
		_check(saved.ok, "migrated scenario saves")
		if saved.ok:
			_check(_canonical(JSON.parse_string(FileAccess.get_file_as_string(saved.path))), "scenario file re-saves canonical paths")
	var invalid := legacy.duplicate(true)
	invalid.runtime.inventory = ["res://resources/items/weapons/missing_weapon.tres"]
	_check(not ScenarioSaveStore.validate_payload(invalid).ok, "unknown item paths are still rejected")
	battle.queue_free()
	await process_frame


func _test_run() -> void:
	var controller := RunController.new()
	controller.config = load("res://resources/run/default_run.tres")
	controller.save_path = DIRECTORY + "/new_run.json"
	root.add_child(controller)
	_check(controller.new_run_with_party(["wizard", "cleric"], 37), "new caster party starts")
	var original := controller.state.to_data()
	for kind in [RunMapGraph.NodeType.SHOP, RunMapGraph.NodeType.CHEST]:
		controller.state = RunState.from_data(original)
		var id := controller.state.available_rooms()[0]
		controller.state.graph.get_node_by_id(id).type = kind
		_check(controller.select_room(id), "pending room fixture saves")
		var data := controller.state.to_data()
		data.inventory = [STAFF, "", BOW]
		data.pending.reward_item = BOW
		if kind == RunMapGraph.NodeType.SHOP:
			data.pending.offers = [STAFF, BOW]
			data.pending.purchased = [0]
		var legacy := _legacy(data)
		var before := JSON.stringify(legacy)
		var loaded := RunState.from_data(legacy)
		_check(loaded != null, "legacy run with pending room loads")
		_check(JSON.stringify(legacy) == before, "run loading leaves input untouched")
		if loaded != null:
			_check(_canonical(loaded.to_data()), "party, inventory, and pending items normalize")
			_check(loaded.party[0].equipment == [STAFF] and loaded.party[1].equipment == [STAFF], "saved caster weapons survive migration")
			_check(loaded.inventory == [STAFF, "", BOW], "run migration preserves inventory slots")
			if kind == RunMapGraph.NodeType.SHOP:
				_check(loaded.pending.offers == [STAFF, BOW] and loaded.pending.purchased == [0], "shop stock and purchases survive migration")
		var standalone := RunPartyMember.from_data(legacy.party[0])
		_check(standalone != null and _canonical(standalone.to_data()), "standalone member restoration migrates nested setup")
		var store := RunSaveStore.new()
		store.path = DIRECTORY + "/legacy_run_%d.json" % kind
		_write(store.path, legacy)
		var disk_run := store.load_run()
		_check(disk_run != null and FileAccess.get_file_as_string(store.path) == before, "loading legacy run does not rewrite its file")
		if disk_run != null:
			_check(store.save_run(disk_run), "migrated run re-saves")
			_check(_canonical(JSON.parse_string(FileAccess.get_file_as_string(store.path))), "run file re-saves canonical paths")
		var invalid := legacy.duplicate(true)
		invalid.inventory = ["res://resources/items/weapons/missing_weapon.tres"]
		_check(RunState.from_data(invalid) == null, "run still rejects unknown item paths")
	controller.queue_free()
	await process_frame


func _legacy(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data).replace(STAFF, OLD_STAFF).replace(BOW, OLD_BOW))


func _canonical(data: Variant) -> bool:
	var text := JSON.stringify(data)
	return not text.contains(OLD_STAFF) and not text.contains(OLD_BOW)


func _write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
