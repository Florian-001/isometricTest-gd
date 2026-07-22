class_name EnemyTurnPlan
extends RefCounted

enum Sequence {
	HOLD,
	MOVE_ONLY,
	CAST_ONLY,
	MOVE_CAST,
	CAST_MOVE,
	MOVE_CAST_MOVE,
}

var sequence: Sequence = Sequence.HOLD
var pre_cast_path: Array[Vector2i] = []
var post_cast_path: Array[Vector2i] = []
var ability: AbilityDefinition
var target_cell := Vector2i(-1, -1)
var cast_origin := Vector2i(-1, -1)
var end_cell := Vector2i(-1, -1)
var ability_index := -1
var scene_target_index := 999999
var movement_cost := 0.0
var effect_score := 0.0
var position_score := 0.0
var preferred_delivery_score := 0.0
var immediate_score := 0.0
var counterplay_score := 0.0
var total_score := 0.0
var score_breakdown: Dictionary = {}


func get_sequence_name() -> String:
	match sequence:
		Sequence.MOVE_ONLY:
			return "Move"
		Sequence.CAST_ONLY:
			return "Cast"
		Sequence.MOVE_CAST:
			return "Move -> Cast"
		Sequence.CAST_MOVE:
			return "Cast -> Move"
		Sequence.MOVE_CAST_MOVE:
			return "Move -> Cast -> Move"
		_:
			return "Hold"


func get_start_cell(fallback: Vector2i) -> Vector2i:
	if not pre_cast_path.is_empty():
		return pre_cast_path[0]
	if not post_cast_path.is_empty():
		return post_cast_path[0]
	return fallback


func get_cast_cell(fallback: Vector2i) -> Vector2i:
	if not pre_cast_path.is_empty():
		return pre_cast_path[pre_cast_path.size() - 1]
	if not post_cast_path.is_empty():
		return post_cast_path[0]
	return fallback


func get_end_cell(fallback: Vector2i) -> Vector2i:
	if not post_cast_path.is_empty():
		return post_cast_path[post_cast_path.size() - 1]
	if not pre_cast_path.is_empty():
		return pre_cast_path[pre_cast_path.size() - 1]
	return fallback


func get_debug_summary() -> String:
	var action := get_sequence_name()
	if ability != null:
		action += " %s from %s @ %s" % [ability.display_name, cast_origin, target_cell]
	action += " -> %s" % end_cell
	return "%s | %.2f = %.2f effect + %.2f position + %.2f style - %.2f reply" % [
		action,
		total_score,
		effect_score,
		position_score,
		preferred_delivery_score,
		counterplay_score,
	]
