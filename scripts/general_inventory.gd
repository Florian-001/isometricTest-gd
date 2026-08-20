class_name GeneralInventory
extends Node

signal items_changed

const GRID_COLUMNS := 10
const GRID_ROWS := 10
const CAPACITY := GRID_COLUMNS * GRID_ROWS

@export_category("Starting Inventory")
## Unused items available when the battle begins. Each entry represents one copy.
## Repeat an ItemDefinition in this list to start with multiple copies.
@export var starting_items: Array[ItemDefinition] = []

var _slots: Array[ItemDefinition] = []


func _ready() -> void:
	initialize_starting_items(starting_items)


## Replaces the runtime contents with a copy of the scene's configured unused items.
## Empty Inspector array entries are ignored so partially authored lists remain safe.
func initialize_starting_items(items: Array[ItemDefinition]) -> void:
	_resize_slots()
	_slots.fill(null)
	var next_slot := 0
	for item in items:
		if item == null:
			continue
		if next_slot >= CAPACITY:
			push_warning("General Inventory holds %d items; remaining starting items were ignored." % CAPACITY)
			break
		_slots[next_slot] = item
		next_slot += 1
	items_changed.emit()


func get_items() -> Array[ItemDefinition]:
	var result: Array[ItemDefinition] = []
	for item in _slots:
		if item != null:
			result.append(item)
	return result


func get_slot_count() -> int:
	_resize_slots()
	return _slots.size()


func get_item_at(index: int) -> ItemDefinition:
	_resize_slots()
	if index < 0 or index >= CAPACITY:
		return null
	return _slots[index]


func find_first_empty_slot() -> int:
	_resize_slots()
	for index in CAPACITY:
		if _slots[index] == null:
			return index
	return -1


func add_item(item: ItemDefinition) -> bool:
	if item == null:
		return false
	var index := find_first_empty_slot()
	if index < 0:
		return false
	_slots[index] = item
	items_changed.emit()
	return true


## Replaces one cell and returns its former item. Invalid cells are unchanged.
func replace_item_at(index: int, item: ItemDefinition) -> ItemDefinition:
	_resize_slots()
	if index < 0 or index >= CAPACITY:
		return null
	var replaced := _slots[index]
	if replaced == item:
		return replaced
	_slots[index] = item
	items_changed.emit()
	return replaced


func swap_items(first_index: int, second_index: int) -> bool:
	_resize_slots()
	if (
		first_index < 0
		or first_index >= CAPACITY
		or second_index < 0
		or second_index >= CAPACITY
	):
		return false
	if first_index == second_index:
		return true
	var first_item := _slots[first_index]
	_slots[first_index] = _slots[second_index]
	_slots[second_index] = first_item
	items_changed.emit()
	return true


func take_item(item: ItemDefinition) -> bool:
	_resize_slots()
	for index in CAPACITY:
		if _slots[index] == item:
			_slots[index] = null
			items_changed.emit()
			return true
	return false


func _resize_slots() -> void:
	if _slots.size() == CAPACITY:
		return
	_slots.resize(CAPACITY)
