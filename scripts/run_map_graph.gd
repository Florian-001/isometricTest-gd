class_name RunMapGraph
extends RefCounted

enum NodeType {
	START,
	NORMAL_COMBAT,
	HARD_COMBAT,
	REST,
	SHOP,
	CHEST,
	RANDOM,
	BOSS,
}

class NodeData:
	extends RefCounted

	var id: int
	var tier: int
	var lane: int
	var type: int

	func _init(id_value: int, tier_value: int, lane_value: int, type_value: int) -> void:
		id = id_value
		tier = tier_value
		lane = lane_value
		type = type_value

	func get_signature() -> String:
		return "%d:%d:%d:%d" % [id, tier, lane, type]


var tier_count: int
var lane_count: int
var nodes: Array[NodeData] = []
var edges: Array[Vector2i] = []
var routes: Array[PackedInt32Array] = []

var _nodes_by_id: Dictionary = {}


func _init(tier_count_value: int = 17, lane_count_value: int = 7) -> void:
	tier_count = tier_count_value
	lane_count = lane_count_value


func add_node(tier: int, lane: int, type: int) -> NodeData:
	var node := NodeData.new(nodes.size(), tier, lane, type)
	nodes.append(node)
	_nodes_by_id[node.id] = node
	return node


func add_edge(from_id: int, to_id: int) -> void:
	var edge := Vector2i(from_id, to_id)
	if not edges.has(edge):
		edges.append(edge)


func add_route(lanes: PackedInt32Array) -> void:
	routes.append(lanes.duplicate())


func get_node_by_id(id: int) -> NodeData:
	return _nodes_by_id.get(id) as NodeData


func get_nodes_in_tier(tier: int) -> Array[NodeData]:
	var result: Array[NodeData] = []
	for node in nodes:
		if node.tier == tier:
			result.append(node)
	return result


func get_signature() -> String:
	var node_parts: Array[String] = []
	for node in nodes:
		node_parts.append(node.get_signature())
	var edge_parts: Array[String] = []
	for edge in edges:
		edge_parts.append("%d>%d" % [edge.x, edge.y])
	var route_parts: Array[String] = []
	for route in routes:
		var lanes: Array[String] = []
		for lane in route:
			lanes.append(str(lane))
		route_parts.append(".".join(lanes))
	return "%s|%s|%s" % [
		",".join(node_parts),
		",".join(edge_parts),
		",".join(route_parts),
	]


static func get_type_display_name(type: int) -> String:
	match type:
		NodeType.START:
			return "Start"
		NodeType.NORMAL_COMBAT:
			return "Combat"
		NodeType.HARD_COMBAT:
			return "Hard Combat"
		NodeType.REST:
			return "Rest"
		NodeType.SHOP:
			return "Shop"
		NodeType.CHEST:
			return "Chest"
		NodeType.RANDOM:
			return "Unknown"
		NodeType.BOSS:
			return "Boss"
	return "Unknown"


static func get_type_color(type: int) -> Color:
	match type:
		NodeType.START:
			return Color("d7b45b")
		NodeType.NORMAL_COMBAT:
			return Color("7fa8c9")
		NodeType.HARD_COMBAT:
			return Color("c65c68")
		NodeType.REST:
			return Color("e58a45")
		NodeType.SHOP:
			return Color("4db6aa")
		NodeType.CHEST:
			return Color("d9ad4a")
		NodeType.RANDOM:
			return Color("9b71d1")
		NodeType.BOSS:
			return Color("d94a4a")
	return Color.WHITE
