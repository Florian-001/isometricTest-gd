class_name TacticalCameraController
extends Camera2D

@export_range(50.0, 2000.0, 25.0) var pan_speed: float = 700.0
@export_range(0.1, 1.0, 0.05) var minimum_zoom: float = 0.55
@export_range(1.0, 4.0, 0.05) var maximum_zoom: float = 2.0
@export_range(0.05, 0.5, 0.05) var zoom_step: float = 0.15

var _middle_dragging := false
var _dev_mode_pan_enabled := false


func _ready() -> void:
	enabled = true


func _process(delta: float) -> void:
	if _dev_mode_pan_enabled:
		return
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		direction.y += 1.0
	if Input.is_key_pressed(KEY_A):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		direction.x += 1.0
	if direction != Vector2.ZERO:
		position += direction.normalized() * pan_speed * delta / zoom.x


func _input(event: InputEvent) -> void:
	if _dev_mode_pan_enabled:
		_handle_middle_pan_input(event)


func _unhandled_input(event: InputEvent) -> void:
	if _dev_mode_pan_enabled:
		return
	if _handle_middle_pan_input(event):
		return
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(zoom.x + zoom_step)
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(zoom.x - zoom_step)
			get_viewport().set_input_as_handled()


func set_dev_mode_pan_enabled(enabled_for_dev_mode: bool) -> void:
	_dev_mode_pan_enabled = enabled_for_dev_mode
	_middle_dragging = false
	process_mode = (
		Node.PROCESS_MODE_ALWAYS
		if _dev_mode_pan_enabled
		else Node.PROCESS_MODE_PAUSABLE
	)


func is_dev_mode_pan_enabled() -> bool:
	return _dev_mode_pan_enabled


func _handle_middle_pan_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_middle_dragging = event.pressed
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventMouseMotion and _middle_dragging:
		position -= event.relative / zoom.x
		get_viewport().set_input_as_handled()
		return true
	return false


func _set_zoom(value: float) -> void:
	var clamped_zoom := clampf(value, minimum_zoom, maximum_zoom)
	zoom = Vector2.ONE * clamped_zoom
