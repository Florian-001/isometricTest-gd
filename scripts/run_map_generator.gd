@tool
class_name RunMapGenerator
extends RefCounted

const DEFAULT_SEED := 1337
const DEFAULT_TIER_COUNT := 16
const ROOM_FLOORS := 15
const LANE_COUNT := 7
var _search_budget: int

func generate(seed_value: int = DEFAULT_SEED, settings: RunMapSettings = null) -> RunMapGraph:
	if settings == null:
		settings = RunMapSettings.new()
	if settings.columns < 2 or settings.routes < 2:
		return null
	for attempt in range(settings.generation_attempts):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value + attempt * 104729
		var graph := _routes(rng, settings)
		graph.seed_value = seed_value
		if _assign_rooms(graph, rng, settings):
			return graph
	return null

func _routes(rng: RandomNumberGenerator, settings: RunMapSettings) -> RunMapGraph:
	var graph := RunMapGraph.new(DEFAULT_TIER_COUNT, settings.columns)
	var cells: Dictionary = {}
	var first_start := -1
	for route in range(settings.routes):
		var lane := rng.randi_range(0, settings.columns - 1)
		if route == 0:
			first_start = lane
		elif route == 1 and lane == first_start:
			lane = (lane + rng.randi_range(1, settings.columns - 1)) % settings.columns
		var source := _cell(graph, cells, 0, lane)
		for tier in range(ROOM_FLOORS - 1):
			var candidates: Array[int] = []
			for target_lane in range(maxi(0, lane - 1), mini(settings.columns, lane + 2)):
				var crosses := false
				for edge in graph.edges:
					var a := graph.get_node_by_id(edge.x)
					var b := graph.get_node_by_id(edge.y)
					if a.tier == tier and (a.lane - lane) * (b.lane - target_lane) < 0:
						crosses = true
						break
				if not crosses:
					candidates.append(target_lane)
			lane = candidates[rng.randi_range(0, candidates.size() - 1)]
			var target := _cell(graph, cells, tier + 1, lane)
			graph.add_edge(source.id, target.id)
			source = target
	var boss := graph.add_node(ROOM_FLOORS, settings.columns >> 1, RunMapGraph.NodeType.BOSS)
	for node in graph.get_nodes_in_tier(ROOM_FLOORS - 1):
		graph.add_edge(node.id, boss.id)
	return graph

func _cell(graph: RunMapGraph, cells: Dictionary, tier: int, lane: int) -> RunMapGraph.NodeData:
	var key := Vector2i(tier, lane)
	if not cells.has(key):
		cells[key] = graph.add_node(tier, lane, RunMapGraph.NodeType.NORMAL_COMBAT)
	return cells[key]

func _assign_rooms(graph: RunMapGraph, rng: RandomNumberGenerator, settings: RunMapSettings) -> bool:
	for tier in range(ROOM_FLOORS):
		var row := graph.get_nodes_in_tier(tier)
		row.sort_custom(func(a: RunMapGraph.NodeData, b: RunMapGraph.NodeData) -> bool: return a.lane < b.lane)
		if tier in [0, 8, 14]:
			for node in row:
				node.type = {0: RunMapGraph.NodeType.NORMAL_COMBAT, 8: RunMapGraph.NodeType.CHEST, 14: RunMapGraph.NodeType.REST}[tier]
			continue
		var domains: Dictionary = {}
		for node in row:
			var weights := settings.weights()
			if tier < 5:
				weights.erase(RunMapGraph.NodeType.HARD_COMBAT)
				weights.erase(RunMapGraph.NodeType.REST)
			if tier == 13:
				weights.erase(RunMapGraph.NodeType.REST)
			for parent_id in graph.incoming(node.id):
				var parent_type := graph.get_node_by_id(parent_id).type
				if parent_type in [RunMapGraph.NodeType.HARD_COMBAT, RunMapGraph.NodeType.REST, RunMapGraph.NodeType.SHOP]:
					weights.erase(parent_type)
			domains[node.id] = _weighted_order(weights, rng)
		_search_budget = 20000
		if not _color_row(graph, row, domains, {}, 0):
			return false
	return true

func _weighted_order(weights: Dictionary, rng: RandomNumberGenerator) -> Array[int]:
	var result: Array[int] = []
	for key in weights.keys():
		if float(weights[key]) <= 0.0:
			weights.erase(key)
	while not weights.is_empty():
		var total := 0.0
		for value in weights.values():
			total += maxf(0.0, float(value))
		if total <= 0.0:
			break
		var roll := rng.randf() * total
		var chosen: int = weights.keys()[0]
		for type: int in weights:
			roll -= maxf(0.0, float(weights[type]))
			if roll <= 0.0:
				chosen = type
				break
		result.append(chosen)
		weights.erase(chosen)
	return result

func _color_row(graph: RunMapGraph, row: Array[RunMapGraph.NodeData], domains: Dictionary, assigned: Dictionary, index: int) -> bool:
	_search_budget -= 1
	if _search_budget < 0:
		return false
	if index == row.size():
		return true
	var node := row[index]
	var forbidden: Array[int] = []
	for parent_id in graph.incoming(node.id):
		for sibling_id in graph.outgoing(parent_id):
			if assigned.has(sibling_id):
				forbidden.append(assigned[sibling_id])
	for type: int in domains[node.id]:
		if forbidden.has(type):
			continue
		assigned[node.id] = type
		node.type = type
		if _color_row(graph, row, domains, assigned, index + 1):
			return true
	assigned.erase(node.id)
	return false
