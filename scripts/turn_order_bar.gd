@tool
class_name TurnOrderBar
extends PanelContainer

@export_range(40.0, 100.0, 2.0) var square_size: float = 60.0
@export_range(0.0, 20.0, 1.0) var active_size_bonus: float = 10.0
@export var active_border_color: Color = Color("ffd34e")
@export var inactive_border_color: Color = Color("60758d")

func rebuild(order: Array[TacticalCharacter], current_unit: TacticalCharacter) -> void:
	var entries := _get_entries()
	for child in entries.get_children():
		entries.remove_child(child)
		child.free()

	for unit in order:
		if is_instance_valid(unit) and unit.current_health > 0:
			entries.add_child(_create_entry(unit, unit == current_unit))


func _get_entries() -> HBoxContainer:
	return get_node("Margin/HBox") as HBoxContainer


func _create_entry(unit: TacticalCharacter, is_current: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	var entry_size := square_size + (active_size_bonus if is_current else 0.0)
	panel.custom_minimum_size = Vector2(entry_size, entry_size)
	panel.tooltip_text = "%s%s" % [unit.name, " | Current Turn" if is_current else ""]
	panel.set_meta("unit", unit)
	panel.set_meta("is_current", is_current)
	panel.set_meta("uses_portrait", unit.definition != null and unit.definition.portrait != null)

	var style := StyleBoxFlat.new()
	var body_color := unit.definition.body_color if unit.definition != null else Color.WHITE
	style.bg_color = body_color.darkened(0.58)
	style.border_color = active_border_color if is_current else inactive_border_color.lerp(body_color, 0.45)
	var border_width := 4 if is_current else 2
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(7)
	panel.add_theme_stylebox_override("panel", style)

	var center := CenterContainer.new()
	panel.add_child(center)
	if unit.definition != null and unit.definition.portrait != null:
		var portrait := TextureRect.new()
		portrait.texture = unit.definition.portrait
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.custom_minimum_size = Vector2(entry_size - 12.0, entry_size - 12.0)
		center.add_child(portrait)
	else:
		var initial := Label.new()
		initial.text = str(unit.name).left(1).to_upper()
		initial.add_theme_color_override("font_color", body_color.lightened(0.35))
		initial.add_theme_font_size_override("font_size", 26 if is_current else 22)
		center.add_child(initial)

	return panel
