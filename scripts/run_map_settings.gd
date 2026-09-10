@tool
class_name RunMapSettings
extends Resource

enum Layout { ASCENT, LINEAR_COMBAT }

@export_category("Topology")
@export var layout: Layout = Layout.ASCENT
## Linear Combat only. Each floor contains one normal combat, with no boss.
@export_range(1, 15) var combat_count: int = 5
@export_range(2, 12) var columns: int = 7
@export_range(2, 12) var routes: int = 6
@export_range(1, 200) var generation_attempts: int = 100
@export_category("Room Weights")
@export var combat_weight: float = 45.0
@export var unknown_weight: float = 22.0
@export var elite_weight: float = 16.0
@export var rest_weight: float = 12.0
@export var shop_weight: float = 5.0

func combat_floor_count() -> int:
	return combat_count if layout == Layout.LINEAR_COMBAT else RunMapGenerator.ROOM_FLOORS

func validate() -> Array[String]:
	if layout == Layout.LINEAR_COMBAT:
		if combat_count < 1 or combat_count > 15:
			return ["Linear combat count must be within 1–15."]
	elif layout != Layout.ASCENT or columns < 2 or columns > 12 or routes < 2 or routes > 12 or generation_attempts < 1:
		return ["Assign a supported layout and valid topology settings."]
	return []

func weights() -> Dictionary:
	return {RunMapGraph.NodeType.NORMAL_COMBAT: combat_weight,
		RunMapGraph.NodeType.RANDOM: unknown_weight,
		RunMapGraph.NodeType.HARD_COMBAT: elite_weight,
		RunMapGraph.NodeType.REST: rest_weight,
		RunMapGraph.NodeType.SHOP: shop_weight}
