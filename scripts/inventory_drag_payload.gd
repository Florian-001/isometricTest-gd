class_name InventoryDragPayload
extends RefCounted

enum SourceKind {
	INVENTORY,
	EQUIPMENT,
}

var source_kind: SourceKind
var item: ItemDefinition
var inventory_index := -1
var equipment_slot := -1
var character: TacticalCharacter


static func from_inventory(source_item: ItemDefinition, index: int) -> InventoryDragPayload:
	var payload := InventoryDragPayload.new()
	payload.source_kind = SourceKind.INVENTORY
	payload.item = source_item
	payload.inventory_index = index
	return payload


static func from_equipment(
	source_item: ItemDefinition,
	slot: ItemDefinition.EquipmentSlot,
	source_character: TacticalCharacter
) -> InventoryDragPayload:
	var payload := InventoryDragPayload.new()
	payload.source_kind = SourceKind.EQUIPMENT
	payload.item = source_item
	payload.equipment_slot = slot
	payload.character = source_character
	return payload
