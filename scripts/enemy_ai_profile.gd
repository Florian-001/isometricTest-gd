@tool
class_name EnemyAIProfile
extends Resource

enum BehaviorStyle {
	MELEE,
	RANGED,
}

@export_category("Identity")
@export var display_name: String = "Enemy AI"
@export var behavior_style: BehaviorStyle = BehaviorStyle.MELEE

@export_category("Search")
## Immediate plans are all scored; only this many receive the expensive counter-turn forecast.
@export_range(1, 256, 1, "or_greater") var lookahead_candidate_limit: int = 32
## Keeps several tactically different destinations after the same cast without exploding the search tree.
@export_range(1, 32, 1, "or_greater") var post_cast_position_limit: int = 4
@export_range(0.0, 2.0, 0.05, "or_greater") var counterplay_discount: float = 0.75

@export_category("Effect Rewards")
@export_range(0.0, 10.0, 0.05, "or_greater") var damage_reward: float = 1.0
@export_range(0.0, 10.0, 0.05, "or_greater") var healing_reward: float = 0.75
@export_range(0.0, 1000.0, 1.0, "or_greater") var defeat_reward: float = 40.0
@export_range(0.0, 10.0, 0.05, "or_greater") var friendly_damage_penalty: float = 2.0
@export_range(0.0, 10.0, 0.05, "or_greater") var enemy_healing_penalty: float = 1.0
@export_range(0.0, 10.0, 0.05, "or_greater") var custom_effect_weight: float = 1.0

@export_category("Melee Behavior")
@export_range(0.0, 100.0, 0.5, "or_greater") var melee_delivery_reward: float = 12.0
@export_range(0.0, 25.0, 0.25, "or_greater") var approach_reward: float = 2.0
@export_range(0.0, 100.0, 0.5, "or_greater") var adjacent_reward: float = 6.0

@export_category("Ranged Behavior")
@export_range(0.0, 100.0, 0.5, "or_greater") var ranged_delivery_reward: float = 8.0
@export_range(0.1, 1.0, 0.05) var ranged_standoff_ratio: float = 0.85
@export_range(0.0, 50.0, 0.5, "or_greater") var ranged_minimum_distance: float = 2.0
@export_range(0.0, 25.0, 0.25, "or_greater") var ranged_distance_penalty: float = 2.0
@export_range(0.0, 25.0, 0.25, "or_greater") var ranged_too_close_penalty: float = 6.0
@export_range(0.0, 25.0, 0.25, "or_greater") var ranged_out_of_range_penalty: float = 3.0
@export_range(0.0, 100.0, 0.5, "or_greater") var ranged_clear_shot_reward: float = 6.0

