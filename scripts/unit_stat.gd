class_name UnitStat
extends RefCounted

enum Type {
	NONE,
	STRENGTH,
	DEXTERITY,
	INTELLIGENCE,
	SPEED,
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
		_:
			return "None"
