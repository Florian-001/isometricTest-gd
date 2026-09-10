@tool
extends McpTestSuite

func suite_name() -> String:
	return "run_map_generation"

func test_one_thousand_seeds_obey_route_and_room_rules() -> void:
	var generator := RunMapGenerator.new()
	var signatures := {}
	var saw_merge := false
	var saw_branch := false
	for seed_value in range(1000):
		var graph := generator.generate(seed_value)
		assert_true(graph != null, "generation must succeed for seed %d" % seed_value)
		if graph == null:
			return
		assert_eq(graph.get_signature(), generator.generate(seed_value).get_signature(), "same seed must reproduce every room and connection")
		signatures[graph.get_signature()] = true
		assert_eq(graph.tier_count, 16, "fifteen floors plus boss")
		assert_eq(graph.lane_count, 7, "seven potential columns")
		assert_true(graph.get_nodes_in_tier(0).size() >= 2, "at least two starts")
		assert_eq(graph.get_nodes_in_tier(15).size(), 1, "one boss")
		assert_eq(graph.get_nodes_in_tier(15)[0].type, RunMapGraph.NodeType.BOSS, "boss at summit")
		for node in graph.nodes:
			var incoming := graph.incoming(node.id)
			var outgoing := graph.outgoing(node.id)
			assert_true(node.tier == 0 or not incoming.is_empty(), "no unreachable rooms")
			assert_true(node.tier == 15 or not outgoing.is_empty(), "no dead ends")
			saw_merge = saw_merge or incoming.size() > 1
			saw_branch = saw_branch or outgoing.size() > 1
			if node.tier in [0, 8, 14]:
				assert_eq(node.type, {0: RunMapGraph.NodeType.NORMAL_COMBAT, 8: RunMapGraph.NodeType.CHEST, 14: RunMapGraph.NodeType.REST}[node.tier], "mandatory floor")
			if node.type in [RunMapGraph.NodeType.HARD_COMBAT, RunMapGraph.NodeType.REST]:
				assert_true(node.tier >= 5, "no early elites/rest")
			assert_true(node.tier != 13 or node.type != RunMapGraph.NodeType.REST, "no floor fourteen rest")
			var sibling_types := {}
			for target_id in outgoing:
				var target := graph.get_node_by_id(target_id)
				assert_eq(target.tier, node.tier + 1, "adjacent floors only")
				assert_true(target.tier == 15 or absi(target.lane - node.lane) <= 1, "nearby columns only")
				if node.type in [RunMapGraph.NodeType.HARD_COMBAT, RunMapGraph.NodeType.REST, RunMapGraph.NodeType.SHOP]:
					assert_true(target.type != node.type, "no repeated restricted room")
				if target.tier not in [8, 14, 15]:
					assert_true(not sibling_types.has(target.type), "branch choices have different room types")
					sibling_types[target.type] = true
		for edge in graph.edges:
			var a := graph.get_node_by_id(edge.x)
			var b := graph.get_node_by_id(edge.y)
			for other in graph.edges:
				var c := graph.get_node_by_id(other.x)
				var d := graph.get_node_by_id(other.y)
				if a.tier == c.tier:
					assert_true((a.lane - c.lane) * (b.lane - d.lane) >= 0, "paths never cross")
		var roundtrip := RunMapGraph.from_data(graph.to_data())
		assert_true(roundtrip != null, "graph serialization remains valid")
		assert_eq(roundtrip.get_signature(), graph.get_signature(), "saved graph preserves exact layout")
	assert_true(saw_merge and saw_branch, "generated maps branch and merge")
	assert_eq(signatures.size(), 1000, "different seeds produce distinct maps")

func test_impossible_configuration_is_bounded() -> void:
	var settings := RunMapSettings.new()
	settings.combat_weight = 0
	settings.shop_weight = 0
	settings.unknown_weight = 0
	settings.generation_attempts = 2
	assert_true(RunMapGenerator.new().generate(2, settings) == null, "invalid room weights fail without hanging")


func test_linear_combat_topology_and_save_validation() -> void:
	var settings := load("res://resources/run/five_combats_map_settings.tres") as RunMapSettings
	for seed_value in range(20):
		var graph := RunMapGenerator.new().generate(seed_value, settings)
		assert_eq(graph.nodes.size(), 5, "exactly five combats")
		assert_eq(graph.lane_count, 1, "one lane")
		assert_eq(graph.edges.size(), 4, "four sequential connections")
		for tier in range(5):
			var node := graph.get_nodes_in_tier(tier)[0]
			assert_eq(node.type, RunMapGraph.NodeType.NORMAL_COMBAT, "normal combats only")
			assert_eq(graph.is_terminal_combat(node.id), tier == 4, "only last combat is terminal")
		assert_eq(RunMapGraph.from_data(graph.to_data()).get_signature(), graph.get_signature(), "linear graph round-trips")
	var data := RunMapGenerator.new().generate(10, settings).to_data()
	for kind in [RunMapGraph.NodeType.BOSS, RunMapGraph.NodeType.HARD_COMBAT, RunMapGraph.NodeType.REST]:
		var invalid := data.duplicate(true)
		invalid.nodes[4][2] = kind
		assert_true(RunMapGraph.from_data(invalid) == null, "linear graphs reject non-normal rooms")
	for key in ["layout", "tiers", "lanes"]:
		var invalid := data.duplicate(true)
		invalid[key] = 1.5
		assert_true(RunMapGraph.from_data(invalid) == null, "fractional %s rejected" % key)
	var broken := data.duplicate(true)
	broken.edges.remove_at(2)
	assert_true(RunMapGraph.from_data(broken) == null, "disconnected chain rejected")
	broken = data.duplicate(true)
	broken.edges.append([0, 2])
	assert_true(RunMapGraph.from_data(broken) == null, "skipped floor rejected")
	broken = data.duplicate(true)
	broken.erase("layout")
	assert_true(RunMapGraph.from_data(broken) == null, "short graphs require explicit layout metadata")
	var legacy := RunMapGenerator.new().generate(10).to_data()
	legacy.erase("layout")
	assert_true(RunMapGraph.from_data(legacy) != null, "legacy Ascent saves remain readable")
	settings = settings.duplicate()
	for count in [1, 15]:
		settings.combat_count = count
		var graph := RunMapGenerator.new().generate(10, settings)
		assert_true(RunMapGraph.from_data(graph.to_data()) != null, "supported count boundary round-trips")
	for count in [0, 16]:
		settings.combat_count = count
		assert_true(RunMapGenerator.new().generate(10, settings) == null, "invalid count rejected")
