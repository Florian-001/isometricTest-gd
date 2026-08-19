@tool
class_name AbilityBar
extends PanelContainer

signal ability_selected(ability: AbilityDefinition)

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
	for ability in unit.get_abilities():
		if ability == null:
			continue
		var button := _create_button(ability, unit)
		button.disabled = not interaction_enabled or not unit.ability_available
		entries.add_child(button)
	set_selected(_selected_ability)


func set_selected(ability: AbilityDefinition) -> void:
	_selected_ability = ability
	for child in _get_entries().get_children():
		if child is Button:
			var button := child as Button
			button.button_pressed = button.get_meta("ability") == ability


func _create_button(ability: AbilityDefinition, caster: TacticalCharacter) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(button_width, button_height)
	button.toggle_mode = true
	var has_damage := _has_damage_effect(ability)
	var damage_text := "%d DMG" % _get_total_damage(ability, caster)
	if ability.image == null:
		button.text = (
			"%s\n%s" % [ability.display_name, damage_text]
			if has_damage
			else ability.display_name
		)
	else:
		button.text = ""
	button.icon = ability.image
	button.expand_icon = true
	button.tooltip_text = "%s\n%s" % [ability.display_name, ability.get_description(caster)]
	button.set_meta("ability", ability)
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
	if ability.image != null and has_damage:
		_add_damage_overlay(button, damage_text)
	return button


func _has_damage_effect(ability: AbilityDefinition) -> bool:
	for effect in ability.effects:
		if effect is DamageEffectDefinition:
			return true
	return false


func _get_total_damage(ability: AbilityDefinition, caster: TacticalCharacter) -> int:
	var total := 0
	for effect in ability.effects:
		if effect is DamageEffectDefinition:
			total += (effect as DamageEffectDefinition).calculate_amount(caster)
	return total


func _add_damage_overlay(button: Button, damage_text: String) -> void:
	var label := Label.new()
	label.name = "DamageLabel"
	label.set_meta("damage_label", true)
	label.text = damage_text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_left = 4.0
	label.offset_top = -21.0
	label.offset_right = -4.0
	label.offset_bottom = -3.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.04, 1.0))
	label.add_theme_constant_override("outline_size", 4)
	button.add_child(label)


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
