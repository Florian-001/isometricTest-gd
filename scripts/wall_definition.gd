@tool
class_name WallDefinition
extends Resource

@export_category("Identity")
@export var display_name: String = "Wall"

@export_category("Appearance")
@export_range(8.0, 160.0, 1.0) var wall_height: float = 68.0
@export var top_color: Color = Color("8d7456")
@export var left_color: Color = Color("574330")
@export var right_color: Color = Color("6f563c")
@export var outline_color: Color = Color("241b16")
@export_range(0.5, 6.0, 0.5) var outline_width: float = 1.5
