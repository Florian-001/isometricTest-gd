@tool
extends "res://addons/ability_balance/draft_store.gd"

## Reuse the established value/path snapshots and recovery, with encounter-specific validation.
const OVERRIDE_LISTS := ["floor_overrides", "elite_floor_overrides"]


func _init() -> void:
	recovery_path = "res://.godot/encounter_balance/recovery.cfg"


func add_resource(path: String) -> void:
	if states.has(path) or not ResourceLoader.exists(path):
		return
	var resource := load(path)
	if not (resource is RunConfig or resource is RunCombatFloorOverride):
		return
	states[path] = capture(resource)
	baselines[path] = states[path].duplicate(true)
	hashes[path] = FileAccess.get_sha256(path)
	for dependency in dependencies(path):
		add_resource(dependency)


func dependencies(path: String) -> Array[String]:
	var result: Array[String] = []
	for key in OVERRIDE_LISTS:
		for entry in states[path].get(key, []):
			if entry is Dictionary and entry.has("$ref") and entry["$ref"] not in result:
				result.append(entry["$ref"])
	return result


func validation(path: String) -> Array[String]:
	var resource := draft(path)
	if resource == null:
		return ["Resource was removed."]
	if resource is RunConfig:
		return resource.validate_configuration().errors
	var errors: Array[String] = []
	if resource.floor < 1 or resource.floor > 15:
		errors.append("Floor must be within 1–15.")
	if resource.override_cr and resource.combat_rating < 1:
		errors.append("Enabled Combat Rating must be positive.")
	if resource.override_enemy_pool:
		var error := RunCombatProgression._pool_error(resource.enemy_pool)
		if not error.is_empty():
			errors.append(error)
	return errors


## Field patches keep undo from reverting unrelated disk fields adopted during save.
func change(title: String, replacements: Dictionary) -> void:
	var previous := {}
	var next := {}
	for path in replacements:
		var normalized_state := normalized(path, replacements[path])
		var old_fields := {}
		var new_fields := {}
		for key in normalized_state:
			if normalized_state[key] != states[path].get(key):
				old_fields[key] = states[path].get(key)
				new_fields[key] = normalized_state[key]
		if not new_fields.is_empty():
			previous[path] = old_fields
			next[path] = new_fields
	if next.is_empty():
		return
	history.create_action(title)
	history.add_do_method(_install_fields.bind(next))
	history.add_undo_method(_install_fields.bind(previous))
	history.commit_action()


func _install_fields(patches: Dictionary) -> void:
	for path in patches:
		var state: Dictionary = states[path].duplicate(true)
		for key in patches[path]:
			state[key] = patches[path][key].duplicate(true) if patches[path][key] is Array or patches[path][key] is Dictionary else patches[path][key]
		states[path] = state
	write_recovery()
	changed.emit()


## Build all cell edits before committing one undo action, including shared-resource edits.
func edit_cells(owner: String, edits: Array, title := "Edit encounter cells") -> bool:
	if not states.has(owner) or not draft(owner) is RunConfig:
		return false
	var replacements := {owner: states[owner].duplicate(true)}
	for edit in edits:
		var list_key: String = "elite_floor_overrides" if str(edit.key).begins_with("elite_") else "floor_overrides"
		var field: String = "combat_rating" if str(edit.key).ends_with("cr") else "enemy_pool"
		var toggle: String = "override_cr" if field == "combat_rating" else "override_enemy_pool"
		var entries: Array = replacements[owner][list_key]
		var index := -1
		for candidate in range(entries.size()):
			var entry: Variant = entries[candidate]
			var fields: Dictionary = states.get(entry.get("$ref", ""), {}) if entry is Dictionary and entry.has("$ref") else entry.get("$fields", {}) if entry is Dictionary else {}
			if int(fields.get("floor", 0)) == int(edit.floor):
				index = candidate
				break
		if index < 0:
			if edit.get("reset", false):
				continue
			var new_entry := RunCombatFloorOverride.new()
			new_entry.floor = int(edit.floor)
			entries.append(encode(new_entry))
			index = entries.size() - 1
		var encoded: Dictionary = entries[index]
		var fields: Dictionary
		if encoded.has("$ref"):
			var path: String = encoded["$ref"]
			if not states.has(path):
				return false
			if not replacements.has(path):
				replacements[path] = states[path].duplicate(true)
			fields = replacements[path]
		else:
			fields = encoded["$fields"]
		fields[toggle] = not edit.get("reset", false)
		if not edit.get("reset", false):
			fields[field] = edit.value if field == "combat_rating" else edit.value.map(func(path): return {"$ref": path})
	change(title, replacements)
	return true


func source_path(owner: String, floor_number: int, elite: bool) -> String:
	for entry in states[owner].get("elite_floor_overrides" if elite else "floor_overrides", []):
		if entry is Dictionary and entry.has("$ref") and int(states.get(entry["$ref"], {}).get("floor", 0)) == floor_number:
			return entry["$ref"]
	return ""


func save_all(overwrite: Array[String] = []) -> Dictionary:
	var result := {"saved": [], "failed": [], "conflicts": []}
	var pending := dirty_paths()
	var blocked: Array[String] = []
	for path in conflicts():
		if path not in overwrite:
			result.conflicts.append(path)
			blocked.append(path)
	# Validate merged disk+draft values, and owners of shared override drafts.
	var authored_states := states
	var merged_states := states.duplicate(true)
	for path in pending:
		if path in blocked or not FileAccess.file_exists(path):
			continue
		var source := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if source == null:
			continue
		var resource: Resource = source.duplicate(false)
		apply_state(resource, _edited_fields(path), false)
		merged_states[path] = capture(resource)
	# Draft decoding resolves external overrides through this candidate graph.
	states = merged_states
	for path in states:
		if path not in pending and not dependencies(path).any(func(p): return p in pending):
			continue
		var errors := validation(path)
		if not errors.is_empty():
			result.failed.append(path + ": " + "; ".join(errors))
			blocked.append(path)
			for dependency in dependencies(path):
				if dependency in pending:
					blocked.append(dependency)
	states = authored_states
	# External overrides save before RunConfigs; configs keep their reference paths.
	pending.sort_custom(func(a, b): return int(states[a].has("floor_overrides")) < int(states[b].has("floor_overrides")))
	for path in pending:
		if path in blocked:
			continue
		if dependencies(path).any(func(p): return p in blocked):
			result.failed.append(path + ": a shared override remains unsaved.")
			continue
		if not FileAccess.file_exists(path):
			result.failed.append(path + ": resource was removed.")
			continue
		var source := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if source == null:
			result.failed.append(path + ": cannot load resource.")
			continue
		var resource: Resource = source.duplicate(false)
		apply_state(resource, _edited_fields(path), false)
		var errors: Array = resource.validate_configuration().errors if resource is RunConfig else []
		if not errors.is_empty():
			result.failed.append(path + ": " + "; ".join(errors))
			blocked.append(path)
			continue
		var uid := ResourceLoader.get_resource_uid(path)
		var error := ResourceSaver.save(resource, path)
		if error == OK and uid != ResourceUID.INVALID_ID:
			error = ResourceSaver.set_uid(path, uid)
		if error != OK:
			result.failed.append(path + ": " + error_string(error))
			blocked.append(path)
			continue
		var saved := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		states[path] = capture(saved)
		baselines[path] = states[path].duplicate(true)
		hashes[path] = FileAccess.get_sha256(path)
		result.saved.append(path)
	write_recovery()
	changed.emit()
	return result


func _edited_fields(path: String) -> Dictionary:
	var result := {}
	for key in states[path]:
		if states[path][key] != baselines[path].get(key):
			result[key] = states[path][key]
	return result


func write_recovery() -> void:
	if recovery_path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(recovery_path.get_base_dir())
	var config := ConfigFile.new()
	# Include clean owners so shared-only drafts can validate after restart.
	var dirty := dirty_paths()
	for path in states:
		if path in dirty or dependencies(path).any(func(p): return p in dirty):
			config.set_value(path, "state", states[path])
			config.set_value(path, "baseline", baselines[path])
			config.set_value(path, "hash", hashes[path])
	recovery_error = config.save(recovery_path)
	if recovery_error != OK:
		push_warning("Encounter Balance recovery failed: " + error_string(recovery_error))
