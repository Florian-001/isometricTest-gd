@tool
class_name GroundImmunityPassiveEffect
extends PassiveEffectDefinition

@export var ignore_tile_effects := true:
	set(value):
		ignore_tile_effects = value
		emit_changed()
@export var ignore_movement_modifiers := true:
	set(value):
		ignore_movement_modifiers = value
		emit_changed()


func validate() -> Array[String]:
	return [] if ignore_tile_effects or ignore_movement_modifiers else ["Ground immunity must enable at least one immunity."]


func get_description() -> String:
	var parts: Array[String] = []
	if ignore_tile_effects:
		parts.append("Ignores ground damage, healing, statuses, and other tile effects")
	if ignore_movement_modifiers:
		parts.append("Uses normal movement costs on every terrain tile")
	return ". ".join(parts) + "."
