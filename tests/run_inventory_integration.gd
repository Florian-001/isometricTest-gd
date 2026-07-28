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

	_check(inventory.get_items().size() == 3, "the general inventory should start with three unused sample items")
	main._on_inventory_button_toggled(true)
	_check(screen.visible, "the Inventory button should open the inventory screen")
	_check(screen.general_entries.get_child_count() == 3, "the screen should list every unused item")
	_check(equipment_entries.get_child_count() == 3, "the character inventory should show all equipment slots")
	_check((screen.general_entries.get_child(0) as Button).text.contains("20 DMG"), "unused weapons should show their damage")
	_check(screen.stats_entries.get_child_count() == 7, "character details should show all seven combat-stat rows")
	_check(_stat_value(screen, "health") == "100 / 100", "the selected character should show current and maximum Health")
	_check(_stat_value(screen, "movement") == "6.5", "Movement should include the selected character's Speed adjustment")
	_check(_stat_value(screen, "strength") == "12", "the selected character should show effective Strength")
	_check(_stat_change(screen, "strength") == "(+2)", "Strength should show its equipment-only increase")
	_check(_stat_value(screen, "dexterity") == "12", "the selected character should show effective Dexterity")
	_check(_stat_change(screen, "dexterity") == "(+2)", "Dexterity should show its equipment-only increase")
	_check(_stat_value(screen, "intelligence") == "12", "the selected character should show effective Intelligence")
	_check(_stat_change(screen, "intelligence") == "(+2)", "Intelligence should show its equipment-only increase")
	_check(_stat_value(screen, "speed") == "12", "the selected character should show effective Speed")
	_check(_stat_value(screen, "weapon_damage") == "20", "the selected character should show equipped weapon damage")
	_check(_stat_change(screen, "weapon_damage") == "(+20)", "weapon damage should be identified as an equipment contribution")
	_check(screen.ability_entries.get_child_count() == 6, "the selected character should show its full ability loadout")
	_check(_ability_summary(screen, "Fireball") == "32 DMG", "magical damage should use current effective Intelligence")
	_check(_ability_summary(screen, "Arrow") == "27 DMG", "physical damage should include current weapon damage and Dexterity")
	_check(_ability_summary(screen, "Heal") == "37 HEAL", "healing should use current effective Intelligence")
	_check(_ability_summary(screen, "Strike") == "32 DMG", "Strength-based physical damage should show its live total")
	_check(_ability_tooltip(screen, "Ice Shard").contains("Slow"), "ability tooltips should include their applied status")

	screen.character_picker.item_selected.emit(1)
	_check(_stat_value(screen, "speed") == "8", "changing the picker should show the newly selected character's Speed")
	_check(_stat_value(screen, "movement") == "4.5", "changing the picker should show the newly selected character's Movement")
	screen.character_picker.item_selected.emit(0)

	var weapon_button := equipment_entries.get_child(0) as Button
	_check(weapon_button.text.contains("20 DMG"), "equipped weapons should show their damage")
	weapon_button.pressed.emit()
	_check(friend_a.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON) == null, "clicking equipped gear should unequip it")
	_check(inventory.get_items().size() == 4, "unequipped gear should return to the general inventory")
	_check(_stat_value(screen, "strength") == "10", "unequipping a stat weapon should immediately update Strength")
	_check(_stat_change(screen, "strength").is_empty(), "a removed equipment bonus should disappear from the comparison")
	_check(_stat_value(screen, "weapon_damage") == "0", "unequipping a weapon should immediately clear weapon damage")
	_check(_ability_summary(screen, "Strike") == "10 DMG", "physical ability summaries should immediately lose weapon and Strength bonuses")
	_check(_ability_summary(screen, "Fireball") == "32 DMG", "unrelated magical damage should remain unchanged")

	var sword_button := screen.general_entries.get_child(0) as Button
	sword_button.pressed.emit()
	_check(friend_a.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON) != null, "clicking an unused item should equip it")
	_check(inventory.get_items().size() == 3, "equipping an item should remove it from the general inventory")
	_check(_stat_value(screen, "strength") == "12", "re-equipping should restore the Strength total")
	_check(_ability_summary(screen, "Strike") == "32 DMG", "re-equipping should restore the live physical ability total")

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

	screen.close_screen()
	_check(not screen.visible, "the Close button behavior should hide the inventory screen")

	empty_screen.queue_free()
	utility_screen.queue_free()
	utility_character.queue_free()
	utility_inventory.queue_free()
	main.queue_free()
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
