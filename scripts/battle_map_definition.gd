@tool
class_name BattleMapDefinition
extends Resource

@export var display_name: String = "New Level"
@export_multiline var description: String = ""
@export var map_scene: PackedScene


func is_configured() -> bool:
	return not display_name.strip_edges().is_empty() and map_scene != null
