class_name RunState
extends RefCounted

enum Status { ACTIVE, WON, LOST }
var graph: RunMapGraph
var route: Array[int] = []
var party: Array[RunPartyMember] = []
var inventory: Array[String] = []
var gold: int = 50
var status: Status = Status.ACTIVE
## Pending room is committed but not acknowledged. Resolved rooms cannot reward twice.
var pending: Dictionary = {}
var last_message: String = "Choose a starting room."

func available_rooms() -> Array[int]:
	var result: Array[int] = []
	if status != Status.ACTIVE or not pending.is_empty():
		return result
	if route.is_empty():
		for node in graph.get_nodes_in_tier(0):
			result.append(node.id)
	else:
		result = graph.outgoing(route.back())
	return result

func to_data() -> Dictionary:
	var members: Array = []
	for member in party:
		members.append(member.to_data())
	return {"version": 1, "graph": graph.to_data(), "route": Array(route), "party": members,
		"inventory": Array(inventory).duplicate(), "gold": gold, "status": int(status),
		"pending": pending.duplicate(true), "message": last_message}

static func from_data(data: Dictionary) -> RunState:
	data = ItemDefinition.normalize_saved_paths(data)
	for key in ["version", "gold", "status"]:
		if not _integer(data.get(key)):
			return null
	if int(data.get("version", 0)) != 1 or not data.get("graph") is Dictionary:
		return null
	for key in ["route", "party", "inventory"]:
		if not data.get(key) is Array:
			return null
	if not data.get("pending") is Dictionary:
		return null
	var state := RunState.new()
	state.graph = RunMapGraph.from_data(data.graph)
	if state.graph == null:
		return null
	state.gold = int(data.get("gold", -1))
	var saved_status := int(data.get("status", -1))
	if state.gold < 0 or saved_status < 0 or saved_status > 2 or data.party.is_empty():
		return null
	state.status = saved_status as Status
	var identities := {}
	for raw in data.party:
		if not raw is Dictionary:
			return null
		var member := RunPartyMember.from_data(raw)
		if member == null or identities.has(member.id):
			return null
		identities[member.id] = true
		state.party.append(member)
	for path in data.inventory:
		if not path is String:
			return null
		if not path.is_empty() and (not ResourceLoader.exists(path) or not load(path) is ItemDefinition):
			return null
		state.inventory.append(path)
	for raw in data.route:
		if not _integer(raw):
			return null
		var id := int(raw)
		if not state.available_rooms().has(id):
			# Validate topology independently of the saved terminal status.
			var node := state.graph.get_node_by_id(id)
			if node == null or (state.route.is_empty() and node.tier != 0) or (not state.route.is_empty() and not state.graph.outgoing(state.route.back()).has(id)):
				return null
		state.route.append(id)
	state.pending = data.pending.duplicate(true)
	if not state.pending.is_empty():
		for key in ["node_id", "type", "gold", "price"]:
			if not _integer(state.pending.get(key)):
				return null
			state.pending[key] = int(state.pending[key])
		if not state.pending.get("resolved") is bool:
			return null
		var fraction: Variant = state.pending.get("rest_fraction")
		if not (fraction is int or fraction is float) or not is_finite(float(fraction)) or float(fraction) < 0 or float(fraction) > 1:
			return null
		if int(state.pending.gold) < 0 or int(state.pending.price) <= 0:
			return null
		var node := state.graph.get_node_by_id(int(state.pending.get("node_id", -1)))
		if node == null or state.route.has(node.id):
			return null
		if (state.route.is_empty() and node.tier != 0) or (not state.route.is_empty() and not state.graph.outgoing(state.route.back()).has(node.id)):
			return null
		var kind := int(state.pending.get("type", -1))
		if kind < 1 or kind > RunMapGraph.NodeType.BOSS or kind == RunMapGraph.NodeType.RANDOM:
			return null
		if node.type != RunMapGraph.NodeType.RANDOM and node.type != kind:
			return null
		if node.type == RunMapGraph.NodeType.RANDOM and kind not in [RunMapGraph.NodeType.NORMAL_COMBAT, RunMapGraph.NodeType.CHEST, RunMapGraph.NodeType.REST]:
			return null
		if not state.pending.get("offers", []) is Array or not state.pending.get("purchased", []) is Array:
			return null
		for key in ["encounter", "reward_item"]:
			var path := str(state.pending.get(key, ""))
			if not path.is_empty() and not ResourceLoader.exists(path):
				return null
		var reward_path := str(state.pending.get("reward_item", ""))
		if not reward_path.is_empty() and not load(reward_path) is ItemDefinition:
			return null
		if kind in [RunMapGraph.NodeType.NORMAL_COMBAT, RunMapGraph.NodeType.HARD_COMBAT, RunMapGraph.NodeType.BOSS]:
			var resolved := RunCombatProgression.resolve_pending(state.pending, node.tier + 1)
			if not resolved.error.is_empty():
				return null
			var encounter: RunEncounterDefinition = resolved.encounter
			if encounter.battle_map is BattleMapTemplateDefinition:
				if not encounter.chief_node_name.is_empty() or not TemplateEncounterSetup.validate_saved(
					encounter.battle_map, state.pending.get("template_setup"), state.party.size()
				).is_empty():
					return null
		elif state.pending.has("combat_progression"):
			return null
		for path in state.pending.get("offers", []):
			if not path is String or not ResourceLoader.exists(path) or not load(path) is ItemDefinition:
				return null
		var purchased := {}
		var purchased_indices: Array[int] = []
		for raw in state.pending.get("purchased", []):
			if not _integer(raw):
				return null
			var index := int(raw)
			if index < 0 or index >= state.pending.get("offers", []).size() or purchased.has(index):
				return null
			purchased[index] = true
			purchased_indices.append(index)
		state.pending.purchased = purchased_indices
	var survivors := state.party.filter(func(member: RunPartyMember) -> bool: return not member.lost).size()
	if (state.status == Status.LOST) != (survivors == 0):
		return null
	var final_completed := not state.route.is_empty() and state.graph.is_terminal_combat(state.route.back())
	final_completed = final_completed or (state.graph.is_terminal_combat(int(state.pending.get("node_id", -1))) and bool(state.pending.get("resolved", false)) and bool(state.pending.get("victory", false)))
	if (state.status == Status.WON) != final_completed:
		return null
	state.last_message = str(data.get("message", ""))
	return state

## Fill saved grid vacancies before extending the pack.
func add_inventory_item(path: String) -> void:
	if path.is_empty():
		return
	var index := inventory.find("")
	if index < 0:
		inventory.append(path)
	else:
		inventory[index] = path


static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))
