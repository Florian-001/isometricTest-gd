@tool
class_name InventoryItemSlot
extends Button

@export var equipment_slot: int = -1
@export var empty_icon: Texture2D:
	set(value):
		empty_icon = value
		if is_node_ready() and Engine.is_editor_hint():
			artwork.texture = empty_icon
@export_range(0.0, 1.0) var empty_icon_opacity: float = 0.22

var screen: InventoryScreen
var slot_index: int = -1
var item: ItemDefinition
@onready var artwork: TextureRect = $Icon


func _ready() -> void:
	artwork.texture = empty_icon
	artwork.modulate.a = empty_icon_opacity


func bind_item(value: ItemDefinition, owner_screen: InventoryScreen, index: int = -1) -> void:
	item = value
	screen = owner_screen
	slot_index = index
	set_meta("item", item)
	artwork.texture = screen.get_item_icon(item) if item != null else empty_icon
	artwork.modulate.a = 1.0 if item != null else empty_icon_opacity
	accessibility_name = item.display_name if item != null else "Empty %s" % (ItemDefinition.EquipmentSlot.keys()[equipment_slot].capitalize() if equipment_slot >= 0 else "inventory cell")


func _gui_input(event: InputEvent) -> void:
	if screen == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
		screen.quick_transfer(self)
		accept_event()
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		screen.quick_transfer(self)
		accept_event()


func _get_drag_data(_position: Vector2) -> Variant:
	if screen == null:
		return null
	var data: Dictionary = screen.create_drag_payload(self)
	if data.is_empty():
		return null
	var preview := artwork.duplicate() as TextureRect
	preview.set_anchors_preset(Control.PRESET_TOP_LEFT)
	preview.size = Vector2(48, 48)
	preview.position = -preview.size * 0.5
	preview.modulate = Color.WHITE
	set_drag_preview(preview)
	return data


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return screen != null and screen.can_drop_on(self, data)


func _drop_data(_position: Vector2, data: Variant) -> void:
	if screen != null:
		screen.drop_on(self, data)


func _on_mouse_entered() -> void:
	if screen != null:
		screen.request_details(self)


func _on_mouse_exited() -> void:
	if screen != null:
		screen.dismiss_details(self)


func _on_focus_entered() -> void:
	if screen != null:
		screen.request_details(self)


func _on_focus_exited() -> void:
	if screen != null:
		screen.dismiss_details(self)


func _process(_delta: float) -> void:
	if screen == null or not is_visible_in_tree():
		return
	if get_viewport().gui_is_dragging() and is_hovered():
		var valid: bool = screen.can_drop_on(self, get_viewport().gui_get_drag_data())
		theme_type_variation = &"InventorySlotValid" if valid else &"InventorySlotInvalid"
	else:
		theme_type_variation = &"InventorySlot"
