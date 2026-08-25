@tool
class_name InventoryPanel
extends Control

@export_category("Slot Presentation")
@export_range(36.0, 64.0, 2.0) var slot_size: float = 48.0
@export var tooltip_offset: Vector2 = Vector2(18.0, 18.0)

var inventory: PartyInventory
var _slots: Array[InventorySlot] = []

var _grid: GridContainer
var _close_button: Button
var _tooltip_panel: PanelContainer
var _tooltip_label: Label


func _ready() -> void:
	_cache_scene_nodes()
	if not _close_button.pressed.is_connected(hide_inventory):
		_close_button.pressed.connect(hide_inventory)
	_tooltip_panel.visible = false
	if inventory != null:
		_rebuild_slots()


func setup(model: PartyInventory) -> void:
	_cache_scene_nodes()
	if inventory != null and inventory.inventory_changed.is_connected(_refresh_slots):
		inventory.inventory_changed.disconnect(_refresh_slots)
	inventory = model
	if inventory != null:
		inventory.inventory_changed.connect(_refresh_slots)
	if _grid != null:
		_rebuild_slots()


func show_inventory() -> void:
	if inventory == null:
		return
	visible = true
	_refresh_slots()
	if is_inside_tree():
		_close_button.grab_focus()


func hide_inventory() -> void:
	_hide_tooltip()
	visible = false
	if is_inside_tree() and is_instance_valid(_close_button):
		_close_button.release_focus()


func toggle_inventory() -> void:
	if visible:
		hide_inventory()
	else:
		show_inventory()


func is_open() -> bool:
	return visible


func get_rendered_slot_count() -> int:
	return _slots.size()


func get_slot_control(index: int) -> InventorySlot:
	if index < 0 or index >= _slots.size():
		return null
	return _slots[index]


func format_item_details(item: ItemDefinition) -> String:
	if item == null:
		return ""
	var lines: Array[String] = [
		item.display_name,
		"Type: %s" % ItemDefinition.EquipmentSlot.keys()[item.slot].capitalize(),
	]
	if not item.description.strip_edges().is_empty():
		lines.append("")
		lines.append(item.description.strip_edges())
	lines.append("")
	if item.modifiers.is_empty():
		lines.append("No stat modifiers")
	else:
		lines.append("Modifiers")
		for modifier in item.modifiers:
			if modifier != null:
				lines.append(_format_modifier(modifier))
	return "\n".join(lines)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_I:
		toggle_inventory()
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and visible:
		hide_inventory()
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


func _process(_delta: float) -> void:
	if _tooltip_panel.visible:
		_position_tooltip()


func _rebuild_slots() -> void:
	_cache_scene_nodes()
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.free()
	_slots.clear()
	_hide_tooltip()
	if inventory == null:
		return
	_grid.columns = inventory.columns
	for index in range(inventory.get_slot_count()):
		var slot := InventorySlot.new()
		slot.name = "Slot%03d" % index
		slot.initialize(inventory, index, Vector2(slot_size, slot_size))
		slot.item_hovered.connect(_show_tooltip)
		slot.item_unhovered.connect(_hide_tooltip)
		slot.item_drag_started.connect(_hide_tooltip)
		_grid.add_child(slot)
		_slots.append(slot)


func _refresh_slots() -> void:
	_hide_tooltip()
	for slot in _slots:
		if is_instance_valid(slot):
			slot.refresh()


func _show_tooltip(item: ItemDefinition) -> void:
	_tooltip_label.text = format_item_details(item)
	_tooltip_panel.visible = true
	_tooltip_panel.reset_size()
	call_deferred("_position_tooltip")


func _hide_tooltip() -> void:
	if is_instance_valid(_tooltip_panel):
		_tooltip_panel.visible = false


func _position_tooltip() -> void:
	if not is_instance_valid(_tooltip_panel) or not _tooltip_panel.visible:
		return
	var viewport_size := get_viewport_rect().size
	var desired := get_local_mouse_position() + tooltip_offset
	var tooltip_size := _tooltip_panel.size
	desired.x = clampf(desired.x, 8.0, maxf(8.0, viewport_size.x - tooltip_size.x - 8.0))
	desired.y = clampf(desired.y, 8.0, maxf(8.0, viewport_size.y - tooltip_size.y - 8.0))
	_tooltip_panel.position = desired


func _format_modifier(modifier: StatModifierDefinition) -> String:
	var stat_name: String = UnitStat.Type.keys()[modifier.stat].capitalize()
	match modifier.operation:
		StatModifierDefinition.Operation.FLAT:
			return "%s%s %s" % [
				"+" if modifier.value >= 0.0 else "",
				_format_number(modifier.value),
				stat_name,
			]
		StatModifierDefinition.Operation.PERCENT_ADD:
			return "%s%s%% %s" % [
				"+" if modifier.value >= 0.0 else "",
				_format_number(modifier.value * 100.0),
				stat_name,
			]
		StatModifierDefinition.Operation.PERCENT_MULTIPLY:
			return "%s ×%s" % [stat_name, _format_number(1.0 + modifier.value)]
		_:
			return stat_name


func _format_number(value: float) -> String:
	var formatted := "%.2f" % value
	while formatted.ends_with("0"):
		formatted = formatted.left(-1)
	if formatted.ends_with("."):
		formatted = formatted.left(-1)
	return formatted


func _cache_scene_nodes() -> void:
	if _grid == null:
		_grid = get_node_or_null("Window/Margin/VBox/InventoryScroll/Grid") as GridContainer
	if _close_button == null:
		_close_button = get_node_or_null("Window/Margin/VBox/Header/CloseButton") as Button
	if _tooltip_panel == null:
		_tooltip_panel = get_node_or_null("Tooltip") as PanelContainer
	if _tooltip_label == null:
		_tooltip_label = get_node_or_null("Tooltip/Margin/Details") as Label
