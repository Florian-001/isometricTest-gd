extends SceneTree

const DIGIT_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
const KEYPAD_KEYS := [
	KEY_KP_1,
	KEY_KP_2,
	KEY_KP_3,
	KEY_KP_4,
	KEY_KP_5,
	KEY_KP_6,
	KEY_KP_7,
	KEY_KP_8,
	KEY_KP_9,
]

var _failed := false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_input_map()
	_test_ability_bar_slots()
	await _test_battle_keyboard_flow()
	if _failed:
		quit(1)
	else:
		print("BATTLE_SHORTCUT_INTEGRATION_OK")
		quit(0)


func _test_input_map() -> void:
	_check(InputMap.has_action(&"battle_end_turn"), "Input Map exposes battle_end_turn")
	_check(
		_action_has_physical_key(&"battle_end_turn", KEY_SPACE),
		"battle_end_turn uses Space"
	)
	for slot_index in range(9):
		var action := StringName("battle_ability_%d" % (slot_index + 1))
		_check(InputMap.has_action(action), "%s exists in the Input Map" % action)
		_check(
			_action_has_physical_key(action, DIGIT_KEYS[slot_index]),
			"%s uses the matching number-row key" % action
		)
		_check(
			_action_has_physical_key(action, KEYPAD_KEYS[slot_index]),
			"%s uses the matching keypad key" % action
		)


func _test_ability_bar_slots() -> void:
	var first := AbilityDefinition.new()
	first.display_name = "First"
	var second := AbilityDefinition.new()
	second.display_name = "Second"
	var definition := CharacterDefinition.new()
	var abilities: Array[AbilityDefinition] = [first, null, second]
	definition.abilities = abilities
	var unit := TacticalCharacter.new()
	unit.definition = definition
	unit.set_dev_ability_loadout(abilities)
	unit._ready()
	unit.reset_ability_action()
	var bar := (load("res://scenes/ability_bar.tscn") as PackedScene).instantiate() as AbilityBar
	bar.rebuild(unit, true)
	var entries := bar.get_node("Margin/HBox") as HBoxContainer
	_check(entries.get_child_count() == 2, "Ability Bar skips null abilities without skipping numbers")
	var first_button := entries.get_child(0) as Button
	var second_button := entries.get_child(1) as Button
	_check(first_button.text.begins_with("[1] First"), "the first visible ability shows [1]")
	_check(second_button.text.begins_with("[2] Second"), "the second visible ability shows [2]")
	_check(first_button.tooltip_text.contains("Shortcut: 1"), "ability tooltips show shortcuts")
	var selected: Array[AbilityDefinition] = []
	bar.ability_selected.connect(func(ability: AbilityDefinition) -> void:
		selected.append(ability)
	)
	_check(bar.activate_slot(0), "an enabled visible slot activates")
	_check(selected == [first], "slot activation emits the displayed ability")
	second_button.disabled = true
	_check(not bar.activate_slot(1), "a disabled slot does not activate")
	_check(selected.size() == 1, "disabled slots emit nothing")
	_check(not bar.activate_slot(8), "an empty in-range slot does not activate")
	_check(not bar.activate_slot(9), "slots beyond the nine shortcuts do not activate")
	bar.free()
	unit.free()


func _test_battle_keyboard_flow() -> void:
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres") as BattleMapDefinition
	root.add_child(battle)
	await process_frame
	_check(battle.initialization_succeeded, "shortcut battle initializes")
	var caster := battle.turn_manager.current_unit
	_check(is_instance_valid(caster) and caster.is_friendly(), "shortcut fixture starts on a player turn")
	if not is_instance_valid(caster) or not caster.is_friendly():
		_remove_battle(battle)
		return

	var first := AbilityDefinition.new()
	first.display_name = "First Shortcut"
	var second := AbilityDefinition.new()
	second.display_name = "Second Shortcut"
	var configured: Array[AbilityDefinition] = [first, second]
	caster.override_template_abilities = true
	caster.ability_overrides = configured
	caster.reset_ability_action()
	battle._set_movement_locked(false)
	battle._select_character(caster)
	battle._refresh_ability_bar()

	_send_key(KEY_1)
	_check(battle._selected_ability == first, "1 selects the first displayed ability")
	_send_key(KEY_KP_2)
	_check(battle._selected_ability == second, "keypad 2 selects the second displayed ability")
	_send_key(KEY_2)
	_check(battle._selected_ability == null, "pressing the selected slot again cancels targeting")
	_send_key(KEY_9)
	_check(battle._selected_ability == null, "an empty shortcut slot is harmless")

	caster.spend_ability_action()
	_send_key(KEY_1)
	_check(battle._selected_ability == null, "disabled abilities cannot be selected by shortcut")
	caster.reset_ability_action()
	battle._refresh_ability_bar()
	var reload_requests := [0]
	battle.battle_reload_requested.connect(func(_payload: Dictionary) -> void:
		reload_requests[0] += 1
	)
	battle.restart_button.grab_focus()

	battle.inventory_screen.show()
	_send_key(KEY_1)
	_check(battle._selected_ability == null, "ability shortcuts stay inactive behind Inventory")
	var active_before_blocked_space := battle.turn_manager.current_unit
	_send_key(KEY_SPACE)
	_check(battle.turn_manager.current_unit == active_before_blocked_space, "Space stays inactive behind Inventory")
	_check(reload_requests[0] == 0, "Inventory-blocked Space cannot activate focused HUD buttons")
	battle.inventory_screen.hide()

	battle._dev_open = true
	_send_key(KEY_1)
	_check(battle._selected_ability == null, "ability shortcuts stay inactive in developer mode")
	_send_key(KEY_SPACE)
	_check(reload_requests[0] == 0, "developer-mode Space cannot activate focused HUD buttons")
	battle._dev_open = false
	paused = true
	_send_key(KEY_SPACE)
	_check(battle.turn_manager.current_unit == active_before_blocked_space, "Space stays inactive while paused")
	_check(reload_requests[0] == 0, "paused Space cannot activate focused HUD buttons")
	paused = false
	battle.return_to_levels_dialog.show()
	_send_key(KEY_SPACE)
	_check(reload_requests[0] == 0, "dialog-blocked Space cannot activate focused HUD buttons")
	battle.return_to_levels_dialog.hide()

	battle._set_movement_locked(true)
	_send_key(KEY_SPACE)
	_check(battle.turn_manager.current_unit == active_before_blocked_space, "Space stays inactive while movement is locked")
	battle._set_movement_locked(false)
	_send_key(KEY_SPACE, true)
	_check(battle.turn_manager.current_unit == active_before_blocked_space, "a held Space repeat cannot end the turn")

	_send_key(KEY_1)
	_check(battle._selected_ability == first, "ability targeting can be restored before ending the turn")
	battle.restart_button.grab_focus()
	_send_key(KEY_SPACE)
	_check(battle.turn_manager.current_unit != active_before_blocked_space, "Space ends exactly the current player turn")
	_check(battle._selected_ability == null, "ending the turn clears keyboard-selected targeting")
	_check(reload_requests[0] == 0, "consumed Space does not activate the focused Restart button")
	_remove_battle(battle)


func _send_key(physical_keycode: Key, echo := false) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = physical_keycode
	press.pressed = true
	press.echo = echo
	root.push_input(press)
	var release := InputEventKey.new()
	release.physical_keycode = physical_keycode
	release.pressed = false
	root.push_input(release)


func _action_has_physical_key(action: StringName, physical_keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == physical_keycode:
			return true
	return false


func _remove_battle(battle: TacticalBattle) -> void:
	if not is_instance_valid(battle):
		return
	battle.shutdown_battle()
	if battle.get_parent() != null:
		battle.get_parent().remove_child(battle)
	battle.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
