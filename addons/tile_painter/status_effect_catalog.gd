@tool
class_name StatusEffectCatalog
extends RefCounted

const STATUS_ROOT := "res://resources/statuses"


static func get_statuses() -> Array[StatusEffectDefinition]:
	var paths: Array[String] = []
	_collect_resource_paths(STATUS_ROOT, paths)
	var result: Array[StatusEffectDefinition] = []
	for path in paths:
		var resource := load(path)
		if resource is StatusEffectDefinition:
			result.append(resource as StatusEffectDefinition)
	result.sort_custom(func(a: StatusEffectDefinition, b: StatusEffectDefinition) -> bool:
		var name_comparison := a.display_name.naturalnocasecmp_to(b.display_name)
		if name_comparison != 0:
			return name_comparison < 0
		return a.resource_path.naturalnocasecmp_to(b.resource_path) < 0
	)
	return result


static func get_labels(statuses: Array[StatusEffectDefinition]) -> Array[String]:
	var name_counts: Dictionary = {}
	for status in statuses:
		var base_name := _get_base_name(status)
		name_counts[base_name] = int(name_counts.get(base_name, 0)) + 1
	var result: Array[String] = []
	for status in statuses:
		var base_name := _get_base_name(status)
		if int(name_counts.get(base_name, 0)) > 1:
			result.append("%s (%s)" % [
				base_name,
				status.resource_path.get_file().get_basename(),
			])
		else:
			result.append(base_name)
	return result


static func _get_base_name(status: StatusEffectDefinition) -> String:
	if status != null and not status.display_name.strip_edges().is_empty():
		return status.display_name.strip_edges()
	if status != null and not status.resource_path.is_empty():
		return status.resource_path.get_file().get_basename().capitalize()
	return "Unnamed Status"


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
