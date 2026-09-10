@tool
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
var layout: RunMapSettings.Layout = RunMapSettings.Layout.ASCENT
var nodes: Array[NodeData] = []
var edges: Array[Vector2i] = []
var seed_value: int = 1337

var _nodes_by_id: Dictionary = {}


func _init(tier_count_value: int = 16, lane_count_value: int = 7) -> void:
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
	return "%s|%s" % [",".join(node_parts), ",".join(edge_parts)]


static func get_type_display_name(type: int) -> String:
	match type:
		NodeType.START:
			return "Start"
		NodeType.NORMAL_COMBAT:
			return "Combat"
		NodeType.HARD_COMBAT:
			return "Elite"
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


func outgoing(id: int) -> Array[int]:
	var result: Array[int] = []
	for edge in edges:
		if edge.x == id:
			result.append(edge.y)
	return result


func incoming(id: int) -> Array[int]:
	var result: Array[int] = []
	for edge in edges:
		if edge.y == id:
			result.append(edge.x)
	return result


func is_terminal_combat(id: int) -> bool:
	var node := get_node_by_id(id)
	return node != null and node.tier == tier_count - 1 and outgoing(id).is_empty() and node.type in [NodeType.NORMAL_COMBAT, NodeType.HARD_COMBAT, NodeType.BOSS]


func to_data() -> Dictionary:
	var room_data: Array = []
	var edge_data: Array = []
	for node in nodes:
		room_data.append([node.tier, node.lane, node.type])
	for edge in edges:
		edge_data.append([edge.x, edge.y])
	return {"layout": int(layout), "tiers": tier_count, "lanes": lane_count, "seed": seed_value, "nodes": room_data, "edges": edge_data}


static func from_data(data: Dictionary) -> RunMapGraph:
	for key in ["tiers", "lanes", "seed"]:
		if not _integer(data.get(key)):
			return null
	var graph := RunMapGraph.new(int(data.get("tiers", 0)), int(data.get("lanes", 0)))
	graph.seed_value = int(data.get("seed", 0))
	var saved_layout: Variant = data.get("layout", RunMapSettings.Layout.ASCENT)
	if not _integer(saved_layout) or int(saved_layout) not in [RunMapSettings.Layout.ASCENT, RunMapSettings.Layout.LINEAR_COMBAT]:
		return null
	graph.layout = int(saved_layout) as RunMapSettings.Layout
	var linear := graph.layout == RunMapSettings.Layout.LINEAR_COMBAT
	if linear:
		if graph.tier_count < 1 or graph.tier_count > 15 or graph.lane_count != 1:
			return null
	elif graph.tier_count != 16 or graph.lane_count < 2 or graph.lane_count > 12:
		return null
	var rooms: Variant = data.get("nodes", [])
	var links: Variant = data.get("edges", [])
	if not rooms is Array or not links is Array or rooms.is_empty() or rooms.size() > 181:
		return null
	if links.size() > rooms.size() * 3:
		return null
	var occupied := {}
	for raw in rooms:
		if not raw is Array or raw.size() != 3:
			return null
		for value in raw:
			if not _integer(value):
				return null
		var tier := int(raw[0])
		var lane := int(raw[1])
		var type := int(raw[2])
		var key := Vector2i(tier, lane)
		if tier < 0 or tier >= graph.tier_count or lane < 0 or lane >= graph.lane_count or type < 1 or type > NodeType.BOSS or occupied.has(key):
			return null
		occupied[key] = true
		graph.add_node(tier, lane, type)
	for raw in links:
		if not raw is Array or raw.size() != 2:
			return null
		for value in raw:
			if not _integer(value):
				return null
		var a := graph.get_node_by_id(int(raw[0]))
		var b := graph.get_node_by_id(int(raw[1]))
		if a == null or b == null or b.tier != a.tier + 1:
			return null
		if b.tier < 15 and absi(a.lane - b.lane) > 1:
			return null
		if graph.edges.has(Vector2i(a.id, b.id)):
			return null
		for edge in graph.edges:
			var c := graph.get_node_by_id(edge.x)
			var d := graph.get_node_by_id(edge.y)
			if a.tier == c.tier and (a.lane - c.lane) * (b.lane - d.lane) < 0:
				return null
		graph.add_edge(a.id, b.id)
	if linear:
		if graph.nodes.size() != graph.tier_count or graph.edges.size() != graph.tier_count - 1:
			return null
	elif graph.get_nodes_in_tier(0).size() < 2 or graph.get_nodes_in_tier(15).size() != 1:
		return null
	for node in graph.nodes:
		if linear and node.type != NodeType.NORMAL_COMBAT:
			return null
		if not linear and (node.tier == 15) != (node.type == NodeType.BOSS):
			return null
		if (node.tier > 0 and graph.incoming(node.id).is_empty()) or (node.tier < graph.tier_count - 1 and graph.outgoing(node.id).is_empty()):
			return null
	return graph


static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))
