class_name MapManager
extends Node

const BattleMapDefinitionScript = preload("res://scripts/battle_map_definition.gd")
const TacticalBattleScript = preload("res://scripts/initiative_battle_controller.gd")

@export_category("Level Catalog")
@export var levels: Array[BattleMapDefinitionScript] = []
@export var battle_scene: PackedScene

@onready var level_select: CanvasLayer = $LevelSelect
@onready var level_buttons: VBoxContainer = $LevelSelect/Root/Center/Panel/Margin/VBox/LevelButtons
@onready var empty_state: Label = $LevelSelect/Root/Center/Panel/Margin/VBox/EmptyState
@onready var show_map_button: Button = $LevelSelect/Root/Center/Panel/Margin/VBox/ShowMapButton
@onready var run_map_screen: RunMapScreen = $RunMapLayer/RunMapScreen

var current_battle: TacticalBattleScript


func _ready() -> void:
	show_map_button.pressed.connect(show_run_map)
	run_map_screen.close_requested.connect(hide_run_map)
	_rebuild_level_buttons()
	_show_level_select()


func show_run_map() -> void:
	if is_instance_valid(current_battle):
		return
	level_select.hide()
	run_map_screen.open_map()


func hide_run_map() -> void:
	run_map_screen.close_map()
	_show_level_select()


func load_level(definition: BattleMapDefinitionScript) -> bool:
	if definition == null or not definition.is_configured() or battle_scene == null:
		return false
	if is_instance_valid(current_battle):
		return false

	var instance := battle_scene.instantiate()
	if not instance is TacticalBattleScript:
		instance.free()
		push_error("Configured battle scene must use TacticalBattle.")
		return false
	current_battle = instance as TacticalBattleScript
	current_battle.map_definition = definition
	_connect_battle(current_battle)
	level_select.hide()
	add_child(current_battle)
	return true


func _connect_battle(battle: TacticalBattleScript) -> void:
	battle.return_to_level_select_requested.connect(
		_on_return_to_level_select_requested.bind(battle)
	)
	battle.dev_snapshot_load_requested.connect(
		_on_dev_snapshot_load_requested.bind(battle)
	)


func _on_dev_snapshot_load_requested(
	snapshot: Dictionary,
	source_battle: TacticalBattleScript
) -> void:
	if source_battle != current_battle or battle_scene == null:
		return
	var definition := load(str(snapshot.get("level_definition", ""))) as BattleMapDefinitionScript
	if definition == null or not definition.is_configured():
		source_battle.dev_mode_panel.set_status("Saved level is unavailable", true)
		return
	var instance := battle_scene.instantiate()
	if not instance is TacticalBattleScript:
		instance.free()
		source_battle.dev_mode_panel.set_status("Configured battle scene is invalid", true)
		return
	var replacement := instance as TacticalBattleScript
	replacement.map_definition = definition
	replacement.pending_dev_snapshot = snapshot.duplicate(true)
	_connect_battle(replacement)
	source_battle.visible = false
	add_child(replacement)
	if not replacement.snapshot_restore_succeeded:
		remove_child(replacement)
		replacement.queue_free()
		source_battle.visible = true
		source_battle.dev_mode_panel.set_status("Save validation failed; current battle was preserved", true)
		return
	current_battle = replacement
	source_battle.shutdown_battle()
	remove_child(source_battle)
	source_battle.queue_free()


func return_to_level_select() -> void:
	if is_instance_valid(current_battle):
		var battle := current_battle
		current_battle = null
		battle.shutdown_battle()
		remove_child(battle)
		battle.queue_free()
	_show_level_select()


func _rebuild_level_buttons() -> void:
	for child in level_buttons.get_children():
		child.queue_free()
	var first_button: Button = null
	for definition in levels:
		var button := Button.new()
		button.custom_minimum_size = Vector2(520.0, 72.0)
		button.text = _get_level_button_text(definition)
		button.tooltip_text = definition.description if definition != null else "Missing level definition"
		button.disabled = definition == null or not definition.is_configured() or battle_scene == null
		button.pressed.connect(load_level.bind(definition))
		level_buttons.add_child(button)
		if first_button == null and not button.disabled:
			first_button = button
	empty_state.visible = levels.is_empty()
	if first_button != null:
		first_button.grab_focus.call_deferred()


func _show_level_select() -> void:
	run_map_screen.close_map()
	level_select.show()


func _on_return_to_level_select_requested(battle: TacticalBattleScript) -> void:
	if battle != current_battle:
		return
	return_to_level_select()


func _get_level_button_text(definition: BattleMapDefinitionScript) -> String:
	if definition == null:
		return "Missing Level"
	if definition.description.strip_edges().is_empty():
		return definition.display_name
	return "%s\n%s" % [definition.display_name, definition.description]
