class_name RunMapGenerator
extends RefCounted

const DEFAULT_SEED := 1337
const DEFAULT_ROOM_FLOOR_COUNT := 15
const DEFAULT_TIER_COUNT := DEFAULT_ROOM_FLOOR_COUNT + 2
const LANE_COUNT := 7
const ROUTE_COUNT := 6

const FIRST_RANDOM_SPECIAL_FLOOR := 6
const TREASURE_FLOOR := 9

const ROOM_TYPE_WEIGHTS := {
	RunMapGraph.NodeType.NORMAL_COMBAT: 45,
	RunMapGraph.NodeType.RANDOM: 22,
	RunMapGraph.NodeType.HARD_COMBAT: 16,
	RunMapGraph.NodeType.REST: 12,
	RunMapGraph.NodeType.SHOP: 5,
}

const NON_CONSECUTIVE_TYPES := {
	RunMapGraph.NodeType.HARD_COMBAT: true,
	RunMapGraph.NodeType.REST: true,
	RunMapGraph.NodeType.SHOP: true,
}


func generate(
	seed_value: int = DEFAULT_SEED,
	room_floor_count: int = DEFAULT_ROOM_FLOOR_COUNT
) -> RunMapGraph:
	room_floor_count = maxi(room_floor_count, DEFAULT_ROOM_FLOOR_COUNT)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var routes := _trace_routes(rng, room_floor_count)
	var graph := _materialize_graph(routes, room_floor_count)
	_assign_room_types(graph, rng, room_floor_count)
	return graph


func _trace_routes(rng: RandomNumberGenerator, room_floor_count: int) -> Array[PackedInt32Array]:
	var routes: Array[PackedInt32Array] = []
	var segments_by_transition: Dictionary = {}
	for route_index in range(ROUTE_COUNT):
		var start_candidates: Array[int] = []
		for lane in range(LANE_COUNT):
			start_candidates.append(lane)
		_shuffle_ints(start_candidates, rng)
		if route_index == 1:
			start_candidates.erase(routes[0][0])

		var route := PackedInt32Array()
		var current_lane: int = start_candidates[0]
		route.append(current_lane)
		for transition in range(room_floor_count - 1):
			var next_candidates: Array[int] = []
			for lane in range(maxi(0, current_lane - 1), mini(LANE_COUNT - 1, current_lane + 1) + 1):
				next_candidates.append(lane)
			_shuffle_ints(next_candidates, rng)

			var existing_segments: Array = segments_by_transition.get(transition, [])
			var next_lane := current_lane
			for candidate in next_candidates:
				if not _would_cross(current_lane, candidate, existing_segments):
					next_lane = candidate
					break
			existing_segments.append(Vector2i(current_lane, next_lane))
			segments_by_transition[transition] = existing_segments
			current_lane = next_lane
			route.append(current_lane)
		routes.append(route)
	return routes


func _would_cross(source_lane: int, target_lane: int, existing_segments: Array) -> bool:
	for segment_value in existing_segments:
		var segment := segment_value as Vector2i
		if (
			source_lane < segment.x and target_lane > segment.y
			or source_lane > segment.x and target_lane < segment.y
		):
			return true
	return false


func _materialize_graph(
	routes: Array[PackedInt32Array],
	room_floor_count: int
) -> RunMapGraph:
	var graph := RunMapGraph.new(room_floor_count + 2, LANE_COUNT)
	for route in routes:
		graph.add_route(route)

	var used_positions: Dictionary = {}
	for route in routes:
		for floor_index in range(room_floor_count):
			used_positions[Vector2i(floor_index + 1, route[floor_index])] = true

	var nodes_by_position: Dictionary = {}
	var start := graph.add_node(0, LANE_COUNT >> 1, RunMapGraph.NodeType.START)
	for floor_number in range(1, room_floor_count + 1):
		var used_lanes: Array[int] = []
		for position_value in used_positions:
			var position := position_value as Vector2i
			if position.x == floor_number:
				used_lanes.append(position.y)
		used_lanes.sort()
		for lane in used_lanes:
			var position := Vector2i(floor_number, lane)
			nodes_by_position[position] = graph.add_node(
				floor_number,
				lane,
				RunMapGraph.NodeType.NORMAL_COMBAT
			)
	var boss := graph.add_node(
		room_floor_count + 1,
		LANE_COUNT >> 1,
		RunMapGraph.NodeType.BOSS
	)

	for first_node in graph.get_nodes_in_tier(1):
		graph.add_edge(start.id, first_node.id)
	for route in routes:
		for floor_index in range(room_floor_count - 1):
			var source := nodes_by_position[
				Vector2i(floor_index + 1, route[floor_index])
			] as RunMapGraph.NodeData
			var target := nodes_by_position[
				Vector2i(floor_index + 2, route[floor_index + 1])
			] as RunMapGraph.NodeData
			graph.add_edge(source.id, target.id)
	for final_node in graph.get_nodes_in_tier(room_floor_count):
		graph.add_edge(final_node.id, boss.id)
	return graph


func _assign_room_types(
	graph: RunMapGraph,
	rng: RandomNumberGenerator,
	room_floor_count: int
) -> void:
	var incoming: Dictionary = {}
	var outgoing: Dictionary = {}
	for node in graph.nodes:
		incoming[node.id] = []
		outgoing[node.id] = []
	for edge in graph.edges:
		(incoming[edge.y] as Array).append(edge.x)
		(outgoing[edge.x] as Array).append(edge.y)

	var assigned: Dictionary = {}
	var variable_nodes: Array[RunMapGraph.NodeData] = []
	for node in graph.nodes:
		if node.type in [RunMapGraph.NodeType.START, RunMapGraph.NodeType.BOSS]:
			assigned[node.id] = node.type
		elif node.tier == 1:
			assigned[node.id] = RunMapGraph.NodeType.NORMAL_COMBAT
		elif node.tier == TREASURE_FLOOR:
			assigned[node.id] = RunMapGraph.NodeType.CHEST
		elif node.tier == room_floor_count:
			assigned[node.id] = RunMapGraph.NodeType.REST
		else:
			variable_nodes.append(node)

	var candidate_orders: Dictionary = {}
	for node in variable_nodes:
		candidate_orders[node.id] = _weighted_type_order(rng, node.tier, room_floor_count)

	var complete := _assign_variable_node(
		0,
		variable_nodes,
		candidate_orders,
		assigned,
		incoming,
		outgoing,
		graph,
		room_floor_count
	)
	if not complete:
		push_error("Run map room assignment could not satisfy all constraints")
	for node in graph.nodes:
		if assigned.has(node.id):
			node.type = int(assigned[node.id])


func _assign_variable_node(
	index: int,
	nodes: Array[RunMapGraph.NodeData],
	candidate_orders: Dictionary,
	assigned: Dictionary,
	incoming: Dictionary,
	outgoing: Dictionary,
	graph: RunMapGraph,
	room_floor_count: int
) -> bool:
	if index >= nodes.size():
		return true
	var node := nodes[index]
	for candidate_value in candidate_orders[node.id]:
		var candidate := int(candidate_value)
		if not _is_valid_room_assignment(
			node,
			candidate,
			assigned,
			incoming,
			outgoing,
			graph,
			room_floor_count
		):
			continue
		assigned[node.id] = candidate
		if _assign_variable_node(
			index + 1,
			nodes,
			candidate_orders,
			assigned,
			incoming,
			outgoing,
			graph,
			room_floor_count
		):
			return true
		assigned.erase(node.id)
	return false


func _is_valid_room_assignment(
	node: RunMapGraph.NodeData,
	candidate: int,
	assigned: Dictionary,
	incoming: Dictionary,
	outgoing: Dictionary,
	graph: RunMapGraph,
	room_floor_count: int
) -> bool:
	if not _is_type_allowed_on_floor(candidate, node.tier, room_floor_count):
		return false
	if NON_CONSECUTIVE_TYPES.has(candidate):
		for parent_id in incoming[node.id]:
			var parent := graph.get_node_by_id(int(parent_id))
			if parent.tier >= 1 and assigned.get(parent.id, -1) == candidate:
				return false
	for parent_id in incoming[node.id]:
		for sibling_id in outgoing[parent_id]:
			if int(sibling_id) == node.id:
				continue
			if assigned.get(int(sibling_id), -1) == candidate:
				return false
	return true


func _weighted_type_order(
	rng: RandomNumberGenerator,
	floor_number: int,
	room_floor_count: int
) -> Array[int]:
	var available: Array[int] = []
	for type_value in ROOM_TYPE_WEIGHTS:
		var type := int(type_value)
		if _is_type_allowed_on_floor(type, floor_number, room_floor_count):
			available.append(type)
	var result: Array[int] = []
	while not available.is_empty():
		var total_weight := 0
		for type in available:
			total_weight += int(ROOM_TYPE_WEIGHTS[type])
		var roll := rng.randi_range(1, total_weight)
		var selected := available[0]
		for type in available:
			roll -= int(ROOM_TYPE_WEIGHTS[type])
			if roll <= 0:
				selected = type
				break
		result.append(selected)
		available.erase(selected)
	return result


func _is_type_allowed_on_floor(
	type: int,
	floor_number: int,
	room_floor_count: int
) -> bool:
	if (
		type in [RunMapGraph.NodeType.HARD_COMBAT, RunMapGraph.NodeType.REST]
		and floor_number < FIRST_RANDOM_SPECIAL_FLOOR
	):
		return false
	if type == RunMapGraph.NodeType.REST and floor_number == room_floor_count - 1:
		return false
	return true


func _shuffle_ints(values: Array[int], rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temporary := values[index]
		values[index] = values[swap_index]
		values[swap_index] = temporary
