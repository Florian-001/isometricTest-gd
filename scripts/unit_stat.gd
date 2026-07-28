class_name UnitStat
extends RefCounted

enum Type {
	NONE,
	STRENGTH,
	DEXTERITY,
	INTELLIGENCE,
	SPEED,
	MOVEMENT_RANGE,
}


static func get_display_name(stat: Type) -> String:
	match stat:
		Type.STRENGTH:
			return "Strength"
		Type.DEXTERITY:
			return "Dexterity"
		Type.INTELLIGENCE:
			return "Intelligence"
		Type.SPEED:
			return "Speed"
		Type.MOVEMENT_RANGE:
			return "Movement Range"
		_:
			return "None"
