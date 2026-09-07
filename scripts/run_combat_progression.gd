@tool
class_name RunCombatProgression
extends RefCounted

## Authoring and checkpoint resolution share this boundary. Cached Resources are never edited.
static func validate_rules(config: RunConfig) -> Array[String]:
	var errors: Array[String] = []
	if config.combat_stages.is_empty():
		if not config.floor_overrides.is_empty():
			errors.append("Add Combat Stages before using Floor Overrides.")
		return errors
	var floors := {}
	for stage in config.combat_stages:
		if stage == null:
			errors.append("Assign a resource to each Combat Stage, or remove the empty entry.")
			continue
		if stage.first_floor < 1 or stage.last_floor > RunMapGenerator.ROOM_FLOORS or stage.last_floor < stage.first_floor:
			errors.append("Stage '%s' needs an inclusive floor range within 1–15." % stage.display_name)
			continue
		if stage.starting_cr < 1 or stage.cr_per_floor < 1:
			errors.append("Stage '%s' needs positive Starting CR and CR Per Floor." % stage.display_name)
		var pool_error := _pool_error(stage.enemy_pool)
		if not pool_error.is_empty():
			errors.append("Stage '%s': %s" % [stage.display_name, pool_error])
		for floor_number in range(stage.first_floor, stage.last_floor + 1):
			if floors.has(floor_number):
				errors.append("Combat Stages overlap on floor %d." % floor_number)
			floors[floor_number] = stage.combat_rating_at(floor_number)
	for floor_number in range(1, RunMapGenerator.ROOM_FLOORS + 1):
		if not floors.has(floor_number):
			errors.append("Combat Stages are missing floor %d." % floor_number)
		elif floors.has(floor_number - 1) and int(floors[floor_number]) <= int(floors[floor_number - 1]):
			errors.append("Stage CR must increase from floor %d to %d. Use a Floor Override for a deliberate exception." % [floor_number - 1, floor_number])
	var overridden := {}
	for entry in config.floor_overrides:
		if entry == null:
			errors.append("Assign a resource to each Floor Override, or remove the empty entry.")
			continue
		if entry.floor < 1 or entry.floor > RunMapGenerator.ROOM_FLOORS:
			errors.append("Floor Overrides must target a floor within 1–15.")
		if overridden.has(entry.floor):
			errors.append("Only one Floor Override is allowed for floor %d." % entry.floor)
		overridden[entry.floor] = true
		if entry.override_cr and entry.combat_rating < 1:
			errors.append("Floor %d: overridden Combat Rating must be positive." % entry.floor)
		if entry.override_enemy_pool:
			var pool_error := _pool_error(entry.enemy_pool)
			if not pool_error.is_empty():
				errors.append("Floor %d: %s" % [entry.floor, pool_error])
	for encounter in config.normal_encounters + config.elite_encounters:
		if encounter == null or not encounter.battle_map is BattleMapTemplateDefinition or not encounter.chief_node_name.is_empty():
			errors.append("Progression needs spawn-template encounters without named chiefs in both encounter catalogs.")
		elif encounter.resource_path.is_empty() or encounter.resource_path.contains("::"):
			errors.append("Save each progression encounter as a separate .tres file for checkpoints.")
		elif not is_finite(encounter.enemy_multiplier) or encounter.enemy_multiplier < 1.0:
			errors.append("Encounter '%s' needs a finite enemy multiplier of at least 1." % encounter.display_name)
	return errors


static func resolve_floor(config: RunConfig, floor_number: int) -> Dictionary:
	var errors := validate_rules(config)
	if not errors.is_empty():
		return {"error": " ".join(errors)}
	return _floor_settings(config, floor_number)


static func _floor_settings(config: RunConfig, floor_number: int) -> Dictionary:
	for stage in config.combat_stages:
		if floor_number < stage.first_floor or floor_number > stage.last_floor:
			continue
		var result := {"error": "", "floor": floor_number, "stage": stage.display_name,
			"combat_rating": stage.combat_rating_at(floor_number), "enemy_pool": stage.enemy_pool.duplicate()}
		for entry in config.floor_overrides:
			if entry.floor != floor_number:
				continue
			if entry.override_cr:
				result.combat_rating = entry.combat_rating
			if entry.override_enemy_pool:
				result.enemy_pool = entry.enemy_pool.duplicate()
		return result
	return {"error": "No combat stage covers floor %d." % floor_number}


## Report generation limits as well as authoring errors; never consume gameplay randomness.
static func validate(config: RunConfig, party_slots: int = 0) -> Dictionary:
	var errors := validate_rules(config)
	var warnings: Array[String] = []
	if not errors.is_empty() or config.combat_stages.is_empty():
		return {"errors": errors, "warnings": warnings}
	var layouts := {}
	var previous_totals := {}
	var previous_budget := 0
	var rng := RandomNumberGenerator.new()
	# A repeated catalog entry can weight layout selection; validate it only once per floor.
	var encounters: Array[RunEncounterDefinition] = []
	for encounter in config.normal_encounters + config.elite_encounters:
		if not encounters.has(encounter):
			encounters.append(encounter)
	for floor_number in range(1, RunMapGenerator.ROOM_FLOORS + 1):
		var settings := _floor_settings(config, floor_number)
		if int(settings.combat_rating) <= previous_budget:
			warnings.append("Floor %d has CR %d after CR %d because of a manual override. The override is honored." % [floor_number, settings.combat_rating, previous_budget])
		previous_budget = int(settings.combat_rating)
		for encounter in encounters:
			var source := encounter.battle_map as BattleMapTemplateDefinition
			if not layouts.has(source):
				layouts[source] = TemplateEncounterSetup.inspect_layout(source, party_slots)
			var layout: Dictionary = layouts[source]
			var label := "Floor %d / %s" % [floor_number, encounter.display_name]
			if not str(layout.error).is_empty():
				errors.append("%s: %s" % [label, layout.error])
				continue
			var effective := source.duplicate() as BattleMapTemplateDefinition
			effective.combat_rating = int(settings.combat_rating)
			# Resource.duplicate() retains array references: replace the array before editing.
			effective.enemy_pool = settings.enemy_pool.duplicate()
			rng.seed = 0
			var generated := EnemyEncounterGenerator.generate(effective, layout.enemy_cells.size(), rng)
			if not generated.error.is_empty():
				errors.append("%s: %s" % [label, generated.error])
				continue
			var total := int(generated.total_cr)
			if total < effective.combat_rating:
				warnings.append("%s can spend only CR %d of budget %d with this enemy pool and spawn capacity." % [label, total, effective.combat_rating])
			if previous_totals.has(encounter) and total <= int(previous_totals[encounter]):
				warnings.append("%s produces CR %d, which does not exceed the previous floor's achievable CR %d." % [label, total, previous_totals[encounter]])
			previous_totals[encounter] = total
	return {"errors": errors, "warnings": warnings}


static func snapshot(config: RunConfig, floor_number: int, encounter: RunEncounterDefinition) -> Dictionary:
	var settings := resolve_floor(config, floor_number)
	if not settings.error.is_empty():
		return settings
	var paths: Array[String] = []
	for scene: PackedScene in settings.enemy_pool:
		if not paths.has(scene.resource_path):
			paths.append(scene.resource_path)
	return {"error": "", "floor": floor_number, "stage": settings.stage,
		"combat_rating": settings.combat_rating, "enemy_pool": paths, "enemy_multiplier": encounter.enemy_multiplier}


## Legacy pending rooms return their authored encounter. New rooms reconstruct private copies.
static func resolve_pending(pending: Dictionary, floor_number: int) -> Dictionary:
	var path: Variant = pending.get("encounter")
	if not path is String or path.is_empty() or not ResourceLoader.exists(path):
		return {"error": "The saved encounter is missing."}
	var base := load(path) as RunEncounterDefinition
	if base == null or base.battle_map == null:
		return {"error": "The saved encounter or battle map is invalid."}
	if not pending.has("combat_progression"):
		return {"error": "", "encounter": base}
	if int(pending.get("type", -1)) not in [RunMapGraph.NodeType.NORMAL_COMBAT, RunMapGraph.NodeType.HARD_COMBAT] or not base.battle_map is BattleMapTemplateDefinition or not base.chief_node_name.is_empty():
		return {"error": "Saved combat progression requires a normal or elite spawn-template encounter."}
	var saved: Variant = pending.combat_progression
	if not saved is Dictionary or not _integer(saved.get("floor")) or int(saved.floor) != floor_number or floor_number < 1 or floor_number > RunMapGenerator.ROOM_FLOORS:
		return {"error": "The saved combat progression floor is invalid."}
	if not saved.get("stage") is String or not _integer(saved.get("combat_rating")) or int(saved.combat_rating) < 1 or not saved.get("enemy_pool") is Array:
		return {"error": "The saved combat progression settings are invalid."}
	var multiplier: Variant = saved.get("enemy_multiplier")
	if not (multiplier is int or multiplier is float) or not is_finite(float(multiplier)) or float(multiplier) < 1.0:
		return {"error": "The saved enemy multiplier is invalid."}
	var pool: Array[PackedScene] = []
	for scene_path in saved.enemy_pool:
		if not scene_path is String or scene_path.contains("::") or not ResourceLoader.exists(scene_path):
			return {"error": "A saved enemy pool scene is missing."}
		var scene := load(scene_path) as PackedScene
		if scene == null:
			return {"error": "A saved enemy pool entry is not a scene."}
		pool.append(scene)
	var pool_error := _pool_error(pool)
	if not pool_error.is_empty():
		return {"error": pool_error}
	var effective := base.duplicate() as RunEncounterDefinition
	var template := base.battle_map.duplicate() as BattleMapTemplateDefinition
	template.combat_rating = int(saved.combat_rating)
	template.enemy_pool = pool
	effective.battle_map = template
	effective.enemy_multiplier = float(multiplier)
	return {"error": "", "encounter": effective}


static func _pool_error(pool: Array[PackedScene]) -> String:
	var template := BattleMapTemplateDefinition.new()
	template.enemy_pool = pool
	var inspected := EnemyEncounterGenerator.catalog(template)
	if not inspected.error.is_empty():
		return inspected.error
	for scene in pool:
		if scene.resource_path.is_empty() or scene.resource_path.contains("::"):
			return "Save each enemy pool scene as a separate .tscn file for checkpoints."
	return ""


static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))
