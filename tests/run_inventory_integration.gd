extends SceneTree

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene := load("res://main.tscn") as PackedScene
	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame

	var inventory := main.get_node("GeneralInventory") as GeneralInventory
	var screen := main.get_node("HUD/InventoryScreen") as InventoryScreen
	var friend_a := main.get_node("Characters/FriendA") as TacticalCharacter
	var friend_b := main.get_node("Characters/FriendB") as TacticalCharacter
	var equipment_entries := screen.equipment_entries

	var starting_property := _get_property_info(inventory, &"starting_items")
	_check(not starting_property.is_empty(), "GeneralInventory should expose Starting Items in the Inspector")
	_check(starting_property.get("type") == TYPE_ARRAY, "GeneralInventory Starting Items should be an array")
	_check(bool(int(starting_property.get("usage", 0)) & PROPERTY_USAGE_EDITOR), "GeneralInventory Starting Items should be Inspector-editable")
	_check(String(starting_property.get("hint_string", "")).contains("ItemDefinition"), "GeneralInventory Starting Items should accept only ItemDefinition resources")
	_check(_get_property_info(main, &"starting_items").is_empty(), "Main should not duplicate the inventory-owned starting-item field")
	_check(inventory.starting_items.size() == 6, "GeneralInventory should expose all configured unused sample items")
	_check(
		inventory.starting_items.map(func(item: ItemDefinition): return item.display_name)
		== ["Iron Sword", "Ranger Armor", "Sage Charm", "Wooden Sword", "Ranger Bow", "Frost Bow"],
		"Frost Bow should be added after the existing unused items"
	)
	_check(inventory.get_items().size() == 6, "the general inventory should start with six unused sample items")
	main._on_inventory_button_toggled(true)
	_check(screen.visible, "the Inventory button should open the inventory screen")
	_check(screen.general_entries.get_child_count() == 6, "the screen should list every unused item")
	_check(equipment_entries.get_child_count() == 3, "the character inventory should show all equipment slots")
	_check(_find_item_button(screen, "Iron Sword").text.contains("Melee"), "unused Melee weapons should show their type")
	_check(_find_item_button(screen, "Ranger Bow").text.contains("Ranged"), "unused Ranged weapons should show their type")
	_check(_find_item_button(screen, "Frost Bow").text.contains("Slow"), "weapon summaries should show their applied status")
	_check(_find_item_button(screen, "Frost Bow").tooltip_text.contains("Reduce Movement Range by 30%"), "weapon tooltips should describe their applied status")
	_check(_find_item_button(screen, "Iron Sword").text.contains("20 DMG"), "unused weapons should show their damage")
	_check(screen.stats_entries.get_child_count() == 7, "character details should show all seven combat-stat rows")
	_check(_stat_value(screen, "health") == "100 / 100", "the selected character should show current and maximum Health")
	_check(_stat_value(screen, "movement") == "6.5", "Movement should include the selected character's Speed adjustment")
	_check(_stat_value(screen, "strength") == "10", "FriendA should lose the inherited Iron Sword Strength bonus")
	_check(_stat_change(screen, "strength").is_empty(), "Frost Bow should not add Strength")
	_check(_stat_value(screen, "dexterity") == "12", "the selected character should show effective Dexterity")
	_check(_stat_change(screen, "dexterity") == "(+2)", "Dexterity should show its equipment-only increase")
	_check(_stat_value(screen, "intelligence") == "12", "the selected character should show effective Intelligence")
	_check(_stat_change(screen, "intelligence") == "(+2)", "Intelligence should show its equipment-only increase")
	_check(_stat_value(screen, "speed") == "12", "the selected character should show effective Speed")
	_check(_stat_value(screen, "weapon_damage") == "10", "FriendA should start with Frost Bow damage")
	_check(_stat_change(screen, "weapon_damage") == "(+10)", "Frost Bow damage should be identified as an equipment contribution")
	_check(screen.ability_entries.get_child_count() == 6, "the selected character should show its full ability loadout")
	_check(_ability_summary(screen, "Fireball") == "32 DMG", "magical damage should use current effective Intelligence")
	_check(_ability_summary(screen, "Arrow") == "17 DMG", "FriendA's Frost Bow should enable Arrow at its live total")
	_check(_ability_summary(screen, "Heal") == "37 HEAL", "healing should use current effective Intelligence")
	_check(_ability_summary(screen, "Strike") == "Requires a Melee weapon", "FriendA's Frost Bow should leave Strike visible but unavailable")
	_check(_ability_tooltip(screen, "Arrow").contains("Weapon applies Slow"), "FriendA's Arrow tooltip should describe Frost Bow Slow")
	_check(_ability_tooltip(screen, "Ice Shard").contains("Slow"), "ability tooltips should include their applied status")

	screen.character_picker.item_selected.emit(1)
	_check(_stat_value(screen, "speed") == "8", "changing the picker should show the newly selected character's Speed")
	_check(_stat_value(screen, "movement") == "4.5", "changing the picker should show the newly selected character's Movement")
	screen.character_picker.item_selected.emit(0)

	var weapon_button := equipment_entries.get_child(0) as Button
	_check(weapon_button.text.contains("Frost Bow"), "FriendA should start with Frost Bow equipped")
	_check(weapon_button.text.contains("Ranged"), "equipped weapons should show their type")
	_check(weapon_button.text.contains("10 DMG"), "equipped weapons should show their damage")
	_check(weapon_button.text.contains("Slow"), "equipped weapons should show their applied status")
	weapon_button.pressed.emit()
	_check(friend_a.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON) == null, "clicking equipped gear should unequip it")
	_check(inventory.get_items().size() == 7, "unequipped gear should return to the general inventory")
	_check(_stat_value(screen, "strength") == "10", "unequipping Frost Bow should leave Strength unchanged")
	_check(_stat_change(screen, "strength").is_empty(), "a removed equipment bonus should disappear from the comparison")
	_check(_stat_value(screen, "weapon_damage") == "0", "unequipping a weapon should immediately clear weapon damage")
	_check(_ability_summary(screen, "Arrow") == "Requires a Ranged weapon", "unequipping Frost Bow should disable Arrow")
	_check(_ability_summary(screen, "Strike") == "Requires a Melee weapon", "an unarmed character should also leave Strike unavailable")
	_check(_ability_summary(screen, "Fireball") == "32 DMG", "unrelated magical damage should remain unchanged")

	var sword_button := _find_item_button(screen, "Iron Sword")
	sword_button.pressed.emit()
	_check(friend_a.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON) != null, "clicking an unused item should equip it")
	_check(inventory.get_items().size() == 6, "equipping an item should remove it from the general inventory")
	_check(_stat_value(screen, "strength") == "12", "equipping Iron Sword should add its Strength bonus")
	_check(_ability_summary(screen, "Strike") == "32 DMG", "equipping Iron Sword should enable and update Strike")
	_check(inventory.starting_items.size() == 6, "runtime equipment transfers must not mutate GeneralInventory's configured starting array")

	var ranger_bow_button := _find_item_button(screen, "Ranger Bow")
	ranger_bow_button.pressed.emit()
	_check(friend_a.get_equipped_weapon_type() == ItemDefinition.WeaponType.RANGED, "equipping Ranger Bow should replace the Melee sword")
	_check(_ability_summary(screen, "Arrow") == "17 DMG", "Arrow should update to Ranger Bow damage plus Dexterity scaling")
	_check(_ability_summary(screen, "Strike") == "Requires a Melee weapon", "Strike should become unavailable after a Ranged weapon swap")
	var arrow := friend_a.get_abilities()[1]
	main._on_ability_selected(arrow)
	_check(main._selected_ability == arrow, "a compatible Ranged ability should enter targeting")
	_find_item_button(screen, "Iron Sword").pressed.emit()
	_check(main._selected_ability == null, "equipping an incompatible weapon should cancel active targeting")
	_check(_ability_summary(screen, "Strike") == "32 DMG", "restoring a Melee weapon should immediately restore Strike")

	_find_item_button(screen, "Frost Bow").pressed.emit()
	_check(friend_a.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON).display_name == "Frost Bow", "Frost Bow should be equippable from the unused inventory")
	_check(_ability_summary(screen, "Arrow") == "17 DMG", "Frost Bow should preserve Arrow's expected live damage")
	_check(_ability_tooltip(screen, "Arrow").contains("Weapon applies Slow"), "ability tooltips should update with the equipped weapon status")
	_find_item_button(screen, "Iron Sword").pressed.emit()
	_check(not _ability_tooltip(screen, "Arrow").contains("Weapon applies Slow"), "swapping weapons should immediately remove the old weapon status tooltip")

	friend_a.apply_damage(5)
	_check(_stat_value(screen, "health") == "95 / 100", "health signals should refresh an open character-details panel")
	friend_a.unequip_item(ItemDefinition.EquipmentSlot.WEAPON)
	_check(_stat_value(screen, "weapon_damage") == "0", "direct equipment changes should refresh the open Inventory")
	_check((screen.equipment_entries.get_child(0) as Button).disabled, "direct equipment changes should also refresh the equipment slots")
	friend_a.equip_item(load("res://resources/items/iron_sword.tres") as ItemDefinition)
	_check(_stat_value(screen, "weapon_damage") == "20", "direct re-equipping should restore the live details")

	var utility_definition := CharacterDefinition.new()
	utility_definition.abilities = [
		load("res://resources/abilities/focus.tres") as AbilityDefinition,
		load("res://resources/abilities/slow.tres") as AbilityDefinition,
		AbilityDefinition.new(),
	]
	utility_definition.abilities[2].display_name = "Custom Utility"
	var utility_character := TacticalCharacter.new()
	utility_character.name = "UtilityCharacter"
	utility_character.definition = utility_definition
	root.add_child(utility_character)
	utility_character.equip_item(load("res://resources/items/goblin_club.tres") as ItemDefinition)
	var details_scene := load("res://scenes/inventory_screen.tscn") as PackedScene
	var utility_screen := details_scene.instantiate() as InventoryScreen
	root.add_child(utility_screen)
	var utility_inventory := GeneralInventory.new()
	root.add_child(utility_inventory)
	var repeated_item := load("res://resources/items/iron_sword.tres") as ItemDefinition
	var repeated_start: Array[ItemDefinition] = [repeated_item, repeated_item]
	utility_inventory.initialize_starting_items(repeated_start)
	_check(utility_inventory.get_items().size() == 2, "repeating an Inspector item should create two runtime entries")
	_check(utility_inventory.take_item(repeated_item), "one repeated item should be removable independently")
	_check(utility_inventory.get_items().size() == 1, "removing one repeated item should retain the second copy")
	_check(repeated_start.size() == 2, "runtime inventory changes should not mutate the configured source array")
	var utility_characters: Array[TacticalCharacter] = [utility_character]
	utility_screen.setup(utility_inventory, utility_characters)
	_check(_ability_summary(utility_screen, "Focus") == "Focus", "additional status abilities should show their status name")
	_check(_ability_summary(utility_screen, "Slow") == "Slow", "direct status abilities should show their status name")
	_check(_ability_summary(utility_screen, "Custom Utility") == "Utility", "other non-numeric abilities should use the Utility summary")
	_check(utility_screen.ability_entries.get_child(0) is PanelContainer, "Inventory abilities should be read-only entries rather than action buttons")
	_check(_stat_change(utility_screen, "speed") == "(-1)", "equipment penalties should display as negative changes")
	_check(_stat_change_color(utility_screen, "speed") == InventoryScreen.NEGATIVE_CHANGE_COLOR, "equipment penalties should use the negative change color")
	_check(_stat_change_color(screen, "strength") == InventoryScreen.POSITIVE_CHANGE_COLOR, "equipment bonuses should use the positive change color")

	var empty_screen := details_scene.instantiate() as InventoryScreen
	root.add_child(empty_screen)
	var no_characters: Array[TacticalCharacter] = []
	empty_screen.setup(utility_inventory, no_characters)
	_check((empty_screen.stats_entries.get_child(0) as Label).text == "No character selected", "missing characters should show a stats empty state")
	_check((empty_screen.ability_entries.get_child(0) as Label).text == "No abilities available", "missing characters should show an abilities empty state")

	friend_b.apply_damage(friend_b.current_health)
	_check(screen.character_picker.item_count == 1, "defeated friendly characters should be removed from the Inventory picker")
	friend_a.apply_damage(friend_a.current_health)
	_check(main._combat_over, "defeating the final friendly should end combat")
	_check(main.turn_manager.current_unit == null, "combat end should clear the active AI turn loop")
	_check(main.turn_status.text == "Defeat", "the battlefield should report defeat when only enemies remain")
	_check(main.end_turn_button.disabled, "turn controls should remain disabled after combat ends")
	var ended_round: int = main.turn_manager.round_number
	await process_frame
	await process_frame
	await process_frame
	_check(main.turn_manager.current_unit == null, "AI turns should not restart after defeat")
	_check(main.turn_manager.round_number == ended_round, "rounds should not advance after defeat")

	screen.close_screen()
	_check(not screen.visible, "the Close button behavior should hide the inventory screen")

	empty_screen.queue_free()
	utility_screen.queue_free()
	utility_character.queue_free()
	utility_inventory.queue_free()
	main.queue_free()
	await process_frame

	var empty_main := main_scene.instantiate()
	var empty_starting_items: Array[ItemDefinition] = []
	(empty_main.get_node("GeneralInventory") as GeneralInventory).starting_items = empty_starting_items
	root.add_child(empty_main)
	await process_frame
	_check(
		(empty_main.get_node("GeneralInventory") as GeneralInventory).get_items().is_empty(),
		"an empty GeneralInventory Starting Items array should create an empty unused inventory"
	)
	_check(
		(empty_main.get_node("Characters/FriendA") as TacticalCharacter).get_equipped_items().size() == 3,
		"an empty unused inventory should not change character starting equipment"
	)
	empty_main.queue_free()
	await process_frame
	if _failed:
		quit(1)
	else:
		print("INVENTORY_INTEGRATION_OK")
		quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _get_property_info(object: Object, property_name: StringName) -> Dictionary:
	for property_info in object.get_property_list():
		if StringName(property_info.name) == property_name:
			return property_info
	return {}


func _find_stat_row(screen: InventoryScreen, key: String) -> Control:
	for row in screen.stats_entries.get_children():
		if row.get_meta("stat_key", "") == key:
			return row as Control
	return null


func _stat_value(screen: InventoryScreen, key: String) -> String:
	var row := _find_stat_row(screen, key)
	return str(row.get_meta("value_text", "")) if row != null else ""


func _stat_change(screen: InventoryScreen, key: String) -> String:
	var row := _find_stat_row(screen, key)
	return str(row.get_meta("change_text", "")) if row != null else ""


func _stat_change_color(screen: InventoryScreen, key: String) -> Color:
	var row := _find_stat_row(screen, key)
	if row == null:
		return Color.TRANSPARENT
	return (row.get_node("Change") as Label).get_theme_color("font_color")


func _find_ability_entry(screen: InventoryScreen, ability_name: String) -> Control:
	for entry in screen.ability_entries.get_children():
		var ability := entry.get_meta("ability") as AbilityDefinition
		if ability != null and ability.display_name == ability_name:
			return entry as Control
	return null


func _ability_summary(screen: InventoryScreen, ability_name: String) -> String:
	var entry := _find_ability_entry(screen, ability_name)
	return str(entry.get_meta("summary_text", "")) if entry != null else ""


func _ability_tooltip(screen: InventoryScreen, ability_name: String) -> String:
	var entry := _find_ability_entry(screen, ability_name)
	return entry.tooltip_text if entry != null else ""


func _find_item_button(screen: InventoryScreen, item_name: String) -> Button:
	for entry in screen.general_entries.get_children():
		if entry is Button:
			var item := entry.get_meta("item") as ItemDefinition
			if item != null and item.display_name == item_name:
				return entry as Button
	return null
