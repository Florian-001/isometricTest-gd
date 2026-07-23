@tool
class_name AbilityEffectDefinition
extends Resource

@export_category("Effect")
@export var display_name: String = "Effect"
## Signed reward used by tactical AI when this effect has no automatic forecast.
## Positive values encourage use; negative values discourage it. Applied once per recipient,
## or once per cast for a cell ability with no recipients.
@export_range(-10000.0, 10000.0, 0.5) var ai_utility_hint: float = 0.0


func apply(_caster: TacticalCharacter, _target: TacticalCharacter) -> void:
	pass


## Side-effect-free prediction used by tactical AI. Custom effects can override this and
## return {"health_delta": int, "utility_hint": float}.
func estimate_for_ai(
	_caster: TacticalCharacter,
	_target: TacticalCharacter,
	_simulated_health: int
) -> Dictionary:
	return {
		"health_delta": 0,
		"utility_hint": ai_utility_hint,
	}


func get_description(_caster: TacticalCharacter = null) -> String:
	return display_name
