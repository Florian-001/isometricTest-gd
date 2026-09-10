@tool
class_name RunMapCanvas
extends Control

signal room_selected(id: int)
@export_category("Editor Preview")
@export var preview_settings: RunMapSettings
@export var preview_seed: int = 1337
@export_tool_button("Refresh map preview") var refresh_preview: Callable = _refresh_preview
@export_category("Scene Templates")
@export var room_scene: PackedScene
@export var floor_label_scene: PackedScene
@export var icons: Array[Texture2D] = []
@export_category("Layout")
@export var floor_spacing: float = 140.0
@export var horizontal_padding: float = 84.0
@export var vertical_padding: float = 130.0
## Compact spacing lets the five-combat route fit in the map viewport.
@export var linear_floor_spacing: float = 90.0
@export var linear_vertical_padding: float = 56.0
@export var room_size: float = 68.0
@export var boss_size: float = 108.0
@export var position_jitter: Vector2 = Vector2(15, 10)
@export_category("Ink")
@export var path_ink: Color = Color(0.34, 0.26, 0.16, 0.48)
@export var chosen_ink: Color = Color(0.57, 0.29, 0.07, 1)
@export var dot_spacing: float = 12.0
@export var dot_radius: float = 1.8

var graph: RunMapGraph
var node_positions: Dictionary = {}
var node_controls: Dictionary = {}
var _floor_controls: Dictionary = {}
var _jitter: Dictionary = {}
var _row_jitter: Dictionary = {}
var _state: RunState
@onready var rooms: Control = $Rooms
@onready var floors: Control = $Floors

func _ready() -> void:
	resized.connect(_layout_rooms)
	if Engine.is_editor_hint():
		_refresh_preview.call_deferred()

func _refresh_preview() -> void:
	if not Engine.is_editor_hint() or not is_node_ready() or room_scene == null or floor_label_scene == null:
		return
	var preview := RunMapGenerator.new().generate(preview_seed, preview_settings)
	if preview != null:
		set_graph(preview)

func set_state(value: RunState) -> void:
	_state = value
	if value == null:
		return
	if graph != value.graph:
		set_graph(value.graph)
	var available := value.available_rooms()
	for node in graph.nodes:
		var button: Button = node_controls[node.id]
		var visited := value.route.has(node.id)
		var pending := int(value.pending.get("node_id", -1)) == node.id
		button.disabled = not available.has(node.id)
		button.focus_mode = Control.FOCUS_NONE if button.disabled else Control.FOCUS_ALL
		button.modulate = Color(1, 1, 1, 1 if visited or pending or available.has(node.id) else 0.48)
		button.get_node("Ring").visible = visited or pending
		button.tooltip_text = "%s · Floor %d%s" % [RunMapGraph.get_type_display_name(node.type), node.tier + 1, " · Completed" if visited else (" · Choose this room" if available.has(node.id) else "")]
	queue_redraw()

func set_graph(value: RunMapGraph) -> void:
	graph = value
	for parent in [rooms, floors]:
		for child in parent.get_children():
			parent.remove_child(child)
			child.queue_free()
	node_controls.clear()
	node_positions.clear()
	_floor_controls.clear()
	_jitter.clear()
	_row_jitter.clear()
	if graph == null:
		return
	var linear := graph.layout == RunMapSettings.Layout.LINEAR_COMBAT
	custom_minimum_size.y = (linear_vertical_padding if linear else vertical_padding) * 2.0 + (linear_floor_spacing if linear else floor_spacing) * (graph.tier_count - 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = graph.seed_value ^ 398279
	for tier in range(graph.tier_count):
		# A shared row height preserves planarity even after visual jitter.
		_row_jitter[tier] = rng.randf_range(-position_jitter.y, position_jitter.y)
		var label := floor_label_scene.instantiate() as Label
		label.text = "BOSS" if graph.get_nodes_in_tier(tier)[0].type == RunMapGraph.NodeType.BOSS else "%02d" % (tier + 1)
		floors.add_child(label)
		_floor_controls[tier] = label
	for node in graph.nodes:
		_jitter[node.id] = rng.randf_range(-position_jitter.x, position_jitter.x)
		var button := room_scene.instantiate() as Button
		button.name = "Room_%d" % node.id
		button.set_meta("node_id", node.id)
		button.set_meta("node_type", node.type)
		var diameter := boss_size if node.type == RunMapGraph.NodeType.BOSS else room_size
		button.custom_minimum_size = Vector2.ONE * diameter
		button.size = Vector2.ONE * diameter
		button.get_node("Margin/Icon").texture = get_icon(node.type)
		button.pressed.connect(func() -> void: room_selected.emit(node.id))
		rooms.add_child(button)
		node_controls[node.id] = button
	_layout_rooms()

func get_icon(type: int) -> Texture2D:
	return icons[type] if type >= 0 and type < icons.size() else null

func _layout_rooms() -> void:
	if graph == null:
		return
	var width := maxf(size.x, custom_minimum_size.x)
	var lane_spacing := (width - horizontal_padding * 2.0) / float(maxi(1, graph.lane_count - 1))
	for node in graph.nodes:
		var x := horizontal_padding + lane_spacing * node.lane
		x += clampf(float(_jitter[node.id]), -lane_spacing * 0.15, lane_spacing * 0.15)
		if node.type == RunMapGraph.NodeType.BOSS or graph.lane_count == 1:
			x = width * 0.5
		var y := _floor_y(node.tier)
		var center := Vector2(x, y)
		node_positions[node.id] = center
		var button: Button = node_controls[node.id]
		button.position = center - button.size * 0.5
	for tier: int in _floor_controls:
		_floor_controls[tier].position = Vector2(16, _floor_y(tier) - 12)
	queue_redraw()

func _floor_y(tier: int) -> float:
	if graph.layout == RunMapSettings.Layout.LINEAR_COMBAT:
		return linear_vertical_padding + (graph.tier_count - 1 - tier) * linear_floor_spacing + float(_row_jitter.get(tier, 0.0))
	return vertical_padding + (graph.tier_count - 1 - tier) * floor_spacing + float(_row_jitter.get(tier, 0.0))

func _draw() -> void:
	if graph == null:
		return
	for edge in graph.edges:
		if not node_positions.has(edge.x) or not node_positions.has(edge.y):
			continue
		var a: Vector2 = node_positions[edge.x]
		var b: Vector2 = node_positions[edge.y]
		var chosen := false
		if _state != null:
			var route := _state.route.duplicate()
			if not _state.pending.is_empty():
				route.append(int(_state.pending.node_id))
			var index := route.find(edge.x)
			chosen = index >= 0 and index + 1 < route.size() and route[index + 1] == edge.y
		var direction := a.direction_to(b)
		a += direction * room_size * 0.48
		b -= direction * (boss_size if graph.get_node_by_id(edge.y).type == RunMapGraph.NodeType.BOSS else room_size) * 0.48
		var distance := a.distance_to(b)
		var count := maxi(1, floori(distance / maxf(4.0, dot_spacing)))
		for index in range(count + 1):
			draw_circle(a.lerp(b, float(index) / count), dot_radius + (0.6 if chosen else 0.0), chosen_ink if chosen else path_ink, true, -1.0, true)
