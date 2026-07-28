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
@export var slot: EquipmentSlot = EquipmentSlot.WEAPON
@export var icon: Texture2D

@export_category("Weapon")
## Added to physical ability damage while this item is equipped in the Weapon slot.
## Non-weapon items should leave this at zero.
@export_range(0, 9999, 1, "or_greater") var weapon_damage: int = 0

@export_category("Stat Modifiers")
@export var modifiers: Array[StatModifierDefinition] = []
