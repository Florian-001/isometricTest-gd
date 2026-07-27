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
	var equipment_entries := screen.equipment_entries

	_check(inventory.get_items().size() == 3, "the general inventory should start with three unused sample items")
	main._on_inventory_button_toggled(true)
	_check(screen.visible, "the Inventory button should open the inventory screen")
	_check(screen.general_entries.get_child_count() == 3, "the screen should list every unused item")
	_check(equipment_entries.get_child_count() == 3, "the character inventory should show all equipment slots")

	var weapon_button := equipment_entries.get_child(0) as Button
	weapon_button.pressed.emit()
	_check(friend_a.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON) == null, "clicking equipped gear should unequip it")
	_check(inventory.get_items().size() == 4, "unequipped gear should return to the general inventory")

	var sword_button := screen.general_entries.get_child(0) as Button
	sword_button.pressed.emit()
	_check(friend_a.get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON) != null, "clicking an unused item should equip it")
	_check(inventory.get_items().size() == 3, "equipping an item should remove it from the general inventory")

	screen.close_screen()
	_check(not screen.visible, "the Close button behavior should hide the inventory screen")

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
