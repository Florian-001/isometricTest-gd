@tool
class_name ItemDefinition
extends Resource

enum EquipmentSlot {
	WEAPON,
	ARMOR,
	ACCESSORY,
}

enum WeaponType {
	MELEE,
	RANGED,
}

@export_category("Item")
@export var display_name: String = "New Item"
@export var slot: EquipmentSlot = EquipmentSlot.WEAPON:
	set(value):
		slot = value
		if Engine.is_editor_hint():
			notify_property_list_changed()
@export var icon: Texture2D

@export_category("Weapon")
## Melee and Ranged abilities require the matching equipped weapon type.
@export var weapon_type: WeaponType = WeaponType.MELEE
## Added to damaging abilities whose Ability Type matches this weapon.
## Non-weapon items should leave this at zero.
@export_range(0, 9999, 1, "or_greater") var weapon_damage: int = 0
## Guaranteed reusable status applied by surviving targets of damaging abilities that use this weapon.
@export var status_effect: StatusEffectDefinition

@export_category("Stat Modifiers")
@export var modifiers: Array[StatModifierDefinition] = []


func _validate_property(property: Dictionary) -> void:
	if property.name in [&"weapon_type", &"status_effect"] and slot != EquipmentSlot.WEAPON:
		property.usage = property.usage & ~PROPERTY_USAGE_EDITOR
