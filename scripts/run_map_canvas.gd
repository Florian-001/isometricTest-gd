class_name RunMapCanvas
extends Control

const CANVAS_SIZE := Vector2(1050.0, 1900.0)
const NODE_SIZE := Vector2(88.0, 88.0)
const MAP_PADDING := Vector2(110.0, 115.0)

const START_ICON := preload("res://assets/map_icons/start.png")
const NORMAL_COMBAT_ICON := preload("res://assets/map_icons/normal_combat.png")
const HARD_COMBAT_ICON := preload("res://assets/map_icons/hard_combat.png")
const REST_ICON := preload("res://assets/map_icons/rest.png")
const SHOP_ICON := preload("res://assets/map_icons/shop.png")
const CHEST_ICON := preload("res://assets/map_icons/chest.png")
const RANDOM_ICON := preload("res://assets/map_icons/random.png")
const BOSS_ICON := preload("res://assets/map_icons/boss.png")

var graph: RunMapGraph
var node_positions: Dictionary = {}
var node_controls: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = CANVAS_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_graph(value: RunMapGraph) -> void:
	graph = value
	for child in get_children():
		child.queue_free()
	node_positions.clear()
	node_controls.clear()
	if graph == null:
		queue_redraw()
		return
	for node in graph.nodes:
		var center := _get_node_center(node)
		node_positions[node.id] = center
		var control := _make_node_control(node)
		node_controls[node.id] = control
		add_child(control)
	queue_redraw()


func get_icon(type: int) -> Texture2D:
	match type:
		RunMapGraph.NodeType.START:
			return START_ICON
		RunMapGraph.NodeType.NORMAL_COMBAT:
			return NORMAL_COMBAT_ICON
		RunMapGraph.NodeType.HARD_COMBAT:
			return HARD_COMBAT_ICON
		RunMapGraph.NodeType.REST:
			return REST_ICON
		RunMapGraph.NodeType.SHOP:
			return SHOP_ICON
		RunMapGraph.NodeType.CHEST:
			return CHEST_ICON
		RunMapGraph.NodeType.RANDOM:
			return RANDOM_ICON
		RunMapGraph.NodeType.BOSS:
			return BOSS_ICON
	return null


func _draw() -> void:
	if graph == null:
		return
	for edge in graph.edges:
		if not node_positions.has(edge.x) or not node_positions.has(edge.y):
			continue
		var from_position: Vector2 = node_positions[edge.x]
		var to_position: Vector2 = node_positions[edge.y]
		draw_line(from_position, to_position, Color(0.01, 0.02, 0.035, 0.88), 9.0, true)
		draw_line(from_position, to_position, Color(0.62, 0.50, 0.27, 0.82), 4.0, true)
		var midpoint := from_position.lerp(to_position, 0.5)
		draw_circle(midpoint, 3.5, Color(0.87, 0.72, 0.38, 0.9))


func _get_node_center(node: RunMapGraph.NodeData) -> Vector2:
	var usable_width := CANVAS_SIZE.x - MAP_PADDING.x * 2.0
	var usable_height := CANVAS_SIZE.y - MAP_PADDING.y * 2.0
	var x := MAP_PADDING.x + usable_width * float(node.lane) / float(graph.lane_count - 1)
	var tier_progress := float(node.tier) / float(graph.tier_count - 1)
	var y := CANVAS_SIZE.y - MAP_PADDING.y - usable_height * tier_progress
	return Vector2(x, y)


func _make_node_control(node: RunMapGraph.NodeData) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Node_%d" % node.id
	panel.position = _get_node_center(node) - NODE_SIZE * 0.5
	panel.size = NODE_SIZE
	panel.custom_minimum_size = NODE_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_meta("node_id", node.id)
	panel.set_meta("tier", node.tier)
	panel.set_meta("lane", node.lane)
	panel.set_meta("node_type", node.type)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.06, 0.095, 0.97)
	style.border_color = RunMapGraph.get_type_color(node.type)
	style.set_border_width_all(4)
	style.set_corner_radius_all(44)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = 8
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 9)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_right", 9)
	margin.add_theme_constant_override("margin_bottom", 9)
	panel.add_child(margin)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = get_icon(node.type)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(icon)
	return panel
