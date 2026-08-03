@tool
extends McpTestSuite


func suite_name() -> String:
	return "run_map_generation"


func test_default_map_is_deterministic_complete_and_traversable() -> void:
	var generator := RunMapGenerator.new()
	var graph := generator.generate()
	var repeated := generator.generate()
	assert_eq(graph.get_signature(), repeated.get_signature(), "the default seed should reproduce the same graph")
	assert_eq(graph.tier_count, 12, "the route should contain exactly twelve tiers")
	assert_eq(graph.get_nodes_in_tier(0).size(), 1, "the first tier should contain one Start")
	assert_eq(graph.get_nodes_in_tier(11).size(), 1, "the final tier should contain one Boss")
	assert_eq(graph.get_nodes_in_tier(0)[0].type, RunMapGraph.NodeType.START, "the first node should be Start")
	assert_eq(graph.get_nodes_in_tier(11)[0].type, RunMapGraph.NodeType.BOSS, "the final node should be Boss")
	assert_eq(graph.lane_count, 3, "the map should expose left, middle, and right lanes")
	for tier in range(1, graph.tier_count - 1):
		var tier_nodes := graph.get_nodes_in_tier(tier)
		assert_eq(tier_nodes.size(), 3, "every intermediate tier should contain three path nodes")
		var lanes: Array[int] = []
		for node in tier_nodes:
			lanes.append(node.lane)
		lanes.sort()
		assert_eq(lanes, [0, 1, 2], "each intermediate tier should fill all three lanes")

	var present_types: Dictionary = {}
	var incoming: Dictionary = {}
	var outgoing: Dictionary = {}
	var crossovers_by_transition: Dictionary = {}
	var crossover_pair_by_transition: Dictionary = {}
	var total_crossovers := 0
	for node in graph.nodes:
		present_types[node.type] = true
		incoming[node.id] = 0
		outgoing[node.id] = 0
	for edge in graph.edges:
		var source := graph.get_node_by_id(edge.x)
		var target := graph.get_node_by_id(edge.y)
		assert_true(source != null and target != null, "every edge should reference real nodes")
		assert_eq(target.tier, source.tier + 1, "edges should only join adjacent tiers")
		assert_true(absi(target.lane - source.lane) <= 1, "edges should never jump across a path")
		if source.tier >= 1 and target.tier < graph.tier_count - 1 and source.lane != target.lane:
			crossovers_by_transition[source.tier] = crossovers_by_transition.get(source.tier, 0) + 1
			crossover_pair_by_transition[source.tier] = mini(source.lane, target.lane)
			total_crossovers += 1
		outgoing[source.id] += 1
		incoming[target.id] += 1
	assert_eq(total_crossovers, graph.tier_count - 3, "every intermediate transition should offer a crossover")
	for tier in range(1, graph.tier_count - 2):
		assert_eq(crossovers_by_transition.get(tier, 0), 1, "each transition should contain one crossover")
		assert_eq(
			crossover_pair_by_transition.get(tier, -1),
			(tier - 1) % (graph.lane_count - 1),
			"crossover pairs should alternate between left-middle and middle-right"
		)

	for tier in range(1, graph.tier_count - 2):
		for lane in range(graph.lane_count):
			var source := _get_node_in_lane(graph, tier, lane)
			var target := _get_node_in_lane(graph, tier + 1, lane)
			assert_true(
				graph.edges.has(Vector2i(source.id, target.id)),
				"every lane should retain its straight path on every intermediate transition"
			)

	for type in [
		RunMapGraph.NodeType.NORMAL_COMBAT,
		RunMapGraph.NodeType.HARD_COMBAT,
		RunMapGraph.NodeType.REST,
		RunMapGraph.NodeType.SHOP,
		RunMapGraph.NodeType.CHEST,
		RunMapGraph.NodeType.RANDOM,
	]:
		assert_true(present_types.has(type), "every requested intermediate node type should appear")

	for node in graph.nodes:
		if node.tier > 0:
			assert_true(incoming[node.id] > 0, "every non-Start node should have an incoming route")
		if node.tier < graph.tier_count - 1:
			assert_true(outgoing[node.id] > 0, "every non-Boss node should have an outgoing route")
		if node.type == RunMapGraph.NodeType.HARD_COMBAT:
			assert_true(node.tier >= 3, "hard combat should not appear in the earliest tiers")

	var start_id: int = graph.get_nodes_in_tier(0)[0].id
	var reachable := _collect_reachable(graph, start_id, false)
	assert_eq(reachable.size(), graph.nodes.size(), "every node should be reachable from Start")
	var boss_id: int = graph.get_nodes_in_tier(graph.tier_count - 1)[0].id
	var reaches_boss := _collect_reachable(graph, boss_id, true)
	assert_eq(reaches_boss.size(), graph.nodes.size(), "every node should lead onward to Boss")


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
