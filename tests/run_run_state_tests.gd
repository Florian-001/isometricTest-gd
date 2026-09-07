extends SceneTree

var failed := false
var controller: RunController
var directory := "res://.godot/run_state_validation"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	controller = RunController.new()
	controller.config = load("res://resources/run/default_run.tres")
	controller.save_path = directory + "/state_%d.json" % Time.get_ticks_usec()
	root.add_child(controller)
	check(controller.new_run(10), "new run checkpoint")
	var state := controller.state
	var original := state.to_data()
	check(not controller.select_room(9999), "invalid room rejected")
	# Isolated room fixtures reuse a generated connected graph.
	var kinds := [RunMapGraph.NodeType.REST, RunMapGraph.NodeType.CHEST, RunMapGraph.NodeType.SHOP, RunMapGraph.NodeType.HARD_COMBAT]
	for kind in kinds:
		controller.state = RunState.from_data(original)
		state = controller.state
		var id := state.available_rooms()[0]
		state.graph.get_node_by_id(id).type = kind
		state.party[0].health = 1
		state.party[1].health = 99
		check(controller.select_room(id), "room selection saves kind %d" % kind)
		match kind:
			RunMapGraph.NodeType.REST:
				check(state.party[0].health == 16 and state.party[1].health == 100, "rest rounds up and caps healing")
				controller.resume_room()
				check(state.party[0].health == 16, "rest cannot heal twice")
			RunMapGraph.NodeType.CHEST:
				check(state.gold == 80 and state.inventory.size() == 1, "treasure grants gold and equipment")
				controller.resume_room()
				check(state.gold == 80 and state.inventory.size() == 1, "treasure cannot reward twice")
			RunMapGraph.NodeType.SHOP:
				check(state.pending.offers.size() == 3, "three merchant offers")
				var stock := {}
				for path in state.pending.offers:
					stock[path] = true
				check(stock.size() == 3, "merchant offers distinct equipment")
				check(not controller.buy_offer(-1) and not controller.buy_offer(3), "invalid offers rejected")
				check(controller.buy_offer(0), "affordable purchase succeeds")
				check(state.gold == 10 and state.inventory.size() == 1, "purchase deducts gold and gives one item")
				check(not controller.buy_offer(0) and not controller.buy_offer(1), "sold and unaffordable offers rejected")
				var saved := controller.save_store.load_run()
				check(saved.pending.purchased.has(0) and saved.gold == 10, "purchases survive loading")
				controller.state = saved
				check(not controller.buy_offer(0), "loading cannot duplicate a purchase")
				controller.state = state
			RunMapGraph.NodeType.HARD_COMBAT:
				var entry := controller.save_store.load_run()
				check(entry.pending.encounter == state.pending.encounter and entry.party[0].health == 1, "battle entry is saved before combat")
				check(not controller.complete_room(), "unresolved combat cannot be skipped")
				var results: Array[Dictionary] = []
				for member in state.party:
					results.append({"id": member.id, "health": member.health, "max_health": member.max_health, "equipment": Array(member.equipment)})
				check(controller.finish_battle(id, true, results, []), "elite battle resolves")
				check(state.gold == 80 and state.inventory.size() == 1, "elite grants gold and equipment")
				check(not controller.finish_battle(id, true, results, []), "duplicate elite result rejected")
		check(controller.complete_room(), "room completion")
		check(not controller.complete_room(), "duplicate room completion rejected")
		check(state.route == [id], "exactly one room recorded")
	# Permanent loss must survive rest and serialization.
	controller.state = RunState.from_data(original)
	state = controller.state
	state.party[0].health = 0
	state.party[0].lost = true
	state.party[0].equipment.clear()
	var id := state.available_rooms()[0]
	state.graph.get_node_by_id(id).type = RunMapGraph.NodeType.REST
	controller.select_room(id)
	check(state.party[0].lost and state.party[0].health == 0, "rest never resurrects")
	check(controller.save_store.load_run().party[0].lost, "loss survives save")
	# Unknown-room content is reproducible, independent of visual randomness.
	var outcomes := {}
	for seed_value in range(100):
		controller.state = RunState.from_data(original)
		state = controller.state
		state.graph.seed_value = seed_value
		var node := state.graph.get_node_by_id(state.available_rooms()[0])
		node.type = RunMapGraph.NodeType.RANDOM
		var first := controller._prepare_room(node)
		var second := controller._prepare_room(node)
		check(first == second, "unknown outcome deterministic")
		outcomes[int(first.type)] = true
	check(outcomes.size() == 3, "unknown rooms exercise combat, treasure, and rest")
	# Save rotation and malformed checkpoints.
	controller.state = RunState.from_data(original)
	state = controller.state
	state.gold = 111
	check(controller.save_store.save_run(state), "first checkpoint")
	state.gold = 222
	check(controller.save_store.save_run(state), "atomic replacement")
	check(controller.save_store.load_run().gold == 222, "latest checkpoint loaded")
	var f := FileAccess.open(controller.save_path, FileAccess.WRITE)
	f.store_string("{broken")
	f.close()
	check(controller.save_store.load_run().gold == 111 and controller.save_store.recovered_backup, "corrupt primary recovers previous checkpoint")
	state.gold = 333
	check(controller.save_store.save_run(state), "saving after backup recovery succeeds")
	check(controller.save_store.load_run().gold == 333, "recovery preserves new progress")
	f = FileAccess.open(controller.save_path, FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	f = FileAccess.open(controller.save_path + ".bak", FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	check(controller.save_store.load_run() == null and not controller.save_store.error_message.is_empty(), "unreadable saves are reported and kept")
	check(controller.save_store.exists(), "corrupt files are not deleted")
	for key in ["version", "graph", "route", "party", "inventory", "pending"]:
		var malformed := original.duplicate(true)
		malformed[key] = null
		check(RunState.from_data(malformed) == null, "malformed %s rejected" % key)
	var invalid_route := original.duplicate(true)
	invalid_route.route = [999]
	check(RunState.from_data(invalid_route) == null, "invalid saved route rejected")
	# Failed writes roll back the in-memory transaction.
	controller.state = RunState.from_data(original)
	controller.state.graph.get_node_by_id(controller.state.available_rooms()[0]).type = RunMapGraph.NodeType.CHEST
	var blocker := directory + "/blocker"
	f = FileAccess.open(blocker, FileAccess.WRITE)
	f.store_string("file")
	f.close()
	controller.save_store.path = blocker + "/cannot_write.json"
	check(not controller.select_room(controller.state.available_rooms()[0]), "failed checkpoint rejects room entry")
	check(controller.state.gold == 50 and controller.state.pending.is_empty(), "failed checkpoint does not mutate progress")
	controller.queue_free()
	await process_frame
	if not failed:
		print("RUN_STATE_TESTS_OK")
	quit(1 if failed else 0)

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
