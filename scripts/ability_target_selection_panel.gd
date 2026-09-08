class_name AbilityTargetSelectionPanel
extends PanelContainer

signal fire_requested
signal cancel_requested
signal target_removed(index: int)

@onready var title_label: Label = $Margin/Content/Title
@onready var hint_label: Label = $Margin/Content/Hint
@onready var target_rows: VBoxContainer = $Margin/Content/Scroll/Targets
@onready var counter_label: Label = $Margin/Content/Actions/Counter
@onready var fire_button: Button = $Margin/Content/Actions/Fire
@onready var cancel_button: Button = $Margin/Content/Actions/Cancel

var _slot_count := 0


func _ready() -> void:
	fire_button.pressed.connect(func(): fire_requested.emit())
	cancel_button.pressed.connect(func(): cancel_requested.emit())
	hide()


func configure(ability: AbilityDefinition) -> void:
	_slot_count = ability.get_hit_count()
	title_label.text = ability.display_name
	hint_label.text = "Choose targets in firing order. %s" % ("You may choose a unit again." if ability.allow_repeated_targets else "Choose distinct units.")
	for child in target_rows.get_children():
		target_rows.remove_child(child)
		child.queue_free()
	for index in range(_slot_count):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(label)
		var remove := Button.new()
		remove.text = "Remove"
		remove.focus_mode = Control.FOCUS_NONE
		remove.tooltip_text = "Remove target %d" % (index + 1)
		remove.pressed.connect(func(): target_removed.emit(index))
		row.add_child(remove)
		target_rows.add_child(row)
	set_targets([], [], false)
	show()


func set_targets(targets: Array[TacticalCharacter], valid: Array[bool], can_fire: bool) -> void:
	counter_label.text = "%d / %d selected" % [targets.size(), _slot_count]
	fire_button.disabled = not can_fire
	for index in range(_slot_count):
		var row := target_rows.get_child(index)
		var label := row.get_child(0) as Label
		var remove := row.get_child(1) as Button
		remove.disabled = index >= targets.size()
		var text := "%d. Choose a target" % (index + 1)
		var color := Color("8095aa")
		if index < targets.size():
			var target := targets[index]
			var target_valid := index < valid.size() and valid[index]
			if is_instance_valid(target):
				text = "%d. %s  ·  (%d, %d)%s" % [index + 1, target.get_combat_display_name(), target.grid_cell.x, target.grid_cell.y, "" if target_valid else "  ·  Invalid target"]
			else:
				text = "%d. Target unavailable — remove to replace" % (index + 1)
			color = Color("eaf0f7") if target_valid else Color("ff9d86")
		label.text = text
		label.tooltip_text = text
		label.add_theme_color_override("font_color", color)
