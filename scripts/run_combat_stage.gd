@tool
class_name RunCombatStage
extends Resource

@export var display_name: String = "Combat Stage"
## Displayed map floors, inclusive. The final boss is configured separately.
@export_range(1, 15, 1) var first_floor: int = 1
@export_range(1, 15, 1) var last_floor: int = 15
@export_range(1, 999, 1, "or_greater") var starting_cr: int = 1
@export_range(1, 999, 1, "or_greater") var cr_per_floor: int = 1
## Allowed enemy scenes. Repeated units are allowed; duplicate entries add no weight.
@export var enemy_pool: Array[PackedScene] = []


func combat_rating_at(floor_number: int) -> int:
	return starting_cr + (floor_number - first_floor) * cr_per_floor
