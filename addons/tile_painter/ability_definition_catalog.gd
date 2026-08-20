@tool
class_name AbilityDefinitionCatalog
extends RefCounted

const ABILITY_ROOT := "res://resources/abilities"


static func get_abilities(root_path: String = ABILITY_ROOT) -> Array[AbilityDefinition]:
	var paths: Array[String] = []
	_collect_resource_paths(root_path, paths)
	var result: Array[AbilityDefinition] = []
	for path in paths:
		var resource := load(path)
		if resource is AbilityDefinition:
			result.append(resource as AbilityDefinition)
	result.sort_custom(func(a: AbilityDefinition, b: AbilityDefinition) -> bool:
		var name_comparison := _get_base_name(a).naturalnocasecmp_to(_get_base_name(b))
		if name_comparison != 0:
			return name_comparison < 0
		return a.resource_path.naturalnocasecmp_to(b.resource_path) < 0
	)
	return result


static func get_labels(abilities: Array[AbilityDefinition]) -> Array[String]:
	var name_counts: Dictionary = {}
	for ability in abilities:
		var base_name := _get_base_name(ability)
		name_counts[base_name] = int(name_counts.get(base_name, 0)) + 1
	var result: Array[String] = []
	for ability in abilities:
		var base_name := _get_base_name(ability)
		if int(name_counts.get(base_name, 0)) > 1:
			result.append("%s (%s)" % [
				base_name,
				ability.resource_path.get_file().get_basename(),
			])
		else:
			result.append(base_name)
	return result


static func get_tooltip(ability: AbilityDefinition) -> String:
	if ability == null:
		return "No ability is assigned to this entry."
	var lines: Array[String] = [_get_base_name(ability)]
	lines.append("Type: %s" % AbilityDefinition.AbilityType.keys()[ability.ability_type].capitalize())
	lines.append("Effect: %s" % AbilityDefinition.PrimaryEffect.keys()[ability.effect].capitalize())
	if not ability.resource_path.is_empty():
		lines.append(ability.resource_path)
	else:
		lines.append("Unsaved external resource")
	return "\n".join(lines)


static func get_external_label(ability: AbilityDefinition) -> String:
	return "%s (external)" % _get_base_name(ability)


static func _get_base_name(ability: AbilityDefinition) -> String:
	if ability != null and not ability.display_name.strip_edges().is_empty():
		return ability.display_name.strip_edges()
	if ability != null and not ability.resource_path.is_empty():
		return ability.resource_path.get_file().get_basename().capitalize()
	return "Unnamed Ability"


static func _collect_resource_paths(folder_path: String, result: Array[String]) -> void:
	var directory := DirAccess.open(folder_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not entry.begins_with("."):
			var entry_path := folder_path.path_join(entry)
			if directory.current_is_dir():
				_collect_resource_paths(entry_path, result)
			elif entry.get_extension().to_lower() in ["tres", "res"]:
				result.append(entry_path)
		entry = directory.get_next()
	directory.list_dir_end()
	result.sort()
