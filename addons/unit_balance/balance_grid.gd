@tool
extends Control

## A virtualized grid: the first column is drawn last and stays pinned. Selection
## is stored by resource path / column key, never by unstable sorted row indices.
signal selection_changed
signal edit_requested(path: String, column: Dictionary)
signal sort_requested(key: String)
signal paste_requested(text: String)
signal undo_requested
signal redo_requested

const ROW := 32.0
const HEADER := 36.0
const NAME_WIDTH := 215.0
var columns: Array = []
var rows: Array = []
var selected: Array[String] = []
var active_path := ""
var active_key := "display_name"
var anchor_path := ""
var anchor_key := "display_name"
var horizontal := HScrollBar.new()
var vertical := VScrollBar.new()


func _init() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(300, 180)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(horizontal)
	add_child(vertical)
	horizontal.value_changed.connect(func(_value): queue_redraw())
	vertical.value_changed.connect(func(_value): queue_redraw())
	resized.connect(_layout)


func set_data(new_columns: Array, new_rows: Array) -> void:
	columns = new_columns
	rows = new_rows
	_layout()
	queue_redraw()


func _layout() -> void:
	var width := 0.0
	for index in range(1, columns.size()):
		width += columns[index].width
	horizontal.position = Vector2(NAME_WIDTH, size.y - 16)
	horizontal.size = Vector2(maxf(0, size.x - NAME_WIDTH - 16), 16)
	horizontal.max_value = width
	horizontal.page = maxf(1, size.x - NAME_WIDTH - 16)
	vertical.position = Vector2(size.x - 16, HEADER)
	vertical.size = Vector2(16, maxf(0, size.y - HEADER - 16))
	vertical.max_value = rows.size() * ROW
	vertical.page = maxf(1, size.y - HEADER - 16)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("202630"))
	if columns.is_empty():
		return
	var x := NAME_WIDTH - horizontal.value
	for column_index in range(1, columns.size()):
		_draw_column(column_index, x, columns[column_index].width)
		x += columns[column_index].width
	_draw_column(0, 0, NAME_WIDTH)
	draw_line(Vector2(NAME_WIDTH, 0), Vector2(NAME_WIDTH, size.y - 16), Color("73859e"), 2)
	# Scrollbar tracks must not expose a partially visible row underneath them.
	draw_rect(Rect2(0, size.y - 16, size.x, 16), Color("202630"))
	draw_rect(Rect2(size.x - 16, HEADER, 16, size.y - HEADER), Color("202630"))
	if rows.is_empty():
		draw_string(get_theme_default_font(), Vector2(16, HEADER + 28), "No matching resources", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("b7c3d4"))


func _draw_column(index: int, x: float, width: float) -> void:
	if x + width < 0 or x > size.x:
		return
	var column: Dictionary = columns[index]
	var font := get_theme_default_font()
	var start := maxi(0, int(vertical.value / ROW))
	var end := mini(rows.size(), start + int(size.y / ROW) + 2)
	for row_index in range(start, end):
		var row: Dictionary = rows[row_index]
		var y := HEADER + row_index * ROW - vertical.value
		var rect := Rect2(x, y, width, ROW)
		var color := Color("252d39") if row_index % 2 == 0 else Color("202630")
		if row.path in selected and index in selected_column_indices():
			color = Color("304f70")
		draw_rect(rect, color)
		draw_line(Vector2(x, y + ROW), Vector2(x + width, y + ROW), Color("384352"))
		var value := str(row.cells.get(column.key, "—"))
		var ink := Color("8fd9c0") if column.kind == "result" else Color("e0e6ef")
		draw_string(font, Vector2(x + 9, y + 21), value, HORIZONTAL_ALIGNMENT_LEFT, width - 16, 14, ink)
		if row.path == active_path and column.key == active_key:
			draw_rect(rect.grow(-1), Color("80b9f1"), false, 2)
	draw_rect(Rect2(x, 0, width, HEADER), Color("354254"))
	draw_string(font, Vector2(x + 9, 23), column.title, HORIZONTAL_ALIGNMENT_LEFT, width - 14, 14, Color.WHITE)


func _get_tooltip(at_position: Vector2) -> String:
	var cell := cell_at(at_position)
	if cell.x < 0 or cell.y < 0:
		return "Click a heading to sort. Shift-click selects a rectangle. Ctrl-click selects rows."
	var row: Dictionary = rows[cell.y]
	var column: Dictionary = columns[cell.x]
	return str(row.cells.get(column.key, "")) + "\n" + row.path + ("\nCalculated result • " + str(row.get("explanation", "")) if column.kind == "result" else "\nDouble-click or Enter to edit")


func cell_at(point: Vector2) -> Vector2i:
	var column_index := -1
	if point.x < NAME_WIDTH:
		column_index = 0
	else:
		var x := NAME_WIDTH - horizontal.value
		for index in range(1, columns.size()):
			if point.x >= x and point.x < x + columns[index].width:
				column_index = index
				break
			x += columns[index].width
	var row_index := int(floorf((point.y - HEADER + vertical.value) / ROW)) if point.y >= HEADER else -1
	if row_index >= rows.size():
		row_index = -1
	return Vector2i(column_index, row_index)


func select_cell(row_index: int, column_index: int, extend := false, toggle := false) -> void:
	if rows.is_empty() or columns.is_empty():
		return
	row_index = clampi(row_index, 0, rows.size() - 1)
	column_index = clampi(column_index, 0, columns.size() - 1)
	active_path = rows[row_index].path
	active_key = columns[column_index].key
	if extend:
		var anchor := row_index_for(anchor_path)
		selected.clear()
		for index in range(mini(anchor, row_index), maxi(anchor, row_index) + 1):
			selected.append(rows[index].path)
	elif toggle:
		if active_path in selected:
			selected.erase(active_path)
		else:
			selected.append(active_path)
		anchor_path = active_path
		anchor_key = active_key
	else:
		selected.assign([active_path])
		anchor_path = active_path
		anchor_key = active_key
	selection_changed.emit()
	queue_redraw()


func row_index_for(path: String) -> int:
	for index in range(rows.size()):
		if rows[index].path == path:
			return index
	return 0


func column_index_for(key: String) -> int:
	for index in range(columns.size()):
		if columns[index].key == key:
			return index
	return 0


func selected_column_indices() -> Array[int]:
	var first := column_index_for(anchor_key)
	var last := column_index_for(active_key)
	var result: Array[int] = []
	for index in range(mini(first, last), maxi(first, last) + 1):
		result.append(index)
	return result


func copy_text() -> String:
	var lines := PackedStringArray()
	for row in rows:
		if row.path not in selected:
			continue
		var cells := PackedStringArray()
		for index in selected_column_indices():
			cells.append(str(row.get("raw", row.cells).get(columns[index].key, "")))
		lines.append("\t".join(cells))
	return "\n".join(lines)


func _gui_input(event: InputEvent) -> void:
	if rows.is_empty() and event is InputEventKey:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP]:
			var bar: Range = horizontal if event.shift_pressed else vertical
			bar.value += ROW * 3 * (1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			grab_focus()
			var cell := cell_at(event.position)
			if cell.x >= 0 and cell.y < 0 and event.position.y < HEADER:
				sort_requested.emit(columns[cell.x].key)
			elif cell.x >= 0 and cell.y >= 0:
				select_cell(cell.y, cell.x, event.shift_pressed, event.ctrl_pressed)
				if event.double_click:
					edit_requested.emit(active_path, columns[cell.x])
			accept_event()
	if not event is InputEventKey or not event.pressed:
		return
	var key: int = event.keycode
	if event.ctrl_pressed or event.meta_pressed:
		match key:
			KEY_C: DisplayServer.clipboard_set(copy_text())
			KEY_V: paste_requested.emit(DisplayServer.clipboard_get())
			KEY_Z:
				if event.shift_pressed:
					redo_requested.emit()
				else:
					undo_requested.emit()
			KEY_Y: redo_requested.emit()
			KEY_A:
				selected.clear()
				for row in rows:
					selected.append(row.path)
				selection_changed.emit()
				queue_redraw()
			_: return
		accept_event()
		return
	var row_index := row_index_for(active_path)
	var column_index := column_index_for(active_key)
	match key:
		KEY_LEFT: column_index -= 1
		KEY_RIGHT: column_index += 1
		KEY_UP: row_index -= 1
		KEY_DOWN: row_index += 1
		KEY_TAB: column_index += -1 if event.shift_pressed else 1
		KEY_HOME: column_index = 0
		KEY_END: column_index = columns.size() - 1
		KEY_ENTER, KEY_KP_ENTER, KEY_F2:
			if not active_path.is_empty() and not columns.is_empty():
				edit_requested.emit(active_path, columns[column_index])
			accept_event()
			return
		_: return
	select_cell(row_index, column_index, event.shift_pressed and key != KEY_TAB)
	_ensure_visible()
	accept_event()


func _ensure_visible() -> void:
	var top := row_index_for(active_path) * ROW
	if top < vertical.value:
		vertical.value = top
	elif top + ROW > vertical.value + vertical.page:
		vertical.value = top + ROW - vertical.page
	var index := column_index_for(active_key)
	if index == 0:
		return
	var left := 0.0
	for previous in range(1, index):
		left += columns[previous].width
	if left < horizontal.value:
		horizontal.value = left
	elif left + columns[index].width > horizontal.value + horizontal.page:
		horizontal.value = left + columns[index].width - horizontal.page
