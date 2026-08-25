@tool
class_name InventorySlot
extends PanelContainer

signal item_hovered(item: ItemDefinition)
signal item_unhovered
signal item_drag_started

var inventory: PartyInventory
var slot_index: int = -1

var _icon: TextureRect
var _fallback: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_icon = TextureRect.new()
	_icon.name = "Icon"
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 5)
	add_child(_icon)

	_fallback = Label.new()
	_fallback.name = "MissingIcon"
	_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fallback.text = "?"
	_fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fallback.add_theme_font_size_override("font_size", 22)
	_fallback.add_theme_color_override("font_color", Color("aab8c7"))
	add_child(_fallback)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_apply_style(false)


func initialize(model: PartyInventory, index: int, minimum_size: Vector2) -> void:
	inventory = model
	slot_index = index
	custom_minimum_size = minimum_size
	refresh()


func refresh() -> void:
	var item := get_item()
	_icon.texture = item.icon if item != null else null
	_fallback.visible = item != null and item.icon == null
	mouse_default_cursor_shape = (
		Control.CURSOR_DRAG if item != null else Control.CURSOR_ARROW
	)
	_apply_style(item != null)


func get_item() -> ItemDefinition:
	return inventory.get_item(slot_index) if inventory != null else null


func get_displayed_texture() -> Texture2D:
	return _icon.texture


func _get_drag_data(_at_position: Vector2) -> Variant:
	var item := get_item()
	if item == null:
		return null
	item_drag_started.emit()
	set_drag_preview(_create_drag_preview(item))
	return {
		"inventory": inventory,
		"source_index": slot_index,
		"item": item,
	}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return (
		data is Dictionary
		and data.get("inventory") == inventory
		and data.get("source_index", -1) != slot_index
		and inventory != null
		and inventory.get_item(int(data.get("source_index", -1))) != null
	)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if _can_drop_data(_at_position, data):
		inventory.move_or_swap(int(data["source_index"]), slot_index)


func _create_drag_preview(item: ItemDefinition) -> Control:
	var preview := PanelContainer.new()
	preview.custom_minimum_size = custom_minimum_size
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _make_style(Color(0.08, 0.12, 0.18, 0.94), Color("ffd34e"), 2)
	preview.add_theme_stylebox_override("panel", style)
	if item.icon != null:
		var texture := TextureRect.new()
		texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture.texture = item.icon
		texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.add_child(texture)
	else:
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.text = "?"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 22)
		preview.add_child(label)
	return preview


func _on_mouse_entered() -> void:
	var item := get_item()
	if item != null:
		item_hovered.emit(item)


func _on_mouse_exited() -> void:
	item_unhovered.emit()


func _apply_style(occupied: bool) -> void:
	var background := Color(0.07, 0.10, 0.145, 0.96)
	var border := Color(0.25, 0.34, 0.44, 1.0)
	if occupied:
		background = Color(0.09, 0.14, 0.20, 0.98)
		border = Color(0.40, 0.55, 0.70, 1.0)
	add_theme_stylebox_override("panel", _make_style(background, border, 1))


func _make_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(4)
	style.content_margin_left = 4.0
	style.content_margin_top = 4.0
	style.content_margin_right = 4.0
	style.content_margin_bottom = 4.0
	return style
