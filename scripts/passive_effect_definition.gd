@tool
class_name PassiveEffectDefinition
extends Resource


func validate() -> Array[String]:
	return ["Choose a concrete passive effect type."]


func get_description() -> String:
	return "Unconfigured passive effect"
