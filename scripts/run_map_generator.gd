class_name RunMapGenerator
extends RefCounted

const DEFAULT_SEED := 1337
const DEFAULT_TIER_COUNT := 12
const LANE_COUNT := 3

const MANDATORY_TYPES := {
	1: RunMapGraph.NodeType.NORMAL_COMBAT,
	2: RunMapGraph.NodeType.RANDOM,
	3: RunMapGraph.NodeType.REST,
	4: RunMapGraph.NodeType.SHOP,
	5: RunMapGraph.NodeType.CHEST,
	6: RunMapGraph.NodeType.HARD_COMBAT,
}


func generate(seed_value: int = DEFAULT_SEED, tier_count: int = DEFAULT_TIER_COUNT) -> RunMapGraph:
	tier_count = maxi(tier_count, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var graph := RunMapGraph.new(tier_count, LANE_COUNT)

	for tier in range(tier_count):
		if tier == 0:
			graph.add_node(tier, LANE_COUNT >> 1, RunMapGraph.NodeType.START)
			continue
		if tier == tier_count - 1:
			graph.add_node(tier, LANE_COUNT >> 1, RunMapGraph.NodeType.BOSS)
			continue

		for lane in range(LANE_COUNT):
			var type := _choose_type(rng, tier)
			if lane == 0 and MANDATORY_TYPES.has(tier):
				type = MANDATORY_TYPES[tier]
			graph.add_node(tier, lane, type)

	_connect_three_paths(graph, rng)
	return graph


func _choose_type(rng: RandomNumberGenerator, tier: int) -> int:
	var choices: Array[int] = [
		RunMapGraph.NodeType.NORMAL_COMBAT,
		RunMapGraph.NodeType.NORMAL_COMBAT,
		RunMapGraph.NodeType.NORMAL_COMBAT,
		RunMapGraph.NodeType.NORMAL_COMBAT,
		RunMapGraph.NodeType.REST,
		RunMapGraph.NodeType.REST,
		RunMapGraph.NodeType.SHOP,
		RunMapGraph.NodeType.CHEST,
		RunMapGraph.NodeType.RANDOM,
		RunMapGraph.NodeType.RANDOM,
	]
	if tier >= 3:
		choices.append(RunMapGraph.NodeType.HARD_COMBAT)
		choices.append(RunMapGraph.NodeType.HARD_COMBAT)
	return choices[rng.randi_range(0, choices.size() - 1)]


func _connect_three_paths(graph: RunMapGraph, rng: RandomNumberGenerator) -> void:
	var start := graph.get_nodes_in_tier(0)[0]
	var first_tier := graph.get_nodes_in_tier(1)
	for target in first_tier:
		graph.add_edge(start.id, target.id)

	# Every lane has a continuous straight route from the first choice to the boss approach.
	for tier in range(1, graph.tier_count - 2):
		var from_nodes := graph.get_nodes_in_tier(tier)
		var to_nodes := graph.get_nodes_in_tier(tier + 1)
		for lane in range(LANE_COUNT):
			graph.add_edge(from_nodes[lane].id, to_nodes[lane].id)

		# Every transition offers one nearby switch, alternating lane pairs.
		var lower_lane := (tier - 1) % (LANE_COUNT - 1)
		var source_lane := lower_lane
		var target_lane := lower_lane + 1
		if rng.randi_range(0, 1) == 1:
			source_lane = lower_lane + 1
			target_lane = lower_lane
		graph.add_edge(from_nodes[source_lane].id, to_nodes[target_lane].id)

	var boss := graph.get_nodes_in_tier(graph.tier_count - 1)[0]
	var final_tier := graph.get_nodes_in_tier(graph.tier_count - 2)
	for source in final_tier:
		graph.add_edge(source.id, boss.id)
