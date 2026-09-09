class_name TurnManager
extends Node

signal turn_started(unit: TacticalCharacter)
## Emitted before status ticks and action resets so terrain can apply turn-start statuses first.
signal turn_starting(unit: TacticalCharacter)
signal turn_ended(unit: TacticalCharacter)
signal turn_order_changed(order: Array[TacticalCharacter])
signal round_started(round_number: int)

var turn_order: Array[TacticalCharacter] = []
var current_unit: TacticalCharacter
var current_index: int = -1
var round_number: int = 1
var _scene_indices: Dictionary = {}


func start_combat(units: Array[TacticalCharacter]) -> void:
	turn_order.clear()
	_scene_indices.clear()
	for index in range(units.size()):
		var unit := units[index]
		_scene_indices[unit] = index
		if not _is_living(unit):
			continue
		turn_order.append(unit)

	_sort_turn_order()

	round_number = 1
	current_index = 0 if not turn_order.is_empty() else -1
	current_unit = turn_order[current_index] if current_index >= 0 else null
	turn_order_changed.emit(get_rotating_order())
	_reset_opportunity_reactions()
	round_started.emit(round_number)
	_start_current_turn()


func end_current_turn() -> void:
	if current_unit == null or turn_order.is_empty():
		return
	var ended_unit := current_unit
	ended_unit.advance_status_durations()
	turn_ended.emit(ended_unit)

	var next_index := current_index
	var wrapped := false
	var found_next := false
	for _step in range(turn_order.size()):
		next_index += 1
		if next_index >= turn_order.size():
			next_index = 0
			wrapped = true
		if _is_living(turn_order[next_index]):
			found_next = true
			break

	if not found_next:
		current_index = -1
		current_unit = null
		turn_order_changed.emit(get_rotating_order())
		return

	if wrapped:
		round_number += 1
		_rebuild_living_turn_order()
		if turn_order.is_empty():
			current_index = -1
			current_unit = null
			turn_order_changed.emit(get_rotating_order())
			return
		current_index = 0
		current_unit = turn_order[0]
		turn_order_changed.emit(get_rotating_order())
		_reset_opportunity_reactions()
		round_started.emit(round_number)
	else:
		current_index = next_index
		current_unit = turn_order[current_index]
		turn_order_changed.emit(get_rotating_order())
	_start_current_turn()


func stop_combat() -> void:
	current_index = -1
	current_unit = null
	turn_order_changed.emit(get_rotating_order())


func remove_unit(unit: TacticalCharacter) -> void:
	if not is_instance_valid(unit):
		return
	var removed_index := turn_order.find(unit)
	_scene_indices.erase(unit)
	if removed_index < 0:
		return
	var removed_current := current_unit == unit
	turn_order.remove_at(removed_index)
	if removed_current:
		current_unit = null
		current_index = -1
	elif is_instance_valid(current_unit):
		current_index = turn_order.find(current_unit)
		if current_index < 0:
			current_unit = null
	else:
		current_unit = null
		current_index = -1
	turn_order_changed.emit(get_rotating_order())


func get_rotating_order() -> Array[TacticalCharacter]:
	var rotating: Array[TacticalCharacter] = []
	if turn_order.is_empty():
		return rotating
	var start_index := current_index if current_index >= 0 else 0
	for offset in range(turn_order.size()):
		var index := (start_index + offset) % turn_order.size()
		var unit := turn_order[index]
		if _is_living(unit):
			rotating.append(unit)
	return rotating


func is_player_turn() -> bool:
	return _is_living(current_unit) and current_unit.is_friendly()


func notify_unit_state_changed() -> void:
	turn_order_changed.emit(get_rotating_order())


func capture_state(
	all_units: Array[TacticalCharacter],
	action_boundary := false
) -> Dictionary:
	var order_ids: Array[String] = []
	for unit in turn_order:
		if is_instance_valid(unit):
			order_ids.append(unit.scenario_unit_id)
	var scene_order_ids: Array[String] = []
	for unit in all_units:
		if is_instance_valid(unit):
			scene_order_ids.append(unit.scenario_unit_id)
	return {
		"round": round_number,
		"action_boundary": action_boundary,
		"current_index": current_index,
		"current_unit": (
			current_unit.scenario_unit_id
			if is_instance_valid(current_unit)
			else ""
		),
		"order": order_ids,
		"scene_order": scene_order_ids,
	}


func restore_state(state: Dictionary, units_by_id: Dictionary) -> bool:
	turn_order.clear()
	_scene_indices.clear()
	var scene_order: Array = state.get("scene_order", [])
	for index in range(scene_order.size()):
		var scene_unit := units_by_id.get(str(scene_order[index])) as TacticalCharacter
		if scene_unit != null:
			_scene_indices[scene_unit] = index
	for unit_id in state.get("order", []):
		var ordered_unit := units_by_id.get(str(unit_id)) as TacticalCharacter
		if ordered_unit == null:
			return false
		turn_order.append(ordered_unit)
	round_number = maxi(1, int(state.get("round", 1)))
	current_unit = units_by_id.get(str(state.get("current_unit", ""))) as TacticalCharacter
	current_index = int(state.get("current_index", -1))
	if current_unit == null:
		current_index = -1
	elif current_index < 0 or current_index >= turn_order.size() or turn_order[current_index] != current_unit:
		current_index = turn_order.find(current_unit)
		if current_index < 0:
			return false
	turn_order_changed.emit(get_rotating_order())
	round_started.emit(round_number)
	return true


func _start_current_turn() -> void:
	var starting_unit := current_unit
	if not _is_living(starting_unit):
		return
	var was_bone_pile := starting_unit.is_bone_pile
	starting_unit.expire_turn_start_statuses()
	turn_starting.emit(starting_unit)
	if current_unit != starting_unit:
		return
	starting_unit.process_status_turn_start()
	if current_unit != starting_unit:
		return
	if not _is_living(starting_unit):
		call_deferred("_advance_defeated_current_unit", starting_unit)
		return
	if was_bone_pile and starting_unit.is_bone_pile:
		starting_unit.reform_from_bones()
	if starting_unit.is_bone_pile:
		# Collapsing during this turn's hazards must wait for the next turn.
		call_deferred("_advance_defeated_current_unit", starting_unit)
		return
	starting_unit.reset_movement()
	starting_unit.reset_ability_action()
	turn_started.emit(starting_unit)


func _advance_defeated_current_unit(unit: TacticalCharacter) -> void:
	if current_unit == unit and (not _is_living(unit) or unit.is_bone_pile):
		end_current_turn()


func _is_living(unit: Variant) -> bool:
	return (
		is_instance_valid(unit)
		and unit is TacticalCharacter
		and (unit as TacticalCharacter).current_health > 0
	)


func _rebuild_living_turn_order() -> void:
	var living_units: Array[TacticalCharacter] = []
	for unit in turn_order:
		if _is_living(unit):
			living_units.append(unit)
	turn_order = living_units
	_sort_turn_order()


func _sort_turn_order() -> void:
	turn_order.sort_custom(func(a: TacticalCharacter, b: TacticalCharacter) -> bool:
		var initiative_a := a.get_initiative()
		var initiative_b := b.get_initiative()
		if initiative_a != initiative_b:
			return initiative_a > initiative_b
		return int(_scene_indices.get(a, 999999)) < int(_scene_indices.get(b, 999999))
	)


func _reset_opportunity_reactions() -> void:
	for unit in turn_order:
		if _is_living(unit):
			unit.reset_opportunity_reaction()
