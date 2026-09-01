class_name DevModePanel
extends PanelContainer

signal close_requested
signal delete_unit_requested
signal add_archetype_selected(scene_path: String)
signal stat_changed(stat_name: String, value: float)
signal health_changed(value: int)
signal faction_changed(value: int)
signal reset_stats_requested
signal reset_faction_requested
signal equipment_changed(slot: ItemDefinition.EquipmentSlot, item: ItemDefinition)
signal abilities_changed(abilities: Array[AbilityDefinition])
signal reset_abilities_requested
signal save_requested(save_name: String)
signal load_requested(save_name: String)
signal delete_save_requested(save_name: String)
signal restore_recovery_requested

var tabs: TabContainer
var selected_name_label: Label
var selected_state_label: Label
var faction_option: OptionButton
var stat_inputs: Dictionary = {}
var effective_labels: Dictionary = {}
var health_input: SpinBox
var equipment_options: Dictionary = {}
var ability_list: VBoxContainer
var add_grid: GridContainer
var save_name_input: LineEdit
var save_list: VBoxContainer
var restore_button: Button
var status_label: Label
var ai_debug_label: Label

var _selected_unit: TacticalCharacter
var _refreshing := false
var _ability_checks: Array[CheckBox] = []


func _ready() -> void:
	_build_ui()
	visible = false


func open_panel() -> void:
	visible = true
	_refresh_add_catalog()


func close_panel() -> void:
	visible = false


func set_selected_unit(unit: TacticalCharacter) -> void:
	_selected_unit = unit
	_refresh_unit_tab()
	if is_instance_valid(unit):
		tabs.current_tab = 0


func set_ai_history(text: String) -> void:
	if ai_debug_label != null:
		ai_debug_label.text = text


func set_status(message: String, error: bool = false) -> void:
	status_label.text = message
	status_label.add_theme_color_override(
		"font_color",
		Color("ff7777") if error else Color("83e6ae")
	)


func refresh_saves(entries: Array[Dictionary], has_recovery: bool) -> void:
	for child in save_list.get_children():
		child.queue_free()
	for entry in entries:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = str(entry.get("name", "Unnamed"))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var load_button := Button.new()
		load_button.text = "Load"
		load_button.pressed.connect(load_requested.emit.bind(label.text))
		row.add_child(load_button)
		var delete_button := Button.new()
		delete_button.text = "×"
		delete_button.tooltip_text = "Delete save"
		delete_button.pressed.connect(delete_save_requested.emit.bind(label.text))
		row.add_child(delete_button)
		save_list.add_child(row)
	restore_button.disabled = not has_recovery


func _build_ui() -> void:
	anchors_preset = Control.PRESET_LEFT_WIDE
	offset_left = 16.0
	offset_top = 16.0
	offset_right = 446.0
	offset_bottom = -112.0
	grow_vertical = Control.GROW_DIRECTION_BOTH
	add_theme_stylebox_override("panel", _panel_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Runtime Dev Mode"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("f2cb58"))
	header.add_child(title)
	var delete_button := Button.new()
	delete_button.text = "Delete Unit"
	delete_button.tooltip_text = "Delete selected unit (Delete)"
	delete_button.pressed.connect(delete_unit_requested.emit)
	header.add_child(delete_button)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close_requested.emit)
	header.add_child(close_button)
	root.add_child(header)
	selected_state_label = Label.new()
	selected_state_label.text = "Click a unit to inspect · Drag it to move"
	selected_state_label.add_theme_color_override("font_color", Color("93a9bf"))
	root.add_child(selected_state_label)

	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	_build_unit_tab()
	_build_add_tab()
	_build_saves_tab()
	_build_ai_tab()

	status_label = Label.new()
	status_label.text = "Ready"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_label)


func _build_unit_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Unit"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	selected_name_label = Label.new()
	selected_name_label.text = "No unit selected"
	selected_name_label.add_theme_font_size_override("font_size", 18)
	content.add_child(selected_name_label)

	var faction_row := HBoxContainer.new()
	faction_row.add_child(_field_label("Faction"))
	faction_option = OptionButton.new()
	faction_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	faction_option.add_item("Inherit", -1)
	faction_option.add_item("Friendly", CharacterDefinition.Faction.FRIENDLY)
	faction_option.add_item("Enemy", CharacterDefinition.Faction.ENEMY)
	faction_option.item_selected.connect(_on_faction_selected)
	faction_row.add_child(faction_option)
	var faction_reset := Button.new()
	faction_reset.text = "Reset"
	faction_reset.pressed.connect(reset_faction_requested.emit)
	faction_row.add_child(faction_reset)
	content.add_child(faction_row)

	var grid := GridContainer.new()
	grid.columns = 3
	content.add_child(grid)
	for key in ["strength", "dexterity", "intelligence", "constitution", "speed", "movement_range"]:
		var label_name: String = str(key).capitalize().replace("_", " ")
		grid.add_child(_field_label(label_name))
		var input := SpinBox.new()
		input.min_value = 0.0
		input.max_value = 999.0
		input.step = 0.5 if key == "movement_range" else 1.0
		input.allow_greater = true
		input.value_changed.connect(_on_stat_value_changed.bind(key))
		stat_inputs[key] = input
		grid.add_child(input)
		var effective := Label.new()
		effective.add_theme_color_override("font_color", Color("8fc6ef"))
		effective_labels[key] = effective
		grid.add_child(effective)
	var reset_stats := Button.new()
	reset_stats.text = "Reset Base Stats to Archetype"
	reset_stats.pressed.connect(reset_stats_requested.emit)
	content.add_child(reset_stats)

	var health_row := HBoxContainer.new()
	health_row.add_child(_field_label("Current HP"))
	health_input = SpinBox.new()
	health_input.min_value = 0
	health_input.max_value = 3996
	health_input.step = 1
	health_input.allow_greater = true
	health_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	health_input.value_changed.connect(_on_health_value_changed)
	health_row.add_child(health_input)
	content.add_child(health_row)

	var equipment_title := Label.new()
	equipment_title.text = "Equipment (Dev Catalog)"
	equipment_title.add_theme_color_override("font_color", Color("f2cb58"))
	content.add_child(equipment_title)
	for slot in [
		ItemDefinition.EquipmentSlot.WEAPON,
		ItemDefinition.EquipmentSlot.ARMOR,
		ItemDefinition.EquipmentSlot.ACCESSORY,
	]:
		var row := HBoxContainer.new()
		row.add_child(_field_label(ItemDefinition.EquipmentSlot.keys()[slot].capitalize()))
		var option := OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.item_selected.connect(_on_equipment_selected.bind(slot))
		equipment_options[slot] = option
		row.add_child(option)
		content.add_child(row)

	var abilities_header := HBoxContainer.new()
	var abilities_title := Label.new()
	abilities_title.text = "Explicit Abilities"
	abilities_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	abilities_title.add_theme_color_override("font_color", Color("f2cb58"))
	abilities_header.add_child(abilities_title)
	var reset_abilities := Button.new()
	reset_abilities.text = "Use Archetype"
	reset_abilities.pressed.connect(reset_abilities_requested.emit)
	abilities_header.add_child(reset_abilities)
	content.add_child(abilities_header)
	ability_list = VBoxContainer.new()
	content.add_child(ability_list)


func _build_add_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Add"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	add_grid = GridContainer.new()
	add_grid.columns = 2
	add_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_grid.add_theme_constant_override("h_separation", 8)
	add_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(add_grid)


func _build_saves_tab() -> void:
	var content := VBoxContainer.new()
	content.name = "Saves"
	content.add_theme_constant_override("separation", 8)
	tabs.add_child(content)
	var save_row := HBoxContainer.new()
	save_name_input = LineEdit.new()
	save_name_input.placeholder_text = "Save name"
	save_name_input.max_length = 48
	save_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(save_name_input)
	var save_button := Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_on_save_pressed)
	save_row.add_child(save_button)
	content.add_child(save_row)
	restore_button = Button.new()
	restore_button.text = "Restore Previous Load"
	restore_button.disabled = true
	restore_button.pressed.connect(restore_recovery_requested.emit)
	content.add_child(restore_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	save_list = VBoxContainer.new()
	save_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(save_list)


func _build_ai_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "AI History"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	ai_debug_label = Label.new()
	ai_debug_label.text = "No AI decisions recorded yet."
	ai_debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ai_debug_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ai_debug_label.add_theme_font_size_override("font_size", 12)
	scroll.add_child(ai_debug_label)


func _refresh_unit_tab() -> void:
	_refreshing = true
	var valid := is_instance_valid(_selected_unit)
	selected_name_label.text = (
		_selected_unit.definition.display_name
		if valid and _selected_unit.definition != null
		else "No unit selected"
	)
	selected_state_label.text = (
		"%s · Cell %s · Drag to move"
		% ["Friendly" if _selected_unit.is_friendly() else "Enemy", _selected_unit.grid_cell]
		if valid
		else "Click a unit to inspect · Drag it to move"
	)
	for input in stat_inputs.values():
		(input as SpinBox).editable = valid
	health_input.editable = valid
	faction_option.disabled = not valid
	if not valid:
		_refreshing = false
		return
	var definition := _selected_unit.definition
	var base_values := {
		"strength": _selected_unit.strength_override if _selected_unit.strength_override >= 0 else definition.strength,
		"dexterity": _selected_unit.dexterity_override if _selected_unit.dexterity_override >= 0 else definition.dexterity,
		"intelligence": _selected_unit.intelligence_override if _selected_unit.intelligence_override >= 0 else definition.intelligence,
		"constitution": _selected_unit.constitution_override if _selected_unit.constitution_override >= 0 else definition.constitution,
		"speed": _selected_unit.speed_override if _selected_unit.speed_override >= 0 else definition.speed,
		"movement_range": _selected_unit.movement_range_override if _selected_unit.movement_range_override >= 0 else definition.movement_range,
	}
	for key in base_values:
		(stat_inputs[key] as SpinBox).value = float(base_values[key])
	var stat_types := {
		"strength": UnitStat.Type.STRENGTH,
		"dexterity": UnitStat.Type.DEXTERITY,
		"intelligence": UnitStat.Type.INTELLIGENCE,
		"constitution": UnitStat.Type.CONSTITUTION,
		"speed": UnitStat.Type.SPEED,
		"movement_range": UnitStat.Type.MOVEMENT_RANGE,
	}
	for key in stat_types:
		(effective_labels[key] as Label).text = "→ %.1f" % _selected_unit.get_effective_stat(stat_types[key])
	health_input.max_value = _selected_unit.get_max_health()
	health_input.value = _selected_unit.current_health
	_select_option_by_id(faction_option, _selected_unit.faction_override)
	_refresh_equipment_options()
	_refresh_ability_checks()
	_refreshing = false


func _refresh_equipment_options() -> void:
	for slot in equipment_options:
		var option := equipment_options[slot] as OptionButton
		option.clear()
		option.add_item("None")
		option.set_item_metadata(0, "")
		var selected_index := 0
		var equipped := _selected_unit.get_equipped_item(slot)
		for item in DevContentCatalog.get_items():
			if item.slot != slot:
				continue
			option.add_item(item.display_name)
			var index := option.item_count - 1
			option.set_item_metadata(index, item.resource_path)
			if equipped == item:
				selected_index = index
		option.select(selected_index)
		option.disabled = false


func _refresh_ability_checks() -> void:
	for child in ability_list.get_children():
		child.queue_free()
	_ability_checks.clear()
	var explicit := _selected_unit.ability_overrides if _selected_unit.override_template_abilities else _selected_unit.definition.abilities
	for ability in DevContentCatalog.get_abilities():
		var check := CheckBox.new()
		check.text = ability.display_name
		check.button_pressed = explicit.has(ability)
		check.set_meta("ability_path", ability.resource_path)
		check.toggled.connect(_on_ability_toggled)
		_ability_checks.append(check)
		ability_list.add_child(check)
	var granted: Array[String] = []
	for item in _selected_unit.get_equipped_items():
		for ability in item.granted_abilities:
			if ability != null:
				granted.append(ability.display_name)
	if not granted.is_empty():
		var label := Label.new()
		label.text = "Equipment granted (read-only): %s" % ", ".join(granted)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color", Color("93a9bf"))
		ability_list.add_child(label)


func _refresh_add_catalog() -> void:
	if add_grid.get_child_count() > 0:
		return
	for entry in DevContentCatalog.get_unit_entries():
		var button := Button.new()
		button.text = "%s\n%s" % [entry.name, "Friendly" if entry.friendly else "Enemy"]
		button.custom_minimum_size = Vector2(180, 58)
		button.tooltip_text = "Select, then click empty battlefield cells to add copies"
		button.pressed.connect(add_archetype_selected.emit.bind(str(entry.path)))
		add_grid.add_child(button)


func _on_stat_value_changed(value: float, key: String) -> void:
	if not _refreshing:
		stat_changed.emit(key, value)


func _on_health_value_changed(value: float) -> void:
	if not _refreshing:
		health_changed.emit(roundi(value))


func _on_faction_selected(index: int) -> void:
	if not _refreshing:
		faction_changed.emit(faction_option.get_item_id(index))


func _on_equipment_selected(index: int, slot: int) -> void:
	if _refreshing:
		return
	var path := str((equipment_options[slot] as OptionButton).get_item_metadata(index))
	var item := load(path) as ItemDefinition if not path.is_empty() else null
	equipment_changed.emit(slot as ItemDefinition.EquipmentSlot, item)


func _on_ability_toggled(_pressed: bool) -> void:
	if _refreshing:
		return
	var selected: Array[AbilityDefinition] = []
	for check in _ability_checks:
		if not check.button_pressed:
			continue
		var ability := load(str(check.get_meta("ability_path"))) as AbilityDefinition
		if ability != null:
			selected.append(ability)
	abilities_changed.emit(selected)


func _on_save_pressed() -> void:
	save_requested.emit(save_name_input.text)


func _select_option_by_id(option: OptionButton, id: int) -> void:
	for index in option.item_count:
		if option.get_item_id(index) == id:
			option.select(index)
			return


func _field_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.custom_minimum_size.x = 105
	return label


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("ee101c2c")
	style.border_color = Color("bfbd9448")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style
