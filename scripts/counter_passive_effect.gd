@tool
class_name CounterPassiveEffect
extends PassiveEffectDefinition


func validate() -> Array[String]:
	return []


func get_description() -> String:
	return "After each complete damaging attack, retaliate once with your basic attack if the attacker is in range. Retaliation costs no action or opportunity reaction. Requires being able to attack; excludes terrain, damage over time, and other counters"
