@tool
class_name TacticalTile
extends Node

@export var definition: TileDefinition:
	set(value):
		definition = value
		_notify_terrain_changed()
		update_configuration_warnings()

@export var grid_cell: Vector2i = Vector2i.ZERO:
	set(value):
		grid_cell = value
		_notify_terrain_changed()
		update_configuration_warnings()


func _ready() -> void:
	_notify_terrain_changed()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if definition == null:
		warnings.append("Assign a Tile Definition.")
	var terrain := get_parent() as TacticalTerrain
	if terrain == null:
		warnings.append("TacticalTile must be a child of a TacticalTerrain node.")
		return warnings
	var root := terrain.get_parent()
	var board := root.get_node_or_null("Grid") as IsometricGrid if root != null else null
	if board != null and not board.is_in_bounds(grid_cell):
		warnings.append("Tile cell %s is outside the grid bounds." % grid_cell)
	var walls := root.get_node_or_null("Walls") if root != null else null
	if walls != null:
		for child in walls.get_children():
			if child is TacticalWall and child.grid_cell == grid_cell:
				warnings.append("Tile cell %s overlaps a wall." % grid_cell)
				break
	for sibling in terrain.get_children():
		if sibling != self and sibling is TacticalTile and sibling.grid_cell == grid_cell:
			warnings.append("Another tile already occupies cell %s." % grid_cell)
			break
	return warnings


func _notify_terrain_changed() -> void:
	if not is_inside_tree():
		return
	var terrain := get_parent() as TacticalTerrain
	if terrain != null:
		terrain.call_deferred("refresh")
