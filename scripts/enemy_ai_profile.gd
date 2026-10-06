@tool
class_name EnemyAIProfile
extends Resource

@export_category("Identity")
@export var display_name: String = "General AI"

@export_category("Effect Scoring")
## Points per actual HP or armor removed. Also scales damage penalties and damage over time.
@export_range(0.0, 10.0, 0.05, "or_greater") var damage_weight: float = 1.0
## Multiplies healing value. Allied healing still scales with the fraction of HP missing.
@export_range(0.0, 10.0, 0.05, "or_greater") var healing_weight: float = 1.0
## Multiplies signed AI utility from statuses, Cleanse, custom effects, and terrain.
## Individual effects retain their own editable AI utility values.
@export_range(0.0, 10.0, 0.05, "or_greater") var utility_weight: float = 1.0
## Multiplies damage value when an action or terrain damages this unit or its allies.
## 2 means allied damage costs twice as much as the same damage to an opponent rewards.
@export_range(0.0, 10.0, 0.05, "or_greater") var friendly_damage_penalty: float = 2.0
## Fraction of the defeated unit's maximum HP added as a bonus, or subtracted for allied defeat.
## 0.25 awards 10 extra points for defeating an opponent with 40 maximum HP.
@export_range(0.0, 1.0, 0.025, "or_greater") var immediate_defeat_ratio: float = 0.25

@export_category("Position Scoring")
## Multiplies the estimated value of a useful action from the plan's final cell next turn.
@export_range(0.0, 1.0, 0.025, "or_greater") var future_value_weight: float = 0.25

@export_category("Team Scoring")
## Rewards pressure on an opponent that allies can attack before its next turn.
@export_range(0.0, 1.0, 0.025, "or_greater") var shared_pressure_weight: float = 0.25
## Fraction of an opponent's maximum HP awarded when allied follow-up can finish it.
@export_range(0.0, 1.0, 0.025, "or_greater") var setup_defeat_ratio: float = 0.125


## Shared fallback for units without a per-unit or enemy-archetype profile, including Auto Battle.
static func get_default() -> EnemyAIProfile:
	return load("res://resources/ai/general_ai.tres") as EnemyAIProfile
