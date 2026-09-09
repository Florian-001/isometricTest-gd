@tool
extends RefCounted
## Shared by the command-line runner and editor plugin. Never loads a battle or unit.

const CLASSES_DIRECTORY := "res://resources/classes"
const OUTPUT_PATH := "res://CLASS_ABILITIES.xlsx"
const BASIC_ATTACKS := ["res://resources/abilities/strike.tres", "res://resources/abilities/arrow.tres"]
const Spreadsheet = preload("res://addons/class_ability_reference/spreadsheet_export.gd")


class BuildErrors extends Logger:
	var messages: Array[String] = []
	var mutex := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		mutex.lock()
		messages.append("%s:%d: %s" % [file, line, rationale if not rationale.is_empty() else code])
		mutex.unlock()


static func build(classes_directory: String = CLASSES_DIRECTORY) -> Dictionary:
	# Godot can return a partially loaded resource after a nested script/load error.
	# Capture those errors as well as validation failures before any output is written.
	var logger := BuildErrors.new()
	OS.add_logger(logger)
	var result := _build(classes_directory)
	OS.remove_logger(logger)
	if not logger.messages.is_empty():
		return _failure(logger.messages)
	if result.is_empty():
		return _failure(["Reference generation did not complete."])
	return result


static func _build(classes_directory: String) -> Dictionary:
	var errors: Array[String] = []
	var paths := _class_paths(classes_directory, errors)
	if paths.is_empty() and errors.is_empty():
		errors.append("No class resources found in %s." % classes_directory)
	var dependencies: Dictionary = {}
	for path in paths + BASIC_ATTACKS:
		_collect_dependencies(path, dependencies, errors)
	if not errors.is_empty():
		return _failure(errors)
	var classes: Array[Dictionary] = []
	var ids: Dictionary = {}
	for path in paths:
		# A deep uncached load reads saved nested abilities/statuses, not Inspector edits.
		var definition := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as CharacterClassDefinition
		if definition == null:
			errors.append("Cannot load a CharacterClassDefinition from %s." % path)
			continue
		errors.append_array(definition.validate())
		if ids.has(definition.class_id):
			errors.append("Duplicate class ID %s in %s." % [definition.class_id, path])
		ids[definition.class_id] = true
		classes.append({"definition": definition, "path": path})
	classes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var comparison := String(a.definition.display_name).nocasecmp_to(b.definition.display_name)
		return a.path < b.path if comparison == 0 else comparison < 0
	)
	if not errors.is_empty():
		return _failure(errors)
	var rows: Array[Dictionary] = []
	for path in BASIC_ATTACKS:
		var ability := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as AbilityDefinition
		if ability == null:
			errors.append("Cannot load basic attack %s." % path)
			continue
		rows.append(_row("All classes", null, ability, errors))
	for entry in classes:
		var unlocks: Array[ClassAbilityUnlock] = entry.definition.get_sorted_unlocks()
		if unlocks.is_empty():
			rows.append({"class_id": String(entry.definition.class_id), "class": entry.definition.display_name, "level": null, "ability": "—", "description": "No class unlocks; basic attacks are still available."})
		for unlock in unlocks:
			rows.append(_row(entry.definition.display_name, unlock.required_level, unlock.ability, errors, entry.definition.class_id))
	return {"ok": true, "rows": rows, "errors": errors} if errors.is_empty() else _failure(errors)


static func _row(class_name_text: String, level: Variant, ability: AbilityDefinition, errors: Array[String], class_id: StringName = &"") -> Dictionary:
	return {"class_id": null if class_id.is_empty() else String(class_id), "class": class_name_text, "level": level, "ability": ability.display_name, "description": _describe(ability, errors)}


static func update(output_path: String = OUTPUT_PATH, classes_directory: String = CLASSES_DIRECTORY, check_only: bool = false) -> Dictionary:
	var result := build(classes_directory)
	if not result.ok:
		return result
	return Spreadsheet.export_rows(result.rows, output_path, check_only)


## Only source content participates: generated workbooks, editor logs, and caches do not.
static func input_fingerprint(classes_directory: String = CLASSES_DIRECTORY) -> String:
	var errors: Array[String] = []
	var paths := _class_paths(classes_directory, errors)
	var dependencies: Dictionary = {}
	for path in paths + BASIC_ATTACKS:
		_collect_dependencies(path, dependencies, errors)
	# Include description helpers whose calls aren't serialized resource dependencies.
	_collect_scripts("res://scripts", dependencies)
	_collect_scripts("res://addons/class_ability_reference", dependencies)
	var sorted_paths := dependencies.keys()
	sorted_paths.sort()
	var parts: Array[String] = [classes_directory, JSON.stringify(Spreadsheet.runtime_paths())]
	for path in sorted_paths:
		parts.append("%s:%s" % [path, FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"])
	parts.append_array(errors)
	return "\n".join(parts).sha256_text()


static func _class_paths(directory: String, errors: Array[String]) -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		errors.append("Cannot read classes directory %s." % directory)
		return paths
	for child in dir.get_directories():
		if not child.begins_with("."):
			paths.append_array(_class_paths(directory.path_join(child), errors))
	for file_name in dir.get_files():
		if file_name.get_extension().to_lower() in ["tres", "res"]:
			paths.append(directory.path_join(file_name))
	paths.sort()
	return paths


static func _collect_dependencies(path: String, found: Dictionary, errors: Array[String]) -> void:
	if found.has(path):
		return
	found[path] = true
	if not FileAccess.file_exists(path):
		errors.append("Missing resource dependency: %s" % path)
		return
	for dependency in ResourceLoader.get_dependencies(path):
		var dependency_path := dependency.get_slice("::", dependency.get_slice_count("::") - 1)
		if dependency_path.begins_with("uid://"):
			var uid := ResourceUID.text_to_id(dependency_path)
			if ResourceUID.has_id(uid):
				dependency_path = ResourceUID.get_id_path(uid)
		_collect_dependencies(dependency_path, found, errors)


static func _collect_scripts(directory: String, found: Dictionary) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	for child in dir.get_directories():
		if not child.begins_with("."):
			_collect_scripts(directory.path_join(child), found)
	for file_name in dir.get_files():
		if file_name.get_extension() in ["gd", "mjs"]:
			found[directory.path_join(file_name)] = true


static func _describe(ability: AbilityDefinition, errors: Array[String]) -> String:
	var configuration_error := ability.get_targeting_configuration_error()
	if not configuration_error.is_empty():
		errors.append("%s: %s" % [ability.display_name, configuration_error])
	var description := ability.get_description()
	if description.strip_edges().is_empty():
		errors.append("Empty description for %s." % ability.display_name)
	var recipients: Array[String] = []
	for entry in [[AbilityDefinition.TargetFlags.FRIEND, "allies"], [AbilityDefinition.TargetFlags.ENEMY, "enemies"], [AbilityDefinition.TargetFlags.SELF, "self"]]:
		if ability.has_target_flag(entry[0]):
			recipients.append(entry[1])
	description += " | Affects: %s" % (", ".join(recipients) if not recipients.is_empty() else "no units")
	if ability.has_target_flag(AbilityDefinition.TargetFlags.CELL) and not ability.caster_centered:
		description += " | Can aim at a cell"
	if not ability.caster_centered:
		if ability.shape == AbilityDefinition.Shape.LINE_FROM_CASTER:
			description += " | Line from caster toward target"
		elif ability.get_effective_area_span() > 1:
			var shape_name: String = AbilityDefinition.Shape.keys()[ability.shape].to_lower().replace("_", " ")
			description += " | Area: %s, %d-cell span" % [shape_name, ability.get_effective_area_span()]
	match ability.get_required_weapon_type():
		ItemDefinition.WeaponType.MELEE:
			description += " | Melee weapon required" if not ability.allow_unarmed_for_friendlies else " | Melee weapon or unarmed friendly"
		ItemDefinition.WeaponType.RANGED:
			description += " | Ranged weapon required"
		_:
			description += " | No weapon required"
	if ability.accepts_weapon_range_bonus:
		description += " | Compatible weapon range bonuses extend normal attacks"
	return description.replace(". | ", " | ").replace(" | ", ". ").replace("\r\n", "\n").replace("\r", "\n") + "."


static func _failure(errors: Array[String]) -> Dictionary:
	return {"ok": false, "rows": [], "changed": false, "errors": errors}
