class_name RunController
extends Node

signal state_changed
signal battle_requested(encounter: RunEncounterDefinition, members: Array[Dictionary], inventory: Array[String], node_id: int)
signal problem_reported(message: String)

@export var config: RunConfig
@export_category("Development")
@export var use_fixed_seed: bool = false
@export var fixed_seed: int = 1337
@export var save_path: String = "user://run/active.json"

var state: RunState
var save_store := RunSaveStore.new()
var error_message: String = ""
var battle_open: bool = false

func _ready() -> void:
	save_store.path = save_path
	state = save_store.load_run()
	error_message = save_store.error_message

func has_saved_run() -> bool:
	return state != null or save_store.exists()

func has_unfinished_run() -> bool:
	return state != null and state.status == RunState.Status.ACTIVE

func new_run(seed_override: int = -1) -> bool:
	if config == null:
		return _problem("Assign a complete run configuration in the Inspector.")
	var report := config.validate_configuration()
	if not report.errors.is_empty():
		return _problem(" ".join(report.errors))
	for warning in report.warnings:
		push_warning(warning)
	var members: Array[RunPartyMember] = []
	var party_scene := config.starting_party.instantiate()
	for child in party_scene.get_children():
		if child is TacticalCharacter:
			members.append(RunPartyMember.from_character(child))
	party_scene.free()
	return _save_new_run(members, seed_override)


func new_run_with_party(character_ids: Array[String], seed_override: int = -1) -> bool:
	if config == null:
		return _problem("Assign a complete run configuration in the Inspector.")
	if character_ids.is_empty() or character_ids.size() > 4:
		return _problem("Choose between one and four unique characters.")
	var roster := config.inspect_starting_roster()
	if not roster.errors.is_empty():
		return _problem(" ".join(roster.errors))
	var scenes := {}
	for entry in roster.entries:
		scenes[entry.id] = entry.scene
	var chosen := {}
	for id in character_ids:
		if not scenes.has(id) or chosen.has(id):
			return _problem("Choose distinct characters from the starting roster.")
		chosen[id] = true
	var report := config.validate_configuration(character_ids.size())
	if not report.errors.is_empty():
		return _problem(" ".join(report.errors))
	for warning in report.warnings:
		push_warning(warning)
	var members: Array[RunPartyMember] = []
	for id in character_ids:
		var character := (scenes[id] as PackedScene).instantiate() as TacticalCharacter
		members.append(RunPartyMember.from_character(character))
		character.free()
	return _save_new_run(members, seed_override)


## Commit the candidate first. A failed write must leave the previous run untouched.
func _save_new_run(members: Array[RunPartyMember], seed_override: int) -> bool:
	var seed_value := seed_override
	if seed_value < 0:
		seed_value = fixed_seed if use_fixed_seed else int(randi())
	var next := RunState.new()
	next.graph = RunMapGenerator.new().generate(seed_value, config.map_settings)
	if next.graph == null:
		return _problem("Could not generate a valid map with these room settings.")
	next.gold = config.starting_gold
	next.party = members
	if next.party.is_empty():
		return _problem("The starting party scene has no characters.")
	if not save_store.save_run(next):
		return _problem(save_store.error_message)
	state = next
	battle_open = false
	error_message = ""
	state_changed.emit()
	return true

func select_room(id: int) -> bool:
	if state == null or not state.available_rooms().has(id) or battle_open:
		return false
	var before := state.to_data()
	var prepared := _prepare_room(state.graph.get_node_by_id(id))
	if prepared.is_empty():
		return false
	state.pending = prepared
	if not _commit(before):
		return false
	resume_room()
	return true

func resume_room() -> void:
	if state == null or state.pending.is_empty() or bool(state.pending.get("resolved", false)) or state.status != RunState.Status.ACTIVE:
		return
	if is_combat_room():
		if battle_open:
			return
		var floor_number := state.graph.get_node_by_id(int(state.pending.node_id)).tier + 1
		var resolved := RunCombatProgression.resolve_pending(state.pending, floor_number)
		if not resolved.error.is_empty():
			_problem("%s Your checkpoint has been kept." % resolved.error)
			return
		var encounter: RunEncounterDefinition = resolved.encounter
		var capacity_error := RunConfig.validate_encounter_capacity(encounter.battle_map, state.party.size())
		if not capacity_error.is_empty():
			_problem("%s Your checkpoint has been kept." % capacity_error)
			return
		if encounter.battle_map is BattleMapTemplateDefinition:
			var error := TemplateEncounterSetup.validate_saved(encounter.battle_map, state.pending.get("template_setup"), state.party.size())
			if not error.is_empty():
				_problem("%s Your checkpoint has been kept." % error)
				return
		var members: Array[Dictionary] = []
		for member in state.party:
			members.append(member.to_data())
		battle_open = true
		battle_requested.emit(encounter, members, state.inventory.duplicate(), int(state.pending.node_id))
	elif int(state.pending.type) != RunMapGraph.NodeType.SHOP:
		var before := state.to_data()
		_apply_reward()
		state.pending.resolved = true
		_commit(before)

func is_combat_room() -> bool:
	return state != null and int(state.pending.get("type", -1)) in [RunMapGraph.NodeType.NORMAL_COMBAT, RunMapGraph.NodeType.HARD_COMBAT, RunMapGraph.NodeType.BOSS]

func finish_battle(node_id: int, victory: bool, results: Array[Dictionary], inventory: Array[String]) -> bool:
	if state == null or state.status != RunState.Status.ACTIVE or not is_combat_room() or int(state.pending.get("node_id", -1)) != node_id or bool(state.pending.get("resolved", false)):
		return false
	var before := state.to_data()
	var by_id := {}
	for result in results:
		by_id[str(result.get("id", ""))] = result
	for member in state.party:
		if member.lost:
			continue
		if not by_id.has(member.id):
			state = RunState.from_data(before)
			return _problem("The battle returned an incomplete party result.")
		var result: Dictionary = by_id[member.id]
		if result.has("class_levels"):
			if not CharacterClassProgression.validate_data(result["class_levels"]).is_empty():
				state = RunState.from_data(before)
				return _problem("The battle returned invalid party class levels.")
			member.setup["class_levels"] = result["class_levels"].duplicate(true)
		member.max_health = maxi(1, int(result.get("max_health", member.max_health)))
		member.health = clampi(int(result.get("health", 0)), 0, member.max_health)
		member.lost = member.health == 0
		member.equipment.clear()
		if not member.lost:
			member.equipment.assign(result.get("equipment", []))
	state.inventory.assign(inventory)
	state.pending.resolved = true
	state.pending.victory = victory
	if victory:
		_apply_reward()
		if int(state.pending.type) == RunMapGraph.NodeType.BOSS:
			state.status = RunState.Status.WON
			state.last_message = "The chief has fallen. Your party reached the summit."
	else:
		state.status = RunState.Status.LOST
		state.last_message = "Your party fell on the road. This run has ended."
	if not _commit(before):
		return false
	battle_open = false
	return true

func buy_offer(index: int) -> bool:
	if state == null or state.status != RunState.Status.ACTIVE or int(state.pending.get("type", -1)) != RunMapGraph.NodeType.SHOP:
		return false
	var offers: Array = state.pending.get("offers", [])
	var purchased: Array = state.pending.get("purchased", [])
	var price := int(state.pending.get("price", 0))
	if index < 0 or index >= offers.size() or purchased.has(index) or state.gold < price:
		return false
	var before := state.to_data()
	state.gold -= price
	state.add_inventory_item(str(offers[index]))
	purchased.append(index)
	state.pending.purchased = purchased
	return _commit(before)

func complete_room() -> bool:
	if state == null or state.pending.is_empty() or battle_open:
		return false
	if not bool(state.pending.get("resolved", false)) and int(state.pending.type) != RunMapGraph.NodeType.SHOP:
		return false
	var before := state.to_data()
	if state.status != RunState.Status.LOST:
		state.route.append(int(state.pending.node_id))
	state.pending.clear()
	return _commit(before)

func _prepare_room(node: RunMapGraph.NodeData) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = state.graph.seed_value ^ (node.id * 1000003 + 730201)
	var type := node.type
	if type == RunMapGraph.NodeType.RANDOM:
		var roll := rng.randi_range(1, config.unknown_combat_weight + config.unknown_treasure_weight + config.unknown_rest_weight)
		type = RunMapGraph.NodeType.NORMAL_COMBAT if roll <= config.unknown_combat_weight else (RunMapGraph.NodeType.CHEST if roll <= config.unknown_combat_weight + config.unknown_treasure_weight else RunMapGraph.NodeType.REST)
	var pending := {"node_id": node.id, "type": type, "resolved": false, "offers": [], "purchased": [],
		"encounter": "", "reward_item": "", "gold": 0, "price": config.shop_price, "rest_fraction": config.rest_fraction}
	match type:
		RunMapGraph.NodeType.NORMAL_COMBAT, RunMapGraph.NodeType.HARD_COMBAT:
			var choices := config.normal_encounters if type == RunMapGraph.NodeType.NORMAL_COMBAT else config.elite_encounters
			if choices.is_empty():
				_problem("Add an encounter to this combat room's encounter catalog.")
				return {}
			var selected := choices[rng.randi_range(0, choices.size() - 1)]
			if selected == null or selected.resource_path.is_empty():
				_problem("Assign a saved encounter resource to every encounter catalog entry.")
				return {}
			pending.encounter = selected.resource_path
			pending.gold = config.combat_gold if type == RunMapGraph.NodeType.NORMAL_COMBAT else config.elite_gold
		RunMapGraph.NodeType.CHEST:
			pending.gold = config.treasure_gold
		RunMapGraph.NodeType.BOSS:
			pending.encounter = config.boss_encounter.resource_path
	if type in [RunMapGraph.NodeType.HARD_COMBAT, RunMapGraph.NodeType.CHEST]:
		pending.reward_item = config.equipment_pool[rng.randi_range(0, config.equipment_pool.size() - 1)].resource_path
	if type == RunMapGraph.NodeType.SHOP:
		var pool: Array[String] = []
		for item in config.equipment_pool:
			if not pool.has(item.resource_path):
				pool.append(item.resource_path)
		for offer in range(config.shop_offer_count):
			var index := rng.randi_range(0, pool.size() - 1)
			pending.offers.append(pool[index])
			pool.remove_at(index)
	if not str(pending.encounter).is_empty():
		var encounter := load(str(pending.encounter)) as RunEncounterDefinition
		if type in [RunMapGraph.NodeType.NORMAL_COMBAT, RunMapGraph.NodeType.HARD_COMBAT] and (not config.combat_stages.is_empty() or not config.floor_overrides.is_empty()):
			var settings := RunCombatProgression.snapshot(config, node.tier + 1, encounter)
			if not settings.error.is_empty():
				_problem(settings.error)
				return {}
			settings.erase("error")
			pending.combat_progression = settings
		var resolved := RunCombatProgression.resolve_pending(pending, node.tier + 1)
		if not resolved.error.is_empty():
			_problem(resolved.error)
			return {}
		encounter = resolved.encounter
		var capacity_error := RunConfig.validate_encounter_capacity(encounter.battle_map, state.party.size())
		if not capacity_error.is_empty():
			_problem(capacity_error)
			return {}
		if encounter.battle_map is BattleMapTemplateDefinition:
			if not encounter.chief_node_name.is_empty():
				_problem("Named-chief encounters require an authored map.")
				return {}
			var encounter_rng := RandomNumberGenerator.new()
			encounter_rng.seed = state.graph.seed_value ^ (node.id * 1000003 + 924731)
			var setup := TemplateEncounterSetup.create(encounter.battle_map, state.party.size(), encounter_rng)
			if not setup.error.is_empty():
				_problem(setup.error)
				return {}
			pending.template_setup = setup
			if pending.has("combat_progression") and int(setup.total_cr) < int(pending.combat_progression.combat_rating):
				push_warning("Floor %d can spend only CR %d of budget %d with this enemy pool and spawn capacity." % [node.tier + 1, setup.total_cr, pending.combat_progression.combat_rating])
	return pending

func _apply_reward() -> void:
	var gold_reward := int(state.pending.get("gold", 0))
	state.gold += gold_reward
	var item_path := str(state.pending.get("reward_item", ""))
	state.last_message = "Victory! +%d gold." % gold_reward if is_combat_room() else "Treasure found. +%d gold." % gold_reward
	if not item_path.is_empty():
		state.add_inventory_item(item_path)
		state.last_message += " Collected %s." % (load(item_path) as ItemDefinition).display_name
	if int(state.pending.type) == RunMapGraph.NodeType.REST:
		for member in state.party:
			if not member.lost:
				member.health = mini(member.max_health, member.health + ceili(member.max_health * float(state.pending.rest_fraction)))
		state.last_message = "Your survivors rest and recover %d%% of their maximum health." % roundi(float(state.pending.rest_fraction) * 100.0)

func _commit(before: Dictionary) -> bool:
	if not save_store.save_run(state):
		state = RunState.from_data(before)
		return _problem(save_store.error_message)
	error_message = ""
	state_changed.emit()
	return true

func _problem(message: String) -> bool:
	error_message = message
	problem_reported.emit(message)
	state_changed.emit()
	return false
