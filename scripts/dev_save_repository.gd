class_name DevSaveRepository
extends RefCounted

const REPOSITORY_VERSION := 1
const DEFAULT_PATH := "user://dev_saves.json"
const DEFAULT_RECOVERY_PATH := "user://dev_recovery.json"

var save_path: String
var recovery_path: String


func _init(path: String = DEFAULT_PATH, recovery: String = DEFAULT_RECOVERY_PATH) -> void:
	save_path = path
	recovery_path = recovery


func list_saves() -> Array[Dictionary]:
	var container := _read_container(save_path)
	var result: Array[Dictionary] = []
	for entry in container.get("saves", []):
		if entry is Dictionary:
			result.append((entry as Dictionary).duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("updated_unix", 0)) > int(b.get("updated_unix", 0))
	)
	return result


func save_named(name: String, snapshot: Dictionary) -> bool:
	var clean_name := name.strip_edges()
	if clean_name.is_empty() or snapshot.is_empty():
		return false
	var container := _read_container(save_path)
	var saves: Array = container.get("saves", [])
	var key := clean_name.to_lower()
	var replacement := {
		"name": clean_name,
		"key": key,
		"updated_unix": int(Time.get_unix_time_from_system()),
		"snapshot": snapshot.duplicate(true),
	}
	var replaced := false
	for index in range(saves.size()):
		if str(saves[index].get("key", "")) == key:
			saves[index] = replacement
			replaced = true
			break
	if not replaced:
		saves.append(replacement)
	container.saves = saves
	return _write_json(save_path, container)


func delete_named(name: String) -> bool:
	var container := _read_container(save_path)
	var saves: Array = container.get("saves", [])
	var key := name.strip_edges().to_lower()
	for index in range(saves.size() - 1, -1, -1):
		if str(saves[index].get("key", "")) == key:
			saves.remove_at(index)
			container.saves = saves
			return _write_json(save_path, container)
	return false


func get_named(name: String) -> Dictionary:
	var key := name.strip_edges().to_lower()
	for entry in list_saves():
		if str(entry.get("key", "")) == key:
			return (entry.get("snapshot", {}) as Dictionary).duplicate(true)
	return {}


func write_recovery(snapshot: Dictionary) -> bool:
	return not snapshot.is_empty() and _write_json(recovery_path, snapshot)


func get_recovery() -> Dictionary:
	return _read_json_dictionary(recovery_path)


func has_recovery() -> bool:
	return not get_recovery().is_empty()


func _read_container(path: String) -> Dictionary:
	var parsed := _read_json_dictionary(path)
	if int(parsed.get("repository_version", 0)) != REPOSITORY_VERSION:
		return {"repository_version": REPOSITORY_VERSION, "saves": []}
	if not (parsed.get("saves", []) is Array):
		return {"repository_version": REPOSITORY_VERSION, "saves": []}
	return parsed


func _read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "  "))
	return file.get_error() == OK
