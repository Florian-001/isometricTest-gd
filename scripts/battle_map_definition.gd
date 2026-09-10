@tool
class_name BattleMapDefinition
extends Resource

@export var display_name: String = "New Level"
@export_multiline var description: String = ""
@export var map_scene: PackedScene

## Runtime progression copies retain the authored map identity for scenario saves.
var source_resource_path: String = ""


func get_save_path() -> String:
	return source_resource_path if not source_resource_path.is_empty() else resource_path


func is_configured() -> bool:
	return not display_name.strip_edges().is_empty() and map_scene != null
