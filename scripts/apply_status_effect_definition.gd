@tool
class_name ApplyStatusEffectDefinition
extends AbilityEffectDefinition

@export_category("Status")
@export var status_effect: StatusEffectDefinition


func _init() -> void:
	display_name = "Apply Status"


func apply(caster: TacticalCharacter, target: TacticalCharacter) -> void:
	if (
		status_effect != null
		and is_instance_valid(target)
		and target.current_health > 0
	):
		target.apply_status(status_effect, caster)


func get_description(_caster: TacticalCharacter = null) -> String:
	if status_effect == null:
		return "No status configured"
	return "%s for %d turn%s" % [
		status_effect.display_name,
		status_effect.duration_turns,
		"" if status_effect.duration_turns == 1 else "s",
	]
