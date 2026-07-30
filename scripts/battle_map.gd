@tool
class_name BattleMap
extends Node2D


func get_grid() -> IsometricGrid:
	return get_node_or_null("Grid") as IsometricGrid


func get_terrain() -> TacticalTerrain:
	return get_node_or_null("Terrain") as TacticalTerrain


func get_walls() -> Node2D:
	return get_node_or_null("Walls") as Node2D


func get_characters() -> Node2D:
	return get_node_or_null("Characters") as Node2D


func is_configured() -> bool:
	return (
		get_grid() != null
		and get_terrain() != null
		and get_walls() != null
		and get_characters() != null
	)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if get_grid() == null:
		warnings.append("BattleMap requires an IsometricGrid child named Grid.")
	if get_terrain() == null:
		warnings.append("BattleMap requires a TacticalTerrain child named Terrain.")
	if get_walls() == null:
		warnings.append("BattleMap requires a Node2D child named Walls.")
	if get_characters() == null:
		warnings.append("BattleMap requires a Node2D child named Characters.")
	return warnings
