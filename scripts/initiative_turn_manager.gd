class_name TurnManager
extends Node

signal turn_started(unit: TacticalCharacter)
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
		round_started.emit(round_number)
	else:
		current_index = next_index
		current_unit = turn_order[current_index]
		turn_order_changed.emit(get_rotating_order())
	_start_current_turn()


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


func _start_current_turn() -> void:
	if not _is_living(current_unit):
		return
	current_unit.reset_movement()
	current_unit.reset_ability_action()
	turn_started.emit(current_unit)


func _is_living(unit: TacticalCharacter) -> bool:
	return is_instance_valid(unit) and unit.current_health > 0


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
