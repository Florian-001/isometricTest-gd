@tool
class_name AbilityBar
extends PanelContainer

signal ability_selected(ability: AbilityDefinition)

const MAX_SHORTCUT_SLOTS := 9

@export_range(70.0, 150.0, 2.0) var button_width: float = 96.0
@export_range(42.0, 100.0, 2.0) var button_height: float = 62.0
@export var selected_border_color: Color = Color("ffd34e")

var _selected_ability: AbilityDefinition


func rebuild(unit: TacticalCharacter, interaction_enabled: bool) -> void:
	var entries := _get_entries()
	for child in entries.get_children():
		entries.remove_child(child)
		child.queue_free()

	if not is_instance_valid(unit):
		return
	var slot_index := 0
	for ability in unit.get_abilities():
		if ability == null:
			continue
		var shortcut_number := slot_index + 1 if slot_index < MAX_SHORTCUT_SLOTS else 0
		var button := _create_button(ability, unit, shortcut_number)
		button.disabled = (
			not interaction_enabled
			or not unit.ability_available
			or not ability.can_be_used_by(unit)
		)
		entries.add_child(button)
		slot_index += 1
	set_selected(_selected_ability)


func set_selected(ability: AbilityDefinition) -> void:
	_selected_ability = ability
	for child in _get_entries().get_children():
		if child is Button:
			var button := child as Button
			button.button_pressed = button.get_meta("ability") == ability


func activate_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= MAX_SHORTCUT_SLOTS:
		return false
	var entries := _get_entries()
	if slot_index >= entries.get_child_count():
		return false
	var button := entries.get_child(slot_index) as Button
	if button == null or button.disabled:
		return false
	button.pressed.emit()
	return true


func _create_button(
	ability: AbilityDefinition,
	caster: TacticalCharacter,
	shortcut_number: int
) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(button_width, button_height)
	button.toggle_mode = true
	var has_damage := ability.has_damage()
	var damage_text := "%d DMG" % ability.calculate_damage(caster)
	var unavailable_reason := ability.get_unavailable_reason(caster)
	var summary_text := damage_text if has_damage else ""
	if not unavailable_reason.is_empty():
		summary_text = unavailable_reason
	var shortcut_text := "[%d]" % shortcut_number if shortcut_number > 0 else ""
	if ability.image == null:
		var title_text := (
			"%s %s" % [shortcut_text, ability.display_name]
			if not shortcut_text.is_empty()
			else ability.display_name
		)
		button.text = (
			"%s\n%s" % [title_text, summary_text]
			if not summary_text.is_empty()
			else title_text
		)
	else:
		button.text = (
			"%s\n%s" % [shortcut_text, summary_text]
			if not shortcut_text.is_empty() and not summary_text.is_empty()
			else shortcut_text if not shortcut_text.is_empty() else summary_text
		)
	button.icon = ability.image
	button.expand_icon = true
	button.tooltip_text = "%s\n%s" % [ability.display_name, ability.get_description(caster)]
	if shortcut_number > 0:
		button.tooltip_text += "\nShortcut: %d" % shortcut_number
	button.set_meta("ability", ability)
	button.set_meta("unavailable_reason", unavailable_reason)
	button.set_meta("shortcut_number", shortcut_number)
	button.pressed.connect(_on_ability_pressed.bind(ability))

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = ability.placeholder_color.darkened(0.68)
	normal_style.border_color = ability.placeholder_color.darkened(0.12)
	normal_style.set_border_width_all(2)
	normal_style.set_corner_radius_all(7)
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", _make_style(ability.placeholder_color.darkened(0.52), ability.placeholder_color, 2))
	button.add_theme_stylebox_override("pressed", _make_style(ability.placeholder_color.darkened(0.42), selected_border_color, 4))
	button.add_theme_stylebox_override("disabled", _make_style(Color(0.06, 0.08, 0.11, 0.88), Color(0.23, 0.28, 0.34), 1))
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.45, 0.49, 0.54))
	button.add_theme_font_size_override("font_size", 13)
	return button


func _make_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(7)
	return style


func _on_ability_pressed(ability: AbilityDefinition) -> void:
	ability_selected.emit(ability)


func _get_entries() -> HBoxContainer:
	return get_node("Margin/HBox") as HBoxContainer
