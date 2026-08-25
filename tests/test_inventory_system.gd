@tool
extends McpTestSuite

const PartyInventoryScript = preload("res://scripts/party_inventory.gd")
const ItemDefinitionScript = preload("res://scripts/item_definition.gd")
const StatModifierScript = preload("res://scripts/stat_modifier_definition.gd")
const InventoryPanelScene = preload("res://scenes/inventory_panel.tscn")


func suite_name() -> String:
	return "inventory_system"


func test_default_grid_has_one_hundred_empty_slots() -> void:
	var inventory := track(PartyInventoryScript.new()) as PartyInventory
	inventory.initialize()
	assert_eq(inventory.rows, 10, "the default inventory should have ten rows")
	assert_eq(inventory.columns, 10, "the default inventory should have ten columns")
	assert_eq(inventory.get_slot_count(), 100, "the default inventory should have 100 slots")
	for index in range(inventory.get_slot_count()):
		assert_eq(inventory.get_item(index), null, "the default inventory should start empty")


func test_add_move_swap_invalid_and_change_notifications() -> void:
	var inventory := track(PartyInventoryScript.new()) as PartyInventory
	inventory.initialize()
	var sword := _make_item("Sword")
	var armor := _make_item("Armor")
	var changes := [0]
	inventory.inventory_changed.connect(func(): changes[0] += 1)

	assert_false(inventory.add_item(null), "null items should be rejected")
	assert_true(inventory.add_item(sword), "the first item should enter the first empty slot")
	assert_true(inventory.add_item(armor), "the second item should enter the next empty slot")
	assert_eq(inventory.get_item(0), sword, "the first item should occupy slot zero")
	assert_eq(inventory.get_item(1), armor, "the second item should occupy slot one")
	assert_true(inventory.move_or_swap(0, 5), "dropping on an empty slot should move the item")
	assert_eq(inventory.get_item(0), null, "a move should clear its source slot")
	assert_eq(inventory.get_item(5), sword, "a move should fill its destination slot")
	assert_true(inventory.move_or_swap(5, 1), "dropping on an item should swap both entries")
	assert_eq(inventory.get_item(5), armor, "the destination item should move to the source")
	assert_eq(inventory.get_item(1), sword, "the dragged item should occupy the destination")
	assert_false(inventory.move_or_swap(1, 1), "dropping on the same slot should be a no-op")
	assert_false(inventory.move_or_swap(-1, 2), "negative source indices should be rejected")
	assert_false(inventory.move_or_swap(1, 100), "indices beyond capacity should be rejected")
	assert_false(inventory.move_or_swap(0, 2), "empty source slots should be rejected")
	assert_eq(changes[0], 4, "two additions, one move, and one swap should each notify once")


func test_starting_items_copy_into_runtime_without_mutating_authored_order() -> void:
	var first := _make_item("First")
	var second := _make_item("Second")
	var inventory := track(PartyInventoryScript.new()) as PartyInventory
	var configured: Array[ItemDefinition] = [first, null, second]
	inventory.starting_items = configured
	inventory.initialize()

	assert_eq(inventory.get_item(0), first, "non-null starting items should be packed from the first slot")
	assert_eq(inventory.get_item(1), second, "empty authored entries should be skipped")
	assert_true(inventory.move_or_swap(0, 8), "runtime starting items should be movable")
	assert_eq(inventory.starting_items, configured, "runtime moves must not mutate the authored starting list")


func test_panel_builds_slots_binds_icons_and_toggles() -> void:
	var inventory := track(PartyInventoryScript.new()) as PartyInventory
	inventory.initialize()
	var panel := track(InventoryPanelScene.instantiate()) as InventoryPanel
	panel.setup(inventory)

	assert_eq(panel.get_rendered_slot_count(), 100, "the panel should render every model slot")
	assert_false(panel.is_open(), "the inventory should begin hidden")
	panel.show_inventory()
	assert_true(panel.is_open(), "show_inventory should reveal the panel")
	panel.toggle_inventory()
	assert_false(panel.is_open(), "toggle_inventory should close an open panel")
	var inventory_key := InputEventKey.new()
	inventory_key.keycode = KEY_I
	inventory_key.pressed = true
	panel._unhandled_key_input(inventory_key)
	assert_true(panel.is_open(), "the I shortcut should open the inventory")
	var escape_key := InputEventKey.new()
	escape_key.keycode = KEY_ESCAPE
	escape_key.pressed = true
	panel._unhandled_key_input(escape_key)
	assert_false(panel.is_open(), "Escape should close the inventory before battle input handles it")

	var item := _make_item("Icon Item")
	var texture := GradientTexture1D.new()
	item.icon = texture
	assert_true(inventory.add_item(item), "the UI fixture item should enter the inventory")
	assert_eq(
		panel.get_slot_control(0).get_displayed_texture(),
		texture,
		"an occupied slot should display its item icon"
	)
	assert_eq(panel.mouse_filter, Control.MOUSE_FILTER_STOP, "the open overlay should stop battlefield pointer input")


func test_tooltip_formats_item_identity_description_and_all_modifier_operations() -> void:
	var inventory := track(PartyInventoryScript.new()) as PartyInventory
	inventory.initialize()
	var panel := track(InventoryPanelScene.instantiate()) as InventoryPanel
	panel.setup(inventory)

	var item := _make_item("Ranger Coat")
	item.description = "Weatherproof travel armor."
	item.slot = ItemDefinition.EquipmentSlot.ARMOR
	var modifiers: Array[StatModifierDefinition] = [
		_make_modifier(UnitStat.Type.STRENGTH, StatModifierDefinition.Operation.FLAT, 2.0),
		_make_modifier(UnitStat.Type.DEXTERITY, StatModifierDefinition.Operation.PERCENT_ADD, -0.25),
		_make_modifier(UnitStat.Type.INTELLIGENCE, StatModifierDefinition.Operation.PERCENT_MULTIPLY, 0.5),
	]
	item.modifiers = modifiers
	var details := panel.format_item_details(item)

	assert_contains(details, "Ranger Coat", "the tooltip should show the item name")
	assert_contains(details, "Type: Armor", "the tooltip should show the equipment type")
	assert_contains(details, "Weatherproof travel armor.", "the tooltip should show the authored description")
	assert_contains(details, "+2 Strength", "flat bonuses should show signed stat points")
	assert_contains(details, "-25% Dexterity", "additive percentages should show signed percentages")
	assert_contains(details, "Intelligence ×1.5", "multipliers should show the resulting multiplier")


func test_slot_drop_accepts_same_inventory_and_routes_to_model_swap() -> void:
	var inventory := track(PartyInventoryScript.new()) as PartyInventory
	inventory.initialize()
	var first := _make_item("First")
	var second := _make_item("Second")
	inventory.add_item(first)
	inventory.add_item(second)
	var panel := track(InventoryPanelScene.instantiate()) as InventoryPanel
	panel.setup(inventory)
	var source := panel.get_slot_control(0)
	var destination := panel.get_slot_control(1)
	var drag_data := {
		"inventory": inventory,
		"source_index": 0,
		"item": first,
	}

	assert_true(destination._can_drop_data(Vector2.ZERO, drag_data), "a different slot in the same inventory should accept the drag")
	destination._drop_data(Vector2.ZERO, drag_data)
	assert_eq(inventory.get_item(0), second, "the destination item should swap back to the source slot")
	assert_eq(inventory.get_item(1), first, "the dragged item should arrive in the destination slot")
	assert_false(source._can_drop_data(Vector2.ZERO, drag_data), "the original source index should reject a same-slot drop")

	var other_inventory := track(PartyInventoryScript.new()) as PartyInventory
	other_inventory.initialize()
	var foreign_drag := drag_data.duplicate()
	foreign_drag["inventory"] = other_inventory
	assert_false(destination._can_drop_data(Vector2.ZERO, foreign_drag), "slots should reject drag data from another inventory")


func test_main_scene_exposes_empty_shared_inventory_and_both_controls() -> void:
	var root := track((load("res://main.tscn") as PackedScene).instantiate())
	var inventory := root.get_node("PartyInventory") as PartyInventory
	var panel := root.get_node("HUD/InventoryPanel") as InventoryPanel
	var button := root.get_node("HUD/InventoryButton") as Button

	assert_eq(inventory.get_slot_count(), 100, "the battle scene should use a 10 by 10 inventory")
	assert_true(inventory.starting_items.is_empty(), "the battle scene inventory should start empty")
	assert_eq(button.text, "Inventory", "the HUD should expose an Inventory button")
	assert_true(panel != null, "the HUD should contain the keyboard-aware inventory panel")


func _make_item(display_name: String) -> ItemDefinition:
	var item := ItemDefinitionScript.new() as ItemDefinition
	item.display_name = display_name
	item.icon = GradientTexture1D.new()
	return item


func _make_modifier(
	stat: UnitStat.Type,
	operation: StatModifierDefinition.Operation,
	value: float
) -> StatModifierDefinition:
	var modifier := StatModifierScript.new() as StatModifierDefinition
	modifier.stat = stat
	modifier.operation = operation
	modifier.value = value
	return modifier
