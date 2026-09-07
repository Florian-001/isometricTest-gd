@tool
class_name RunCombatFloorOverride
extends Resource

@export_range(1, 15, 1) var floor: int = 1
@export_group("Combat Rating")
## Replace the stage budget for this floor. Later floors still use their own settings.
@export var override_cr: bool = false
@export_range(1, 999, 1, "or_greater") var combat_rating: int = 1
@export_group("Enemy Pool")
## Replace the entire stage pool, rather than adding enemies to it.
@export var override_enemy_pool: bool = false
@export var enemy_pool: Array[PackedScene] = []
