@tool
class_name ItemDefinition
extends Resource

enum EquipmentSlot {
	WEAPON,
	ARMOR,
	ACCESSORY,
}

@export_category("Item")
@export var display_name: String = "New Item"
@export_multiline var description: String = ""
@export var slot: EquipmentSlot = EquipmentSlot.WEAPON
@export var icon: Texture2D

@export_category("Stat Modifiers")
@export var modifiers: Array[StatModifierDefinition] = []
