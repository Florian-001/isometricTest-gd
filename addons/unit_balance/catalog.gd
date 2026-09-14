@tool
extends RefCounted

var enemies: Array[String] = []
var items: Array[String] = []
var abilities: Array[String] = []
var passives: Array[String] = []
var profiles: Array[String] = []
var statuses: Array[String] = []


func scan(root := "res://resources") -> void:
	for collection in [enemies, items, abilities, passives, profiles, statuses]:
		collection.clear()
	_collect(root)
	for collection in [enemies, items, abilities, passives, profiles, statuses]:
		collection.sort()


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
		if resource is EnemyDefinition:
			enemies.append(path)
		elif resource is ItemDefinition:
			items.append(path)
		elif resource is AbilityDefinition:
			abilities.append(path)
		elif resource is PassiveAbilityDefinition:
			passives.append(path)
		elif resource is EnemyAIProfile:
			profiles.append(path)
		elif resource is StatusEffectDefinition:
			statuses.append(path)


static func label(path: String) -> String:
	if path.is_empty():
		return "None"
	var resource := load(path)
	if resource != null and resource.get("display_name") != null:
		return str(resource.get("display_name"))
	return path.get_file().get_basename().capitalize()
