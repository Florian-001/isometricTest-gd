extends SceneTree

const DEFAULT := "res://resources/run/default_run.tres"
const GOBLIN := "res://scenes/enemies/goblin_archer.tscn"
const SKELETON := "res://scenes/enemies/skeleton_archer.tscn"
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _config() -> RunConfig:
	var source := load(DEFAULT) as RunConfig
	var config := source.duplicate() as RunConfig
	config.normal_encounters = source.normal_encounters.duplicate()
	config.elite_encounters = source.elite_encounters.duplicate()
	config.combat_stages = []
	for stage in source.combat_stages:
		config.combat_stages.append(stage.duplicate())
	config.floor_overrides = []
	return config


func _override(floor_number: int, budget: int = 0, pool: Array[PackedScene] = []) -> RunCombatFloorOverride:
	var entry := RunCombatFloorOverride.new()
	entry.floor = floor_number
	entry.override_cr = budget != 0
	entry.combat_rating = budget
	entry.override_enemy_pool = not pool.is_empty()
	entry.enemy_pool = pool
	return entry


func _run() -> void:
	_test_rules()
	_test_overrides()
	_test_generation()
	await process_frame
	if _failures.is_empty():
		print("COMBAT_PROGRESSION_TESTS_OK")
	for failure in _failures:
		push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _invalid(config: RunConfig, description: String) -> void:
	_check(not config.validate_configuration().errors.is_empty(), description)


func _test_rules() -> void:
	var config := _config()
	var template := config.normal_encounters[0].battle_map as BattleMapTemplateDefinition
	var original_pool := template.enemy_pool.duplicate()
	var original_cr := template.combat_rating
	var report := config.validate_configuration()
	_check(report.errors.is_empty() and report.warnings.is_empty(), "Default progression is valid and can spend every floor budget")
	_check(template.enemy_pool == original_pool and template.combat_rating == original_cr, "Full authoring validation does not mutate the shared template")
	config.normal_encounters.append(config.normal_encounters[0])
	_check(config.validate_configuration().warnings.is_empty(), "Repeated layout entries do not create false difficulty-plateau warnings")
	config.normal_encounters = [config.normal_encounters[0]]
	for floor_number in range(1, 16):
		var resolved := RunCombatProgression.resolve_floor(config, floor_number)
		_check(resolved.error.is_empty() and resolved.combat_rating == floor_number, "Every default floor has its own rising CR")
		_check(resolved.stage == ("Goblins" if floor_number <= 3 else "Skeletons"), "Stage boundaries include 3→4, 8→9 and the final room floor")
	_check(not RunCombatProgression.resolve_floor(config, 16).error.is_empty(), "Boss floor has no generated stage")
	config.combat_stages.reverse()
	_check(config.is_configured(), "Floor ranges, rather than Inspector array order, select stages")
	config = _config()
	config.combat_stages[0].last_floor = 4
	_invalid(config, "Overlapping stages fail validation")
	config = _config()
	config.combat_stages[1].first_floor = 5
	_invalid(config, "Missing floors fail validation")
	config = _config()
	config.combat_stages[0].first_floor = 0
	_invalid(config, "Stage bounds reject floor zero")
	config = _config()
	config.combat_stages[1].last_floor = 16
	_invalid(config, "Stages cannot include the boss")
	config = _config()
	config.combat_stages[0].starting_cr = 0
	_invalid(config, "Nonpositive stage budgets fail")
	config = _config()
	config.combat_stages[1].cr_per_floor = 0
	_invalid(config, "Stage increments must be positive")
	config = _config()
	config.combat_stages[1].starting_cr = 3
	_invalid(config, "Stage boundaries must increase CR")
	config = _config()
	config.combat_stages[0].enemy_pool = []
	_invalid(config, "Empty stage pools fail")
	config = _config()
	config.combat_stages[0].enemy_pool = [load("res://scenes/friendlies/friend_a.tscn")]
	_invalid(config, "Friendly scenes cannot enter a stage pool")
	config = _config()
	config.combat_stages.append(null)
	_invalid(config, "Empty stage resources fail safely")
	config = _config()
	config.floor_overrides = [_override(5, 6), _override(5, 7)]
	_invalid(config, "Duplicate floor overrides fail")
	config.floor_overrides = [_override(16, 6)]
	_invalid(config, "Overrides cannot target the boss")
	config.floor_overrides = [_override(5, -1)]
	_invalid(config, "Nonpositive enabled CR overrides fail")
	config.floor_overrides = [_override(5)]
	config.floor_overrides[0].override_enemy_pool = true
	_invalid(config, "An enabled empty pool fails instead of falling back")
	config.floor_overrides = [null]
	_invalid(config, "Empty override resources fail safely")
	config = _config()
	config.normal_encounters = [load("res://resources/run/goblin_skirmish_normal.tres")]
	_invalid(config, "Authored normal maps are incompatible with active progression")
	config.combat_stages = []
	_check(config.is_configured(), "Empty stages and overrides retain legacy authored encounters")
	config.floor_overrides = [_override(2, 2)]
	_invalid(config, "Overrides require stages")
	config = _config()
	config.floor_overrides = [_override(5, 20)]
	report = config.validate_configuration()
	_check(report.errors.is_empty() and "only CR 15 of budget 20" in " ".join(report.warnings), "Capacity limits are reported without silently increasing enemy stats")
	config.floor_overrides = [_override(5, 4)]
	report = config.validate_configuration()
	_check(report.errors.is_empty() and "manual override" in " ".join(report.warnings), "Manual CR plateaus remain valid with a warning")


func _test_overrides() -> void:
	var config := _config()
	config.floor_overrides = [_override(5, 9), _override(6, 0, [load(GOBLIN)]), _override(7, 3, [load(GOBLIN)])]
	var fifth := RunCombatProgression.resolve_floor(config, 5)
	_check(fifth.combat_rating == 9 and fifth.enemy_pool == config.combat_stages[1].enemy_pool, "CR-only override preserves the stage pool")
	var sixth := RunCombatProgression.resolve_floor(config, 6)
	_check(sixth.combat_rating == 6 and sixth.enemy_pool == [load(GOBLIN)], "Pool-only override replaces the entire pool and preserves stage CR")
	var seventh := RunCombatProgression.resolve_floor(config, 7)
	_check(seventh.combat_rating == 3 and seventh.enemy_pool == [load(GOBLIN)], "Both overrides can be enabled independently")
	var eighth := RunCombatProgression.resolve_floor(config, 8)
	_check(eighth.combat_rating == 8 and eighth.enemy_pool == config.combat_stages[1].enemy_pool, "Overrides do not shift later floors")
	config.floor_overrides[0].override_cr = false
	config.floor_overrides[0].combat_rating = -1
	config.floor_overrides[0].enemy_pool = [null]
	_check(RunCombatProgression.resolve_floor(config, 5).combat_rating == 5, "Disabled override values are ignored")


func _test_generation() -> void:
	var controller := RunController.new()
	controller.config = _config()
	controller.state = RunState.new()
	controller.state.graph = RunMapGenerator.new().generate(37, controller.config.map_settings)
	var party := controller.config.starting_party.instantiate()
	for child in party.get_children():
		controller.state.party.append(RunPartyMember.from_character(child))
	party.free()
	var source := controller.config.normal_encounters[0].battle_map as BattleMapTemplateDefinition
	var original_pool := source.enemy_pool.duplicate()
	var original_cr := source.combat_rating
	for floor_number in range(1, 16):
		var node := RunMapGraph.NodeData.new(floor_number + 100, floor_number - 1, 0, RunMapGraph.NodeType.NORMAL_COMBAT)
		var pending := controller._prepare_room(node)
		_check(not pending.is_empty(), "Every floor generates a roster")
		if pending.is_empty():
			continue
		_check(pending.template_setup.total_cr == floor_number, "Achievable roster CR rises on every floor")
		for enemy in pending.template_setup.enemies:
			_check(("goblin_" if floor_number <= 3 else "skeleton_") in enemy.scene, "Generated enemies stay in the stage pool")
		_check(pending == controller._prepare_room(node), "Seeded progression generation is deterministic")
		var effective := RunCombatProgression.resolve_pending(pending, floor_number)
		_check(effective.encounter != controller.config.normal_encounters[0] and effective.encounter.battle_map != source, "Generated encounters use private resource copies")
		_check(TemplateEncounterSetup.validate_saved(effective.encounter.battle_map, pending.template_setup, 2).is_empty(), "Resolved settings validate the saved roster")
	_check(source.combat_rating == original_cr and source.enemy_pool == original_pool, "Generation never mutates shared template settings")
	controller.config.floor_overrides = [_override(6, 4, [load(SKELETON)])]
	var elite_node := RunMapGraph.NodeData.new(200, 5, 0, RunMapGraph.NodeType.HARD_COMBAT)
	var elite := controller._prepare_room(elite_node)
	_check(elite.template_setup.total_cr == 4 and elite.combat_progression.enemy_multiplier == 1.5, "Elites apply their multiplier after the overridden base CR")
	controller.config.unknown_combat_weight = 1
	controller.config.unknown_treasure_weight = 0
	controller.config.unknown_rest_weight = 0
	elite_node.type = RunMapGraph.NodeType.RANDOM
	var unknown := controller._prepare_room(elite_node)
	_check(unknown.type == RunMapGraph.NodeType.NORMAL_COMBAT and unknown.template_setup.total_cr == 4 and unknown.combat_progression.enemy_multiplier == 1.0, "Revealed combat uses its floor overrides as normal combat")
	for kind in [RunMapGraph.NodeType.REST, RunMapGraph.NodeType.SHOP, RunMapGraph.NodeType.CHEST]:
		elite_node.type = kind
		_check(not controller._prepare_room(elite_node).has("combat_progression"), "Noncombat rooms have no generated combat settings")
	elite_node.type = RunMapGraph.NodeType.BOSS
	elite_node.tier = 15
	var boss := controller._prepare_room(elite_node)
	_check(not boss.has("combat_progression") and boss.encounter == controller.config.boss_encounter.resource_path, "Boss remains separately authored")
	elite_node.type = RunMapGraph.NodeType.NORMAL_COMBAT
	elite_node.tier = 0
	controller.config.normal_encounters = []
	_check(controller._prepare_room(elite_node).is_empty(), "Empty edited encounter catalogs reject selection without a script error")
	controller.config.normal_encounters = [null]
	_check(controller._prepare_room(elite_node).is_empty(), "Empty edited encounter entries reject selection without a script error")
	controller.free()
