@tool
extends McpTestSuite


func suite_name() -> String:
	return "run_map_generation"


func test_default_map_is_deterministic_sparse_and_uses_six_routes() -> void:
	var generator := RunMapGenerator.new()
	var graph := generator.generate()
	var repeated := generator.generate()
	assert_eq(graph.get_signature(), repeated.get_signature(), "the default seed should reproduce the same graph")
	assert_eq(graph.tier_count, 17, "Start, fifteen room floors, and Boss should produce seventeen tiers")
	assert_eq(graph.lane_count, 7, "the room template should use seven lanes")
	assert_eq(graph.routes.size(), 6, "the generator should trace exactly six routes")
	assert_true(graph.routes[0][0] != graph.routes[1][0], "the first two routes should start in different rooms")

	var used_positions: Dictionary = {}
	for route in graph.routes:
		assert_eq(route.size(), 15, "every traced route should cross all fifteen room floors")
		for floor_index in range(route.size()):
			var floor_number := floor_index + 1
			var lane := route[floor_index]
			assert_true(lane >= 0 and lane < graph.lane_count, "route lanes should remain inside the template")
			used_positions[Vector2i(floor_number, lane)] = true
			if floor_index == 0:
				continue
			assert_true(absi(lane - route[floor_index - 1]) <= 1, "routes should move only to a neighboring room")
			var source := _get_node_in_lane(graph, floor_number - 1, route[floor_index - 1])
			var target := _get_node_in_lane(graph, floor_number, lane)
			assert_true(graph.edges.has(Vector2i(source.id, target.id)), "every traced segment should exist in the materialized graph")

	var room_node_count := 0
	for node in graph.nodes:
		if node.tier >= 1 and node.tier <= 15:
			room_node_count += 1
			assert_true(used_positions.has(Vector2i(node.tier, node.lane)), "pathless template rooms should be removed")
	assert_eq(room_node_count, used_positions.size(), "every traced room position should materialize exactly once")
	assert_true(room_node_count < 7 * 15, "six routes should produce a sparse map instead of filling the template")
	for floor_number in range(1, 16):
		var floor_nodes := graph.get_nodes_in_tier(floor_number)
		assert_true(not floor_nodes.is_empty(), "every room floor should retain at least one path room")
		assert_true(floor_nodes.size() <= RunMapGenerator.ROUTE_COUNT, "a floor cannot use more rooms than traced routes")

	assert_eq(graph.get_nodes_in_tier(0).size(), 1, "the map should retain one Start marker")
	assert_eq(graph.get_nodes_in_tier(16).size(), 1, "the map should end at one Boss")
	assert_eq(graph.get_nodes_in_tier(0)[0].type, RunMapGraph.NodeType.START, "tier zero should be Start")
	assert_eq(graph.get_nodes_in_tier(16)[0].type, RunMapGraph.NodeType.BOSS, "tier sixteen should be Boss")


func test_sparse_topology_never_crosses_and_every_room_is_traversable() -> void:
	var graph := RunMapGenerator.new().generate()
	var incoming: Dictionary = {}
	var outgoing: Dictionary = {}
	for node in graph.nodes:
		incoming[node.id] = 0
		outgoing[node.id] = 0
	for edge in graph.edges:
		var source := graph.get_node_by_id(edge.x)
		var target := graph.get_node_by_id(edge.y)
		assert_true(source != null and target != null, "every edge should reference real nodes")
		assert_eq(target.tier, source.tier + 1, "all connections should advance exactly one tier")
		if source.tier >= 1 and target.tier <= 15:
			assert_true(absi(target.lane - source.lane) <= 1, "room connections should use one of the three closest rooms")
		outgoing[source.id] += 1
		incoming[target.id] += 1

	var room_edges: Array[Vector2i] = []
	for edge in graph.edges:
		var source := graph.get_node_by_id(edge.x)
		var target := graph.get_node_by_id(edge.y)
		if source.tier >= 1 and target.tier <= 15:
			room_edges.append(edge)
	for first_index in range(room_edges.size()):
		var first_source := graph.get_node_by_id(room_edges[first_index].x)
		var first_target := graph.get_node_by_id(room_edges[first_index].y)
		for second_index in range(first_index + 1, room_edges.size()):
			var second_source := graph.get_node_by_id(room_edges[second_index].x)
			var second_target := graph.get_node_by_id(room_edges[second_index].y)
			if first_source.tier != second_source.tier:
				continue
			var crosses := (
				first_source.lane < second_source.lane and first_target.lane > second_target.lane
				or first_source.lane > second_source.lane and first_target.lane < second_target.lane
			)
			assert_false(crosses, "room-to-room route segments should never cross")

	var start := graph.get_nodes_in_tier(0)[0]
	var boss := graph.get_nodes_in_tier(16)[0]
	assert_eq(outgoing[start.id], graph.get_nodes_in_tier(1).size(), "Start should fan into every used first-floor room")
	assert_eq(incoming[boss.id], graph.get_nodes_in_tier(15).size(), "every top Rest room should connect to Boss")
	for node in graph.nodes:
		if node.id != start.id:
			assert_true(incoming[node.id] > 0, "every non-Start node should have an incoming path")
		if node.id != boss.id:
			assert_true(outgoing[node.id] > 0, "every non-Boss node should have an outgoing path")

	var reachable := _collect_reachable(graph, start.id, false)
	assert_eq(reachable.size(), graph.nodes.size(), "every sparse room should be reachable from Start")
	var reaches_boss := _collect_reachable(graph, boss.id, true)
	assert_eq(reaches_boss.size(), graph.nodes.size(), "every sparse room should lead onward to Boss")


func test_room_assignment_matches_fixed_floors_weights_and_constraints() -> void:
	assert_eq(RunMapGenerator.ROOM_TYPE_WEIGHTS, {
		RunMapGraph.NodeType.NORMAL_COMBAT: 45,
		RunMapGraph.NodeType.RANDOM: 22,
		RunMapGraph.NodeType.HARD_COMBAT: 16,
		RunMapGraph.NodeType.REST: 12,
		RunMapGraph.NodeType.SHOP: 5,
	}, "room weights should match the guide's A20 distribution")
	for seed_value in range(24):
		_assert_room_assignment_rules(RunMapGenerator.new().generate(seed_value), 15)


func test_optional_length_argument_represents_room_floors() -> void:
	var graph := RunMapGenerator.new().generate(91, 18)
	assert_eq(graph.tier_count, 20, "eighteen room floors should add separate Start and Boss tiers")
	assert_eq(graph.routes.size(), 6, "custom-length maps should retain six route traces")
	for route in graph.routes:
		assert_eq(route.size(), 18, "route length should match the requested room-floor count")
	_assert_room_assignment_rules(graph, 18)


func _assert_room_assignment_rules(graph: RunMapGraph, room_floor_count: int) -> void:
	for node in graph.get_nodes_in_tier(1):
		assert_eq(node.type, RunMapGraph.NodeType.NORMAL_COMBAT, "floor one should contain only normal combat")
	for node in graph.get_nodes_in_tier(RunMapGenerator.TREASURE_FLOOR):
		assert_eq(node.type, RunMapGraph.NodeType.CHEST, "floor nine should contain only treasure")
	for node in graph.get_nodes_in_tier(room_floor_count):
		assert_eq(node.type, RunMapGraph.NodeType.REST, "the final room floor should contain only Rest sites")
	for node in graph.nodes:
		if node.type in [RunMapGraph.NodeType.HARD_COMBAT, RunMapGraph.NodeType.REST]:
			assert_true(node.tier >= RunMapGenerator.FIRST_RANDOM_SPECIAL_FLOOR, "Elite and Rest rooms should not appear below floor six")
		if node.type == RunMapGraph.NodeType.REST:
			assert_true(node.tier != room_floor_count - 1, "Rest should not appear immediately before the fixed top Rest floor")

	var outgoing: Dictionary = {}
	for node in graph.nodes:
		outgoing[node.id] = []
	for edge in graph.edges:
		(outgoing[edge.x] as Array).append(edge.y)
		var source := graph.get_node_by_id(edge.x)
		var target := graph.get_node_by_id(edge.y)
		if (
			source.tier >= 1
			and target.tier <= room_floor_count
			and source.type == target.type
			and RunMapGenerator.NON_CONSECUTIVE_TYPES.has(source.type)
		):
			assert_true(false, "Elite, Rest, and Shop rooms should not repeat across a direct path")

	for source in graph.nodes:
		var destination_ids := outgoing[source.id] as Array
		if destination_ids.size() < 2:
			continue
		var first_destination := graph.get_node_by_id(int(destination_ids[0]))
		if first_destination.tier in [1, RunMapGenerator.TREASURE_FLOOR, room_floor_count]:
			continue
		var destination_types: Dictionary = {}
		for destination_id in destination_ids:
			var destination := graph.get_node_by_id(int(destination_id))
			assert_false(destination_types.has(destination.type), "random branch destinations should have distinct room types")
			destination_types[destination.type] = true


func _get_node_in_lane(graph: RunMapGraph, tier: int, lane: int) -> RunMapGraph.NodeData:
	for node in graph.get_nodes_in_tier(tier):
		if node.lane == lane:
			return node
	return null


func _collect_reachable(graph: RunMapGraph, first_id: int, reverse: bool) -> Dictionary:
	var visited := {first_id: true}
	var pending: Array[int] = [first_id]
	while not pending.is_empty():
		var current: int = pending.pop_front()
		for edge in graph.edges:
			var source := edge.y if reverse else edge.x
			var target := edge.x if reverse else edge.y
			if source == current and not visited.has(target):
				visited[target] = true
				pending.append(target)
	return visited
