class_name StartingHub
extends Control

signal back_requested
signal start_requested(character_ids: Array[String])

const GOLD := Color(0.92, 0.77, 0.43)
const MUTED := Color(0.63, 0.69, 0.76)
const CARD_COLOR := Color(0.067, 0.085, 0.112)

@onready var roster_grid: GridContainer = $Margin/Layout/Scroll/Content/Roster
@onready var slot_grid: GridContainer = $Margin/Layout/Scroll/Content/Slots
@onready var scroll: ScrollContainer = $Margin/Layout/Scroll
@onready var count_label: Label = $Margin/Layout/Scroll/Content/PartyHeading
@onready var error_label: Label = $Margin/Layout/Error
@onready var start_button: Button = $Margin/Layout/Actions/Start
@onready var back_button: Button = $Margin/Layout/Actions/Back

var slots: Array[String] = ["", "", "", ""]
var cards: Dictionary = {}
var slot_buttons: Array[Button] = []
var _entries: Dictionary = {}
var _busy := false
var _configuration_error := ""


func _ready() -> void:
	start_button.pressed.connect(_request_start)
	back_button.pressed.connect(func() -> void:
		if not _busy:
			back_requested.emit())
	scroll.resized.connect(_update_columns)
	for index in range(4):
		var button := _make_card(Vector2(210, 142))
		button.pressed.connect(remove_slot.bind(index))
		slot_grid.add_child(button)
		slot_buttons.append(button)
	_style_button(back_button)
	_style_button(start_button)
	hide()


func open_hub(config: RunConfig) -> void:
	slots.assign(["", "", "", ""])
	_busy = false
	_entries.clear()
	cards.clear()
	for child in roster_grid.get_children():
		roster_grid.remove_child(child)
		child.queue_free()
	var report := config.inspect_starting_roster() if config != null else {"entries": [], "errors": ["Assign a run configuration."]}
	_configuration_error = " ".join(report.errors)
	for entry: Dictionary in report.entries:
		_entries[entry.id] = entry
		var button := _make_card(Vector2(210, 316))
		button.name = entry.id.to_pascal_case() + "Card"
		button.pressed.connect(toggle_character.bind(str(entry.id)))
		button.tooltip_text = "%s\n%s\nStarting abilities: %s" % [entry.name, entry.class_summary, entry.abilities]
		roster_grid.add_child(button)
		cards[entry.id] = button
		var content := _content(button)
		_add_label(content, entry.name, 23, GOLD)
		_add_label(content, entry.class_summary, 13, MUTED)
		_add_art(content, entry.art, 132)
		_add_label(content, entry.abilities, 15, Color.WHITE)
		_add_label(content, "HP %d   ·   Speed %d   ·   Move %s" % [entry.health, entry.speed, str(entry.movement)], 13, MUTED)
		var status := _add_label(content, "Select character", 13, GOLD)
		status.name = "SelectionStatus"
	show()
	scroll.scroll_vertical = 0
	_refresh()
	_update_columns.call_deferred()
	back_button.grab_focus()


func get_selected_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in slots:
		if not id.is_empty():
			ids.append(id)
	return ids


func toggle_character(id: String) -> void:
	if _busy or not _entries.has(id) or not _configuration_error.is_empty():
		return
	var index := slots.find(id)
	if index >= 0:
		slots[index] = ""
	else:
		index = slots.find("")
		if index < 0:
			return
		slots[index] = id
	_refresh()


func remove_slot(index: int) -> void:
	if _busy or index < 0 or index >= slots.size():
		return
	slots[index] = ""
	_refresh()


func set_busy(value: bool) -> void:
	_busy = value
	_refresh()


func show_error(message: String) -> void:
	error_label.text = message
	error_label.tooltip_text = message
	error_label.visible = not message.is_empty()


func _request_start() -> void:
	if _busy or start_button.disabled or not visible:
		return
	var ids := get_selected_ids()
	set_busy(true)
	start_requested.emit(ids)


func _refresh() -> void:
	var selected := get_selected_ids()
	count_label.text = "YOUR PARTY   ·   %d / 4" % selected.size()
	start_button.disabled = _busy or selected.is_empty() or not _configuration_error.is_empty()
	start_button.text = "Starting…" if _busy else "Start Run"
	back_button.disabled = _busy
	show_error(_configuration_error)
	for id: String in cards:
		var button: Button = cards[id]
		button.disabled = _busy
		var index := slots.find(id)
		button.add_theme_stylebox_override("normal", _panel(index >= 0))
		var label := button.get_node("Content/SelectionStatus") as Label
		label.text = "Selected · Slot %d  /  Remove" % (index + 1) if index >= 0 else "Select character"
	for index in range(4):
		var button := slot_buttons[index]
		button.disabled = _busy or slots[index].is_empty()
		button.add_theme_stylebox_override("normal", _panel(not slots[index].is_empty()))
		for child in button.get_children():
			button.remove_child(child)
			child.queue_free()
		var content := _content(button)
		if slots[index].is_empty():
			_add_label(content, "%02d" % (index + 1), 24, MUTED)
			_add_label(content, "Empty slot", 16, MUTED)
			_add_label(content, "Choose a character above", 12, MUTED)
		else:
			var entry: Dictionary = _entries[slots[index]]
			_add_label(content, "%02d   %s" % [index + 1, entry.name], 16, GOLD)
			_add_art(content, entry.art, 74)
			_add_label(content, "Level 1 · Click to remove", 12, MUTED)


func _update_columns() -> void:
	var columns := clampi(int((size.x - 64.0) / 224.0), 1, 4)
	roster_grid.columns = columns
	slot_grid.columns = columns


func _make_card(minimum: Vector2) -> Button:
	var button := Button.new()
	button.custom_minimum_size = minimum
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(button)
	return button


func _style_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _panel(false))
	button.add_theme_stylebox_override("hover", _panel(true))
	button.add_theme_stylebox_override("pressed", _panel(true))
	button.add_theme_stylebox_override("focus", _panel(true, true))
	button.add_theme_stylebox_override("disabled", _panel(false))
	button.add_theme_color_override("font_color", GOLD)
	button.add_theme_color_override("font_disabled_color", MUTED.darkened(0.25))


func _panel(selected: bool, focus_only: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.14) if selected else CARD_COLOR
	style.draw_center = not focus_only
	style.border_color = GOLD if selected else Color(0.21, 0.24, 0.28)
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(8)
	return style


func _content(button: Button) -> VBoxContainer:
	var content := VBoxContainer.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 12
	content.offset_top = 10
	content.offset_right = -12
	content.offset_bottom = -10
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 6)
	button.add_child(content)
	return content


func _add_label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _add_art(parent: Node, texture: Texture2D, height: float) -> void:
	var art := TextureRect.new()
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.texture = texture
	art.custom_minimum_size.y = height
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(art)
