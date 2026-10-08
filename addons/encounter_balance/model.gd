@tool
extends RefCounted

const Catalog = preload("res://addons/encounter_balance/catalog.gd")


static func columns(linear: bool) -> Array:
	var result: Array = [
		{"key": "display_name", "title": "Floor", "kind": "result", "width": 215},
		{"key": "stage", "title": "Stage", "kind": "result", "width": 140},
		{"key": "normal_cr", "title": "Normal CR", "kind": "cr", "width": 130},
		{"key": "normal_pool", "title": "Normal Units Pool", "kind": "pool", "width": 300}]
	if not linear:
		result.append_array([
			{"key": "elite_cr", "title": "Elite CR", "kind": "cr", "width": 130},
			{"key": "elite_pool", "title": "Elite Units Pool", "kind": "pool", "width": 300}])
	result.append({"key": "validation", "title": "Validation", "kind": "result", "width": 280})
	return result


## Permit invalid intermediate drafts to remain visible and editable.
static func settings(config: RunConfig, floor_number: int, elite := false) -> Dictionary:
	var result := {"stage": "Missing stage", "cr": 0, "pool": [], "cr_source": "stage", "pool_source": "stage"}
	for stage in config.combat_stages:
		if stage != null and floor_number >= stage.first_floor and floor_number <= stage.last_floor:
			result.stage = stage.display_name
			result.cr = stage.combat_rating_at(floor_number)
			result.pool = stage.enemy_pool.duplicate()
			break
	_apply(result, config.floor_overrides, floor_number, "normal" if elite else "override")
	if elite:
		_apply(result, config.elite_floor_overrides, floor_number, "override")
		if result.cr_source == "stage":
			result.cr_source = "normal"
		if result.pool_source == "stage":
			result.pool_source = "normal"
	return result


static func _apply(result: Dictionary, overrides: Array[RunCombatFloorOverride], floor_number: int, source: String) -> void:
	for entry in overrides:
		if entry != null and entry.floor == floor_number:
			if entry.override_cr:
				result.cr = entry.combat_rating
				result.cr_source = source
			if entry.override_enemy_pool:
				result.pool = entry.enemy_pool.duplicate()
				result.pool_source = source


static func pool_paths(pool: Array) -> Array[String]:
	var result: Array[String] = []
	for scene in pool:
		result.append(scene.resource_path if scene != null else "<missing>")
	return result


static func parse(key: String, text: String) -> Dictionary:
	if key.ends_with("cr"):
		if not text.strip_edges().is_valid_int() or text.to_int() < 1:
			return {"error": "CR must be a positive whole number."}
		return {"value": text.to_int()}
	if not key.ends_with("pool"):
		return {"error": "This column is read-only."}
	var paths: Array[String] = []
	for token in text.split(";", false):
		var path := token.strip_edges()
		var entry := Catalog.inspect_enemy(path)
		if not entry.error.is_empty():
			return entry
		if path not in paths:
			paths.append(path)
	if paths.is_empty():
		return {"error": "Choose at least one enemy scene. Use Reset to inherit the pool."}
	return {"value": paths}


static func preview(config: RunConfig, floor_number: int, elite: bool, encounter_index: int, sample_seed: int) -> Dictionary:
	var combat_type := RunMapGraph.NodeType.HARD_COMBAT if elite else RunMapGraph.NodeType.NORMAL_COMBAT
	var resolved := RunCombatProgression.resolve_floor(config, floor_number, combat_type)
	if not resolved.error.is_empty():
		return resolved
	var encounters := config.elite_encounters if elite else config.normal_encounters
	if encounter_index < 0 or encounter_index >= encounters.size() or encounters[encounter_index] == null:
		return {"error": "Choose an encounter layout."}
	var encounter := encounters[encounter_index]
	var source := encounter.battle_map as BattleMapTemplateDefinition
	if source == null:
		return {"error": "Preview needs a spawn-template encounter."}
	var party_slots := 0
	if config.starting_party != null and config.starting_party.can_instantiate():
		var party := config.starting_party.instantiate()
		for child in party.get_children():
			if child is TacticalCharacter:
				party_slots += 1
		party.free()
	var layout := TemplateEncounterSetup.inspect_layout(source, party_slots)
	if not layout.error.is_empty():
		return layout
	var effective := source.duplicate() as BattleMapTemplateDefinition
	effective.combat_rating = int(resolved.combat_rating)
	effective.enemy_pool = resolved.enemy_pool.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = sample_seed
	var generated := EnemyEncounterGenerator.generate(effective, layout.enemy_cells.size(), rng)
	if not generated.error.is_empty():
		return generated
	var roster := {}
	for scene in generated.scenes:
		var path: String = scene.resource_path
		if not roster.has(path):
			roster[path] = Catalog.inspect_enemy(path)
			roster[path].count = 0
		roster[path].count += 1
	return {"error": "", "budget": resolved.combat_rating, "total_cr": generated.total_cr,
		"capacity": layout.enemy_cells.size(), "friendly_capacity": layout.friendly_cells.size(),
		"unused": int(resolved.combat_rating) - int(generated.total_cr), "roster": roster,
		"multiplier": encounter.enemy_multiplier}
