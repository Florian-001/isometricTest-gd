extends SceneTree

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_inventory_model()
	_test_item_icon_catalog()

	var main_scene := load("res://scenes/battle.tscn") as PackedScene
	var terrain_showcase := load("res://resources/maps/terrain_showcase.tres") as BattleMapDefinition
	var main := main_scene.instantiate() as TacticalBattle
	main.map_definition = terrain_showcase
	root.add_child(main)
	await process_frame

	var inventory := main.general_inventory
	var screen := main.inventory_screen
	var friend_a := main.characters_container.get_node("FriendA") as TacticalCharacter
	var friend_b := main.characters_container.get_node("FriendB") as TacticalCharacter
	var iron_sword := load("res://resources/items/iron_sword.tres") as ItemDefinition
	var long_sword := load("res://resources/items/long_sword.tres") as ItemDefinition
	var ranger_armor := load("res://resources/items/ranger_armor.tres") as ItemDefinition
	var frost_bow := load("res://resources/items/frost_bow.tres") as ItemDefinition
	var charge := load("res://resources/abilities/charge.tres") as AbilityDefinition

	_check(inventory.get_slot_count() == 100, "General Inventory should expose exactly 100 indexed cells")
	_check(inventory.get_items().size() == 7, "the battle should retain all seven configured starting items")
	main._on_inventory_button_toggled(true)
	_check(screen.visible, "the Inventory button should open the redesigned screen")
	_check(screen.inventory_grid.columns == 10, "the inventory grid should use ten columns")
	_check(screen.inventory_grid.get_child_count() == 100, "the inventory grid should render every cell")
	_check(screen.unit_tabs.tab_count == 2, "living friendly units should be represented by tabs")
	_check(screen.equipment_grid.get_child_count() == 3, "the selected unit should show three equipment slots")
	_check(screen.unit_portrait.texture != null, "the selected unit should use its existing character artwork")
	_check(_inventory_slot(screen, 0).item == iron_sword, "configured items should populate from the first cell")
	_check(_inventory_slot(screen, 7).item == null, "unused capacity should render as empty cells")
	var first_cell: Node = screen.inventory_grid.get_child(0)
	_check(not (first_cell is BaseButton), "inventory cells should not retain click-to-equip behavior")

	screen.show_item_details(iron_sword)
	_check(screen.detail_name.text == "Iron Sword", "hover details should show the item name")
	_check(screen.detail_type.text.contains("Weapon"), "hover details should show the equipment type")
	_check(screen.detail_body.text.contains("Weapon damage: 20"), "hover details should show weapon damage")
	_check(screen.detail_body.text.contains("+2 Strength"), "hover details should show stat modifiers")
	screen.show_item_details(frost_bow)
	_check(screen.detail_body.text.contains("Reduce Movement Range by 30%"), "hover details should describe applied statuses")
	screen.show_item_details(long_sword)
	_check(screen.detail_body.text.contains("Grants: Charge"), "hover details should show granted abilities")
	screen.clear_item_details(long_sword)
	_check(screen.detail_type.text == "Nothing selected", "leaving an item should restore the empty details state")

	# Inventory-to-inventory movement retains the exact indexed copy and rejects stale payloads.
	var first_payload := InventoryDragPayload.from_inventory(iron_sword, 0)
	_check(screen.can_drop_on_slot(first_payload, _inventory_slot(screen, 7)), "an item should be movable to an empty inventory cell")
	_check(screen.drop_on_slot(first_payload, _inventory_slot(screen, 7)), "an inventory move should succeed")
	_check(inventory.get_item_at(0) == null and inventory.get_item_at(7) == iron_sword, "moving should swap the source and destination cells")
	_check(not screen.can_drop_on_slot(first_payload, _inventory_slot(screen, 8)), "payloads should become stale after their source changes")

	# Wrong item types never mutate equipment or inventory.
	var armor_payload := InventoryDragPayload.from_inventory(ranger_armor, 2)
	var weapon_slot := _equipment_slot(screen, ItemDefinition.EquipmentSlot.WEAPON)
	_check(not screen.can_drop_on_slot(armor_payload, weapon_slot), "Armor should be rejected by the Weapon slot")
	_check(not screen.drop_on_slot(armor_payload, weapon_slot), "an invalid equipment drop should report failure")
	_check(inventory.get_item_at(2) == ranger_armor, "an invalid drop should leave its source untouched")
	_check(friend_a.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON) == frost_bow, "an invalid drop should leave equipment untouched")

	# Equipping over an occupied slot returns the old gear to the exact source cell.
	var equipment_events := [0]
	screen.equipment_updated.connect(func(_character: TacticalCharacter): equipment_events[0] += 1)
	var iron_payload := InventoryDragPayload.from_inventory(iron_sword, 7)
	_check(screen.drop_on_slot(iron_payload, weapon_slot), "a matching Weapon should equip")
	_check(friend_a.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON) == iron_sword, "the selected unit should receive the dragged item")
	_check(inventory.get_item_at(7) == frost_bow, "replaced equipment should return to the source inventory cell")
	_check(friend_a.get_effective_stat(UnitStat.Type.STRENGTH) == 12.0, "drag-equipping should update effective stats")

	# Equipment can be returned to an empty cell.
	var equipped_iron := InventoryDragPayload.from_equipment(iron_sword, ItemDefinition.EquipmentSlot.WEAPON, friend_a)
	_check(screen.drop_on_slot(equipped_iron, _inventory_slot(screen, 0)), "equipped gear should drag into an empty inventory cell")
	_check(friend_a.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON) == null, "dragging gear out should unequip it")
	_check(inventory.get_item_at(0) == iron_sword, "unequipped gear should occupy the requested destination cell")

	# Item-granted abilities remain live when equipment is changed through drag and drop.
	friend_a.override_template_abilities = true
	friend_a.ability_overrides = []
	var long_payload := InventoryDragPayload.from_inventory(long_sword, 1)
	weapon_slot = _equipment_slot(screen, ItemDefinition.EquipmentSlot.WEAPON)
	_check(screen.drop_on_slot(long_payload, weapon_slot), "Long Sword should equip into an empty Weapon slot")
	_check(friend_a.get_abilities() == [charge], "equipping Long Sword should grant Charge")
	main._on_ability_selected(charge)
	_check(main._selected_ability == charge, "an item-granted ability should enter targeting")

	# A compatible occupied inventory cell reverse-swaps with equipment.
	var equipped_long := InventoryDragPayload.from_equipment(long_sword, ItemDefinition.EquipmentSlot.WEAPON, friend_a)
	_check(screen.can_drop_on_slot(equipped_long, _inventory_slot(screen, 7)), "equipped Weapons should swap with inventory Weapons")
	_check(screen.drop_on_slot(equipped_long, _inventory_slot(screen, 7)), "the compatible reverse swap should succeed")
	_check(friend_a.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON) == frost_bow, "the inventory Weapon should become equipped")
	_check(inventory.get_item_at(7) == long_sword, "the former equipment should occupy the target inventory cell")
	_check(friend_a.get_abilities().is_empty(), "replacing Long Sword should remove its granted ability")
	_check(main._selected_ability == null, "removing an ability-granting item should cancel active targeting")

	var equipped_frost := InventoryDragPayload.from_equipment(frost_bow, ItemDefinition.EquipmentSlot.WEAPON, friend_a)
	_check(not screen.can_drop_on_slot(equipped_frost, _inventory_slot(screen, 2)), "equipped Weapons should not reverse-swap with Armor")
	_check(not screen.drop_on_slot(equipped_frost, _inventory_slot(screen, 2)), "an incompatible reverse swap should fail")
	_check(friend_a.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON) == frost_bow, "failed reverse swaps should preserve equipment")
	_check(inventory.get_item_at(2) == ranger_armor, "failed reverse swaps should preserve inventory")

	# Occupied inventory cells swap without collapsing gaps.
	var long_index := _find_item_index(inventory, long_sword)
	var wooden_index := _find_item_index(inventory, load("res://resources/items/wooden_sword.tres") as ItemDefinition)
	var wooden_item := inventory.get_item_at(wooden_index)
	_check(screen.drop_on_slot(InventoryDragPayload.from_inventory(long_sword, long_index), _inventory_slot(screen, wooden_index)), "occupied inventory cells should swap")
	_check(inventory.get_item_at(long_index) == wooden_item and inventory.get_item_at(wooden_index) == long_sword, "occupied swaps should retain both items")

	# Unit tabs change only the equipment panel's selected unit.
	screen._on_unit_tab_changed(1)
	_check(screen._character == friend_b, "selecting the second tab should change the displayed unit")
	_check(_equipment_slot(screen, ItemDefinition.EquipmentSlot.WEAPON).item == iron_sword, "unit tabs should rebuild the selected unit's equipment")
	_check(inventory.get_items().size() == 7, "switching tabs should not change general inventory contents")
	screen._on_unit_tab_changed(0)

	friend_b.apply_damage(friend_b.current_health)
	_check(screen.unit_tabs.tab_count == 1, "defeated friendlies should be removed from unit tabs")
	_check(screen._character == friend_a, "the remaining friendly should stay selected after tab rebuilding")
	_check(equipment_events[0] >= 3, "successful equipment transfers should emit update notifications")

	screen.close_screen()
	_check(not screen.visible, "the Close button behavior should hide the inventory screen")
	main.queue_free()
	await process_frame

	if _failed:
		quit(1)
	else:
		print("INVENTORY_INTEGRATION_OK")
		quit(0)


func _test_inventory_model() -> void:
	var inventory := GeneralInventory.new()
	root.add_child(inventory)
	var first := ItemDefinition.new()
	first.display_name = "First"
	var repeated := ItemDefinition.new()
	repeated.display_name = "Repeated"
	var configured: Array[ItemDefinition] = [first, repeated, repeated]
	inventory.initialize_starting_items(configured)
	_check(inventory.get_slot_count() == GeneralInventory.CAPACITY, "the model should always contain 100 indexed slots")
	_check(inventory.get_item_at(0) == first and inventory.get_item_at(1) == repeated and inventory.get_item_at(2) == repeated, "starting items should retain their configured order")
	_check(inventory.find_first_empty_slot() == 3, "the model should locate its first gap")
	_check(inventory.swap_items(1, 10), "indexed items should swap with empty cells")
	_check(inventory.get_item_at(1) == null and inventory.get_item_at(10) == repeated, "swapping should preserve the exact repeated copy's cell")
	_check(inventory.get_items().size() == 3, "the compact compatibility view should omit empty cells")
	_check(inventory.take_item(repeated), "take_item should retain its compact compatibility behavior")
	_check(inventory.get_items().size() == 2, "take_item should remove only one repeated copy")
	var full: Array[ItemDefinition] = []
	for index in GeneralInventory.CAPACITY:
		full.append(first)
	inventory.initialize_starting_items(full)
	_check(inventory.find_first_empty_slot() == -1, "a full inventory should have no empty cell")
	_check(not inventory.add_item(repeated), "add_item should reject overflow without replacing an item")
	_check(inventory.get_items().size() == GeneralInventory.CAPACITY, "overflow rejection should preserve all existing items")
	inventory.queue_free()


func _test_item_icon_catalog() -> void:
	var directory := DirAccess.open("res://resources/items")
	_check(directory != null, "the saved item directory should be readable")
	if directory == null:
		return
	var item_paths: Array[String] = []
	for filename in directory.get_files():
		if filename.ends_with(".tres"):
			item_paths.append("res://resources/items/%s" % filename)
	item_paths.sort()
	_check(item_paths.size() == 13, "the current catalog should contain thirteen saved items")
	for path in item_paths:
		var item := load(path) as ItemDefinition
		_check(item != null and item.icon != null, "%s should load a generated icon" % path)
		if item == null or item.icon == null:
			continue
		var image := item.icon.get_image()
		_check(image != null and image.get_width() == 256 and image.get_height() == 256, "%s should use a normalized 256x256 icon" % item.display_name)
		if image != null:
			_check(image.detect_alpha() != Image.ALPHA_NONE, "%s should preserve transparent alpha" % item.display_name)


func _inventory_slot(screen: InventoryScreen, index: int) -> InventoryItemSlot:
	return screen.inventory_grid.get_child(index) as InventoryItemSlot


func _equipment_slot(screen: InventoryScreen, slot_type: ItemDefinition.EquipmentSlot) -> InventoryItemSlot:
	for child in screen.equipment_grid.get_children():
		var slot := child as InventoryItemSlot
		if slot.equipment_slot == slot_type:
			return slot
	return null


func _find_item_index(inventory: GeneralInventory, item: ItemDefinition) -> int:
	for index in GeneralInventory.CAPACITY:
		if inventory.get_item_at(index) == item:
			return index
	return -1


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
