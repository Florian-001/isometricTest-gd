@tool
extends RefCounted

var runs: Array[String] = []
var enemies: Dictionary = {}


func scan(resource_root := "res://resources", scene_root := "res://scenes/enemies") -> void:
	runs.clear()
	enemies.clear()
	for path in files(resource_root, ["tres", "res"]):
		if load(path) is RunConfig:
			runs.append(path)
	for path in files(scene_root, ["tscn", "scn"]):
		add_enemy(path)
	runs.sort()


func add_enemy(path: String) -> void:
	if enemies.has(path):
		return
	var entry := inspect_enemy(path)
	if entry.error.is_empty():
		enemies[path] = entry


static func files(folder: String, extensions: Array) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(folder)
	if directory == null:
		return result
	for child in directory.get_directories():
		if not child.begins_with("."):
			result.append_array(files(folder.path_join(child), extensions))
	for file in directory.get_files():
		if file.get_extension() in extensions:
			result.append(folder.path_join(file))
	result.sort()
	return result


static func inspect_enemy(path: String) -> Dictionary:
	if not ResourceLoader.exists(path) or path.contains("::"):
		return {"error": "Enemy scene is missing: " + path}
	var scene := load(path) as PackedScene
	if scene == null or not scene.can_instantiate():
		return {"error": "Select a saved enemy scene: " + path}
	var instance := scene.instantiate()
	if not instance is TacticalCharacter or not instance.definition is EnemyDefinition or instance.definition.faction != CharacterDefinition.Faction.ENEMY or instance.definition.combat_rating < 1:
		instance.free()
		return {"error": "Scene needs an enemy TacticalCharacter with positive authored CR: " + path}
	var result := {"error": "", "path": path, "name": instance.definition.display_name,
		"cr": instance.definition.combat_rating, "icon": instance.facing_right_texture}
	instance.free()
	return result
