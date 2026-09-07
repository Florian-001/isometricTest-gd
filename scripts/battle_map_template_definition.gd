@tool
class_name BattleMapTemplateDefinition
extends BattleMapDefinition

@export_category("Encounter")
## Maximum combined enemy Combat Rating. Generation finds the closest total without exceeding it.
@export_range(1, 999, 1, "or_greater") var combat_rating: int = 1
## Spawnable enemy scenes. Repeated enemies are allowed; duplicate list entries do not add weight.
@export var enemy_pool: Array[PackedScene] = []
## Party scene used in standalone battles. Runs use their current party instead.
@export var standalone_party: PackedScene
