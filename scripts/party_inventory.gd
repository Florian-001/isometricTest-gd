@tool
class_name PartyInventory
extends Node

signal inventory_changed

@export_category("Grid")
@export_range(1, 20, 1) var rows: int = 10:
	set(value):
		rows = maxi(1, value)
		update_configuration_warnings()
@export_range(1, 20, 1) var columns: int = 10:
	set(value):
		columns = maxi(1, value)
		update_configuration_warnings()

@export_category("Starting Contents")
## Items are copied into runtime slots from left to right when the scene starts.
## Empty entries are skipped. Runtime reordering never modifies this authored list.
@export var starting_items: Array[ItemDefinition] = []:
	set(value):
		starting_items = value
		update_configuration_warnings()

var _slots: Array[ItemDefinition] = []


func _ready() -> void:
	if not Engine.is_editor_hint():
		initialize()


func initialize() -> void:
	_slots.clear()
	_slots.resize(get_slot_count())
	var next_slot := 0
	for item in starting_items:
		if item == null:
			continue
		if next_slot >= _slots.size():
			push_warning(
				"PartyInventory has more starting items than its %d available slots."
				% _slots.size()
			)
			break
		_warn_for_missing_icon(item)
		_slots[next_slot] = item
		next_slot += 1
	inventory_changed.emit()


func get_slot_count() -> int:
	return rows * columns


func get_item(index: int) -> ItemDefinition:
	if not _is_valid_index(index):
		return null
	return _slots[index]


func add_item(item: ItemDefinition) -> bool:
	if item == null:
		return false
	_ensure_initialized()
	for index in range(_slots.size()):
		if _slots[index] != null:
			continue
		_warn_for_missing_icon(item)
		_slots[index] = item
		inventory_changed.emit()
		return true
	return false


func move_or_swap(from_index: int, to_index: int) -> bool:
	_ensure_initialized()
	if (
		not _is_valid_index(from_index)
		or not _is_valid_index(to_index)
		or from_index == to_index
		or _slots[from_index] == null
	):
		return false
	var destination := _slots[to_index]
	_slots[to_index] = _slots[from_index]
	_slots[from_index] = destination
	inventory_changed.emit()
	return true


func _ensure_initialized() -> void:
	if _slots.size() != get_slot_count():
		initialize()


func _is_valid_index(index: int) -> bool:
	return index >= 0 and index < _slots.size()


func _warn_for_missing_icon(item: ItemDefinition) -> void:
	if item.icon == null:
		push_warning(
			"Inventory item '%s' has no icon; the inventory will show a fallback marker."
			% item.display_name
		)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var capacity := get_slot_count()
	var configured_items := 0
	for item in starting_items:
		if item == null:
			continue
		configured_items += 1
		if item.icon == null:
			warnings.append(
				"Starting item '%s' has no icon and will use a fallback marker."
				% item.display_name
			)
	if configured_items > capacity:
		warnings.append(
			"Starting Contents has %d items but the grid only has %d slots."
			% [configured_items, capacity]
		)
	return warnings
