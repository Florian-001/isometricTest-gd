@tool
class_name PassiveAbilityDefinition
extends Resource

@export var passive_id: StringName = &"":
	set(value):
		passive_id = value
		emit_changed()
@export var display_name := "New Passive":
	set(value):
		display_name = value
		emit_changed()
@export_multiline var description := "":
	set(value):
		description = value
		emit_changed()
@export var icon: Texture2D:
	set(value):
		icon = value
		emit_changed()
@export var effects: Array[PassiveEffectDefinition] = []:
	set(value):
		for effect in effects:
			if effect != null and effect.changed.is_connected(_effect_changed):
				effect.changed.disconnect(_effect_changed)
		effects = value.duplicate()
		for effect in effects:
			if effect != null and not effect.changed.is_connected(_effect_changed):
				effect.changed.connect(_effect_changed)
		emit_changed()


func _effect_changed() -> void:
	emit_changed()


func validate() -> Array[String]:
	var errors: Array[String] = []
	if str(passive_id).strip_edges().is_empty() or display_name.strip_edges().is_empty():
		errors.append("Passives need a stable ID and display name.")
	if effects.is_empty():
		errors.append("Assign at least one passive effect.")
	for effect in effects:
		if effect == null:
			errors.append("Passive effect references cannot be empty.")
		else:
			errors.append_array(effect.validate())
	return errors


func get_description() -> String:
	var parts: Array[String] = []
	if not description.strip_edges().is_empty():
		parts.append(description)
	for effect in effects:
		if effect != null:
			parts.append(effect.get_description())
	return "\n".join(parts)
