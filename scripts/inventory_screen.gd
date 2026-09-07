class_name InventoryScreen
extends Control

const POSITIVE_CHANGE_COLOR := Color(0.34, 0.9, 0.5)
const NEGATIVE_CHANGE_COLOR := Color(1.0, 0.38, 0.36)
const MUTED_TEXT_COLOR := Color(0.58, 0.66, 0.74)

signal closed
signal equipment_updated(character: TacticalCharacter)

@export_category("Grid Presentation")
@export var item_slot_scene: PackedScene
@export var weapon_fallback_icon: Texture2D
@export var ranged_fallback_icon: Texture2D
@export var armor_fallback_icon: Texture2D
@export var accessory_fallback_icon: Texture2D
@export_range(1, 20) var minimum_rows: int = 4
@export_range(0.0, 1.0, 0.05) var hover_delay: float = 0.2

var _inventory: GeneralInventory
var _characters: Array[TacticalCharacter] = []
var _character: TacticalCharacter
var _context_revision: int = 0
var _refresh_pending: bool = false
var _detail_cell: InventoryItemSlot
var _drag_scroll_direction: float = 0.0
var _applying_transfer: bool = false

@onready var character_picker: OptionButton = $Dim/Panel/Margin/VBox/CharacterRow/CharacterPicker
@onready var character_name: Label = $Dim/Panel/Margin/VBox/Columns/EquipmentPanel/Margin/VBox/CharacterName
@onready var general_entries: GridContainer = $Dim/Panel/Margin/VBox/Columns/GeneralPanel/Margin/VBox/Scroll/Entries
@onready var equipment_entries: GridContainer = $Dim/Panel/Margin/VBox/Columns/EquipmentPanel/Margin/VBox/EquipmentEntries
@onready var inventory_scroll: ScrollContainer = $Dim/Panel/Margin/VBox/Columns/GeneralPanel/Margin/VBox/Scroll
@onready var item_details: InventoryItemDetails = $ItemDetails
@onready var hover_timer: Timer = $HoverTimer
@onready var stats_entries: VBoxContainer = $Dim/Panel/Margin/VBox/Columns/DetailsPanel/Margin/VBox/StatsEntries
@onready var ability_entries: VBoxContainer = $Dim/Panel/Margin/VBox/Columns/DetailsPanel/Margin/VBox/AbilitiesScroll/AbilityEntries
@onready var close_button: Button = $Dim/Panel/Margin/VBox/Header/CloseButton


func _ready() -> void:
	close_button.pressed.connect(close_screen)
	character_picker.item_selected.connect(_on_character_selected)
	inventory_scroll.get_v_scroll_bar().value_changed.connect(_on_inventory_scrolled)


func setup(inventory: GeneralInventory, characters: Array[TacticalCharacter]) -> void:
	_invalidate_interaction()
	if is_instance_valid(_inventory) and _inventory.items_changed.is_connected(_queue_refresh):
		_inventory.items_changed.disconnect(_queue_refresh)
	_inventory = inventory
	_characters.assign(characters)
	if _inventory != null:
		_inventory.items_changed.connect(_queue_refresh)
	var next_character := _character
	if not is_instance_valid(next_character) or not _characters.has(next_character):
		next_character = _characters[0] if not _characters.is_empty() else null
	_set_character(next_character)
	_rebuild_character_picker()
	_refresh()


func open_for(preferred_character: TacticalCharacter = null) -> void:
	if is_instance_valid(preferred_character) and _characters.has(preferred_character):
		_set_character(preferred_character)
	elif not is_instance_valid(_character) and not _characters.is_empty():
		_set_character(_characters[0])
	_sync_character_picker()
	_refresh()
	show()
	close_button.grab_focus()


func close_screen() -> void:
	if not visible:
		return
	_invalidate_interaction()
	hide()
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		if get_viewport().gui_is_dragging():
			_invalidate_interaction()
		else:
			close_screen()
		get_viewport().set_input_as_handled()


func _rebuild_character_picker() -> void:
	character_picker.clear()
	for character in _characters:
		character_picker.add_item(_get_character_display_name(character))
	_sync_character_picker()


func _sync_character_picker() -> void:
	var index := _characters.find(_character)
	if index >= 0:
		character_picker.select(index)


func _on_character_selected(index: int) -> void:
	if index < 0 or index >= _characters.size():
		return
	_set_character(_characters[index])
	_refresh()


func _refresh() -> void:
	_refresh_pending = false
	if not is_node_ready():
		return
	_hide_details()
	_build_general_inventory()
	_build_equipment_slots()
	_refresh_character_details()


func _set_character(character: TacticalCharacter) -> void:
	if _character == character:
		_connect_character_signals()
		return
	_invalidate_interaction()
	_disconnect_character_signals()
	_character = character
	_connect_character_signals()


func _connect_character_signals() -> void:
	if not is_instance_valid(_character):
		return
	if not _character.class_progression_changed.is_connected(_on_selected_character_stats_changed):
		_character.class_progression_changed.connect(_on_selected_character_stats_changed)
	if not _character.stats_changed.is_connected(_on_selected_character_stats_changed):
		_character.stats_changed.connect(_on_selected_character_stats_changed)
	if not _character.health_changed.is_connected(_on_selected_character_health_changed):
		_character.health_changed.connect(_on_selected_character_health_changed)
	if not _character.equipment_changed.is_connected(_on_selected_character_equipment_changed):
		_character.equipment_changed.connect(_on_selected_character_equipment_changed)


func _disconnect_character_signals() -> void:
	if not is_instance_valid(_character):
		return
	if _character.class_progression_changed.is_connected(_on_selected_character_stats_changed):
		_character.class_progression_changed.disconnect(_on_selected_character_stats_changed)
	if _character.stats_changed.is_connected(_on_selected_character_stats_changed):
		_character.stats_changed.disconnect(_on_selected_character_stats_changed)
	if _character.health_changed.is_connected(_on_selected_character_health_changed):
		_character.health_changed.disconnect(_on_selected_character_health_changed)
	if _character.equipment_changed.is_connected(_on_selected_character_equipment_changed):
		_character.equipment_changed.disconnect(_on_selected_character_equipment_changed)


func _on_selected_character_stats_changed() -> void:
	_refresh_character_details()


func _on_selected_character_health_changed(_current: int, _maximum: int) -> void:
	if _current <= 0:
		_invalidate_interaction()
	_refresh_character_details()


func _on_selected_character_equipment_changed(
	_slot: ItemDefinition.EquipmentSlot,
	_item: ItemDefinition
) -> void:
	_invalidate_interaction()
	_queue_refresh()


func _refresh_character_details() -> void:
	if not is_node_ready():
		return
	_clear_entries(stats_entries)
	_clear_entries(ability_entries)
	if not is_instance_valid(_character):
		_add_empty_label(stats_entries, "No character selected")
		_add_empty_label(ability_entries, "No abilities available")
		return
	_build_stat_entries()
	_build_ability_entries()


func _build_stat_entries() -> void:
	if _character.is_friendly():
		var summary := Label.new()
		summary.name = "ClassProgression"
		summary.text = CharacterClassProgression.get_summary(_character.get_class_levels())
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stats_entries.add_child(summary)
	_add_stat_row(
		"health",
		"Health",
		"%d / %d" % [_character.current_health, _character.get_max_health()]
	)
	_add_effective_stat_row("movement", "Movement", UnitStat.Type.MOVEMENT_RANGE)
	_add_effective_stat_row("strength", "Strength", UnitStat.Type.STRENGTH)
	_add_effective_stat_row("dexterity", "Dexterity", UnitStat.Type.DEXTERITY)
	_add_effective_stat_row("intelligence", "Intelligence", UnitStat.Type.INTELLIGENCE)
	_add_effective_stat_row("constitution", "Constitution", UnitStat.Type.CONSTITUTION)
	_add_effective_stat_row("speed", "Speed", UnitStat.Type.SPEED)
	_add_stat_row(
		"weapon_damage",
		"Weapon Damage",
		str(_character.get_weapon_damage()),
		float(_character.get_weapon_damage())
	)


func _add_effective_stat_row(key: String, label_text: String, stat: UnitStat.Type) -> void:
	var total := _character.get_effective_stat(stat)
	var without_equipment := _character.get_effective_stat_without_equipment(stat)
	_add_stat_row(key, label_text, _format_stat_value(total), total - without_equipment)


func _add_stat_row(
	key: String,
	label_text: String,
	value_text: String,
	equipment_change: float = 0.0
) -> void:
	var row := HBoxContainer.new()
	row.name = key.to_pascal_case()
	row.set_meta("stat_key", key)
	row.set_meta("value_text", value_text)
	row.custom_minimum_size = Vector2(0.0, 22.0)

	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = label_text
	name_label.custom_minimum_size.x = 126.0
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var value_label := Label.new()
	value_label.name = "Value"
	value_label.text = value_text
	value_label.custom_minimum_size.x = 72.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	var change_label := Label.new()
	change_label.name = "Change"
	change_label.custom_minimum_size.x = 58.0
	change_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if not is_zero_approx(equipment_change):
		change_label.text = "(%s%s)" % ["+" if equipment_change > 0.0 else "", _format_stat_value(equipment_change)]
		change_label.add_theme_color_override(
			"font_color",
			POSITIVE_CHANGE_COLOR if equipment_change > 0.0 else NEGATIVE_CHANGE_COLOR
		)
	row.set_meta("change_text", change_label.text)
	row.add_child(change_label)
	stats_entries.add_child(row)


func _build_ability_entries() -> void:
	var abilities := _character.get_abilities()
	if abilities.is_empty():
		_add_empty_label(ability_entries, "No abilities configured")
		return
	for ability in abilities:
		if ability != null:
			ability_entries.add_child(_make_ability_entry(ability))


func _make_ability_entry(ability: AbilityDefinition) -> PanelContainer:
	var entry := PanelContainer.new()
	entry.custom_minimum_size = Vector2(0.0, 54.0)
	entry.mouse_filter = Control.MOUSE_FILTER_STOP
	entry.tooltip_text = "%s\n%s" % [ability.display_name, ability.get_description(_character)]
	entry.set_meta("ability", ability)
	var summary := _get_ability_summary(ability)
	entry.set_meta("summary_text", summary)

	var style := StyleBoxFlat.new()
	style.bg_color = ability.placeholder_color.darkened(0.78)
	style.border_color = ability.placeholder_color.darkened(0.18)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	entry.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 7)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	entry.add_child(margin)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 9)
	margin.add_child(row)

	var visual: Control
	if ability.image != null:
		var icon := TextureRect.new()
		icon.texture = ability.image
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		visual = icon
	else:
		var swatch := ColorRect.new()
		swatch.color = ability.placeholder_color
		visual = swatch
	visual.custom_minimum_size = Vector2(38.0, 38.0)
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(visual)

	var labels := VBoxContainer.new()
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.add_theme_constant_override("separation", 0)
	row.add_child(labels)
	var name_label := Label.new()
	name_label.text = ability.display_name
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.add_child(name_label)
	var summary_label := Label.new()
	summary_label.name = "Summary"
	summary_label.text = summary
	summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	labels.add_child(summary_label)
	return entry


func _get_ability_summary(ability: AbilityDefinition) -> String:
	var unavailable_reason := ability.get_unavailable_reason(_character)
	if not unavailable_reason.is_empty():
		return unavailable_reason
	if ability.has_damage():
		return "%d DMG" % ability.calculate_damage(_character)
	if ability.effect == AbilityDefinition.PrimaryEffect.HEAL:
		return "%d HEAL" % ability.calculate_primary_effect_amount(_character)
	var applied_status := ability.status_effect
	if applied_status == null:
		for additional_effect in ability.effects:
			if additional_effect is ApplyStatusEffectDefinition:
				applied_status = (additional_effect as ApplyStatusEffectDefinition).status_effect
				if applied_status != null:
					break
	if applied_status != null:
		return applied_status.display_name
	return "Utility"


func _format_stat_value(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return "%.1f" % value


func _build_general_inventory() -> void:
	var count := 0 if _inventory == null else _inventory.get_slots().size()
	var columns := general_entries.columns
	var cells := maxi(minimum_rows * columns, ceili(float(count + 1) / columns) * columns)
	while general_entries.get_child_count() < cells:
		general_entries.add_child(item_slot_scene.instantiate())
	# Keep existing cells alive during refreshes, including drag completion.
	for index in general_entries.get_child_count():
		var cell := general_entries.get_child(index) as InventoryItemSlot
		cell.visible = index < cells
		cell.bind_item(_inventory.get_item_at(index) if _inventory != null else null, self, index)
	var item_count := 0 if _inventory == null else _inventory.get_items().size()
	$Dim/Panel/Margin/VBox/Columns/GeneralPanel/Margin/VBox/Subtitle.text = "%d %s · shared pack" % [item_count, "item" if item_count == 1 else "items"]


func _build_equipment_slots() -> void:
	character_name.text = _get_character_display_name(_character) if is_instance_valid(_character) else "No character selected"
	for column in equipment_entries.get_children():
		var cell := column.get_node("Slot") as InventoryItemSlot
		cell.bind_item(_character.get_equipped_item(cell.equipment_slot) if is_instance_valid(_character) else null, self)


func get_item_icon(item: ItemDefinition) -> Texture2D:
	if item.icon != null:
		return item.icon
	match item.slot:
		ItemDefinition.EquipmentSlot.ARMOR:
			return armor_fallback_icon
		ItemDefinition.EquipmentSlot.ACCESSORY:
			return accessory_fallback_icon
		_:
			return ranged_fallback_icon if item.weapon_type == ItemDefinition.WeaponType.RANGED else weapon_fallback_icon


func _queue_refresh() -> void:
	_hide_details()
	if not _refresh_pending:
		_refresh_pending = true
		_refresh.call_deferred()


func _invalidate_interaction() -> void:
	_context_revision += 1
	_hide_details()
	if not _applying_transfer and is_inside_tree() and get_viewport().gui_is_dragging():
		get_viewport().gui_cancel_drag()


func create_drag_payload(cell: InventoryItemSlot) -> Dictionary:
	if not visible or _inventory == null or cell.item == null:
		return {}
	_hide_details()
	return {
		"screen": self, "context": _context_revision, "inventory_revision": _inventory.revision,
		"character": _character, "slot": cell.slot_index, "equipment_slot": cell.equipment_slot,
		"item": cell.item,
	}


func _valid_payload(data: Variant) -> bool:
	if not visible or _inventory == null or not data is Dictionary:
		return false
	if data.get("screen") != self or data.get("context", -1) != _context_revision or data.get("inventory_revision", -1) != _inventory.revision:
		return false
	if data.get("character") != _character or not data.get("item") is ItemDefinition:
		return false
	if not data.get("slot") is int or not data.get("equipment_slot") is int:
		return false
	var slot: int = data.equipment_slot
	if slot >= 0:
		return is_instance_valid(_character) and _character.current_health > 0 and ItemDefinition.EquipmentSlot.values().has(slot) and _character.get_equipped_item(slot) == data.item
	return _inventory.get_item_at(data.slot) == data.item


func can_drop_on(cell: InventoryItemSlot, data: Variant) -> bool:
	if cell.screen != self or not cell.visible or not _valid_payload(data):
		return false
	if cell.equipment_slot >= 0:
		return data.equipment_slot < 0 and _inventory.can_equip_from_slot(data.slot, _character, cell.equipment_slot)
	if data.equipment_slot >= 0:
		return _inventory.can_unequip_to_slot(_character, data.equipment_slot, cell.slot_index)
	return _inventory.can_move_or_swap(data.slot, cell.slot_index)


func drop_on(cell: InventoryItemSlot, data: Variant) -> void:
	if not can_drop_on(cell, data):
		return
	var equipment_change: bool = cell.equipment_slot >= 0 or data.equipment_slot >= 0
	_applying_transfer = true
	if cell.equipment_slot >= 0:
		_inventory.equip_from_slot(data.slot, _character, cell.equipment_slot)
	elif data.equipment_slot >= 0:
		_inventory.unequip_to_slot(_character, data.equipment_slot, cell.slot_index)
	else:
		_inventory.move_or_swap(data.slot, cell.slot_index)
	_applying_transfer = false
	if equipment_change:
		equipment_updated.emit(_character)


func quick_transfer(cell: InventoryItemSlot) -> void:
	if not visible or _inventory == null or cell.item == null or get_viewport().gui_is_dragging():
		return
	var changed := false
	if cell.equipment_slot >= 0:
		changed = _inventory.unequip_to_slot(_character, cell.equipment_slot, _inventory.first_empty_slot())
	elif _inventory.get_item_at(cell.slot_index) == cell.item:
		changed = _inventory.equip_from_slot(cell.slot_index, _character, cell.item.slot)
	if changed:
		equipment_updated.emit(_character)


func request_details(cell: InventoryItemSlot) -> void:
	_hide_details()
	if not visible or cell.item == null or get_viewport().gui_is_dragging():
		return
	_detail_cell = cell
	hover_timer.start(maxf(hover_delay, 0.001))


func dismiss_details(cell: InventoryItemSlot) -> void:
	if _detail_cell == cell:
		_hide_details()


func _hide_details() -> void:
	_detail_cell = null
	if is_node_ready():
		hover_timer.stop()
		item_details.hide()


func _on_hover_timeout() -> void:
	if not visible or not is_instance_valid(_detail_cell) or _detail_cell.item == null or get_viewport().gui_is_dragging():
		return
	item_details.show_item(_detail_cell.item, _detail_cell.equipment_slot >= 0)
	item_details.place_next_to(_detail_cell)


func _on_inventory_scrolled(_value: float) -> void:
	_hide_details()


func _process(delta: float) -> void:
	if not visible:
		return
	if item_details.visible and is_instance_valid(_detail_cell):
		item_details.place_next_to(_detail_cell)
	if get_viewport().gui_is_dragging():
		_hide_details()
		var rect := inventory_scroll.get_global_rect()
		var point := get_global_mouse_position()
		if rect.has_point(point):
			_drag_scroll_direction = -1.0 if point.y < rect.position.y + 28.0 else (1.0 if point.y > rect.end.y - 28.0 else 0.0)
			inventory_scroll.scroll_vertical += roundi(_drag_scroll_direction * 480.0 * delta)


func _clear_entries(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _add_empty_label(container: Container, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", MUTED_TEXT_COLOR)
	container.add_child(label)


func _get_character_display_name(character: TacticalCharacter) -> String:
	if character.definition != null and not character.definition.display_name.is_empty():
		return "%s (%s)" % [character.definition.display_name, character.name]
	return str(character.name)
