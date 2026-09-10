@tool
class_name ItemDefinition
extends Resource

const LEGACY_RESOURCE_PATHS := {
	"res://resources/items/weapons/mage_staff.tres": "res://resources/items/weapons/staff.tres",
	"res://resources/items/weapons/weathered_bow.tres": "res://resources/items/weapons/short_bow.tres",
}


## Normalize exact historical item paths without altering the caller's save data.
## Recursive traversal also covers status sources and pending rewards/shop offers.
static func normalize_saved_paths(value: Variant) -> Variant:
	if value is String:
		return LEGACY_RESOURCE_PATHS.get(value, value)
	if value is Dictionary:
		var result: Dictionary = value.duplicate()
		for key in result:
			result[key] = normalize_saved_paths(result[key])
		return result
	if value is Array:
		var result: Array = value.duplicate()
		for index in range(result.size()):
			result[index] = normalize_saved_paths(result[index])
		return result
	return value


enum EquipmentSlot {
	WEAPON,
	ARMOR,
	ACCESSORY,
	OFFHAND = 3,
}

enum WeaponType {
	MELEE,
	RANGED,
}

enum WeaponHandedness {
	ONE_HANDED,
	TWO_HANDED,
}

@export_category("Item")
@export var display_name: String = "New Item"
@export var slot: EquipmentSlot = EquipmentSlot.WEAPON:
	set(value):
		slot = value
		if Engine.is_editor_hint():
			notify_property_list_changed()
@export var icon: Texture2D

@export_category("Armor")
## Adds to the separate armor pool while equipped. Armor absorbs all damage before health.
## Spent armor is restored at encounter end, not by healing or swapping equipment.
@export_range(0, 9999, 1, "or_greater") var armor: int = 0:
	set(value):
		armor = maxi(0, value)

@export_category("Weapon")
## Two-handed weapons also occupy Offhand, displacing any offhand item.
@export var weapon_handedness: WeaponHandedness = WeaponHandedness.ONE_HANDED
## Melee and Ranged abilities require the matching equipped weapon type.
@export var weapon_type: WeaponType = WeaponType.MELEE
## Added to damaging abilities whose Ability Type matches this weapon.
## Non-weapon items should leave this at zero.
@export_range(0, 9999, 1, "or_greater") var weapon_damage: int = 0
## Extra weighted grid reach for abilities that accept weapon range bonuses.
## Strike accepts this bonus for normal attacks; opportunity reach stays adjacent.
@export_range(0.0, 100.0, 0.5, "or_greater") var weapon_range_bonus: float = 0.0
## Guaranteed reusable status applied by surviving targets of damaging abilities that use this weapon.
@export var status_effect: StatusEffectDefinition

@export_category("Stat Modifiers")
@export var modifiers: Array[StatModifierDefinition] = []


## Basic attacks granted to friendly units while this weapon is equipped.
func get_granted_abilities() -> Array[AbilityDefinition]:
	if slot != EquipmentSlot.WEAPON:
		return []
	# Load lazily: ability definitions also reference item weapon types.
	var path := "res://resources/abilities/strike.tres" if weapon_type == WeaponType.MELEE else "res://resources/abilities/arrow.tres"
	return [load(path) as AbilityDefinition]


func is_two_handed() -> bool:
	return slot == EquipmentSlot.WEAPON and weapon_handedness == WeaponHandedness.TWO_HANDED


func get_occupied_slots() -> Array[int]:
	return [EquipmentSlot.WEAPON, EquipmentSlot.OFFHAND] if is_two_handed() else [slot]


func conflicts_with(other: ItemDefinition) -> bool:
	if other == null:
		return false
	for occupied_slot in get_occupied_slots():
		if other.get_occupied_slots().has(occupied_slot):
			return true
	return false


func _validate_property(property: Dictionary) -> void:
	if property.name in [&"weapon_handedness", &"weapon_type", &"weapon_range_bonus", &"status_effect"] and slot != EquipmentSlot.WEAPON:
		property.usage = property.usage & ~PROPERTY_USAGE_EDITOR
