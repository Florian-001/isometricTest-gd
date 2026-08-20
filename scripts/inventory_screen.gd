class_name InventoryScreen
extends Control

signal closed
signal equipment_updated(character: TacticalCharacter)

var _inventory: GeneralInventory
var _characters: Array[TacticalCharacter] = []
var _character: TacticalCharacter
var _detail_item: ItemDefinition
var _suspend_refresh := false
var _refresh_pending := false

@onready var inventory_grid: GridContainer = $Dim/Panel/Margin/VBox/Content/InventoryPanel/Margin/VBox/InventoryGrid
@onready var unit_tabs: TabBar = $Dim/Panel/Margin/VBox/Content/UnitPanel/Margin/VBox/UnitTabs
@onready var unit_portrait: TextureRect = $Dim/Panel/Margin/VBox/Content/UnitPanel/Margin/VBox/UnitSummary/Portrait
@onready var unit_name: Label = $Dim/Panel/Margin/VBox/Content/UnitPanel/Margin/VBox/UnitSummary/Name
@onready var equipment_grid: GridContainer = $Dim/Panel/Margin/VBox/Content/UnitPanel/Margin/VBox/EquipmentGrid
@onready var detail_name: Label = $Dim/Panel/Margin/VBox/Content/UnitPanel/Margin/VBox/DetailsPanel/Margin/VBox/Name
@onready var detail_type: Label = $Dim/Panel/Margin/VBox/Content/UnitPanel/Margin/VBox/DetailsPanel/Margin/VBox/Type
@onready var detail_body: Label = $Dim/Panel/Margin/VBox/Content/UnitPanel/Margin/VBox/DetailsPanel/Margin/VBox/Body
@onready var close_button: Button = $Dim/Panel/Margin/VBox/Header/CloseButton


func _ready() -> void:
	close_button.pressed.connect(close_screen)
	unit_tabs.tab_changed.connect(_on_unit_tab_changed)
	show_item_details(null)


func setup(inventory: GeneralInventory, characters: Array[TacticalCharacter]) -> void:
	if _inventory != null and _inventory.items_changed.is_connected(_request_refresh):
		_inventory.items_changed.disconnect(_request_refresh)
	_inventory = inventory
	_characters.assign(characters)
	if _inventory != null and not _inventory.items_changed.is_connected(_request_refresh):
		_inventory.items_changed.connect(_request_refresh)
	var next_character := _character
	if not is_instance_valid(next_character) or not _characters.has(next_character):
		next_character = _characters[0] if not _characters.is_empty() else null
	_set_character(next_character)
	_rebuild_unit_tabs()
	_refresh()


func open_for(preferred_character: TacticalCharacter = null) -> void:
	if is_instance_valid(preferred_character) and _characters.has(preferred_character):
		_set_character(preferred_character)
	elif not is_instance_valid(_character) and not _characters.is_empty():
		_set_character(_characters[0])
	_sync_unit_tabs()
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


func _rebuild_unit_tabs() -> void:
	unit_tabs.clear_tabs()
	for character in _characters:
		unit_tabs.add_tab(_get_character_display_name(character))
	_sync_unit_tabs()


func _sync_unit_tabs() -> void:
	var index := _characters.find(_character)
	if index >= 0:
		unit_tabs.current_tab = index


func _on_unit_tab_changed(index: int) -> void:
	if index < 0 or index >= _characters.size():
		return
	_set_character(_characters[index])
	_refresh()


func _set_character(character: TacticalCharacter) -> void:
	if _character == character:
		_connect_character_signals()
		return
	_disconnect_character_signals()
	_character = character
	_connect_character_signals()


func _connect_character_signals() -> void:
	if is_instance_valid(_character) and not _character.equipment_changed.is_connected(_on_selected_character_equipment_changed):
		_character.equipment_changed.connect(_on_selected_character_equipment_changed)


func _disconnect_character_signals() -> void:
	if is_instance_valid(_character) and _character.equipment_changed.is_connected(_on_selected_character_equipment_changed):
		_character.equipment_changed.disconnect(_on_selected_character_equipment_changed)


func _on_selected_character_equipment_changed(
	_slot: ItemDefinition.EquipmentSlot,
	_item: ItemDefinition
) -> void:
	_request_refresh()


func _request_refresh() -> void:
	if _suspend_refresh:
		_refresh_pending = true
		return
	_refresh()


func _refresh() -> void:
	if not is_node_ready():
		return
	_refresh_pending = false
	_clear_entries(inventory_grid)
	_clear_entries(equipment_grid)
	_build_inventory_grid()
	_build_equipment_slots()
	_refresh_unit_summary()
	if _detail_item != null:
		show_item_details(_detail_item)


func _build_inventory_grid() -> void:
	for index in GeneralInventory.CAPACITY:
		var cell_item := _inventory.get_item_at(index) if _inventory != null else null
		var slot := InventoryItemSlot.new()
		slot.name = "Cell%03d" % index
		slot.configure_inventory(self, index, cell_item)
		inventory_grid.add_child(slot)


func _build_equipment_slots() -> void:
	for slot_type in [
		ItemDefinition.EquipmentSlot.WEAPON,
		ItemDefinition.EquipmentSlot.ARMOR,
		ItemDefinition.EquipmentSlot.ACCESSORY,
	]:
		var cell_item := _character.get_equipped_item(slot_type) if is_instance_valid(_character) else null
		var slot := InventoryItemSlot.new()
		slot.name = "%sSlot" % ItemDefinition.EquipmentSlot.keys()[slot_type].capitalize()
		slot.configure_equipment(self, slot_type, _character, cell_item)
		equipment_grid.add_child(slot)


func _refresh_unit_summary() -> void:
	if not is_instance_valid(_character):
		unit_name.text = "No unit available"
		unit_portrait.texture = null
		return
	unit_name.text = _get_character_display_name(_character)
	unit_portrait.texture = _character.facing_right_texture if _character.facing_right_texture != null else _character.facing_left_texture


func can_drop_on_slot(payload: InventoryDragPayload, target: InventoryItemSlot) -> bool:
	if not _is_payload_current(payload) or target == null:
		return false
	if target.source_kind == InventoryDragPayload.SourceKind.INVENTORY:
		if payload.source_kind == InventoryDragPayload.SourceKind.INVENTORY:
			return payload.inventory_index != target.inventory_index
		if payload.source_kind == InventoryDragPayload.SourceKind.EQUIPMENT:
			return target.item == null or target.item.slot == payload.equipment_slot
		return false
	if target.source_kind == InventoryDragPayload.SourceKind.EQUIPMENT:
		return (
			payload.source_kind == InventoryDragPayload.SourceKind.INVENTORY
			and is_instance_valid(target.character)
			and payload.item.slot == target.equipment_slot
		)
	return false


func drop_on_slot(payload: InventoryDragPayload, target: InventoryItemSlot) -> bool:
	if not can_drop_on_slot(payload, target):
		return false
	_suspend_refresh = true
	var changed := false
	var changed_character: TacticalCharacter
	if target.source_kind == InventoryDragPayload.SourceKind.INVENTORY:
		if payload.source_kind == InventoryDragPayload.SourceKind.INVENTORY:
			changed = _inventory.swap_items(payload.inventory_index, target.inventory_index)
		else:
			var destination_item := _inventory.get_item_at(target.inventory_index)
			var equipped_item: ItemDefinition
			if destination_item == null:
				equipped_item = payload.character.unequip_item(payload.equipment_slot)
			else:
				equipped_item = payload.character.equip_item(destination_item)
			if equipped_item == payload.item:
				_inventory.replace_item_at(target.inventory_index, equipped_item)
				changed = true
				changed_character = payload.character
	else:
		var replaced := target.character.equip_item(payload.item)
		_inventory.replace_item_at(payload.inventory_index, replaced)
		changed = true
		changed_character = target.character
	_suspend_refresh = false
	if changed_character != null:
		equipment_updated.emit(changed_character)
	if changed or _refresh_pending:
		_refresh()
	return changed


func _is_payload_current(payload: InventoryDragPayload) -> bool:
	if payload == null or payload.item == null or _inventory == null:
		return false
	if payload.source_kind == InventoryDragPayload.SourceKind.INVENTORY:
		return _inventory.get_item_at(payload.inventory_index) == payload.item
	return (
		is_instance_valid(payload.character)
		and _characters.has(payload.character)
		and payload.character.get_equipped_item(payload.equipment_slot) == payload.item
	)


func show_item_details(item: ItemDefinition) -> void:
	_detail_item = item
	if not is_node_ready():
		return
	if item == null:
		detail_name.text = "Item Details"
		detail_type.text = "Nothing selected"
		detail_body.text = "Hover an inventory item or equipped item to inspect it."
		return
	detail_name.text = item.display_name
	detail_type.text = _get_item_slot_summary(item)
	detail_body.text = _get_item_detail_body(item)


func clear_item_details(item: ItemDefinition) -> void:
	if _detail_item == item:
		show_item_details(null)


func _get_item_detail_body(item: ItemDefinition) -> String:
	var lines: Array[String] = []
	if item.slot == ItemDefinition.EquipmentSlot.WEAPON:
		lines.append("Weapon type: %s" % _get_weapon_type_name(item))
		lines.append("Weapon damage: %d" % item.weapon_damage)
		if item.status_effect != null:
			lines.append("Applies: %s" % item.status_effect.get_description())
	if not item.modifiers.is_empty():
		lines.append("")
		lines.append("Modifiers")
		for modifier in item.modifiers:
			if modifier != null:
				lines.append(_format_modifier(modifier))
	var granted_names := _get_granted_ability_names(item)
	if not granted_names.is_empty():
		lines.append("")
		lines.append("Grants: %s" % ", ".join(granted_names))
	if lines.is_empty():
		lines.append("No additional effects.")
	return "\n".join(lines)


func _format_modifier(modifier: StatModifierDefinition) -> String:
	var stat_name := UnitStat.get_display_name(modifier.stat)
	match modifier.operation:
		StatModifierDefinition.Operation.FLAT:
			return "%s%s %s" % ["+" if modifier.value >= 0.0 else "", _format_number(modifier.value), stat_name]
		StatModifierDefinition.Operation.PERCENT_ADD:
			return "%s%s%% %s" % ["+" if modifier.value >= 0.0 else "", _format_number(modifier.value * 100.0), stat_name]
		StatModifierDefinition.Operation.PERCENT_MULTIPLY:
			return "%s%s%% multiplicative %s" % ["+" if modifier.value >= 0.0 else "", _format_number(modifier.value * 100.0), stat_name]
	return stat_name


func _format_number(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value


func _get_item_slot_summary(item: ItemDefinition) -> String:
	var summary: String = ItemDefinition.EquipmentSlot.keys()[item.slot].capitalize()
	if item.slot == ItemDefinition.EquipmentSlot.WEAPON:
		summary += " · %s · %d DMG" % [_get_weapon_type_name(item), item.weapon_damage]
	return summary


func _get_granted_ability_names(item: ItemDefinition) -> Array[String]:
	var result: Array[String] = []
	for ability in item.granted_abilities:
		if ability != null and not result.has(ability.display_name):
			result.append(ability.display_name)
	return result


func _get_weapon_type_name(item: ItemDefinition) -> String:
	return ItemDefinition.WeaponType.keys()[item.weapon_type].capitalize()


func _get_character_display_name(character: TacticalCharacter) -> String:
	if character.definition != null and not character.definition.display_name.is_empty():
		return "%s (%s)" % [character.definition.display_name, character.name]
	return str(character.name)


func _clear_entries(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
