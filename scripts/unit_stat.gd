class_name UnitStat
extends RefCounted

const DEFAULT_SCALING_RULES := preload("res://resources/stat_scaling_rules.tres")

enum Type {
	NONE = 0,
	STRENGTH = 1,
	DEXTERITY = 2,
	INTELLIGENCE = 3,
	CONSTITUTION = 7,
	SPEED = 4,
	MOVEMENT_RANGE = 5,
}


static func get_scaling_rules() -> StatScalingRules:
	return DEFAULT_SCALING_RULES as StatScalingRules


static func get_display_name(stat: Type) -> String:
	match stat:
		Type.STRENGTH:
			return "Strength"
		Type.DEXTERITY:
			return "Dexterity"
		Type.INTELLIGENCE:
			return "Intelligence"
		Type.CONSTITUTION:
			return "Constitution"
		Type.SPEED:
			return "Speed"
		Type.MOVEMENT_RANGE:
			return "Movement Range"
		_:
			return "None"
