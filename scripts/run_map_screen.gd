class_name RunMapScreen
extends Control

signal close_requested

@export var map_seed := RunMapGenerator.DEFAULT_SEED
@export_range(15, 24, 1) var room_floor_count := RunMapGenerator.DEFAULT_ROOM_FLOOR_COUNT

@onready var back_button: Button = $Margin/VBox/Header/BackButton
@onready var legend: HFlowContainer = $Margin/VBox/LegendPanel/LegendMargin/Legend
@onready var map_length: Label = $Margin/VBox/Header/MapLength
@onready var map_scroll: ScrollContainer = $Margin/VBox/MapPanel/MapScroll
@onready var map_canvas: RunMapCanvas = $Margin/VBox/MapPanel/MapScroll/MapCenter/MapCanvas

var graph: RunMapGraph


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	_build_legend()
	_rebuild_map()
	hide()


func open_map() -> void:
	show()
	_scroll_to_start.call_deferred()
	back_button.grab_focus.call_deferred()


func close_map() -> void:
	hide()


func _rebuild_map() -> void:
	graph = RunMapGenerator.new().generate(map_seed, room_floor_count)
	map_length.text = "%d floors" % room_floor_count
	map_canvas.set_graph(graph)


func _build_legend() -> void:
	for child in legend.get_children():
		child.queue_free()
	for type in [
		RunMapGraph.NodeType.START,
		RunMapGraph.NodeType.NORMAL_COMBAT,
		RunMapGraph.NodeType.HARD_COMBAT,
		RunMapGraph.NodeType.REST,
		RunMapGraph.NodeType.SHOP,
		RunMapGraph.NodeType.CHEST,
		RunMapGraph.NodeType.RANDOM,
		RunMapGraph.NodeType.BOSS,
	]:
		legend.add_child(_make_legend_entry(type))


func _make_legend_entry(type: int) -> HBoxContainer:
	var entry := HBoxContainer.new()
	entry.custom_minimum_size = Vector2(116.0, 34.0)
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_theme_constant_override("separation", 6)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(30.0, 30.0)
	icon.texture = map_canvas.get_icon(type)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(icon)

	var label := Label.new()
	label.text = RunMapGraph.get_type_display_name(type)
	label.add_theme_color_override("font_color", RunMapGraph.get_type_color(type).lightened(0.22))
	label.add_theme_font_size_override("font_size", 13)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(label)
	return entry


func _scroll_to_start() -> void:
	map_scroll.scroll_vertical = maxi(
		0,
		roundi(map_canvas.custom_minimum_size.y - map_scroll.size.y)
	)


func _on_back_pressed() -> void:
	close_requested.emit()
