class_name ScenarioSaveStore
extends RefCounted

const SCHEMA_VERSION := 1
const SAVE_DIRECTORY := "user://dev_saves"


static func list_saves(directory_path := SAVE_DIRECTORY) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var absolute_directory := ProjectSettings.globalize_path(directory_path)
	if not DirAccess.dir_exists_absolute(absolute_directory):
		return entries
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return entries
	for file_name in directory.get_files():
		if file_name.get_extension().to_lower() != "json":
			continue
		var path := "%s/%s" % [directory_path, file_name]
		var loaded := load_save(path, directory_path)
		if loaded.ok:
			var payload: Dictionary = loaded.payload
			var metadata: Dictionary = payload.get("metadata", {})
			entries.append({
				"path": path,
				"status": "ok",
				"name": str(metadata.get("name", file_name.get_basename())),
				"saved_at": str(metadata.get("saved_at", "")),
				"round": int(metadata.get("round", 1)),
				"map_name": str(metadata.get("map_name", "Unknown Map")),
			})
		else:
			entries.append({
				"path": path,
				"status": "corrupt",
				"name": file_name.get_basename(),
				"saved_at": "",
				"round": 0,
				"map_name": "Unreadable save",
				"error": " ".join(loaded.errors),
			})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var saved_a := str(a.get("saved_at", ""))
		var saved_b := str(b.get("saved_at", ""))
		if saved_a != saved_b:
			return saved_a > saved_b
		return str(a.get("path", "")) > str(b.get("path", ""))
	)
	return entries


static func save_new(payload: Dictionary, directory_path := SAVE_DIRECTORY) -> Dictionary:
	var prepared := payload.duplicate(true)
	var metadata: Dictionary = prepared.get("metadata", {})
	var timestamp := Time.get_datetime_string_from_system(false, true)
	metadata["saved_at"] = timestamp
	if str(metadata.get("name", "")).strip_edges().is_empty():
		metadata["name"] = _automatic_name(metadata, timestamp)
	prepared["metadata"] = metadata
	var directory_result := _ensure_directory(directory_path)
	if not directory_result.ok:
		return directory_result
	var sequence := Time.get_ticks_msec()
	var path := "%s/save_%d_%d.json" % [
		directory_path,
		int(Time.get_unix_time_from_system()),
		sequence,
	]
	while FileAccess.file_exists(path):
		sequence += 1
		path = "%s/save_%d_%d.json" % [
			directory_path,
			int(Time.get_unix_time_from_system()),
			sequence,
		]
	return _write_validated(path, prepared)


static func replace_save(
	path: String,
	payload: Dictionary,
	directory_path := SAVE_DIRECTORY
) -> Dictionary:
	if not _is_managed_path(path, directory_path):
		return _failure("Save path is outside the developer save directory.")
	var existing := load_save(path, directory_path)
	if not existing.ok:
		return existing
	var prepared := payload.duplicate(true)
	var old_metadata: Dictionary = existing.payload.get("metadata", {})
	var metadata: Dictionary = prepared.get("metadata", {})
	metadata["name"] = str(old_metadata.get("name", metadata.get("name", "Save")))
	metadata["saved_at"] = Time.get_datetime_string_from_system(false, true)
	prepared["metadata"] = metadata
	return _write_validated(path, prepared)


static func rename_save(
	path: String,
	new_name: String,
	directory_path := SAVE_DIRECTORY
) -> Dictionary:
	if not _is_managed_path(path, directory_path):
		return _failure("Save path is outside the developer save directory.")
	var cleaned := new_name.strip_edges().left(72)
	if cleaned.is_empty():
		return _failure("Save name cannot be empty.")
	var loaded := load_save(path, directory_path)
	if not loaded.ok:
		return loaded
	var payload: Dictionary = loaded.payload
	var metadata: Dictionary = payload.get("metadata", {})
	metadata["name"] = cleaned
	payload["metadata"] = metadata
	return _write_validated(path, payload)


static func delete_save(path: String, directory_path := SAVE_DIRECTORY) -> Dictionary:
	if not _is_managed_path(path, directory_path):
		return _failure("Save path is outside the developer save directory.")
	if not FileAccess.file_exists(path):
		return {"ok": true, "errors": []}
	var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if error != OK:
		return _failure("Could not delete the save (error %d)." % error)
	return {"ok": true, "errors": []}


static func load_save(path: String, directory_path := SAVE_DIRECTORY) -> Dictionary:
	if not _is_managed_path(path, directory_path):
		return _failure("Save path is outside the developer save directory.")
	if not FileAccess.file_exists(path):
		return _failure("Save file does not exist.")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Could not open the save file.")
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		return _failure(
			"Malformed JSON at line %d: %s" % [
				parser.get_error_line(),
				parser.get_error_message(),
			]
		)
	if not parser.data is Dictionary:
		return _failure("Save root must be a JSON object.")
	return validate_payload(parser.data)


static func validate_payload(input: Dictionary) -> Dictionary:
	input = input.duplicate(true)
	var errors: Array[String] = []
	if int(input.get("schema_version", -1)) != SCHEMA_VERSION:
		errors.append("Unsupported save schema version.")
	var map_path := str(input.get("map_definition", ""))
	var map_definition := _load_typed_resource(map_path, "map", errors)
	if map_definition != null and not map_definition is BattleMapDefinition:
		errors.append("Map definition is not a BattleMapDefinition: %s" % map_path)
	var setup = input.get("setup", {})
	var runtime = input.get("runtime", {})
	if not setup is Dictionary:
		errors.append("Setup must be an object.")
		setup = {}
	if not runtime is Dictionary:
		errors.append("Runtime state must be an object.")
		runtime = {}
	var grid_value: Array = setup.get("grid_size", [])
	var width := int(grid_value[0]) if grid_value.size() >= 2 else 0
	var height := int(grid_value[1]) if grid_value.size() >= 2 else 0
	if width <= 0 or height <= 0:
		errors.append("Grid size must contain positive width and height.")
	var legacy_wall_keys := {}
	var raw_wall_cells = setup.get("wall_cells", [])
	if not raw_wall_cells is Array:
		errors.append("Wall cells must be an array.")
		raw_wall_cells = []
	for value in raw_wall_cells:
		var cell: Variant = _parse_cell(value)
		if cell == null:
			errors.append("Wall cell is invalid: %s" % [value])
		else:
			var key := _cell_key(cell)
			if legacy_wall_keys.has(key):
				errors.append("Duplicate wall cell: %s" % key)
			legacy_wall_keys[key] = true
	var terrain_keys := {}
	if setup.has("terrain"):
		var raw_terrain = setup.get("terrain", [])
		if not raw_terrain is Array:
			errors.append("Terrain setup must be an array.")
		else:
			for raw_entry in raw_terrain:
				if not raw_entry is Dictionary:
					errors.append("Every terrain entry must be an object.")
					continue
				var entry: Dictionary = raw_entry
				var cell: Variant = _parse_cell(entry.get("cell", []))
				if cell == null:
					errors.append("Terrain entry has an invalid cell.")
					continue
				var key := _cell_key(cell)
				if terrain_keys.has(key):
					errors.append("Duplicate terrain cell: %s" % key)
				terrain_keys[key] = true
				if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
					errors.append("Terrain cell %s is outside the grid." % key)
				var path := str(entry.get("definition", ""))
				var resource := _load_typed_resource(path, "terrain", errors)
				if resource != null and not resource is TileDefinition:
					errors.append("Terrain has the wrong resource type: %s" % path)
	var wall_keys: Dictionary = legacy_wall_keys.duplicate()
	var has_rich_walls: bool = setup.has("walls")
	if has_rich_walls:
		wall_keys.clear()
		var raw_walls = setup.get("walls", [])
		if not raw_walls is Array:
			errors.append("Wall setup must be an array.")
		else:
			for raw_entry in raw_walls:
				if not raw_entry is Dictionary:
					errors.append("Every wall entry must be an object.")
					continue
				var entry: Dictionary = raw_entry
				var cell: Variant = _parse_cell(entry.get("cell", []))
				if cell == null:
					errors.append("Wall entry has an invalid cell.")
					continue
				var key := _cell_key(cell)
				if wall_keys.has(key):
					errors.append("Duplicate wall setup cell: %s" % key)
				wall_keys[key] = true
				if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
					errors.append("Wall cell %s is outside the grid." % key)
				var definition_path := str(entry.get("definition", ""))
				if definition_path.is_empty():
					_validate_legacy_wall_appearance(entry.get("appearance", {}), key, errors)
				else:
					var resource := _load_typed_resource(definition_path, "wall", errors)
					if resource != null and not resource is WallDefinition:
						errors.append("Wall has the wrong resource type: %s" % definition_path)
		if wall_keys.size() != legacy_wall_keys.size():
			errors.append("Legacy wall cells do not match the wall setup.")
		else:
			for key in wall_keys:
				if not legacy_wall_keys.has(key):
					errors.append("Legacy wall cells do not match the wall setup.")
					break
	for key in terrain_keys:
		if wall_keys.has(key):
			errors.append("Terrain and a wall overlap at %s." % key)
	if map_definition is BattleMapDefinition:
		_validate_map_geometry(
			map_definition as BattleMapDefinition,
			width,
			height,
			wall_keys,
			not has_rich_walls,
			errors
		)
	var ids := {}
	var occupied := {}
	var factions := {}
	var unit_factions := {}
	var units = setup.get("units", [])
	if not units is Array or units.is_empty():
		errors.append("Scenario must contain units.")
		units = []
	for raw_unit in units:
		if not raw_unit is Dictionary:
			errors.append("Every unit setup entry must be an object.")
			continue
		var unit: Dictionary = raw_unit
		var unit_id := str(unit.get("id", "")).strip_edges()
		if unit_id.is_empty():
			errors.append("Every unit needs a stable ID.")
		elif ids.has(unit_id):
			errors.append("Duplicate unit ID: %s" % unit_id)
		ids[unit_id] = true
		var scene_path := str(unit.get("scene", ""))
		var scene := _load_typed_resource(scene_path, "unit scene", errors)
		if scene != null and not scene is PackedScene:
			errors.append("Unit scene is not a PackedScene: %s" % scene_path)
		elif scene is PackedScene:
			var instance := (scene as PackedScene).instantiate()
			if not instance is TacticalCharacter:
				errors.append("Unit scene root must be TacticalCharacter: %s" % scene_path)
			instance.free()
		var definition_path := str(unit.get("definition", ""))
		var definition := _load_typed_resource(definition_path, "unit definition", errors)
		if definition != null and not definition is CharacterDefinition:
			errors.append("Unit definition is not a CharacterDefinition: %s" % definition_path)
		elif definition is CharacterDefinition:
			var faction := int(unit.get("faction", -1))
			if faction not in [CharacterDefinition.Faction.FRIENDLY, CharacterDefinition.Faction.ENEMY]:
				errors.append("Unit %s has an invalid faction." % unit_id)
			elif faction != int((definition as CharacterDefinition).faction):
				errors.append("Unit %s faction does not match its template." % unit_id)
			else:
				factions[faction] = true
				unit_factions[unit_id] = faction
		var cell: Variant = _parse_cell(unit.get("cell", []))
		if cell == null:
			errors.append("Unit %s has an invalid cell." % unit_id)
		else:
			var key := _cell_key(cell)
			if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
				errors.append("Unit %s is outside the grid." % unit_id)
			elif wall_keys.has(key):
				errors.append("Unit %s is placed on a wall." % unit_id)
			elif occupied.has(key):
				errors.append("Units %s and %s share a cell." % [occupied[key], unit_id])
			occupied[key] = unit_id
		_validate_resource_paths(unit.get("abilities", []), "ability", errors)
		_validate_resource_paths(unit.get("equipment", []), "item", errors)
		_validate_resource_paths(unit.get("legacy_equipment", []), "item", errors)
		errors.append_array(CharacterClassProgression.prepare_setup(unit))
	if factions.size() < 2:
		errors.append("Scenario requires at least one friendly and one enemy unit.")
	var fresh_start := bool(runtime.get("fresh_start", false))
	if not fresh_start:
		_validate_runtime(runtime, ids, unit_factions, width, height, wall_keys, errors)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return {"ok": true, "errors": [], "payload": input.duplicate(true)}


static func _validate_runtime(
	runtime: Dictionary,
	ids: Dictionary,
	unit_factions: Dictionary,
	width: int,
	height: int,
	wall_keys: Dictionary,
	errors: Array[String]
) -> void:
	var runtime_ids := {}
	var occupied := {}
	for raw_state in runtime.get("units", []):
		if not raw_state is Dictionary:
			errors.append("Every unit runtime entry must be an object.")
			continue
		var state: Dictionary = raw_state
		var unit_id := str(state.get("id", ""))
		var removed_enemy := (
			int(unit_factions.get(unit_id, -1)) == CharacterDefinition.Faction.ENEMY
			and int(state.get("current_health", 1)) <= 0
		)
		if not ids.has(unit_id):
			errors.append("Runtime state references an unknown unit: %s" % unit_id)
		elif runtime_ids.has(unit_id):
			errors.append("Duplicate runtime unit state: %s" % unit_id)
		runtime_ids[unit_id] = true
		var cell: Variant = _parse_cell(state.get("cell", []))
		if cell == null:
			errors.append("Runtime unit %s has an invalid cell." % unit_id)
		else:
			var key := _cell_key(cell)
			if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
				errors.append("Runtime unit %s is outside the grid." % unit_id)
			elif wall_keys.has(key):
				errors.append("Runtime unit %s is placed on a wall." % unit_id)
			elif not removed_enemy and occupied.has(key):
				errors.append("Runtime units %s and %s share a cell." % [occupied[key], unit_id])
			if not removed_enemy:
				occupied[key] = unit_id
		_validate_resource_paths(state.get("equipped_items", []), "item", errors)
		for raw_status in state.get("statuses", []):
			if not raw_status is Dictionary:
				errors.append("Unit %s has an invalid status entry." % unit_id)
				continue
			var status: Dictionary = raw_status
			var definition_path := str(status.get("definition", ""))
			var definition := _load_typed_resource(definition_path, "status", errors)
			if definition != null and not definition is StatusEffectDefinition:
				errors.append("Status resource has the wrong type: %s" % definition_path)
			var source_path := str(status.get("source_resource", ""))
			if not source_path.is_empty() and not ResourceLoader.exists(source_path):
				errors.append("Status source resource is missing: %s" % source_path)
			var source_unit_id := str(status.get("source_unit", ""))
			if not source_unit_id.is_empty() and not ids.has(source_unit_id):
				errors.append("Status references an unknown source unit: %s" % source_unit_id)
	if runtime_ids.size() != ids.size():
		errors.append("Runtime state must include every scenario unit.")
	var turn: Dictionary = runtime.get("turn", {})
	if not bool(turn.get("action_boundary", false)):
		errors.append("Save was not captured at a stable action boundary.")
	var ordered_ids := {}
	var order: Array = turn.get("order", [])
	for unit_id in order:
		var ordered_id := str(unit_id)
		if not ids.has(ordered_id):
			errors.append("Turn order references an unknown unit: %s" % unit_id)
		elif ordered_ids.has(ordered_id):
			errors.append("Turn order contains duplicate unit: %s" % unit_id)
		ordered_ids[ordered_id] = true
	var current_id := str(turn.get("current_unit", ""))
	if not current_id.is_empty() and not ids.has(current_id):
		errors.append("Current turn references an unknown unit: %s" % current_id)
	var current_index := int(turn.get("current_index", -1))
	if current_id.is_empty():
		if current_index != -1:
			errors.append("A save without an active unit must use current index -1.")
	elif current_index < 0 or current_index >= order.size() or str(order[current_index]) != current_id:
		errors.append("Current turn index does not match the active unit.")
	var scene_ids := {}
	for unit_id in turn.get("scene_order", []):
		var scene_id := str(unit_id)
		if not ids.has(scene_id):
			errors.append("Scene order references an unknown unit: %s" % scene_id)
		elif scene_ids.has(scene_id):
			errors.append("Scene order contains duplicate unit: %s" % scene_id)
		scene_ids[scene_id] = true
	if scene_ids.size() != ids.size():
		errors.append("Scene order must include every scenario unit.")
	if not bool(runtime.get("combat_over", false)) and current_id.is_empty():
		errors.append("An active battle must have a current unit.")
	_validate_resource_paths(runtime.get("inventory", []), "item", errors)


static func _validate_resource_paths(
	values,
	expected_kind: String,
	errors: Array[String]
) -> void:
	var label := "ability" if expected_kind == "ability" else "item"
	if not values is Array:
		errors.append("%s list must be an array." % label.capitalize())
		return
	for value in values:
		var path := str(value)
		if path.is_empty():
			continue
		var resource := _load_typed_resource(path, label, errors)
		var has_expected_type := false
		if expected_kind == "ability":
			has_expected_type = resource is AbilityDefinition
		else:
			has_expected_type = resource is ItemDefinition
		if resource != null and not has_expected_type:
			errors.append("%s has the wrong resource type: %s" % [label.capitalize(), path])


static func _validate_map_geometry(
	definition: BattleMapDefinition,
	width: int,
	height: int,
	wall_keys: Dictionary,
	validate_authored_walls: bool,
	errors: Array[String]
) -> void:
	if not definition.is_configured():
		errors.append("Map definition is not configured.")
		return
	var instance := definition.map_scene.instantiate()
	if not instance is BattleMap:
		errors.append("Map scene root must be BattleMap.")
		instance.free()
		return
	var battle_map := instance as BattleMap
	if not battle_map.is_configured():
		errors.append("Map scene is missing required containers.")
		instance.free()
		return
	var map_grid := battle_map.get_grid()
	if map_grid.grid_size != Vector2i(width, height):
		errors.append("Saved grid size does not match the selected map.")
	if not validate_authored_walls:
		instance.free()
		return
	var map_walls := {}
	for child in battle_map.get_walls().get_children():
		if child is TacticalWall:
			map_walls[_cell_key((child as TacticalWall).grid_cell)] = true
	if map_walls.size() != wall_keys.size():
		errors.append("Saved walls do not match the selected map.")
	else:
		for key in map_walls:
			if not wall_keys.has(key):
				errors.append("Saved walls do not match the selected map.")
				break
	instance.free()


static func _validate_legacy_wall_appearance(
	appearance,
	cell_key: String,
	errors: Array[String]
) -> void:
	if not appearance is Dictionary:
		errors.append("Wall %s needs legacy appearance values." % cell_key)
		return
	var values: Dictionary = appearance
	for field in ["wall_height", "outline_width", "top_color", "left_color", "right_color", "outline_color"]:
		if not values.has(field):
			errors.append("Wall %s is missing appearance field %s." % [cell_key, field])
	var wall_height := float(values.get("wall_height", 0.0))
	if wall_height < 8.0 or wall_height > 160.0:
		errors.append("Wall %s has an invalid height." % cell_key)
	var outline_width := float(values.get("outline_width", 0.0))
	if outline_width < 0.5 or outline_width > 6.0:
		errors.append("Wall %s has an invalid outline width." % cell_key)
	for color_field in ["top_color", "left_color", "right_color", "outline_color"]:
		if not Color.html_is_valid(str(values.get(color_field, ""))):
			errors.append("Wall %s has an invalid %s." % [cell_key, color_field])


static func _load_typed_resource(path: String, label: String, errors: Array[String]) -> Resource:
	if path.is_empty() or not path.begins_with("res://") or path.contains("::"):
		errors.append("%s path is invalid: %s" % [label.capitalize(), path])
		return null
	if not ResourceLoader.exists(path):
		errors.append("%s resource is missing: %s" % [label.capitalize(), path])
		return null
	var resource := load(path)
	if resource == null:
		errors.append("%s resource could not be loaded: %s" % [label.capitalize(), path])
	return resource


static func _write_validated(path: String, payload: Dictionary) -> Dictionary:
	var validation := validate_payload(payload)
	if not validation.ok:
		return validation
	var directory_result := _ensure_directory(path.get_base_dir())
	if not directory_result.ok:
		return directory_result
	var temporary := path + ".tmp"
	var backup := path + ".bak"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _failure("Could not create the temporary save file.")
	file.store_string(JSON.stringify(validation.payload, "\t"))
	file.close()
	var absolute_target := ProjectSettings.globalize_path(path)
	var absolute_temporary := ProjectSettings.globalize_path(temporary)
	var absolute_backup := ProjectSettings.globalize_path(backup)
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(absolute_backup)
	var had_existing := FileAccess.file_exists(path)
	if had_existing:
		var backup_error := DirAccess.rename_absolute(absolute_target, absolute_backup)
		if backup_error != OK:
			DirAccess.remove_absolute(absolute_temporary)
			return _failure("Could not prepare the previous save for replacement.")
	var replace_error := DirAccess.rename_absolute(absolute_temporary, absolute_target)
	if replace_error != OK:
		if had_existing:
			DirAccess.rename_absolute(absolute_backup, absolute_target)
		if FileAccess.file_exists(temporary):
			DirAccess.remove_absolute(absolute_temporary)
		return _failure("Could not replace the save file.")
	if had_existing and FileAccess.file_exists(backup):
		DirAccess.remove_absolute(absolute_backup)
	return {"ok": true, "errors": [], "path": path, "payload": validation.payload}


static func _ensure_directory(directory_path: String) -> Dictionary:
	var error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(directory_path)
	)
	if error != OK and error != ERR_ALREADY_EXISTS:
		return _failure("Could not create the developer save directory.")
	return {"ok": true, "errors": []}


static func _automatic_name(metadata: Dictionary, timestamp: String) -> String:
	var map_name := str(metadata.get("map_name", "Scenario"))
	var round_number := int(metadata.get("round", 1))
	return "%s — Round %d — %s" % [map_name, round_number, timestamp.replace("T", " ")]


static func _is_managed_path(path: String, directory_path: String) -> bool:
	return path.get_base_dir() == directory_path and path.get_extension().to_lower() == "json"


static func _parse_cell(value):
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return null


static func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": [message]}
