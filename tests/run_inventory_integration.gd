extends SceneTree

var _failed: bool = false
var inventory: GeneralInventory
var screen: InventoryScreen
var character: TacticalCharacter
var other: TacticalCharacter
var sword: ItemDefinition = load("res://resources/items/iron_sword.tres")
var bow: ItemDefinition = load("res://resources/items/frost_bow.tres")
var armor: ItemDefinition = load("res://resources/items/ranger_armor.tres")
var charm: ItemDefinition = load("res://resources/items/sage_charm.tres")
var _capture_directory: String = ""
var _mouse_position := Vector2.ZERO
var _mouse_down: bool = false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	# A watchdog makes unexpected script errors fail instead of silently timing out.
	create_timer(40.0).timeout.connect(func() -> void: push_error("Inventory test timed out"); quit(1))
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_capture_directory = args[0]
	if args.size() >= 2:
		var dimensions := args[1].split("x")
		root.size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	inventory = GeneralInventory.new()
	root.add_child(inventory)
	character = _make_character("Inventory Fixture")
	other = _make_character("Second Fixture")
	screen = (load("res://scenes/inventory_screen.tscn") as PackedScene).instantiate() as InventoryScreen
	root.add_child(screen)
	screen.setup(inventory, [character, other])
	screen.open_for(character)
	await process_frame
	_test_model()
	_test_equipment_statistics()
	await _test_ui()
	await _test_save_flow()
	await _test_battle_signals()
	await _capture_overview()
	screen.queue_free()
	inventory.queue_free()
	character.queue_free()
	other.queue_free()
	await process_frame
	if not _failed:
		print("INVENTORY_INTEGRATION_OK")
	quit(1 if _failed else 0)


func _make_character(display_name: String) -> TacticalCharacter:
	var unit := TacticalCharacter.new()
	unit.definition = CharacterDefinition.new()
	unit.definition.display_name = display_name
	unit.set_dev_ability_loadout([load("res://resources/abilities/strike.tres"), load("res://resources/abilities/arrow.tres"), load("res://resources/abilities/fireball.tres")])
	root.add_child(unit)
	return unit


func _reset() -> void:
	for slot in ItemDefinition.EquipmentSlot.values():
		character.unequip_item(slot)
	inventory.initialize_starting_items([sword, bow, armor, charm, sword])
	screen.open_for(character)


func _test_model() -> void:
	for file_name in DirAccess.get_files_at("res://resources/items"):
		if file_name.ends_with(".tres"):
			var item := load("res://resources/items/" + file_name) as ItemDefinition
			_check(item != null and item.icon != null, file_name + " has assigned artwork")
	_reset()
	var config: Array[ItemDefinition] = [sword, null, sword]
	inventory.initialize_starting_items(config)
	_check(inventory.get_items().size() == 2, "starting nulls ignored, duplicate copies retained")
	_check(inventory.take_item(sword) and inventory.get_item_at(0) == null and inventory.get_item_at(1) == sword, "take leaves a stable vacant cell")
	_check(config == [sword, null, sword], "starting resources remain unchanged")
	inventory.add_item(bow)
	_check(inventory.get_slots() == [bow, sword], "add fills first gap")
	_check(not inventory.move_or_swap(9, 0) and not inventory.move_or_swap(0, -1), "invalid moves rejected")
	_check(inventory.move_or_swap(0, 17), "moving beyond current cells grows storage")
	_check(inventory.get_item_at(17) == bow and inventory.get_item_at(1) == sword and inventory.get_items().size() == 2, "moving preserves holes and count")
	_check(inventory.move_or_swap(17, 1) and inventory.get_item_at(17) == sword and inventory.get_item_at(1) == bow, "occupied inventory cells swap")
	var revision := inventory.revision
	inventory.move_or_swap(17, 17)
	_check(inventory.revision == revision, "same-cell drop is a no-op")
	# Every source type is tested against every equipment destination.
	for item in [sword, armor, charm]:
		for slot in ItemDefinition.EquipmentSlot.values():
			inventory.initialize_starting_items([item])
			var before := inventory.get_slots()
			var equipment := character.get_equipped_items()
			var accepted := inventory.equip_from_slot(0, character, slot)
			_check(accepted == (item.slot == slot), "equipment type %d into slot %d" % [item.slot, slot])
			if not accepted:
				_check(inventory.get_slots() == before and character.get_equipped_items() == equipment, "invalid equipment drop is atomic")
	_reset()
	character.equip_item(bow)
	var events := [0]
	var listener := func() -> void: events[0] += 1
	inventory.items_changed.connect(listener)
	_check(inventory.equip_from_slot(4, character, 0), "equip exact duplicate copy")
	_check(inventory.get_item_at(0) == sword and inventory.get_item_at(4) == bow, "replaced gear returns to dragged copy's cell")
	_check(events[0] == 1, "one inventory notification per transfer")
	inventory.items_changed.disconnect(listener)
	var snapshot := inventory.get_slots()
	_check(not inventory.unequip_to_slot(character, 0, 2), "weapon cannot swap with inventory armor")
	_check(inventory.get_slots() == snapshot and character.get_equipped_item(0) == sword, "invalid reverse swap changes neither side")
	_check(inventory.unequip_to_slot(character, 0, 1) and character.get_equipped_item(0) == bow and inventory.get_item_at(1) == sword, "reverse compatible swap")
	_check(inventory.unequip_to_slot(character, 0, 12) and character.get_equipped_item(0) == null and inventory.get_item_at(12) == bow, "unequip into exact empty destination")
	_check(not inventory.equip_from_slot(0, null, 0), "missing character rejected")
	var health := character.current_health
	character.current_health = 0
	_check(not inventory.equip_from_slot(0, character, 0), "defeated character rejected")
	character.current_health = health


func _test_ui() -> void:
	_reset()
	await _frames(3)
	_check(screen.general_entries.columns == 5 and screen.general_entries.get_child_count() >= 20, "five-column grid with at least four rows")
	_check(screen.equipment_entries.get_child_count() == 3, "three labeled equipment cells")
	_check(_cell(0).artwork.texture == sword.icon and sword.icon != null, "item icons render from resources")
	_check(_equipment(0).artwork.texture != null and _equipment(0).artwork.modulate.a < 1.0, "empty equipment uses faint category symbols")
	var fallback := ItemDefinition.new()
	_check(screen.get_item_icon(fallback) != null, "unassigned artwork uses category fallback")
	await _click(_cell(0))
	_check(character.get_equipped_item(0) == null and inventory.get_item_at(0) == sword, "single click selects without equipping")
	await _click(_cell(0), true)
	_check(character.get_equipped_item(0) == sword and inventory.get_item_at(0) == null, "double-click equips")
	await _click(_equipment(0), true)
	_check(character.get_equipped_item(0) == null and inventory.get_item_at(0) == sword, "double-click unequips into first gap")
	_equipment(0).grab_focus()
	_cell(0).grab_focus()
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	root.push_input(enter, true)
	enter = enter.duplicate()
	enter.pressed = false
	root.push_input(enter, true)
	await _frames(2)
	_check(character.get_equipped_item(0) == sword, "Enter equips focused item")
	_reset()
	await _frames(2)
	await _drag(_cell(0), _cell(8))
	_check(inventory.get_item_at(8) == sword and inventory.get_item_at(0) == null, "native mouse drag moves to empty cell")
	await _drag(_cell(8), _cell(1))
	_check(inventory.get_item_at(8) == bow and inventory.get_item_at(1) == sword, "native mouse drag swaps cells")
	await _drag(_cell(1), _equipment(1))
	_check(inventory.get_item_at(1) == sword and character.get_equipped_item(1) == null, "native invalid equipment drop rejected")
	await _drag(_cell(1), _equipment(0))
	_check(character.get_equipped_item(0) == sword and inventory.get_item_at(1) == null, "native mouse drag equips")
	await _drag(_equipment(0), _cell(2))
	_check(character.get_equipped_item(0) == sword and inventory.get_item_at(2) == armor, "native invalid reverse swap rejected")
	await _drag(_equipment(0), _cell(8))
	_check(character.get_equipped_item(0) == bow and inventory.get_item_at(8) == sword, "native compatible reverse swap")
	await _drag(_equipment(0), _cell(7))
	_check(character.get_equipped_item(0) == null and inventory.get_item_at(7) == bow, "native mouse drag unequips")
	var before := inventory.get_slots()
	await _begin_drag(_cell(7))
	await _motion(Vector2(15, 15))
	await _release()
	_check(inventory.get_slots() == before, "outside drop preserves contents")
	await _begin_drag(_cell(7))
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.pressed = true
	root.push_input(cancel, true)
	await _release()
	_check(inventory.get_slots() == before and screen.visible, "Escape cancels drag without closing inventory")
	var payload := screen.create_drag_payload(_cell(7))
	inventory.add_item(charm)
	_check(not screen.can_drop_on(_equipment(0), payload), "changed inventory rejects stale drag")
	await _frames(2)
	payload = screen.create_drag_payload(_cell(7))
	screen.open_for(other)
	_check(not screen.can_drop_on(_equipment(0), payload), "changed selection rejects stale drag")
	screen.open_for(character)
	await _begin_drag(_cell(7))
	screen.close_screen()
	_check(not root.gui_is_dragging(), "closing cancels native drag")
	await _release()
	screen.open_for(character)
	await _frames(2)
	_check(inventory.get_item_at(7) == bow, "reopening retains arrangement")
	await _begin_drag(_cell(7))
	character.apply_damage(character.current_health)
	_check(not root.gui_is_dragging(), "defeat cancels an active drag")
	await _release()
	character.current_health = character.get_max_health()
	screen._refresh_character_details()
	await _motion(_cell(7).get_global_rect().get_center())
	await create_timer(0.3).timeout
	_check(screen.item_details.visible and screen.item_details.title.text == bow.display_name, "hover opens adjacent item card")
	_check(screen.item_details.body.text.contains("Slow") and screen.item_details.body.text.contains(str(bow.weapon_damage)), "hover includes damage and status description")
	_check(not screen.item_details.get_global_rect().intersects(_cell(7).get_global_rect()), "hover card sits next to source item")
	await _capture("hover")
	# Resource-authored modifier operations are represented without losing signs.
	var modifier_item := ItemDefinition.new()
	modifier_item.display_name = "Modifier fixture"
	for operation in StatModifierDefinition.Operation.values():
		var modifier := StatModifierDefinition.new()
		modifier.operation = operation
		modifier.value = -0.25 if operation != 0 else 2.0
		modifier_item.modifiers.append(modifier)
	screen.item_details.show_item(modifier_item, false)
	_check(screen.item_details.body.text.contains("+2 Strength") and screen.item_details.body.text.contains("-25%") and screen.item_details.body.text.contains("multiplicative"), "hover describes every modifier operation")
	var marker := Control.new()
	root.add_child(marker)
	marker.position = root.get_visible_rect().size - Vector2(70, 70)
	marker.size = Vector2(64, 64)
	screen.item_details.place_next_to(marker)
	_check(root.get_visible_rect().encloses(screen.item_details.get_global_rect()), "edge hover card stays in viewport")
	_check(screen.item_details.position.x < marker.position.x, "right-edge hover flips left")
	marker.queue_free()
	for index in range(35):
		inventory.add_item(armor)
	await _frames(4)
	_check(screen.general_entries.get_child_count() >= 45, "inventory grows with spare cells")
	screen.inventory_scroll.scroll_vertical = 140
	await _frames(3)
	_check(not screen.item_details.visible, "scrolling dismisses obsolete hover card")
	await _capture("scroll")
	var no_characters: Array[TacticalCharacter] = []
	screen.setup(inventory, no_characters)
	_check(not screen.can_drop_on(_equipment(0), screen.create_drag_payload(_cell(0))), "equipment drop without selected character rejected")
	screen.setup(inventory, [character, other])


func _test_save_flow() -> void:
	inventory.initialize_starting_items([sword, sword, armor])
	inventory.move_or_swap(1, 18)
	var saved := inventory.capture_state()
	_check(saved.size() == 19 and saved[1] == "" and saved[18] == sword.resource_path, "save records exact slots including gaps")
	inventory.restore_state(saved)
	_check(inventory.capture_state() == saved and inventory.get_items().size() == 3, "save restore preserves duplicates and positions")
	inventory.restore_state([sword.resource_path, armor.resource_path])
	_check(inventory.get_slots() == [sword, armor], "legacy compact saves load unchanged")
	var controller := RunController.new()
	controller.config = load("res://resources/run/default_run.tres")
	controller.save_path = "res://.godot/inventory_validation/run.json"
	root.add_child(controller)
	_check(controller.new_run(10), "create isolated run checkpoint")
	controller.state.inventory.assign(saved)
	_check(controller.save_store.save_run(controller.state), "save sparse run inventory")
	controller.state = controller.save_store.load_run()
	_check(controller.state.inventory == saved, "reload sparse run inventory")
	var state_before := controller.state.to_data().duplicate(true)
	var node_id := controller.state.available_rooms()[0]
	controller.state.graph.get_node_by_id(node_id).type = RunMapGraph.NodeType.SHOP
	_check(controller.select_room(node_id) and controller.buy_offer(0), "purchase with sparse inventory")
	_check(controller.state.inventory[1] != "" and controller.state.inventory[18] == sword.resource_path, "shop fills gap without shifting other items")
	controller.state = RunState.from_data(state_before)
	controller.state.graph.get_node_by_id(node_id).type = RunMapGraph.NodeType.CHEST
	_check(controller.select_room(node_id), "treasure with sparse inventory")
	_check(controller.state.inventory[1] != "" and controller.state.inventory[18] == sword.resource_path, "reward fills gap without shifting other items")
	controller.state = RunState.from_data(state_before)
	controller.state.graph.get_node_by_id(node_id).type = RunMapGraph.NodeType.NORMAL_COMBAT
	var received: Array = []
	controller.battle_requested.connect(func(_encounter, _members, items, _id) -> void: received.assign(items))
	_check(controller.select_room(node_id), "start battle from sparse inventory checkpoint")
	if received != saved:
		print("HANDOFF_EXPECTED=", saved, " RECEIVED=", received, " PENDING=", controller.state.pending)
	_check(received == saved, "battle handoff keeps exact slots")
	var results: Array[Dictionary] = []
	for member in controller.state.party:
		results.append({"id": member.id, "health": member.health, "max_health": member.max_health, "equipment": Array(member.equipment)})
	_check(controller.finish_battle(node_id, true, results, saved), "battle returns sparse inventory")
	_check(controller.save_store.load_run().inventory == saved, "completed battle checkpoint retains arrangement")
	var independent_snapshot := controller.state.to_data()
	controller.state.add_inventory_item(charm.resource_path)
	_check(independent_snapshot.inventory == saved, "vacancy filling cannot mutate a rollback snapshot")
	controller.queue_free()
	await process_frame


func _test_battle_signals() -> void:
	screen.hide()
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	root.add_child(battle)
	await process_frame
	var unit: TacticalCharacter = battle.turn_manager.current_unit
	_check(unit.is_friendly(), "battle fixture starts with a friendly turn")
	var ui: InventoryScreen = battle.inventory_screen
	var pack: GeneralInventory = battle.general_inventory
	pack.initialize_starting_items([bow])
	battle._on_inventory_button_toggled(true)
	ui.open_for(unit)
	pack.equip_from_slot(0, unit, 0)
	await _frames(2)
	var arrow := load("res://resources/abilities/arrow.tres") as AbilityDefinition
	unit.override_template_abilities = true
	unit.ability_overrides = [arrow]
	unit.reset_ability_action()
	battle._on_ability_selected(arrow)
	_check(battle._selected_ability == arrow, "ranged weapon enables ability targeting")
	_check(unit.get_equipped_weapon_type() == ItemDefinition.WeaponType.RANGED, "battle equipment changes use actual actor API")
	for row in ui.stats_entries.get_children():
		if row.get_meta("stat_key", "") == "weapon_damage":
			_check(row.get_meta("value_text") == str(bow.weapon_damage), "battle details refresh live weapon damage")
	await _capture("battle")
	pack.add_item(sword)
	var sword_index := pack.get_slots().find(sword)
	pack.equip_from_slot(sword_index, unit, 0)
	await _frames(2)
	_check(unit.get_equipped_weapon_type() == ItemDefinition.WeaponType.MELEE, "battle equipment can change weapon type")
	_check(battle._selected_ability == null and not arrow.can_be_used_by(unit), "weapon swap cancels incompatible targeting and ability availability")
	var saved := battle.capture_save_payload(false)
	pack.move_or_swap(sword_index, 17)
	saved = battle.capture_save_payload(false)
	_check(saved.runtime.inventory.size() == 18, "scenario checkpoint includes sparse grid")
	var directory := "res://.godot/inventory_validation/scenarios"
	var result := ScenarioSaveStore.save_new(saved, directory)
	_check(result.ok, "scenario save validates sparse inventory")
	if result.ok:
		var loaded := ScenarioSaveStore.load_save(result.path, directory)
		_check(loaded.ok and loaded.payload.runtime.inventory == saved.runtime.inventory, "scenario disk round trip preserves gaps")
		pack.initialize_starting_items([])
		_check(battle._restore_runtime_state(loaded.payload.runtime), "scenario runtime restores")
		_check(pack.capture_state() == saved.runtime.inventory, "scenario restore returns exact grid positions")
	battle.queue_free()
	await _frames(2)


func _capture_overview() -> void:
	_reset()
	character.equip_item(bow)
	character.equip_item(armor)
	character.equip_item(charm)
	screen.open_for(character)
	await _motion(Vector2(20, 20))
	await _frames(4)
	await _capture("overview")


func _test_equipment_statistics() -> void:
	var suite := (load("res://tests/test_stats_system.gd") as Script).new() as McpTestSuite
	for method in [
		"test_equipment_modifier_order_replacement_and_shared_template_isolation",
		"test_effective_stats_without_equipment_keep_statuses_and_speed_movement_rules",
		"test_constitution_drives_health_modifiers_inspector_and_ai_snapshots",
	]:
		suite._reset()
		suite.setup()
		suite.call(method)
		suite.teardown()
		suite._free_tracked()
		_check(not suite._failed, method + ": " + suite._message)


func _cell(index: int) -> InventoryItemSlot:
	return screen.general_entries.get_child(index) as InventoryItemSlot


func _equipment(slot: int) -> InventoryItemSlot:
	return screen.equipment_entries.get_child(slot).get_node("Slot") as InventoryItemSlot


func _click(cell: Control, double_click: bool = false) -> void:
	await _motion(cell.get_global_rect().get_center())
	var event := InputEventMouseButton.new()
	event.position = _mouse_position
	event.global_position = _mouse_position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.double_click = double_click
	root.push_input(event, true)
	_mouse_down = true
	await _release()


func _motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point - _mouse_position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if _mouse_down else 0
	_mouse_position = point
	root.push_input(event, true)
	await process_frame


func _begin_drag(cell: Control) -> void:
	await _motion(cell.get_global_rect().get_center())
	var event := InputEventMouseButton.new()
	event.position = _mouse_position
	event.global_position = _mouse_position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.pressed = true
	root.push_input(event, true)
	_mouse_down = true
	await process_frame
	await _motion(_mouse_position + Vector2(18, 0))
	_check(root.gui_is_dragging(), "mouse movement starts native drag")
	_check(not screen.item_details.visible, "drag hides hover card")


func _drag(source: Control, destination: Control) -> void:
	await _begin_drag(source)
	await _motion(destination.get_global_rect().get_center())
	await _release()


func _release() -> void:
	var event := InputEventMouseButton.new()
	event.position = _mouse_position
	event.global_position = _mouse_position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	root.push_input(event, true)
	_mouse_down = false
	await _frames(3)


func _frames(count: int) -> void:
	for frame in count:
		await process_frame


func _capture(label: String) -> void:
	if _capture_directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path := _capture_directory.path_join("inventory_%s_%dx%d.png" % [label, root.size.x, root.size.y])
	_check(root.get_texture().get_image().save_png(path) == OK, "capture " + label)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)
