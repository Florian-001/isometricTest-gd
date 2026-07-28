class_name GeneralInventory
extends Node

signal items_changed

@export_category("Starting Inventory")
## Unused items available when the battle begins. Each entry represents one copy.
## Repeat an ItemDefinition in this list to start with multiple copies.
@export var starting_items: Array[ItemDefinition] = []

var _items: Array[ItemDefinition] = []


func _ready() -> void:
	initialize_starting_items(starting_items)


## Replaces the runtime contents with a copy of the scene's configured unused items.
## Empty Inspector array entries are ignored so partially authored lists remain safe.
func initialize_starting_items(items: Array[ItemDefinition]) -> void:
	_items.clear()
	for item in items:
		if item != null:
			_items.append(item)
	items_changed.emit()


func get_items() -> Array[ItemDefinition]:
	var result: Array[ItemDefinition] = []
	result.assign(_items)
	return result


func add_item(item: ItemDefinition) -> void:
	if item == null:
		return
	_items.append(item)
	items_changed.emit()


func take_item(item: ItemDefinition) -> bool:
	var index := _items.find(item)
	if index < 0:
		return false
	_items.remove_at(index)
	items_changed.emit()
	return true
