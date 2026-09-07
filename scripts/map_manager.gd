class_name MapManager
extends Node

const BattleMapDefinitionScript = preload("res://scripts/battle_map_definition.gd")
const TacticalBattleScript = preload("res://scripts/initiative_battle_controller.gd")

@export_category("Level Catalog")
@export var levels: Array[BattleMapDefinitionScript] = []
@export var battle_scene: PackedScene
@export_category("Battle Presentation")
@export var unit_names_visible := true

@onready var level_select: CanvasLayer = $LevelSelect
@onready var level_buttons: VBoxContainer = $LevelSelect/Root/Center/Panel/Margin/VBox/LevelButtons
@onready var empty_state: Label = $LevelSelect/Root/Center/Panel/Margin/VBox/EmptyState
@onready var show_map_button: Button = $LevelSelect/Root/Center/Panel/Margin/VBox/ShowMapButton
@onready var run_map_screen: RunMapScreen = $RunMapLayer/RunMapScreen
@onready var run_controller: RunController = $RunController
@onready var continue_run_button: Button = $LevelSelect/Root/Center/Panel/Margin/VBox/ContinueRunButton
@onready var replace_run_dialog: ConfirmationDialog = $LevelSelect/ReplaceRunDialog
@onready var run_message: Label = $LevelSelect/Root/Center/Panel/Margin/VBox/RunMessage
var _pending_run_result: Dictionary = {}

var current_battle: TacticalBattleScript


func _ready() -> void:
	show_map_button.pressed.connect(show_run_map)
	run_map_screen.close_requested.connect(hide_run_map)
	run_map_screen.setup(run_controller)
	continue_run_button.pressed.connect(continue_run)
	replace_run_dialog.confirmed.connect(_start_new_run)
	run_controller.battle_requested.connect(_start_run_battle)
	run_controller.state_changed.connect(_refresh_run_menu)
	_rebuild_level_buttons()
	_show_level_select()


func show_run_map() -> void:
	if is_instance_valid(current_battle):
		return
	if run_controller.has_unfinished_run() or (run_controller.state == null and run_controller.has_saved_run()):
		replace_run_dialog.popup_centered()
		return
	_start_new_run()


func _start_new_run() -> void:
	if not run_controller.new_run():
		return
	level_select.hide()
	run_map_screen.open_map()


func continue_run() -> void:
	if is_instance_valid(current_battle):
		return
	if run_controller.state == null:
		run_message.text = run_controller.error_message
		return
	level_select.hide()
	run_map_screen.open_map()
	run_controller.resume_room()


func _refresh_run_menu() -> void:
	continue_run_button.visible = run_controller.has_saved_run()
	run_message.text = run_controller.error_message
	if run_controller.state != null and run_controller.state.status != RunState.Status.ACTIVE:
		continue_run_button.text = "View Last Run"
	else:
		continue_run_button.text = "Continue Run"


func hide_run_map() -> void:
	run_map_screen.close_map()
	_show_level_select()


func load_level(definition: BattleMapDefinitionScript) -> bool:
	if definition == null or not definition.is_configured() or battle_scene == null:
		return false
	if is_instance_valid(current_battle):
		return false
	return _create_battle(definition)


func reload_battle_from_payload(payload: Dictionary, source_battle: TacticalBattleScript) -> bool:
	if source_battle != current_battle or battle_scene == null:
		if is_instance_valid(source_battle):
			source_battle.report_reload_failed("Could not replace the active battle.")
		return false
	var validation := ScenarioSaveStore.validate_payload(payload)
	if not validation.ok:
		source_battle.report_reload_failed("Load failed: %s" % " ".join(validation.errors))
		return false
	var map_path := str(validation.payload.get("map_definition", ""))
	var definition: BattleMapDefinitionScript
	for configured_level in levels:
		if configured_level != null and configured_level.resource_path == map_path:
			definition = configured_level
			break
	if definition == null:
		source_battle.report_reload_failed("This save uses a map that is not in the level catalog.")
		return false
	var instance := battle_scene.instantiate()
	if not instance is TacticalBattleScript:
		instance.free()
		push_error("Configured battle scene must use TacticalBattle.")
		source_battle.report_reload_failed("The configured battle scene is invalid.")
		return false
	var replacement := instance as TacticalBattleScript
	replacement.map_definition = definition
	replacement.pending_restore_payload = validation.payload
	replacement.unit_names_visible = unit_names_visible
	_connect_battle(replacement)
	replacement.visible = false
	add_child(replacement)
	if not replacement.initialization_succeeded:
		remove_child(replacement)
		replacement.queue_free()
		source_battle.report_reload_failed("The saved battle could not be initialized.")
		return false
	current_battle = null
	source_battle.shutdown_battle()
	remove_child(source_battle)
	source_battle.queue_free()
	current_battle = replacement
	level_select.hide()
	replacement.visible = true
	get_tree().paused = false
	return true


func _create_battle(
	definition: BattleMapDefinitionScript,
	restore_payload: Dictionary = {}
) -> bool:
	var instance := battle_scene.instantiate()
	if not instance is TacticalBattleScript:
		instance.free()
		push_error("Configured battle scene must use TacticalBattle.")
		return false
	current_battle = instance as TacticalBattleScript
	current_battle.map_definition = definition
	current_battle.pending_restore_payload = restore_payload
	current_battle.unit_names_visible = unit_names_visible
	_connect_battle(current_battle)
	level_select.hide()
	add_child(current_battle)
	return true


func _connect_battle(battle: TacticalBattleScript) -> void:
	battle.return_to_level_select_requested.connect(
		_on_return_to_level_select_requested.bind(battle)
	)
	battle.battle_reload_requested.connect(
		reload_battle_from_payload.bind(battle)
	)
	battle.unit_name_visibility_changed.connect(_on_unit_name_visibility_changed)


func return_to_level_select() -> void:
	if is_instance_valid(current_battle):
		var battle := current_battle
		current_battle = null
		battle.shutdown_battle()
		remove_child(battle)
		battle.queue_free()
	run_controller.battle_open = false
	_pending_run_result.clear()
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
	_refresh_run_menu()


func _on_return_to_level_select_requested(battle: TacticalBattleScript) -> void:
	if battle != current_battle:
		return
	return_to_level_select()


func _on_unit_name_visibility_changed(visible: bool) -> void:
	unit_names_visible = visible


func _get_level_button_text(definition: BattleMapDefinitionScript) -> String:
	if definition == null:
		return "Missing Level"
	if definition.description.strip_edges().is_empty():
		return definition.display_name
	return "%s\n%s" % [definition.display_name, definition.description]


func _start_run_battle(encounter: RunEncounterDefinition, members: Array[Dictionary], inventory: Array[String], node_id: int) -> void:
	if is_instance_valid(current_battle):
		return
	var battle := battle_scene.instantiate() as TacticalBattleScript
	battle.map_definition = encounter.battle_map
	battle.run_encounter = encounter
	battle.run_party_input = members
	battle.run_inventory_input = inventory
	battle.unit_names_visible = unit_names_visible
	_connect_battle(battle)
	battle.battle_finished.connect(_on_run_battle_finished.bind(battle, node_id))
	current_battle = battle
	level_select.hide()
	run_map_screen.close_map()
	add_child(battle)
	if not battle.initialization_succeeded:
		current_battle = null
		remove_child(battle)
		battle.queue_free()
		run_controller.battle_open = false
		run_controller.error_message = "The encounter could not load. Your entry checkpoint is safe."
		run_map_screen.open_map()


func _on_run_battle_finished(victory: bool, members: Array[Dictionary], inventory: Array[String], battle: TacticalBattleScript, node_id: int) -> void:
	if battle != current_battle:
		return
	if not run_controller.finish_battle(node_id, victory, members, inventory):
		# Keep the result alive if disk writing fails; the finished battle can be retried safely.
		_pending_run_result = {"victory": victory, "members": members, "inventory": inventory, "node_id": node_id}
		battle.levels_button.text = "Retry saving result"
		battle.levels_button.tooltip_text = run_controller.error_message
		battle.levels_button.pressed.disconnect(battle._on_levels_button_pressed)
		battle.levels_button.pressed.connect(_retry_run_result)
		return
	_close_finished_run_battle()


func _retry_run_result() -> void:
	if _pending_run_result.is_empty():
		return
	var members: Array[Dictionary] = []
	members.assign(_pending_run_result.members)
	var inventory: Array[String] = []
	inventory.assign(_pending_run_result.inventory)
	if run_controller.finish_battle(int(_pending_run_result.node_id), bool(_pending_run_result.victory), members, inventory):
		_close_finished_run_battle()


func _close_finished_run_battle() -> void:
	var battle := current_battle
	current_battle = null
	_pending_run_result.clear()
	battle.shutdown_battle()
	remove_child(battle)
	battle.queue_free()
	run_map_screen.open_map()
