class_name RunMapScreen
extends Control

signal close_requested
@export var party_entry_scene: PackedScene
@export var shop_offer_scene: PackedScene

@onready var back_button: Button = %BackButton
@onready var map_scroll: ScrollContainer = %MapScroll
@onready var map_canvas: RunMapCanvas = %MapCanvas
@onready var room_panel: PanelContainer = %RoomPanel
@onready var room_title: Label = %RoomTitle
@onready var room_body: Label = %RoomBody
@onready var room_action: Button = %RoomAction
@onready var offers: VBoxContainer = %Offers
@onready var party_entries: HFlowContainer = %PartyEntries
@onready var inventory_label: Label = %InventoryLabel
@onready var message: Label = %Message
var controller: RunController
var graph: RunMapGraph
var _last_scroll_target: int = -999

func _ready() -> void:
	back_button.pressed.connect(func() -> void: close_requested.emit())
	room_action.pressed.connect(_on_room_action)
	map_canvas.room_selected.connect(_on_room_selected)
	map_scroll.resized.connect(_reset_scroll)
	hide()

func setup(value: RunController) -> void:
	controller = value
	controller.state_changed.connect(refresh)
	refresh()

func open_map() -> void:
	show()
	_last_scroll_target = -999
	refresh()
	_scroll_to_choices.call_deferred()

func close_map() -> void:
	hide()

func refresh() -> void:
	if controller == null or controller.state == null:
		return
	var state := controller.state
	graph = state.graph
	map_canvas.set_state(state)
	%GoldLabel.text = "%d  GOLD" % state.gold
	%MapLength.text = "ACT I  /  %d OF 15 FLOORS" % mini(state.route.size(), 15)
	message.text = controller.error_message if not controller.error_message.is_empty() else ("Choose your next room. Only connected paths may be followed." if state.status == RunState.Status.ACTIVE else state.last_message)
	_clear(party_entries)
	for member in state.party:
		var entry := party_entry_scene.instantiate()
		entry.get_node("Name").text = member.display_name
		entry.get_node("Classes").text = member.get_class_summary()
		entry.get_node("Health").text = "FALLEN · permanently lost" if member.lost else "%d / %d HP" % [member.health, member.max_health]
		if member.lost:
			entry.modulate = Color(0.65, 0.42, 0.32)
		party_entries.add_child(entry)
	var names: Array[String] = []
	for path in state.inventory:
		if not path.is_empty():
			names.append((load(path) as ItemDefinition).display_name)
	inventory_label.text = "PACK  ·  " + (", ".join(names) if not names.is_empty() else "Empty")
	inventory_label.tooltip_text = inventory_label.text
	_refresh_room_panel()
	if visible:
		_scroll_to_choices.call_deferred()

func _refresh_room_panel() -> void:
	var state := controller.state
	_clear(offers)
	room_panel.visible = not state.pending.is_empty() or state.status != RunState.Status.ACTIVE
	%RoomShade.visible = room_panel.visible
	if not room_panel.visible:
		return
	if state.status != RunState.Status.ACTIVE:
		room_title.text = "THE SUMMIT IS YOURS" if state.status == RunState.Status.WON else "THE ROAD ENDS HERE"
		var completed := state.route.size() + (1 if state.status == RunState.Status.WON and not state.pending.is_empty() else 0)
		room_body.text = state.last_message + "\n\n%d rooms completed · %d gold remaining" % [completed, state.gold]
		room_action.text = "Return to menu"
	else:
		var type := int(state.pending.type)
		room_title.text = RunMapGraph.get_type_display_name(type).to_upper()
		if type == RunMapGraph.NodeType.SHOP:
			room_body.text = "A travelling merchant unfolds a worn canvas.\nChoose your supplies, or continue on your way."
			var stock: Array = state.pending.offers
			for index in range(stock.size()):
				var item := load(str(stock[index])) as ItemDefinition
				var button := shop_offer_scene.instantiate() as Button
				var bought: bool = state.pending.purchased.has(index)
				button.text = "%s   ·   %s" % [item.display_name, "Purchased" if bought else "%d gold" % int(state.pending.price)]
				button.disabled = bought or state.gold < int(state.pending.price)
				button.pressed.connect(_buy_offer.bind(index))
				offers.add_child(button)
			room_action.text = "Leave merchant"
		elif bool(state.pending.get("resolved", false)):
			room_body.text = state.last_message
			room_action.text = "Continue along the road"
		else:
			room_body.text = "Your choice is saved. This encounter will begin from its entry checkpoint."
			room_action.text = "Enter encounter"
	if not controller.error_message.is_empty():
		room_body.text += "\n\n" + controller.error_message
	room_action.grab_focus.call_deferred()

func _on_room_selected(id: int) -> void:
	controller.select_room(id)

func _buy_offer(index: int) -> void:
	controller.buy_offer(index)

func _on_room_action() -> void:
	if controller.state.status != RunState.Status.ACTIVE:
		if not controller.state.pending.is_empty():
			if not controller.complete_room():
				return
		close_requested.emit()
	elif bool(controller.state.pending.get("resolved", false)) or int(controller.state.pending.get("type", -1)) == RunMapGraph.NodeType.SHOP:
		controller.complete_room()
	else:
		controller.resume_room()

func _scroll_to_choices() -> void:
	# Containers update scrollbar limits after the resize notification.
	await get_tree().process_frame
	await get_tree().process_frame
	if not visible or graph == null:
		return
	var available := controller.state.available_rooms()
	var target_id := available[0] if not available.is_empty() else int(controller.state.pending.get("node_id", -1))
	if target_id == -1 and not controller.state.route.is_empty():
		target_id = controller.state.route.back()
	if target_id == _last_scroll_target or not map_canvas.node_controls.has(target_id):
		return
	_last_scroll_target = target_id
	var button: Button = map_canvas.node_controls[target_id]
	map_scroll.scroll_vertical = maxi(0, roundi(button.position.y - map_scroll.size.y * 0.65))
	if not available.is_empty():
		button.grab_focus()

func _reset_scroll() -> void:
	_last_scroll_target = -999
	_scroll_to_choices.call_deferred()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
