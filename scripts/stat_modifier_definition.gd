@tool
class_name StatModifierDefinition
extends Resource

enum Operation {
	FLAT,
	PERCENT_ADD,
	PERCENT_MULTIPLY,
}

@export var stat: UnitStat.Type = UnitStat.Type.STRENGTH
@export var operation: Operation = Operation.FLAT
## Flat values are direct stat points. Percentage values use decimals: 0.25 means +25%.
@export_range(-10000.0, 10000.0, 0.05, "or_greater", "or_less") var value: float = 0.0
