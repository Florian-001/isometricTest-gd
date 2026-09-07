class_name DevModePanel
extends Control

signal play_requested
signal save_requested(replace_path: String)
signal load_payload_requested(payload: Dictionary)
signal selected_unit_deleted
signal selected_unit_heal_requested
signal unit_setup_changed
signal unit_palette_drag_started(unit_scene: PackedScene)
signal terrain_brush_changed(kind: int, resource: Resource)
signal terrain_undo_requested
signal terrain_redo_requested
signal terrain_reset_requested
signal active_tab_changed(tab_index: int)
signal ai_history_restore_requested(history_index: int)

const NORMAL_TEXT := Color("d6e4f0")
const SUCCESS_TEXT := Color("65d98b")
const ERROR_TEXT := Color("ff7373")
const UNIT_TAB := 0
const TERRAIN_TAB := 1
const AI_LOG_TAB := 3
const BRUSH_TILE := 0
const BRUSH_WALL := 1
const BRUSH_ERASE := 2
const AI_LOG_SEPARATOR := "\n\n────────────────────────────────────────\n\n"

@onready var drawer: PanelContainer = $Drawer
@onready var play_button: Button = $Drawer/Margin/Main/TopBar/PlayButton
@onready var save_button: Button = $Drawer/Margin/Main/TopBar/SaveButton
@onready var status_label: Label = $Drawer/Margin/Main/Status
@onready var palette_entries: HBoxContainer = $Drawer/Margin/Main/Tabs/Unit/UnitContent/PaletteScroll/PaletteEntries
@onready var tabs: TabContainer = $Drawer/Margin/Main/Tabs
@onready var no_selection: Label = $Drawer/Margin/Main/Tabs/Unit/UnitContent/NoSelection
@onready var unit_editor: VBoxContainer = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor
@onready var unit_name: Label = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/UnitHeader/UnitName
@onready var heal_unit_button: Button = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/UnitHeader/HealUnitButton
@onready var derived_stats: Label = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/DerivedStats
@onready var class_editor: VBoxContainer = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/Classes
@onready var class_summary: Label = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/Classes/Summary
@onready var class_entries: VBoxContainer = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/Classes/Entries
@onready var class_picker: OptionButton = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/Classes/AddClass/Picker
@onready var add_class_button: Button = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/Classes/AddClass/AddButton
@onready var ability_bypass: CheckBox = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/AbilityBypass
@onready var strength_spin: SpinBox = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/Stats/StrengthSpin
@onready var dexterity_spin: SpinBox = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/Stats/DexteritySpin
@onready var intelligence_spin: SpinBox = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/Stats/IntelligenceSpin
@onready var constitution_spin: SpinBox = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/Stats/ConstitutionSpin
@onready var speed_spin: SpinBox = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/Stats/SpeedSpin
@onready var movement_spin: SpinBox = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/Stats/MovementSpin
@onready var strength_reset: Button = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/Stats/StrengthReset
@onready var dexterity_reset: Button = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/Stats/DexterityReset
@onready var intelligence_reset: Button = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/Stats/IntelligenceReset
@onready var constitution_reset: Button = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/Stats/ConstitutionReset
@onready var speed_reset: Button = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/Stats/SpeedReset
@onready var movement_reset: Button = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/Stats/MovementReset
@onready var abilities_reset: Button = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/AbilitiesHeader/AbilitiesReset
@onready var ability_entries: VBoxContainer = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/AbilitiesScroll/AbilityEntries
@onready var equipment_reset: Button = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/EquipmentHeader/EquipmentReset
@onready var weapon_picker: OptionButton = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/Equipment/WeaponPicker
@onready var armor_picker: OptionButton = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/Equipment/ArmorPicker
@onready var accessory_picker: OptionButton = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/Equipment/AccessoryPicker
@onready var delete_unit_button: Button = $Drawer/Margin/Main/Tabs/Unit/UnitContent/UnitEditor/DeleteUnitButton
@onready var tile_brushes: FlowContainer = $Drawer/Margin/Main/Tabs/Terrain/TerrainContent/TileBrushes
@onready var wall_brushes: FlowContainer = $Drawer/Margin/Main/Tabs/Terrain/TerrainContent/WallBrushes
@onready var erase_button: Button = $Drawer/Margin/Main/Tabs/Terrain/TerrainContent/EraseButton
@onready var brush_details: Label = $Drawer/Margin/Main/Tabs/Terrain/TerrainContent/BrushDetails
@onready var undo_button: Button = $Drawer/Margin/Main/Tabs/Terrain/TerrainContent/History/UndoButton
@onready var redo_button: Button = $Drawer/Margin/Main/Tabs/Terrain/TerrainContent/History/RedoButton
@onready var reset_map_button: Button = $Drawer/Margin/Main/Tabs/Terrain/TerrainContent/History/ResetMapButton
@onready var save_entries: VBoxContainer = $Drawer/Margin/Main/Tabs/Saves/SavesScroll/SaveEntries
@onready var copy_ai_log_button: Button = $Drawer/Margin/Main/Tabs/AILog/AILogActions/CopyAILogButton
@onready var ai_log_scroll: ScrollContainer = $Drawer/Margin/Main/Tabs/AILog/AILogScroll
@onready var ai_log_empty_state: Label = $Drawer/Margin/Main/Tabs/AILog/AILogScroll/AILogContent/EmptyState
@onready var ai_log_entries: VBoxContainer = $Drawer/Margin/Main/Tabs/AILog/AILogScroll/AILogContent/AILogEntries
@onready var delete_save_dialog: ConfirmationDialog = $DeleteSaveDialog
@onready var discard_edits_dialog: ConfirmationDialog = $DiscardEditsDialog

var _catalog: DevToolCatalog
var _tile_palette: TilePalette
var _selected_unit: TacticalCharacter
var _dirty := false
var _syncing := false
var _pending_delete_path := ""
var _pending_load_path := ""
var _terrain_brush_group := ButtonGroup.new()
var _selected_brush_kind := BRUSH_ERASE
var _selected_brush_resource: Resource
var _ai_history_copy_text := ""


func _ready() -> void:
	play_button.pressed.connect(_play_pressed)
	save_button.pressed.connect(_save_new_pressed)
	delete_unit_button.pressed.connect(_delete_unit_pressed)
	heal_unit_button.pressed.connect(_heal_unit_pressed)
	delete_save_dialog.confirmed.connect(_confirm_delete_save)
	discard_edits_dialog.confirmed.connect(_confirm_load_save)
	_connect_stat(strength_spin, strength_reset, UnitStat.Type.STRENGTH)
	_connect_stat(dexterity_spin, dexterity_reset, UnitStat.Type.DEXTERITY)
	_connect_stat(intelligence_spin, intelligence_reset, UnitStat.Type.INTELLIGENCE)
	_connect_stat(constitution_spin, constitution_reset, UnitStat.Type.CONSTITUTION)
	_connect_stat(speed_spin, speed_reset, UnitStat.Type.SPEED)
	_connect_stat(movement_spin, movement_reset, UnitStat.Type.MOVEMENT_RANGE)
	abilities_reset.pressed.connect(_reset_abilities)
	ability_bypass.toggled.connect(_ability_bypass_toggled)
	add_class_button.pressed.connect(_add_class_pressed)
	equipment_reset.pressed.connect(_reset_equipment)
	weapon_picker.item_selected.connect(_equipment_selected.bind(ItemDefinition.EquipmentSlot.WEAPON, weapon_picker))
	armor_picker.item_selected.connect(_equipment_selected.bind(ItemDefinition.EquipmentSlot.ARMOR, armor_picker))
	accessory_picker.item_selected.connect(_equipment_selected.bind(ItemDefinition.EquipmentSlot.ACCESSORY, accessory_picker))
	erase_button.button_group = _terrain_brush_group
	erase_button.pressed.connect(_terrain_erase_pressed)
	undo_button.pressed.connect(func() -> void: terrain_undo_requested.emit())
	redo_button.pressed.connect(func() -> void: terrain_redo_requested.emit())
	reset_map_button.pressed.connect(func() -> void: terrain_reset_requested.emit())
	copy_ai_log_button.pressed.connect(_copy_ai_history)
	tabs.tab_changed.connect(_tab_changed)
	tabs.set_tab_title(AI_LOG_TAB, "AI Log")
	hide()


func setup(catalog: DevToolCatalog, tile_palette: TilePalette = null) -> void:
	_catalog = catalog
	_tile_palette = tile_palette
	_rebuild_palette()
	_rebuild_terrain_brushes()
	_refresh_selected_unit()
	refresh_saves()


func open_panel(initial_tab := UNIT_TAB) -> void:
	show()
	tabs.current_tab = clampi(initial_tab, 0, tabs.get_tab_count() - 1)
	show_message("Battle paused. Middle-drag to pan; drag units to arrange the scenario.")
	refresh_saves()
	_focus_play_button.call_deferred()


func close_panel() -> void:
	hide()
	_selected_unit = null


func _focus_play_button() -> void:
	if is_inside_tree() and visible:
		play_button.grab_focus()


func set_dirty(value: bool) -> void:
	_dirty = value
	play_button.text = "Restart & Play" if _dirty else "Resume"


func select_unit(unit: TacticalCharacter) -> void:
	_selected_unit = unit
	_refresh_selected_unit()


func clear_unit_selection() -> void:
	_selected_unit = null
	_refresh_selected_unit()


func get_selected_unit() -> TacticalCharacter:
	return _selected_unit if is_instance_valid(_selected_unit) else null


func is_pointer_over_drawer(screen_position: Vector2) -> bool:
	return visible and drawer.get_global_rect().has_point(screen_position)


func blocks_board_shortcuts() -> bool:
	if delete_save_dialog.visible or discard_edits_dialog.visible:
		return true
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is SpinBox


func has_open_dialog() -> bool:
	return delete_save_dialog.visible or discard_edits_dialog.visible


func can_delete_selected_with_shortcut() -> bool:
	return is_unit_tab_active() and is_instance_valid(_selected_unit)


func is_unit_tab_active() -> bool:
	return tabs.current_tab == UNIT_TAB


func is_terrain_tab_active() -> bool:
	return tabs.current_tab == TERRAIN_TAB


func set_terrain_history_state(can_undo: bool, can_redo: bool) -> void:
	undo_button.disabled = not can_undo
	redo_button.disabled = not can_redo


func set_ai_history(entries: Array[String], selected_history_index := -1) -> void:
	var retained_scroll_position := get_ai_history_scroll_position()
	_clear_children(ai_log_entries)
	ai_log_empty_state.visible = entries.is_empty()
	var newest_first: Array[String] = []
	var selection_group := ButtonGroup.new()
	for history_index in range(entries.size() - 1, -1, -1):
		var entry_text := entries[history_index]
		newest_first.append(entry_text)
		var entry_button := Button.new()
		entry_button.custom_minimum_size = Vector2(0.0, 36.0)
		entry_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry_button.text = _get_ai_history_summary(entry_text)
		entry_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry_button.autowrap_mode = TextServer.AUTOWRAP_OFF
		entry_button.clip_text = true
		entry_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		entry_button.toggle_mode = true
		entry_button.button_group = selection_group
		entry_button.set_pressed_no_signal(history_index == selected_history_index)
		var restore_guidance := "Restore to immediately before this AI decision"
		if history_index == selected_history_index:
			restore_guidance = "Selected restore point; newer logs will be discarded on Resume"
		elif selected_history_index >= 0 and history_index > selected_history_index:
			restore_guidance = "Future log; click to restore to immediately before this AI decision"
		entry_button.tooltip_text = "%s\n\n%s" % [restore_guidance, entry_text]
		entry_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		entry_button.pressed.connect(_request_ai_history_restore.bind(history_index))
		ai_log_entries.add_child(entry_button)
	_ai_history_copy_text = AI_LOG_SEPARATOR.join(newest_first)
	copy_ai_log_button.disabled = _ai_history_copy_text.is_empty()
	restore_ai_history_scroll_position(retained_scroll_position)


func get_ai_history_scroll_position() -> int:
	return ai_log_scroll.scroll_vertical


func restore_ai_history_scroll_position(scroll_position: int) -> void:
	_apply_ai_history_scroll_position.call_deferred(maxi(scroll_position, 0))


func _apply_ai_history_scroll_position(scroll_position: int) -> void:
	if not is_inside_tree():
		return
	ai_log_scroll.scroll_vertical = scroll_position


func _get_ai_history_summary(entry_text: String) -> String:
	var summary_lines: Array[String] = []
	for raw_line in entry_text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty():
			continue
		summary_lines.append(line)
		if summary_lines.size() == 2:
			break
	if summary_lines.is_empty():
		return "AI decision"
	return " — ".join(summary_lines)


func _request_ai_history_restore(history_index: int) -> void:
	ai_history_restore_requested.emit(history_index)


func _copy_ai_history() -> void:
	if _ai_history_copy_text.is_empty():
		return
	DisplayServer.clipboard_set(_ai_history_copy_text)
	show_message("AI logs copied. Paste them into your LLM chat.")


func show_message(message: String, is_error := false) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", ERROR_TEXT if is_error else NORMAL_TEXT)


func persist_payload(payload: Dictionary, replace_path := "") -> Dictionary:
	var result := (
		ScenarioSaveStore.save_new(payload)
		if replace_path.is_empty()
		else ScenarioSaveStore.replace_save(replace_path, payload)
	)
	if result.ok:
		show_message("Saved successfully.")
		status_label.add_theme_color_override("font_color", SUCCESS_TEXT)
	else:
		show_message("Save failed: %s" % " ".join(result.errors), true)
	refresh_saves()
	return result


func refresh_saves() -> void:
	if not is_node_ready():
		return
	_clear_children(save_entries)
	var entries := ScenarioSaveStore.list_saves()
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "No saves yet. Save creates a named snapshot in one click."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", Color("8095aa"))
		save_entries.add_child(empty)
		return
	for entry in entries:
		_add_save_row(entry)


func _connect_stat(spin: SpinBox, reset: Button, stat: UnitStat.Type) -> void:
	spin.value_changed.connect(_stat_changed.bind(stat))
	reset.pressed.connect(_stat_reset.bind(stat))


func _play_pressed() -> void:
	play_requested.emit()


func _save_new_pressed() -> void:
	save_requested.emit("")


func _delete_unit_pressed() -> void:
	selected_unit_deleted.emit()


func _heal_unit_pressed() -> void:
	selected_unit_heal_requested.emit()


func _stat_changed(value: float, stat: UnitStat.Type) -> void:
	if _syncing or not is_instance_valid(_selected_unit):
		return
	_selected_unit.set_dev_stat_override(stat, value)
	_mark_setup_changed()
	_refresh_selected_unit()


func _stat_reset(stat: UnitStat.Type) -> void:
	if not is_instance_valid(_selected_unit):
		return
	_selected_unit.clear_dev_stat_override(stat)
	_mark_setup_changed()
	_refresh_selected_unit()


func _reset_abilities() -> void:
	if not is_instance_valid(_selected_unit):
		return
	_selected_unit.reset_dev_ability_loadout()
	_mark_setup_changed()
	_refresh_selected_unit()


func _ability_toggled(pressed: bool, ability: AbilityDefinition) -> void:
	if _syncing or not is_instance_valid(_selected_unit):
		return
	if _selected_unit.is_friendly() and not _selected_unit.override_template_abilities:
		return
	var values: Array[AbilityDefinition] = []
	values.assign(_selected_unit.get_abilities())
	if pressed and not values.has(ability):
		values.append(ability)
	elif not pressed:
		values.erase(ability)
	_selected_unit.set_dev_ability_loadout(values)
	_mark_setup_changed()
	_refresh_selected_unit()


func _ability_bypass_toggled(enabled: bool) -> void:
	if _syncing or not is_instance_valid(_selected_unit) or not _selected_unit.is_friendly():
		return
	if enabled:
		_selected_unit.set_dev_ability_loadout(_selected_unit.get_abilities())
	else:
		_selected_unit.reset_dev_ability_loadout()
	_mark_setup_changed()
	_refresh_selected_unit()


func _add_class_pressed() -> void:
	if class_picker.selected < 0 or not is_instance_valid(_selected_unit):
		return
	_set_class_level(1, class_picker.get_selected_metadata() as CharacterClassDefinition)


func _set_class_level(value: float, character_class: CharacterClassDefinition) -> void:
	if _syncing or not is_instance_valid(_selected_unit):
		return
	if _selected_unit.set_class_level(character_class, int(value)):
		_mark_setup_changed()
	_refresh_selected_unit()


func _rebuild_classes() -> void:
	class_editor.visible = _selected_unit.is_friendly()
	ability_bypass.visible = _selected_unit.is_friendly()
	ability_bypass.set_pressed_no_signal(_selected_unit.override_template_abilities)
	abilities_reset.text = "Use Class Unlocks" if _selected_unit.is_friendly() else "Reset to Template"
	abilities_reset.tooltip_text = "Disable the developer bypass and restore class unlocks" if _selected_unit.is_friendly() else "Restore the template ability loadout"
	_clear_children(class_entries)
	class_picker.clear()
	if not _selected_unit.is_friendly():
		return
	var levels := _selected_unit.get_class_levels()
	class_summary.text = CharacterClassProgression.get_summary(levels)
	var active_ids := {}
	for allocation in levels:
		if allocation == null or allocation.character_class == null:
			continue
		var definition := allocation.character_class
		active_ids[definition.class_id] = true
		var row := HBoxContainer.new()
		row.set_meta("class_id", definition.class_id)
		var label := Label.new()
		label.text = definition.display_name
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var spin := SpinBox.new()
		spin.name = "Level"
		spin.min_value = 1
		spin.max_value = 99
		spin.allow_greater = true
		spin.step = 1
		spin.value = allocation.level
		spin.tooltip_text = "Levels invested in %s" % definition.display_name
		spin.value_changed.connect(_set_class_level.bind(definition))
		row.add_child(spin)
		var remove := Button.new()
		remove.name = "Remove"
		remove.text = "Remove"
		remove.disabled = levels.size() <= 1
		remove.tooltip_text = "A friendly must retain at least one class"
		remove.pressed.connect(_set_class_level.bind(0.0, definition))
		row.add_child(remove)
		class_entries.add_child(row)
	if _catalog != null:
		for definition in _catalog.character_classes:
			if definition == null or active_ids.has(definition.class_id):
				continue
			class_picker.add_item(definition.display_name)
			class_picker.set_item_metadata(class_picker.item_count - 1, definition)
	add_class_button.disabled = class_picker.item_count == 0
	class_picker.disabled = class_picker.item_count == 0


func _reset_equipment() -> void:
	if not is_instance_valid(_selected_unit):
		return
	_selected_unit.reset_dev_equipment_to_template()
	_mark_setup_changed()
	_refresh_selected_unit()


func _equipment_selected(
	index: int,
	slot: ItemDefinition.EquipmentSlot,
	picker: OptionButton
) -> void:
	if _syncing or not is_instance_valid(_selected_unit):
		return
	var item := picker.get_item_metadata(index) as ItemDefinition
	_selected_unit.set_dev_equipment(slot, item)
	_mark_setup_changed()
	_refresh_selected_unit()


func _mark_setup_changed() -> void:
	_dirty = true
	play_button.text = "Restart & Play"
	unit_setup_changed.emit()


func _refresh_selected_unit() -> void:
	if not is_node_ready():
		return
	var valid := is_instance_valid(_selected_unit)
	no_selection.visible = not valid
	unit_editor.visible = valid
	heal_unit_button.disabled = true
	if not valid:
		return
	_syncing = true
	unit_name.text = (
		_selected_unit.definition.display_name
		if _selected_unit.definition != null
		else str(_selected_unit.name)
	)
	strength_spin.set_value_no_signal(_base_stat_value(UnitStat.Type.STRENGTH))
	dexterity_spin.set_value_no_signal(_base_stat_value(UnitStat.Type.DEXTERITY))
	intelligence_spin.set_value_no_signal(_base_stat_value(UnitStat.Type.INTELLIGENCE))
	constitution_spin.set_value_no_signal(_base_stat_value(UnitStat.Type.CONSTITUTION))
	speed_spin.set_value_no_signal(_base_stat_value(UnitStat.Type.SPEED))
	movement_spin.set_value_no_signal(_base_movement_value())
	strength_reset.disabled = _selected_unit.strength_override < 0
	dexterity_reset.disabled = _selected_unit.dexterity_override < 0
	intelligence_reset.disabled = _selected_unit.intelligence_override < 0
	constitution_reset.disabled = _selected_unit.constitution_override < 0
	speed_reset.disabled = _selected_unit.speed_override < 0
	movement_reset.disabled = _selected_unit.movement_range_override < 0.0
	var maximum_health := _selected_unit.get_max_health()
	heal_unit_button.disabled = (
		_selected_unit.current_health <= 0
		or _selected_unit.current_health >= maximum_health
	)
	derived_stats.text = "Health: %d / %d · %.1f Move · %d Initiative" % [
		_selected_unit.current_health,
		maximum_health,
		_selected_unit.get_movement_range(),
		_selected_unit.get_initiative(),
	]
	_rebuild_classes()
	_rebuild_abilities()
	_rebuild_equipment_picker(weapon_picker, ItemDefinition.EquipmentSlot.WEAPON)
	_rebuild_equipment_picker(armor_picker, ItemDefinition.EquipmentSlot.ARMOR)
	_rebuild_equipment_picker(accessory_picker, ItemDefinition.EquipmentSlot.ACCESSORY)
	_syncing = false


func _base_stat_value(stat: UnitStat.Type) -> float:
	if _selected_unit == null or _selected_unit.definition == null:
		return 0.0
	match stat:
		UnitStat.Type.STRENGTH:
			return _selected_unit.strength_override if _selected_unit.strength_override >= 0 else _selected_unit.definition.strength
		UnitStat.Type.DEXTERITY:
			return _selected_unit.dexterity_override if _selected_unit.dexterity_override >= 0 else _selected_unit.definition.dexterity
		UnitStat.Type.INTELLIGENCE:
			return _selected_unit.intelligence_override if _selected_unit.intelligence_override >= 0 else _selected_unit.definition.intelligence
		UnitStat.Type.CONSTITUTION:
			return _selected_unit.constitution_override if _selected_unit.constitution_override >= 0 else _selected_unit.definition.constitution
		UnitStat.Type.SPEED:
			return _selected_unit.speed_override if _selected_unit.speed_override >= 0 else _selected_unit.definition.speed
	return 0.0


func _base_movement_value() -> float:
	if _selected_unit == null:
		return 0.0
	if _selected_unit.movement_range_override >= 0.0:
		return _selected_unit.movement_range_override
	return _selected_unit.definition.movement_range if _selected_unit.definition != null else 0.0


func _rebuild_abilities() -> void:
	_clear_children(ability_entries)
	if _selected_unit.is_friendly() and not _selected_unit.override_template_abilities:
		for allocation in _selected_unit.get_class_levels():
			if allocation == null or allocation.character_class == null:
				continue
			for unlock in allocation.character_class.get_sorted_unlocks():
				if unlock.ability == null:
					continue
				var entry := VBoxContainer.new()
				entry.add_theme_constant_override("separation", 0)
				var label := Label.new()
				var unlocked := allocation.level >= unlock.required_level
				entry.set_meta("ability", unlock.ability)
				entry.set_meta("unlocked", unlocked)
				label.text = "%s · %s %d · %s" % [unlock.ability.display_name, allocation.character_class.display_name, unlock.required_level, "Unlocked" if unlocked else "Locked"]
				label.tooltip_text = unlock.ability.get_description(_selected_unit)
				label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				label.add_theme_color_override("font_color", SUCCESS_TEXT if unlocked else Color("8095aa"))
				entry.add_child(label)
				_add_damage_breakdown(entry, unlock.ability, label.tooltip_text)
				ability_entries.add_child(entry)
		return
	if _catalog == null:
		return
	var current := _selected_unit.get_abilities()
	for ability in _catalog.abilities:
		if ability == null:
			continue
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 0)
		entry.set_meta("ability", ability)
		var check := CheckBox.new()
		check.text = ability.display_name
		check.tooltip_text = ability.get_description(_selected_unit)
		check.button_pressed = current.has(ability)
		check.toggled.connect(_ability_toggled.bind(ability))
		entry.add_child(check)
		_add_damage_breakdown(entry, ability, check.tooltip_text)
		ability_entries.add_child(entry)


func _add_damage_breakdown(entry: VBoxContainer, ability: AbilityDefinition, description: String) -> void:
	var damage_breakdown := Label.new()
	damage_breakdown.name = "DamageBreakdown"
	damage_breakdown.text = ability.get_damage_calculation_description(_selected_unit)
	damage_breakdown.tooltip_text = description
	damage_breakdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_breakdown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	damage_breakdown.add_theme_font_size_override("font_size", 12)
	damage_breakdown.add_theme_color_override("font_color", Color("79cbe8") if ability.has_damage() else Color("8095aa"))
	entry.add_child(damage_breakdown)


func _rebuild_equipment_picker(
	picker: OptionButton,
	slot: ItemDefinition.EquipmentSlot
) -> void:
	picker.clear()
	picker.add_item("Empty")
	picker.set_item_metadata(0, null)
	var selected_index := 0
	var equipped := _selected_unit.get_equipped_item(slot)
	if _catalog != null:
		for item in _catalog.items:
			if item == null or item.slot != slot:
				continue
			var index := picker.item_count
			picker.add_item(item.display_name)
			picker.set_item_metadata(index, item)
			if item == equipped:
				selected_index = index
	picker.select(selected_index)


func _rebuild_palette() -> void:
	if not is_node_ready():
		return
	_clear_children(palette_entries)
	if _catalog == null:
		return
	for unit_scene in _catalog.unit_scenes:
		if unit_scene == null:
			continue
		var button := Button.new()
		button.custom_minimum_size = Vector2(112.0, 42.0)
		button.text = _get_unit_scene_name(unit_scene)
		button.tooltip_text = "Drag onto an empty board cell to add"
		button.button_down.connect(_palette_button_down.bind(unit_scene))
		palette_entries.add_child(button)


func _palette_button_down(unit_scene: PackedScene) -> void:
	unit_palette_drag_started.emit(unit_scene)
	show_message("Drag onto an empty board cell.")


func _rebuild_terrain_brushes() -> void:
	if not is_node_ready():
		return
	_clear_children(tile_brushes)
	_clear_children(wall_brushes)
	var first_button: Button
	if _tile_palette != null:
		for definition in _tile_palette.tiles:
			if definition == null:
				continue
			var button := _make_brush_button(definition.display_name, BRUSH_TILE, definition)
			tile_brushes.add_child(button)
			if first_button == null:
				first_button = button
	if _catalog != null:
		for definition in _catalog.wall_styles:
			if definition == null:
				continue
			var button := _make_brush_button(definition.display_name, BRUSH_WALL, definition)
			wall_brushes.add_child(button)
			if first_button == null:
				first_button = button
	if first_button != null:
		first_button.button_pressed = true
		_select_terrain_brush(
			int(first_button.get_meta("brush_kind")),
			first_button.get_meta("brush_resource") as Resource
		)
	else:
		erase_button.button_pressed = true
		_select_terrain_brush(BRUSH_ERASE, null)


func _make_brush_button(label: String, kind: int, brush_resource: Resource) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(126.0, 38.0)
	button.text = label
	button.toggle_mode = true
	button.button_group = _terrain_brush_group
	button.set_meta("brush_kind", kind)
	button.set_meta("brush_resource", brush_resource)
	button.pressed.connect(_select_terrain_brush.bind(kind, brush_resource))
	return button


func _terrain_erase_pressed() -> void:
	_select_terrain_brush(BRUSH_ERASE, null)


func _select_terrain_brush(kind: int, brush_resource: Resource) -> void:
	_selected_brush_kind = kind
	_selected_brush_resource = brush_resource
	match kind:
		BRUSH_TILE:
			var tile := brush_resource as TileDefinition
			brush_details.text = "%s · Movement cost ×%.2f" % [
				tile.display_name,
				tile.get_movement_cost_multiplier(),
			]
		BRUSH_WALL:
			var wall := brush_resource as WallDefinition
			brush_details.text = "%s · %.0f px high · Blocks movement and sight" % [
				wall.display_name,
				wall.wall_height,
			]
		_:
			brush_details.text = "Eraser · Removes terrain or walls"
	terrain_brush_changed.emit(_selected_brush_kind, _selected_brush_resource)


func _tab_changed(tab_index: int) -> void:
	active_tab_changed.emit(tab_index)
	if tab_index == UNIT_TAB:
		show_message("Drag units to move them, or drag a template onto an empty cell.")
	elif tab_index == TERRAIN_TAB:
		show_message("Paint with left-drag, erase with right-drag, and pan with middle-drag.")


func _get_unit_scene_name(unit_scene: PackedScene) -> String:
	var instance := unit_scene.instantiate()
	var display_name := unit_scene.resource_path.get_file().get_basename().capitalize()
	if instance is TacticalCharacter and instance.definition != null:
		display_name = instance.definition.display_name
	instance.free()
	return display_name


func _add_save_row(entry: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0.0, 72.0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(details)
	var name_edit := LineEdit.new()
	name_edit.text = str(entry.get("name", "Save"))
	name_edit.editable = entry.get("status") == "ok"
	name_edit.tooltip_text = "Rename this save"
	name_edit.text_submitted.connect(_rename_save.bind(str(entry.path), name_edit))
	name_edit.focus_exited.connect(_rename_save_from_focus.bind(str(entry.path), name_edit))
	details.add_child(name_edit)
	var metadata := Label.new()
	metadata.text = (
		"%s · Round %d · %s" % [entry.map_name, entry.round, entry.saved_at]
		if entry.get("status") == "ok"
		else str(entry.get("error", "Corrupt save"))
	)
	metadata.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	metadata.add_theme_color_override("font_color", Color("8095aa") if entry.get("status") == "ok" else ERROR_TEXT)
	details.add_child(metadata)
	var load_button := Button.new()
	load_button.text = "Load"
	load_button.disabled = entry.get("status") != "ok"
	load_button.pressed.connect(_request_load_save.bind(str(entry.path)))
	row.add_child(load_button)
	var replace_button := Button.new()
	replace_button.text = "↻"
	replace_button.tooltip_text = "Replace with the current battle"
	replace_button.disabled = entry.get("status") != "ok"
	replace_button.pressed.connect(_replace_save_pressed.bind(str(entry.path)))
	row.add_child(replace_button)
	var delete_button := Button.new()
	delete_button.text = "×"
	delete_button.tooltip_text = "Delete save"
	delete_button.pressed.connect(_request_delete_save.bind(str(entry.path), str(entry.name)))
	row.add_child(delete_button)
	save_entries.add_child(panel)


func _rename_save(_submitted_text: String, path: String, editor: LineEdit) -> void:
	editor.release_focus()


func _replace_save_pressed(path: String) -> void:
	save_requested.emit(path)


func _rename_save_from_focus(path: String, editor: LineEdit) -> void:
	var result := ScenarioSaveStore.rename_save(path, editor.text)
	if result.ok:
		show_message("Save renamed.")
	else:
		show_message("Rename failed: %s" % " ".join(result.errors), true)
	refresh_saves.call_deferred()


func _request_delete_save(path: String, save_name: String) -> void:
	_pending_delete_path = path
	delete_save_dialog.dialog_text = "Delete ‘%s’? This cannot be undone." % save_name
	delete_save_dialog.popup_centered()


func _confirm_delete_save() -> void:
	var result := ScenarioSaveStore.delete_save(_pending_delete_path)
	_pending_delete_path = ""
	if not result.ok:
		show_message("Delete failed: %s" % " ".join(result.errors), true)
	refresh_saves()


func _request_load_save(path: String) -> void:
	_pending_load_path = path
	if _dirty:
		discard_edits_dialog.popup_centered()
	else:
		_confirm_load_save()


func _confirm_load_save() -> void:
	var path := _pending_load_path
	_pending_load_path = ""
	var result := ScenarioSaveStore.load_save(path)
	if not result.ok:
		show_message("Load failed: %s" % " ".join(result.errors), true)
		refresh_saves()
		return
	load_payload_requested.emit(result.payload)


func _clear_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
