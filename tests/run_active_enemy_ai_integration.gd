extends SceneTree

const TIMEOUT_MSEC := 12000

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var battle_scene := load("res://scenes/battle.tscn") as PackedScene
	var battle := battle_scene.instantiate() as TacticalBattle
	battle.map_definition = load(
		"res://resources/maps/terrain_showcase.tres"
	) as BattleMapDefinition
	battle.center_camera_on_start = false
	get_root().add_child(battle)
	await process_frame

	_check(battle.initialization_succeeded, "the Terrain Showcase battle should initialize")
	var melee_enemy := battle.characters_container.get_node_or_null(
		"MeleeEnemy"
	) as TacticalCharacter
	_check(melee_enemy != null, "the Terrain Showcase should contain its Goblin Warrior")
	if melee_enemy == null:
		await _finish(battle)
		return

	for unit in battle._characters:
		unit.movement_animation_speed = 1000.0
	var starting_cell := melee_enemy.grid_cell
	var saw_active_move := false
	var saw_strike := false
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline and not saw_strike and not battle._combat_over:
		for entry in battle._ai_debug_history:
			if not entry.contains("· MeleeEnemy ·"):
				continue
			_check(
				not entry.contains(": Hold ->"),
				"the Goblin Warrior should not Hold while it can advance or Strike\n%s" % entry
			)
			saw_active_move = saw_active_move or entry.contains(": Move ->")
			saw_strike = saw_strike or entry.contains(": Cast Strike ")
		if battle.turn_manager.is_player_turn() and not battle._movement_locked:
			battle._on_end_turn_pressed()
		await process_frame

	_check(saw_active_move, "the Goblin Warrior should advance in the rendered battle")
	_check(melee_enemy.grid_cell != starting_cell, "the rendered Goblin Warrior should leave its authored cell")
	_check(
		saw_strike,
		"the Goblin Warrior should eventually reach range and choose Strike "
		+ "(round %d, cell %s, current %s)\n%s" % [
			battle.turn_manager.round_number,
			melee_enemy.grid_cell,
			battle.turn_manager.current_unit.name if battle.turn_manager.current_unit != null else "none",
			"\n---\n".join(battle._ai_debug_history),
		]
	)
	await _finish(battle)


func _finish(battle: TacticalBattle) -> void:
	battle.queue_free()
	await process_frame
	if _failed:
		quit(1)
	else:
		print("ACTIVE_ENEMY_AI_INTEGRATION_OK")
		quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
