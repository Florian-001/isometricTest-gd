@tool
class_name ItemDefinitionCatalog
extends RefCounted

const ITEM_ROOT := "res://resources/items"


static func get_items(root_path: String = ITEM_ROOT) -> Array[ItemDefinition]:
	var paths: Array[String] = []
	_collect_resource_paths(root_path, paths)
	var result: Array[ItemDefinition] = []
	for path in paths:
		var resource := load(path)
		if resource is ItemDefinition:
			result.append(resource as ItemDefinition)
	result.sort_custom(func(a: ItemDefinition, b: ItemDefinition) -> bool:
		var name_comparison := _get_base_name(a).naturalnocasecmp_to(_get_base_name(b))
		if name_comparison != 0:
			return name_comparison < 0
		return a.resource_path.naturalnocasecmp_to(b.resource_path) < 0
	)
	return result


static func get_labels(items: Array[ItemDefinition]) -> Array[String]:
	var name_counts: Dictionary = {}
	for item in items:
		var base_name := _get_base_name(item)
		name_counts[base_name] = int(name_counts.get(base_name, 0)) + 1
	var result: Array[String] = []
	for item in items:
		var base_name := _get_base_name(item)
		if int(name_counts.get(base_name, 0)) > 1:
			result.append("%s (%s)" % [
				base_name,
				item.resource_path.get_file().get_basename(),
			])
		else:
			result.append(base_name)
	return result


static func get_tooltip(item: ItemDefinition) -> String:
	if item == null:
		return "No item is assigned to this entry."
	var lines: Array[String] = [_get_base_name(item)]
	lines.append("Slot: %s" % ItemDefinition.EquipmentSlot.keys()[item.slot].capitalize())
	if item.slot == ItemDefinition.EquipmentSlot.WEAPON:
		lines.append("Weapon type: %s" % ItemDefinition.WeaponType.keys()[item.weapon_type].capitalize())
		lines.append("Damage: %d" % item.weapon_damage)
	var granted_names: Array[String] = []
	for ability in item.granted_abilities:
		if ability != null and not granted_names.has(ability.display_name):
			granted_names.append(ability.display_name)
	if not granted_names.is_empty():
		lines.append("Grants: %s" % ", ".join(granted_names))
	if not item.resource_path.is_empty():
		lines.append(item.resource_path)
	else:
		lines.append("Unsaved external resource")
	return "\n".join(lines)


static func get_external_label(item: ItemDefinition) -> String:
	return "%s (external)" % _get_base_name(item)


static func _get_base_name(item: ItemDefinition) -> String:
	if item != null and not item.display_name.strip_edges().is_empty():
		return item.display_name.strip_edges()
	if item != null and not item.resource_path.is_empty():
		return item.resource_path.get_file().get_basename().capitalize()
	return "Unnamed Item"


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
