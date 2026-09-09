@tool
class_name KnockbackEffectDefinition
extends AbilityEffectDefinition

## Board-aware delivery is handled by AbilityExecutor and EnemyAIPlanner.
@export_range(0, 99, 1) var distance: int = 2
@export_range(0, 9999, 1) var collision_damage: int = 1


func get_description(_caster: TacticalCharacter = null) -> String:
	return ("Push up to %d tiles away; walls and board edges deal %d collision damage; "
		+ "hitting a unit stops the push and deals %d to both (armor applies). "
		+ "No chain push, terrain entry effects, or opportunity attacks.") % [distance, collision_damage, collision_damage]
