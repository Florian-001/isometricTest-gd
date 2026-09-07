@tool
class_name RunMapSettings
extends Resource

@export_category("Topology")
@export_range(2, 12) var columns: int = 7
@export_range(2, 12) var routes: int = 6
@export_range(1, 200) var generation_attempts: int = 100
@export_category("Room Weights")
@export var combat_weight: float = 45.0
@export var unknown_weight: float = 22.0
@export var elite_weight: float = 16.0
@export var rest_weight: float = 12.0
@export var shop_weight: float = 5.0

func weights() -> Dictionary:
	return {RunMapGraph.NodeType.NORMAL_COMBAT: combat_weight,
		RunMapGraph.NodeType.RANDOM: unknown_weight,
		RunMapGraph.NodeType.HARD_COMBAT: elite_weight,
		RunMapGraph.NodeType.REST: rest_weight,
		RunMapGraph.NodeType.SHOP: shop_weight}
