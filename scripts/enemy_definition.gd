@tool
class_name EnemyDefinition
extends CharacterDefinition

@export_category("Encounter")
## Combat Rating (CR) represents encounter difficulty cost for future enemy selection.
@export_range(1, 999, 1, "or_greater") var combat_rating: int = 1

@export_category("Health")
## 0 uses normal Constitution-based health. Otherwise this is maximum HP at the
## definition's authored Constitution; effective Constitution scales HP proportionally.
@export_range(0, 999, 1, "or_greater") var base_health_override: int = 0:
	set(value):
		base_health_override = maxi(0, value)
		if Engine.is_editor_hint():
			notify_property_list_changed()

@export_category("Enemy AI")
## Default AI used by every unit that references this enemy archetype.
@export var ai_profile: EnemyAIProfile


func _init() -> void:
	faction = Faction.ENEMY


func calculate_max_health(effective_constitution: float) -> int:
	if base_health_override == 0:
		return super.calculate_max_health(effective_constitution)
	var minimum := maxf(0.0, UnitStat.get_scaling_rules().minimum_constitution_for_health)
	var authored := maxf(float(constitution), minimum)
	var effective := maxf(maxf(0.0, effective_constitution), minimum)
	return maxi(1, roundi(float(base_health_override) * effective / authored))
