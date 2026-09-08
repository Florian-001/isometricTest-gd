extends SceneTree

var _failures: Array[String] = []
var _paths: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _run() -> void:
	await _test_checkpoint_and_battle()
	for path in _paths:
		for suffix in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	if _failures.is_empty():
		print("COMBAT_PROGRESSION_INTEGRATION_OK")
	for failure in _failures:
		push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_checkpoint_and_battle() -> void:
	var manager := (load("res://main.tscn") as PackedScene).instantiate() as MapManager
	var run := manager.get_node("RunController") as RunController
	var source_config := run.config
	run.config = source_config.duplicate()
	run.config.combat_stages = []
	for stage in source_config.combat_stages:
		run.config.combat_stages.append(stage.duplicate())
	# This fixture later lowers stage two to CR 5. Keep its earlier stage below
	# that value instead of depending on the current authored starting budget.
	run.config.combat_stages[0].starting_cr = 1
	run.config.combat_stages[0].cr_per_floor = 1
	run.save_path = "res://.godot/progression_validation/run_%d.json" % Time.get_ticks_usec()
	_paths.append(run.save_path)
	root.add_child(manager)
	_check(run.new_run(37), "New progression run saves successfully")
	if run.state == null:
		manager.queue_free()
		await process_frame
		return
	# Skip five rooms through a valid route. Their types must not determine combat progression.
	for index in range(5):
		var id := run.state.available_rooms()[0]
		run.state.graph.get_node_by_id(id).type = RunMapGraph.NodeType.REST
		run.state.route.append(id)
	var node := run.state.graph.get_node_by_id(run.state.available_rooms()[0])
	node.type = RunMapGraph.NodeType.HARD_COMBAT
	var override := RunCombatFloorOverride.new()
	override.floor = 6
	override.override_cr = true
	override.combat_rating = 4
	override.override_enemy_pool = true
	override.enemy_pool = [load("res://scenes/enemies/skeleton_archer.tscn")]
	run.config.floor_overrides = [override]
	_check(run.select_room(node.id), "A floor-six elite commits its overridden settings before opening")
	var battle := manager.current_battle
	_check(battle != null and battle.initialization_succeeded, "Progression settings reach a real TacticalBattle through MapManager")
	if battle == null:
		manager.queue_free()
		await process_frame
		return
	var enemies := battle._characters.filter(func(actor: TacticalCharacter) -> bool: return not actor.is_friendly())
	_check(enemies.size() == 4, "A four-CR override spawns four current CR-1 enemies")
	for actor: TacticalCharacter in enemies:
		_check(actor.definition.display_name == "Skeleton Archer", "The runtime battle uses the replacement pool")
		_check(actor.constitution_override == ceili(actor.definition.constitution * 1.5), "The existing elite stat multiplier is applied to generated enemies")
	var initial_units: Array = battle.capture_save_payload(true).setup.units
	var initial_pending: Dictionary = JSON.parse_string(JSON.stringify(run.state.pending))
	var checkpoint := run.save_store.load_run()
	_check(checkpoint != null and JSON.parse_string(JSON.stringify(checkpoint.pending)) == initial_pending, "Checkpoint includes the floor, pool, budget, multiplier, and concrete roster")
	manager.return_to_level_select()
	await process_frame
	# Edit both the progression data and the original template's fallback pool/budget.
	# The selected map scene remains compatible, so a committed battle must still restore.
	run.config.combat_stages[1].starting_cr = 40
	run.config.combat_stages[1].enemy_pool = [load("res://scenes/enemies/goblin_archer.tscn")]
	override.combat_rating = 10
	override.enemy_pool = [load("res://scenes/enemies/goblin_warrior.tscn")]
	var source_encounter := load(initial_pending.encounter) as RunEncounterDefinition
	var source_template := source_encounter.battle_map as BattleMapTemplateDefinition
	var original_cr := source_template.combat_rating
	var original_pool := source_template.enemy_pool.duplicate()
	var original_multiplier := source_encounter.enemy_multiplier
	source_template.combat_rating = 1
	source_template.enemy_pool = [load("res://scenes/enemies/goblin_archer.tscn")]
	source_encounter.enemy_multiplier = 2.0
	run.battle_open = false
	run.state = run.save_store.load_run()
	_check(run.state != null, "Editing stage, override, and template defaults does not invalidate an entry snapshot")
	if run.state != null:
		run.resume_room()
		_check(manager.current_battle != null and manager.current_battle.initialization_succeeded, "Continue reopens the committed progression battle")
		if manager.current_battle != null:
			_check(manager.current_battle.capture_save_payload(true).setup.units == initial_units, "Continue restores the same enemies, positions, equipment, and elite stats")
		_check(JSON.parse_string(JSON.stringify(run.state.pending)) == initial_pending, "Continue never rewrites or rerolls the entry snapshot")
	source_template.combat_rating = original_cr
	source_template.enemy_pool = original_pool
	source_encounter.enemy_multiplier = original_multiplier
	manager.return_to_level_select()
	await process_frame
	run.battle_open = false
	if run.state == null:
		manager.queue_free()
		await process_frame
		return
	var valid_data := run.state.to_data()
	for key in ["floor", "stage", "combat_rating", "enemy_pool", "enemy_multiplier"]:
		var invalid := valid_data.duplicate(true)
		invalid.pending.combat_progression[key] = null
		_check(RunState.from_data(invalid) == null, "Malformed progression %s is rejected" % key)
	var invalid := valid_data.duplicate(true)
	invalid.pending.combat_progression.floor = 5
	_check(RunState.from_data(invalid) == null, "Snapshot floor must match the selected map room")
	invalid = valid_data.duplicate(true)
	invalid.pending.combat_progression.combat_rating = 1
	_check(RunState.from_data(invalid) == null, "Saved roster cannot exceed its saved budget")
	invalid = valid_data.duplicate(true)
	invalid.pending.combat_progression.enemy_pool = ["res://scenes/enemies/goblin_archer.tscn"]
	_check(RunState.from_data(invalid) == null, "Saved roster must belong to its saved pool")
	invalid = valid_data.duplicate(true)
	invalid.pending.template_setup.enemies[0].cell = [99, 99]
	_check(RunState.from_data(invalid) == null, "Snapshot does not bypass spawn-layout validation")
	# The next uncommitted room uses the edited stage settings.
	run.state.pending = {}
	run.state.route.append(node.id)
	var next_node := run.state.graph.get_node_by_id(run.state.available_rooms()[0])
	next_node.type = RunMapGraph.NodeType.NORMAL_COMBAT
	run.config.combat_stages[1].starting_cr = 5
	var next := run._prepare_room(next_node)
	_check(not next.is_empty(), "Edited stage settings prepare a future room: " + run.error_message)
	if next.is_empty():
		manager.queue_free()
		await process_frame
		return
	_check(next.combat_progression.combat_rating == 8 and next.combat_progression.enemy_pool == ["res://scenes/enemies/goblin_archer.tscn"], "Future uncommitted rooms use current stage settings")
	var before := run.state.to_data()
	var valid_path := run.save_store.path
	run.save_store.path = "res://project.godot/impossible_progression_save.json"
	_check(not run.select_room(next_node.id), "Failed checkpoint write prevents starting a generated battle")
	_check(run.state.to_data() == before and not run.battle_open and manager.current_battle == null, "Failed write rolls back the pending snapshot and roster")
	run.save_store.path = valid_path
	run.config.combat_stages[1].enemy_pool = []
	_check(not run.select_room(next_node.id) and run.state.to_data() == before, "Invalid edited pools leave the run checkpoint untouched")
	# Legacy authored and fixed-budget template saves have no progression field.
	run.config.combat_stages = []
	run.config.floor_overrides = []
	for encounter_path in ["res://resources/run/goblin_skirmish_normal.tres", "res://resources/run/spawn_template_normal.tres"]:
		run.config.normal_encounters = [load(encounter_path)]
		_check(run.new_run(37), "Legacy encounter configuration can start a run")
		_check(run.select_room(run.state.available_rooms()[0]), "Legacy encounter enters and saves")
		_check(not run.state.pending.has("combat_progression") and run.save_store.load_run() != null, "Version-one checkpoints without progression stay compatible")
		manager.return_to_level_select()
		await process_frame
		run.battle_open = false
	manager.queue_free()
	await process_frame
