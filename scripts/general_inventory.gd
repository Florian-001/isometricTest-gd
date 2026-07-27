class_name GeneralInventory
extends Node

signal items_changed

@export var starting_items: Array[ItemDefinition] = []

var _items: Array[ItemDefinition] = []


func _ready() -> void:
	_items.assign(starting_items)


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
