@tool
extends RefCounted

const GROUP := &"tactical_editor_paint_buttons"

static func register(button: Button) -> void:
	button.add_to_group(GROUP)

static func activate(button: Button) -> void:
	for other in button.get_tree().get_nodes_in_group(GROUP):
		if other != button and other is Button:
			other.button_pressed = false
