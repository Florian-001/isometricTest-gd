@tool
extends RefCounted

## Snapshots contain values and resource paths only; never live mutable Resources.
signal changed
const Columns = preload("res://addons/ability_balance/columns.gd")
var states: Dictionary = {}
var baselines: Dictionary = {}
var hashes: Dictionary = {}
var history := UndoRedo.new()
var recovery_path := "res://.godot/ability_balance/recovery.cfg"
var recovery_error: Error = OK


static func capture(resource: Resource) -> Dictionary:
	var result := {}
	for property in resource.get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE and property.name != "script":
			result[str(property.name)] = encode(resource.get(property.name))
	return result


static func encode(value: Variant) -> Variant:
	if value is Resource:
		if not value.resource_path.is_empty() and "::" not in value.resource_path:
			return {"$ref": value.resource_path}
		return {"$script": value.get_script().resource_path if value.get_script() != null else "", "$class": value.get_class(), "$fields": capture(value)}
	if value is Array:
		var result: Array = []
		for entry in value:
			result.append(encode(entry))
		return result
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = encode(value[key])
		return {"$dictionary": result}
	return value


func decode(value: Variant, use_drafts := true, memo: Dictionary = {}) -> Variant:
	if value is Dictionary:
		if value.has("$dictionary"):
			var dictionary := {}
			for key in value["$dictionary"]:
				dictionary[key] = decode(value["$dictionary"][key], use_drafts, memo)
			return dictionary
		if value.has("$ref"):
			return draft(value["$ref"], memo) if use_drafts and states.has(value["$ref"]) else load(value["$ref"])
		if value.has("$fields"):
			var resource: Resource = load(value["$script"]).new() if not value["$script"].is_empty() else ClassDB.instantiate(value["$class"])
			apply_state(resource, value["$fields"], use_drafts, memo)
			return resource
		var result := {}
		for key in value:
			result[key] = decode(value[key], use_drafts, memo)
		return result
	if value is Array:
		var result: Array = []
		for entry in value:
			result.append(decode(entry, use_drafts, memo))
		return result
	return value


func apply_state(resource: Resource, state: Dictionary, use_drafts := true, memo: Dictionary = {}) -> void:
	# Type/effect setters normalize scaling; apply the chosen scaling after them.
	var keys := state.keys()
	keys.erase("scaling_stat")
	if state.has("scaling_stat"):
		keys.append("scaling_stat")
	for key in keys:
		var value: Variant = decode(state[key], use_drafts, memo)
		var current: Variant = resource.get(key)
		if current is Array and value is Array:
			var typed: Array = current.duplicate()
			typed.assign(value)
			value = typed
		elif current is Dictionary and value is Dictionary:
			var typed_dictionary: Dictionary = current.duplicate()
			typed_dictionary.assign(value)
			value = typed_dictionary
		resource.set(key, value)
	if resource is AbilityDefinition:
		resource._normalize_weapon_scaling()


func add_resource(path: String) -> void:
	if states.has(path) or not ResourceLoader.exists(path):
		return
	var resource := load(path)
	if not (resource is AbilityDefinition or resource is PassiveAbilityDefinition or resource is AbilityEffectDefinition or resource is PassiveEffectDefinition):
		return
	states[path] = capture(resource)
	baselines[path] = states[path].duplicate(true)
	hashes[path] = FileAccess.get_sha256(path)
	if resource is AbilityDefinition or resource is PassiveAbilityDefinition:
		for effect in resource.effects:
			if effect != null and not effect.resource_path.is_empty() and "::" not in effect.resource_path:
				add_resource(effect.resource_path)


func draft(path: String, memo: Dictionary = {}) -> Resource:
	if not states.has(path) or not FileAccess.file_exists(path):
		return null
	if memo.has(path):
		return memo[path]
	var source := load(path)
	if source == null:
		return null
	var resource: Resource = source.duplicate(false)
	memo[path] = resource
	apply_state(resource, states[path], true, memo)
	return resource


func normalized(path: String, state: Dictionary) -> Dictionary:
	# Keep external links encoded, even when their drafts have no resource path.
	var resource: Resource = load(path).duplicate(false)
	apply_state(resource, state, false)
	return capture(resource)


func is_dirty(path: String) -> bool:
	return states.has(path) and states[path] != baselines[path]


func dirty_paths() -> Array[String]:
	var result: Array[String] = []
	for path in states:
		if is_dirty(path):
			result.append(path)
	return result


func change(title: String, replacements: Dictionary) -> void:
	var previous := {}
	var next := {}
	for path in replacements:
		previous[path] = states[path].duplicate(true)
		next[path] = normalized(path, replacements[path])
	if previous == next:
		return
	history.create_action(title)
	history.add_do_method(_install.bind(next))
	history.add_undo_method(_install.bind(previous))
	history.commit_action()


func _install(replacements: Dictionary) -> void:
	for path in replacements:
		states[path] = replacements[path].duplicate(true)
	write_recovery()
	changed.emit()


func set_field(path: String, key: String, value: Variant) -> void:
	var state: Dictionary = states[path].duplicate(true)
	state[key] = value
	change("Edit " + key.capitalize(), {path: state})


func effect_location(owner: String, index: int) -> Dictionary:
	var value: Variant = states[owner].effects[index]
	if value is Dictionary and value.has("$ref"):
		return {"path": value["$ref"], "index": -1}
	return {"path": owner, "index": index}


func set_effect_field(owner: String, index: int, key: String, value: Variant) -> void:
	var location := effect_location(owner, index)
	if location.index < 0:
		set_field(location.path, key, value)
	else:
		var effects: Array = states[owner].effects.duplicate(true)
		effects[index]["$fields"][key] = value
		set_field(owner, "effects", effects)


func validation(path: String) -> Array[String]:
	var errors: Array[String] = []
	var resource := draft(path)
	if resource == null:
		return ["Resource was removed."]
	if resource is PassiveAbilityDefinition or resource is PassiveEffectDefinition:
		errors.append_array(resource.validate())
	if resource is AbilityDefinition:
		if resource.display_name.strip_edges().is_empty():
			errors.append("Ability needs a display name.")
		if resource.ap_cost < 1 or resource.cooldown_turns < 0:
			errors.append("AP cost must be positive and cooldown turns must be nonnegative.")
		var targeting: String = resource.get_targeting_configuration_error()
		if not targeting.is_empty():
			errors.append(targeting)
	if resource is AbilityDefinition or resource is PassiveAbilityDefinition:
		for effect in resource.effects:
			if effect == null:
				errors.append("Effect references cannot be empty.")
			elif effect is ApplyStatusEffectDefinition and effect.status_effect == null:
				errors.append("Apply Status needs a status resource.")
	return errors


func dependencies(path: String) -> Array[String]:
	var result: Array[String] = []
	for entry in states[path].get("effects", []):
		if entry is Dictionary and entry.has("$ref"):
			result.append(entry["$ref"])
	return result


func conflicts() -> Array[String]:
	var result: Array[String] = []
	for path in dirty_paths():
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != hashes[path] or capture(load(path)) != baselines[path]:
			result.append(path)
	return result


func save_all(overwrite: Array[String] = []) -> Dictionary:
	var result := {"saved": [], "failed": [], "conflicts": []}
	var pending := dirty_paths()
	var blocked: Array[String] = []
	for path in conflicts():
		if path not in overwrite:
			result.conflicts.append(path)
			blocked.append(path)
	# Validate owners affected by shared effect edits, too.
	for path in states:
		var affected: bool = path in pending or dependencies(path).any(func(p): return p in pending)
		if not affected:
			continue
		var errors := validation(path)
		if not errors.is_empty():
			result.failed.append(path + ": " + "; ".join(errors))
			blocked.append(path)
			for dependency in dependencies(path):
				if dependency in pending:
					blocked.append(dependency)
	# Shared effects must save before owners referencing them.
	pending.sort_custom(func(a, b): return int(states[a].has("effects")) < int(states[b].has("effects")))
	for path in pending:
		if path in blocked:
			continue
		if dependencies(path).any(func(p): return p in blocked):
			result.failed.append(path + ": a shared effect remains unsaved.")
			blocked.append(path)
			continue
		if not FileAccess.file_exists(path):
			result.failed.append(path + ": resource was removed.")
			blocked.append(path)
			continue
		var source := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if source == null:
			result.failed.append(path + ": cannot load resource.")
			blocked.append(path)
			continue
		var resource: Resource = source.duplicate(false)
		var edited := {}
		for key in states[path]:
			if states[path][key] != baselines[path].get(key):
				edited[key] = states[path][key]
		apply_state(resource, edited, false)
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


func refresh_clean() -> void:
	for path in states.keys():
		if is_dirty(path) or not FileAccess.file_exists(path):
			continue
		var disk_changed: bool = FileAccess.get_sha256(path) != hashes[path]
		if disk_changed or capture(load(path)) != baselines[path]:
			var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) if disk_changed else load(path)
			states[path] = capture(resource)
			baselines[path] = states[path].duplicate(true)
			hashes[path] = FileAccess.get_sha256(path)
			for dependency in dependencies(path):
				add_resource(dependency)


func reload_paths(paths: Array) -> void:
	for path in paths:
		if not FileAccess.file_exists(path):
			states.erase(path)
			baselines.erase(path)
			hashes.erase(path)
			continue
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if resource != null:
			states[path] = capture(resource)
			baselines[path] = states[path].duplicate(true)
			hashes[path] = FileAccess.get_sha256(path)
			for dependency in dependencies(path):
				add_resource(dependency)
	history.clear_history()
	write_recovery()
	changed.emit()


func write_recovery() -> void:
	if recovery_path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(recovery_path.get_base_dir())
	var config := ConfigFile.new()
	for path in dirty_paths():
		config.set_value(path, "state", states[path])
		config.set_value(path, "baseline", baselines[path])
		config.set_value(path, "hash", hashes[path])
	recovery_error = config.save(recovery_path)
	if recovery_error != OK:
		push_warning("Ability Balance recovery failed: " + error_string(recovery_error))


func restore_recovery() -> int:
	var config := ConfigFile.new()
	if config.load(recovery_path) != OK:
		return 0
	var count := 0
	for path in config.get_sections():
		var recovered: Variant = config.get_value(path, "state", null)
		var baseline: Variant = config.get_value(path, "baseline", null)
		if not recovered is Dictionary or not baseline is Dictionary:
			continue
		add_resource(path)
		# Keep deleted-file drafts recoverable until the user restores or reverts them.
		states[path] = recovered
		baselines[path] = baseline
		hashes[path] = config.get_value(path, "hash", "")
		count += 1
	return count
