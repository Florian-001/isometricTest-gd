@tool
extends RefCounted

## State contains only values, paths, and modifier dictionaries. No mutable shared
## Resources enter the undo history or recovery file.
signal changed

const ENEMY_FIELDS := ["display_name", "combat_rating", "strength", "dexterity", "intelligence", "constitution", "speed", "movement_range", "base_health_override", "starting_equipment", "abilities", "passive_abilities", "ai_profile"]
const ITEM_FIELDS := ["display_name", "slot", "armor", "weapon_damage", "weapon_type", "weapon_handedness", "weapon_range_bonus", "modifiers", "status_effect"]
const ARRAY_FIELDS := ["starting_equipment", "abilities", "passive_abilities"]
const REFERENCE_FIELDS := ["ai_profile", "status_effect"]

var states: Dictionary = {}
var baselines: Dictionary = {}
var hashes: Dictionary = {}
var history := UndoRedo.new()
var recovery_path := "res://.godot/unit_balance/recovery.cfg"
var recovery_error: Error = OK


func add_resource(path: String) -> void:
	if states.has(path):
		return
	var resource := load(path)
	if not (resource is EnemyDefinition or resource is ItemDefinition):
		return
	states[path] = capture(resource)
	baselines[path] = states[path].duplicate(true)
	hashes[path] = FileAccess.get_sha256(path)


static func capture(resource: Resource) -> Dictionary:
	var result := {}
	for field in ENEMY_FIELDS if resource is EnemyDefinition else ITEM_FIELDS:
		var value: Variant = resource.get(field)
		if field in ARRAY_FIELDS:
			var paths: Array = []
			for entry in value:
				paths.append(entry.resource_path if entry != null else "")
			result[field] = paths
		elif field in REFERENCE_FIELDS:
			result[field] = value.resource_path if value != null else ""
		elif field == "modifiers":
			var modifiers: Array = []
			for modifier in value:
				modifiers.append({"stat": int(modifier.stat), "operation": int(modifier.operation), "value": modifier.value} if modifier != null else null)
			result[field] = modifiers
		else:
			result[field] = value
	return result


static func apply_state(resource: Resource, state: Dictionary) -> void:
	for field in state:
		if field in ARRAY_FIELDS:
			var values: Array = resource.get(field).duplicate()
			values.clear()
			for path in state[field]:
				values.append(load(path) if not str(path).is_empty() else null)
			resource.set(field, values)
		elif field in REFERENCE_FIELDS:
			resource.set(field, load(state[field]) if not str(state[field]).is_empty() else null)
		elif field == "modifiers":
			var modifiers: Array[StatModifierDefinition] = []
			for data in state[field]:
				if data == null:
					modifiers.append(null)
					continue
				var modifier := StatModifierDefinition.new()
				modifier.stat = data.stat
				modifier.operation = data.operation
				modifier.value = data.value
				modifiers.append(modifier)
			resource.set(field, modifiers)
		else:
			resource.set(field, state[field])


func draft(path: String) -> Resource:
	var result: Resource = load(path).duplicate()
	apply_state(result, states[path])
	return result


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
	for path in replacements:
		previous[path] = states[path].duplicate(true)
	if previous == replacements:
		return
	history.create_action(title)
	history.add_do_method(_install.bind(replacements.duplicate(true)))
	history.add_undo_method(_install.bind(previous))
	history.commit_action()


func _install(replacements: Dictionary) -> void:
	for path in replacements:
		states[path] = replacements[path].duplicate(true)
	write_recovery()
	changed.emit()


func set_field(path: String, field: String, value: Variant) -> void:
	var state: Dictionary = states[path].duplicate(true)
	state[field] = value
	change("Edit " + field.capitalize(), {path: state})


## Resolve slot conflicts through the same ItemDefinition rules as runtime.
func equipment_state(state: Dictionary, slot: int, item_path: String) -> Dictionary:
	var result := state.duplicate(true)
	var equipped: Array[ItemDefinition] = []
	var paths: Array = []
	for path in state.starting_equipment:
		if str(path).is_empty():
			continue
		var item := (draft(path) if states.has(path) else load(path)) as ItemDefinition
		for index in range(equipped.size() - 1, -1, -1):
			if item.conflicts_with(equipped[index]):
				equipped.remove_at(index)
				paths.remove_at(index)
		equipped.append(item)
		paths.append(path)
	var replacement := (draft(item_path) if states.has(item_path) else load(item_path)) as ItemDefinition if not item_path.is_empty() else null
	for index in range(equipped.size() - 1, -1, -1):
		if equipped[index].slot == slot or (replacement == null and slot in equipped[index].get_occupied_slots()) or (replacement != null and replacement.conflicts_with(equipped[index])):
			paths.remove_at(index)
	if replacement != null:
		paths.append(item_path)
	result.starting_equipment = paths
	return result


func conflicts() -> Array[String]:
	var result: Array[String] = []
	for path in dirty_paths():
		if FileAccess.get_sha256(path) != hashes[path] or capture(load(path)) != baselines[path]:
			result.append(path)
	return result


func save_all(overwrite: Array[String] = []) -> Dictionary:
	var blocked := conflicts()
	var result := {"saved": [], "failed": [], "conflicts": []}
	# Items first, so dependent previews resolve refreshed shared resources.
	var pending := dirty_paths()
	pending.sort_custom(func(a: String, b: String): return int(states[a].has("combat_rating")) < int(states[b].has("combat_rating")))
	for path in pending:
		if path in blocked and path not in overwrite:
			result.conflicts.append(path)
			continue
		if not FileAccess.file_exists(path):
			result.failed.append(path + ": resource was removed")
			continue
		var source := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) if path in blocked else load(path)
		if source == null:
			result.failed.append(path + ": cannot load resource")
			continue
		var resource := source.duplicate()
		var source_state := capture(source)
		var changed_fields := {}
		for field in states[path]:
			if states[path][field] != source_state[field]:
				changed_fields[field] = states[path][field]
		apply_state(resource, changed_fields)
		# Save to the original path; external item/ability references stay external.
		var original_uid := ResourceLoader.get_resource_uid(path)
		var error := ResourceSaver.save(resource, path)
		if error == OK and original_uid != ResourceUID.INVALID_ID:
			error = ResourceSaver.set_uid(path, original_uid)
		if error != OK:
			result.failed.append(path + ": " + error_string(error))
			continue
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		baselines[path] = states[path].duplicate(true)
		hashes[path] = FileAccess.get_sha256(path)
		result.saved.append(path)
	write_recovery()
	changed.emit()
	return result


func reload_paths(paths: Array) -> void:
	for path in paths:
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if resource != null:
			states[path] = capture(resource)
			baselines[path] = states[path].duplicate(true)
			hashes[path] = FileAccess.get_sha256(path)
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
		push_warning("Unit Balance could not preserve draft recovery: " + error_string(recovery_error))


func restore_recovery() -> int:
	var config := ConfigFile.new()
	if config.load(recovery_path) != OK:
		return 0
	var count := 0
	for path in config.get_sections():
		if states.has(path):
			states[path] = config.get_value(path, "state")
			baselines[path] = config.get_value(path, "baseline")
			hashes[path] = config.get_value(path, "hash")
			count += 1
	return count
