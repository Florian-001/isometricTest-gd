@tool
extends RefCounted

var active: Array[String] = []
var passives: Array[String] = []
var statuses: Array[String] = []
var references: Dictionary = {}


func scan(root := "res://resources") -> void:
	active.clear()
	passives.clear()
	statuses.clear()
	references.clear()
	_collect(root)
	active.sort()
	passives.sort()
	statuses.sort()


func _collect(folder: String) -> void:
	var directory := DirAccess.open(folder)
	if directory == null:
		return
	for child in directory.get_directories():
		if not child.begins_with("."):
			_collect(folder.path_join(child))
	for file in directory.get_files():
		if file.get_extension() not in ["tres", "res"]:
			continue
		var path := folder.path_join(file)
		var resource := load(path)
		if resource is AbilityDefinition:
			active.append(path)
		elif resource is PassiveAbilityDefinition:
			passives.append(path)
		elif resource is StatusEffectDefinition:
			statuses.append(path)
		if resource is CharacterDefinition or resource is CharacterClassDefinition or resource is StatusEffectDefinition:
			_find_references(resource, path, {})


func _find_references(value: Variant, owner: String, seen: Dictionary) -> void:
	if value is Resource:
		if seen.has(value.get_instance_id()):
			return
		seen[value.get_instance_id()] = true
		if value is AbilityDefinition or value is PassiveAbilityDefinition:
			var path: String = value.resource_path
			if not references.has(path):
				references[path] = []
			if owner not in references[path]:
				references[path].append(owner)
			return
		for property in value.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE and property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				_find_references(value.get(property.name), owner, seen)
	elif value is Array or value is Dictionary:
		for child in value.values() if value is Dictionary else value:
			_find_references(child, owner, seen)


static func label(path: String) -> String:
	if path.is_empty():
		return "None"
	var resource := load(path)
	return str(resource.get("display_name")) if resource != null and resource.get("display_name") != null else path.get_file().get_basename().capitalize()
