class_name InventoryScreen
extends Control

signal closed
signal equipment_updated(character: TacticalCharacter)

var _inventory: GeneralInventory
var _characters: Array[TacticalCharacter] = []
var _character: TacticalCharacter

@onready var character_picker: OptionButton = $Dim/Panel/Margin/VBox/CharacterRow/CharacterPicker
@onready var character_name: Label = $Dim/Panel/Margin/VBox/Columns/EquipmentPanel/Margin/VBox/CharacterName
@onready var general_entries: VBoxContainer = $Dim/Panel/Margin/VBox/Columns/GeneralPanel/Margin/VBox/Scroll/Entries
@onready var equipment_entries: VBoxContainer = $Dim/Panel/Margin/VBox/Columns/EquipmentPanel/Margin/VBox/EquipmentEntries
@onready var close_button: Button = $Dim/Panel/Margin/VBox/Header/CloseButton


func _ready() -> void:
	close_button.pressed.connect(close_screen)
	character_picker.item_selected.connect(_on_character_selected)


func setup(inventory: GeneralInventory, characters: Array[TacticalCharacter]) -> void:
	_inventory = inventory
	_characters.assign(characters)
	if not _inventory.items_changed.is_connected(_refresh):
		_inventory.items_changed.connect(_refresh)
	_rebuild_character_picker()
	if _character == null and not _characters.is_empty():
		_character = _characters[0]
	_refresh()


func open_for(preferred_character: TacticalCharacter = null) -> void:
	if is_instance_valid(preferred_character) and _characters.has(preferred_character):
		_character = preferred_character
	elif not is_instance_valid(_character) and not _characters.is_empty():
		_character = _characters[0]
	_sync_character_picker()
	_refresh()
	show()
	close_button.grab_focus()


func close_screen() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_screen()
		get_viewport().set_input_as_handled()


func _rebuild_character_picker() -> void:
	character_picker.clear()
	for character in _characters:
		character_picker.add_item(_get_character_display_name(character))
	_sync_character_picker()


func _sync_character_picker() -> void:
	var index := _characters.find(_character)
	if index >= 0:
		character_picker.select(index)


func _on_character_selected(index: int) -> void:
	if index < 0 or index >= _characters.size():
		return
	_character = _characters[index]
	_refresh()


func _refresh() -> void:
	if not is_node_ready():
		return
	_clear_entries(general_entries)
	_clear_entries(equipment_entries)
	_build_general_inventory()
	_build_equipment_slots()


func _build_general_inventory() -> void:
	if _inventory == null:
		_add_empty_label(general_entries, "Inventory unavailable")
		return
	var items := _inventory.get_items()
	if items.is_empty():
		_add_empty_label(general_entries, "No unused items")
		return
	for item in items:
		var button := _make_item_button(item, false)
		button.pressed.connect(_equip_item.bind(item))
		general_entries.add_child(button)


func _build_equipment_slots() -> void:
	if not is_instance_valid(_character):
		character_name.text = "No character selected"
		return
	character_name.text = _get_character_display_name(_character)
	for slot in [
		ItemDefinition.EquipmentSlot.WEAPON,
		ItemDefinition.EquipmentSlot.ARMOR,
		ItemDefinition.EquipmentSlot.ACCESSORY,
	]:
		var item := _character.get_equipped_item(slot)
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 64.0)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%s\n%s" % [
			_get_slot_name(slot),
			_get_item_name_with_damage(item) if item != null else "Empty",
		]
		button.tooltip_text = (
			_get_item_tooltip(item, "unequip")
			if item != null
			else "%s slot" % _get_slot_name(slot)
		)
		button.disabled = item == null
		if item != null:
			button.icon = item.icon
			button.expand_icon = true
			button.pressed.connect(_unequip_slot.bind(slot))
		equipment_entries.add_child(button)


func _equip_item(item: ItemDefinition) -> void:
	if _inventory == null or not is_instance_valid(_character):
		return
	if not _inventory.take_item(item):
		return
	var replaced := _character.equip_item(item)
	if replaced != null:
		_inventory.add_item(replaced)
	equipment_updated.emit(_character)
	_refresh()


func _unequip_slot(slot: ItemDefinition.EquipmentSlot) -> void:
	if _inventory == null or not is_instance_valid(_character):
		return
	var removed := _character.unequip_item(slot)
	if removed == null:
		return
	_inventory.add_item(removed)
	equipment_updated.emit(_character)
	_refresh()


func _make_item_button(item: ItemDefinition, equipped: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0.0, 56.0)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text = "%s\n%s" % [item.display_name, _get_item_slot_summary(item)]
	button.tooltip_text = _get_item_tooltip(item, "unequip" if equipped else "equip")
	button.icon = item.icon
	button.expand_icon = true
	return button


func _clear_entries(container: VBoxContainer) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _add_empty_label(container: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.58, 0.66, 0.74))
	container.add_child(label)


func _get_character_display_name(character: TacticalCharacter) -> String:
	if character.definition != null and not character.definition.display_name.is_empty():
		return "%s (%s)" % [character.definition.display_name, character.name]
	return str(character.name)


func _get_slot_name(slot: ItemDefinition.EquipmentSlot) -> String:
	return ItemDefinition.EquipmentSlot.keys()[slot].capitalize()


func _get_item_name_with_damage(item: ItemDefinition) -> String:
	if item.slot == ItemDefinition.EquipmentSlot.WEAPON:
		return "%s · %d DMG" % [item.display_name, item.weapon_damage]
	return item.display_name


func _get_item_slot_summary(item: ItemDefinition) -> String:
	var summary := _get_slot_name(item.slot)
	if item.slot == ItemDefinition.EquipmentSlot.WEAPON:
		summary += " · %d DMG" % item.weapon_damage
	return summary


func _get_item_tooltip(item: ItemDefinition, action: String) -> String:
	var lines: Array[String] = [item.display_name]
	if item.slot == ItemDefinition.EquipmentSlot.WEAPON:
		lines.append("Weapon damage: %d" % item.weapon_damage)
	lines.append("Click to %s" % action)
	return "\n".join(lines)
