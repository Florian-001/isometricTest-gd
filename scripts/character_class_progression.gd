class_name CharacterClassProgression
extends RefCounted


static func copy_levels(levels: Array[CharacterClassLevel]) -> Array[CharacterClassLevel]:
	var result: Array[CharacterClassLevel] = []
	for entry in levels:
		result.append(CharacterClassLevel.create(entry.character_class, entry.level) if entry != null else null)
	return result


static func validate_levels(levels: Array[CharacterClassLevel], require_saved := false) -> Array[String]:
	var errors: Array[String] = []
	if levels.is_empty():
		errors.append("Friendly characters need a starting class or a class-level allocation.")
	var ids := {}
	var total := 0
	for entry in levels:
		if entry == null or entry.character_class == null or entry.level < 1:
			errors.append("Every class allocation needs a class and a positive level.")
			continue
		var definition := entry.character_class
		if entry.level > 9223372036854775807 - total:
			errors.append("Total character level exceeds the supported integer range.")
		else:
			total += entry.level
		errors.append_array(definition.validate())
		if ids.has(definition.class_id):
			errors.append("Duplicate class ID: %s" % definition.class_id)
		ids[definition.class_id] = true
		if require_saved and definition.resource_path.is_empty():
			errors.append("Class %s must be saved as a resource." % definition.display_name)
	return errors


static func to_data(levels: Array[CharacterClassLevel]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in levels:
		if entry != null and entry.character_class != null:
			result.append({"class": entry.character_class.resource_path, "level": entry.level})
	return result


static func validate_data(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is Array or value.is_empty():
		errors.append("Class levels must be a nonempty array.")
		return errors
	for entry in value:
		if not entry is Dictionary:
			errors.append("Class allocation must be an object.")
			continue
		var level: Variant = entry.get("level")
		if not (level is int or level is float) or not is_finite(float(level)) or float(level) < 1 or float(level) != floor(float(level)) or float(level) >= float(9223372036854775807):
			errors.append("Class level must be a positive integer.")
		var path: Variant = entry.get("class")
		if not path is String or not ResourceLoader.exists(path) or not load(path) is CharacterClassDefinition:
			errors.append("Class allocation references a missing or invalid class resource.")
	if errors.is_empty():
		errors.append_array(validate_levels(from_data(value), true))
	return errors


## Call validate_data before decoding untrusted save data.
static func from_data(value: Array) -> Array[CharacterClassLevel]:
	var result: Array[CharacterClassLevel] = []
	for entry in value:
		result.append(CharacterClassLevel.create(load(entry["class"]) as CharacterClassDefinition, int(entry.level)))
	return result


## Upgrade old snapshots using the scene's authored allocation, with its saved template.
## Existing ability override fields are deliberately retained.
static func prepare_setup(setup: Dictionary) -> Array[String]:
	var path := str(setup.get("definition", ""))
	var definition := load(path) as CharacterDefinition if ResourceLoader.exists(path) else null
	if definition == null or definition.faction != CharacterDefinition.Faction.FRIENDLY:
		var no_errors: Array[String] = []
		return no_errors
	if not setup.has("class_levels"):
		var scene_path := str(setup.get("scene", ""))
		var scene := load(scene_path) as PackedScene if ResourceLoader.exists(scene_path) else null
		var instance := scene.instantiate() if scene != null else null
		var character := instance as TacticalCharacter
		if character == null:
			if instance != null:
				instance.free()
			return ["Cannot restore the friendly's starting class from its scene."]
		character.definition = definition
		var starting_levels := character.get_class_levels()
		if not starting_levels.is_empty() and starting_levels[0] != null:
			starting_levels = [CharacterClassLevel.create(starting_levels[0].character_class)]
		setup["class_levels"] = to_data(starting_levels)
		character.free()
	return validate_data(setup["class_levels"])


static func get_summary(levels: Array[CharacterClassLevel]) -> String:
	var names: Array[String] = []
	var total := 0
	for entry in levels:
		if entry != null and entry.character_class != null:
			names.append("%s %d" % [entry.character_class.display_name, entry.level])
			total += entry.level
	return "Level %d · %s" % [maxi(1, total), " / ".join(names) if not names.is_empty() else "Class unassigned"]
