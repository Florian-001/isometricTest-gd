class_name InventoryScreen
extends Control

const POSITIVE_CHANGE_COLOR := Color(0.34, 0.9, 0.5)
const NEGATIVE_CHANGE_COLOR := Color(1.0, 0.38, 0.36)
const MUTED_TEXT_COLOR := Color(0.58, 0.66, 0.74)

signal closed
signal equipment_updated(character: TacticalCharacter)

var _inventory: GeneralInventory
var _characters: Array[TacticalCharacter] = []
var _character: TacticalCharacter

@onready var character_picker: OptionButton = $Dim/Panel/Margin/VBox/CharacterRow/CharacterPicker
@onready var character_name: Label = $Dim/Panel/Margin/VBox/Columns/EquipmentPanel/Margin/VBox/CharacterName
@onready var general_entries: VBoxContainer = $Dim/Panel/Margin/VBox/Columns/GeneralPanel/Margin/VBox/Scroll/Entries
@onready var equipment_entries: VBoxContainer = $Dim/Panel/Margin/VBox/Columns/EquipmentPanel/Margin/VBox/EquipmentEntries
@onready var stats_entries: VBoxContainer = $Dim/Panel/Margin/VBox/Columns/DetailsPanel/Margin/VBox/StatsEntries
@onready var ability_entries: VBoxContainer = $Dim/Panel/Margin/VBox/Columns/DetailsPanel/Margin/VBox/AbilitiesScroll/AbilityEntries
@onready var close_button: Button = $Dim/Panel/Margin/VBox/Header/CloseButton


func _ready() -> void:
	close_button.pressed.connect(close_screen)
	character_picker.item_selected.connect(_on_character_selected)


func setup(inventory: GeneralInventory, characters: Array[TacticalCharacter]) -> void:
	_inventory = inventory
	_characters.assign(characters)
	if not _inventory.items_changed.is_connected(_refresh):
		_inventory.items_changed.connect(_refresh)
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
	hide()
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
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
	if not is_node_ready():
		return
	_clear_entries(general_entries)
	_clear_entries(equipment_entries)
	_build_general_inventory()
	_build_equipment_slots()
	_refresh_character_details()


func _set_character(character: TacticalCharacter) -> void:
	if _character == character:
		_connect_character_signals()
		return
	_disconnect_character_signals()
	_character = character
	_connect_character_signals()


func _connect_character_signals() -> void:
	if not is_instance_valid(_character):
		return
	if not _character.stats_changed.is_connected(_on_selected_character_stats_changed):
		_character.stats_changed.connect(_on_selected_character_stats_changed)
	if not _character.health_changed.is_connected(_on_selected_character_health_changed):
		_character.health_changed.connect(_on_selected_character_health_changed)
	if not _character.equipment_changed.is_connected(_on_selected_character_equipment_changed):
		_character.equipment_changed.connect(_on_selected_character_equipment_changed)


func _disconnect_character_signals() -> void:
	if not is_instance_valid(_character):
		return
	if _character.stats_changed.is_connected(_on_selected_character_stats_changed):
		_character.stats_changed.disconnect(_on_selected_character_stats_changed)
	if _character.health_changed.is_connected(_on_selected_character_health_changed):
		_character.health_changed.disconnect(_on_selected_character_health_changed)
	if _character.equipment_changed.is_connected(_on_selected_character_equipment_changed):
		_character.equipment_changed.disconnect(_on_selected_character_equipment_changed)


func _on_selected_character_stats_changed() -> void:
	_refresh_character_details()


func _on_selected_character_health_changed(_current: int, _maximum: int) -> void:
	_refresh_character_details()


func _on_selected_character_equipment_changed(
	_slot: ItemDefinition.EquipmentSlot,
	_item: ItemDefinition
) -> void:
	_refresh()


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
	_add_stat_row(
		"health",
		"Health",
		"%d / %d" % [_character.current_health, _character.get_max_health()]
	)
	_add_effective_stat_row("movement", "Movement", UnitStat.Type.MOVEMENT_RANGE)
	_add_effective_stat_row("strength", "Strength", UnitStat.Type.STRENGTH)
	_add_effective_stat_row("dexterity", "Dexterity", UnitStat.Type.DEXTERITY)
	_add_effective_stat_row("intelligence", "Intelligence", UnitStat.Type.INTELLIGENCE)
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
	if _inventory == null:
		_add_empty_label(general_entries, "Inventory unavailable")
		return
	var items := _inventory.get_items()
	if items.is_empty():
		_add_empty_label(general_entries, "No unused items")
		return
	for item in items:
		var button := _make_item_button(item, false)
		button.pressed.connect(_equip_item.bind(item))
		general_entries.add_child(button)


func _build_equipment_slots() -> void:
	if not is_instance_valid(_character):
		character_name.text = "No character selected"
		return
	character_name.text = _get_character_display_name(_character)
	for slot in [
		ItemDefinition.EquipmentSlot.WEAPON,
		ItemDefinition.EquipmentSlot.ARMOR,
		ItemDefinition.EquipmentSlot.ACCESSORY,
	]:
		var item := _character.get_equipped_item(slot)
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 64.0)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%s\n%s" % [
			_get_slot_name(slot),
			_get_item_name_with_damage(item) if item != null else "Empty",
		]
		button.tooltip_text = (
			_get_item_tooltip(item, "unequip")
			if item != null
			else "%s slot" % _get_slot_name(slot)
		)
		button.disabled = item == null
		if item != null:
			button.icon = item.icon
			button.expand_icon = true
			button.pressed.connect(_unequip_slot.bind(slot))
		equipment_entries.add_child(button)


func _equip_item(item: ItemDefinition) -> void:
	if _inventory == null or not is_instance_valid(_character):
		return
	if not _inventory.take_item(item):
		return
	var replaced := _character.equip_item(item)
	if replaced != null:
		_inventory.add_item(replaced)
	equipment_updated.emit(_character)
	_refresh()


func _unequip_slot(slot: ItemDefinition.EquipmentSlot) -> void:
	if _inventory == null or not is_instance_valid(_character):
		return
	var removed := _character.unequip_item(slot)
	if removed == null:
		return
	_inventory.add_item(removed)
	equipment_updated.emit(_character)
	_refresh()


func _make_item_button(item: ItemDefinition, equipped: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0.0, 56.0)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text = "%s\n%s" % [item.display_name, _get_item_slot_summary(item)]
	button.tooltip_text = _get_item_tooltip(item, "unequip" if equipped else "equip")
	button.icon = item.icon
	button.expand_icon = true
	return button


func _clear_entries(container: VBoxContainer) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _add_empty_label(container: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", MUTED_TEXT_COLOR)
	container.add_child(label)


func _get_character_display_name(character: TacticalCharacter) -> String:
	if character.definition != null and not character.definition.display_name.is_empty():
		return "%s (%s)" % [character.definition.display_name, character.name]
	return str(character.name)


func _get_slot_name(slot: ItemDefinition.EquipmentSlot) -> String:
	return ItemDefinition.EquipmentSlot.keys()[slot].capitalize()


func _get_item_name_with_damage(item: ItemDefinition) -> String:
	if item.slot == ItemDefinition.EquipmentSlot.WEAPON:
		return "%s · %d DMG" % [item.display_name, item.weapon_damage]
	return item.display_name


func _get_item_slot_summary(item: ItemDefinition) -> String:
	var summary := _get_slot_name(item.slot)
	if item.slot == ItemDefinition.EquipmentSlot.WEAPON:
		summary += " · %d DMG" % item.weapon_damage
	return summary


func _get_item_tooltip(item: ItemDefinition, action: String) -> String:
	var lines: Array[String] = [item.display_name]
	if item.slot == ItemDefinition.EquipmentSlot.WEAPON:
		lines.append("Weapon damage: %d" % item.weapon_damage)
	lines.append("Click to %s" % action)
	return "\n".join(lines)
