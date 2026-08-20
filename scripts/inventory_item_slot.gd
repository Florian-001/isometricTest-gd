class_name InventoryItemSlot
extends PanelContainer

const INVENTORY_SIZE := Vector2(48.0, 48.0)
const EQUIPMENT_SIZE := Vector2(132.0, 92.0)
const EMPTY_ICON := preload("res://icon.svg")

var screen: InventoryScreen
var source_kind := InventoryDragPayload.SourceKind.INVENTORY
var inventory_index := -1
var equipment_slot := -1
var character: TacticalCharacter
var item: ItemDefinition
var slot_label := ""

var _icon_margin: MarginContainer
var _icon: TextureRect
var _label: Label
var _dragging := false
var _drop_valid := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_icon_margin = MarginContainer.new()
	_icon_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon_margin)
	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_margin.add_child(_icon)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color("d5b85b"))
	_label.add_theme_color_override("font_shadow_color", Color("07101a"))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func configure_inventory(owner_screen: InventoryScreen, index: int, source_item: ItemDefinition) -> void:
	screen = owner_screen
	source_kind = InventoryDragPayload.SourceKind.INVENTORY
	inventory_index = index
	equipment_slot = -1
	character = null
	item = source_item
	slot_label = ""
	custom_minimum_size = INVENTORY_SIZE
	_icon_margin.add_theme_constant_override("margin_bottom", 0)
	_update_visual()


func configure_equipment(
	owner_screen: InventoryScreen,
	slot: ItemDefinition.EquipmentSlot,
	source_character: TacticalCharacter,
	source_item: ItemDefinition
) -> void:
	screen = owner_screen
	source_kind = InventoryDragPayload.SourceKind.EQUIPMENT
	inventory_index = -1
	equipment_slot = slot
	character = source_character
	item = source_item
	slot_label = ItemDefinition.EquipmentSlot.keys()[slot].capitalize()
	custom_minimum_size = EQUIPMENT_SIZE
	_icon_margin.add_theme_constant_override("margin_bottom", 18)
	_update_visual()


func _update_visual() -> void:
	_label.text = slot_label
	_icon.texture = item.icon if item != null and item.icon != null else (EMPTY_ICON if item != null else null)
	_icon.modulate = Color.WHITE if item == null or item.icon != null else Color("73869b")
	tooltip_text = item.display_name if item != null else ("Empty %s slot" % slot_label if not slot_label.is_empty() else "Empty inventory cell")
	_apply_style()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item == null or screen == null:
		return null
	var payload: InventoryDragPayload
	if source_kind == InventoryDragPayload.SourceKind.INVENTORY:
		payload = InventoryDragPayload.from_inventory(item, inventory_index)
	else:
		payload = InventoryDragPayload.from_equipment(item, equipment_slot, character)
	_dragging = true
	_apply_style()
	set_drag_preview(_make_drag_preview())
	return payload


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	_drop_valid = data is InventoryDragPayload and screen != null and screen.can_drop_on_slot(data, self)
	_apply_style()
	return _drop_valid


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_drop_valid = false
	if data is InventoryDragPayload and screen != null:
		screen.drop_on_slot(data, self)
	_apply_style()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_dragging = false
		_drop_valid = false
		_apply_style()


func _on_mouse_entered() -> void:
	if screen != null:
		screen.show_item_details(item)
	_apply_style(true)


func _on_mouse_exited() -> void:
	if screen != null:
		screen.clear_item_details(item)
	_apply_style()


func _make_drag_preview() -> Control:
	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(58.0, 58.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1a2b42d5")
	style.border_color = Color("e0c360")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	preview.add_theme_stylebox_override("panel", style)
	var icon := TextureRect.new()
	icon.texture = item.icon if item.icon != null else EMPTY_ICON
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.add_child(icon)
	return preview


func _apply_style(hovered := false) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("122032d5")
	style.border_color = Color("455b72")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	if source_kind == InventoryDragPayload.SourceKind.EQUIPMENT:
		style.bg_color = Color("16273be0")
		style.border_color = Color("8a7136")
	if item != null:
		style.bg_color = style.bg_color.lightened(0.06)
	if hovered:
		style.border_color = Color("d9bd61")
		style.set_border_width_all(2)
	if _dragging:
		style.border_color = Color("f1d77a")
		style.set_border_width_all(3)
	if _drop_valid:
		style.bg_color = Color("1d513bb5")
		style.border_color = Color("61d895")
		style.set_border_width_all(3)
	add_theme_stylebox_override("panel", style)
