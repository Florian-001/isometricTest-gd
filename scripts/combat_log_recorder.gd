class_name CombatLogRecorder
extends RefCounted

## Collects one complete action, including nested reactions. Stored data contains
## stable IDs and values only, so it survives transactional battle replacement.
var active: Dictionary = {}
var _previous: Dictionary = {}
var _started_msec := 0


func begin(kind: String, actor: TacticalCharacter, round_number: int, control: String,
		description: String, checkpoint: Dictionary, units: Array[TacticalCharacter],
		diagnostics: String = "") -> void:
	if not active.is_empty():
		return
	_previous.clear()
	for unit in units:
		if is_instance_valid(unit):
			_previous[unit.scenario_unit_id] = _snapshot(unit)
	active = {
		"kind": kind, "actor_id": actor.scenario_unit_id,
		"actor_name": actor.get_combat_display_name(), "round": round_number,
		"control": control, "description": description, "checkpoint": checkpoint,
		"diagnostics": diagnostics, "events": [], "paths": {},
	}
	active.paths[actor.scenario_unit_id] = [actor.grid_cell]
	_started_msec = Time.get_ticks_msec()


func note(message: String) -> void:
	if not active.is_empty():
		active.events.append({"kind": "note", "text": message})


func observe(unit: TacticalCharacter) -> void:
	if active.is_empty() or not is_instance_valid(unit):
		return
	var unit_id := unit.scenario_unit_id
	var after := _snapshot(unit)
	var before: Dictionary = _previous.get(unit_id, after)
	var display_name := unit.get_combat_display_name()
	for key in ["health", "armor", "ap", "movement"]:
		if before[key] == after[key]:
			continue
		var change := float(after[key]) - float(before[key])
		var label: String = {"health": "HP", "armor": "Armor", "ap": "AP", "movement": "Movement"}[key]
		active.events.append({
			"kind": key, "unit_id": unit_id, "before": before[key], "after": after[key],
			"amount": change,
			"text": "%s: %s %s → %s (%+.2f)" % [display_name, label, before[key], after[key], change],
		})
	for key in ["cooldowns", "statuses", "reaction", "form"]:
		if before[key] == after[key]:
			continue
		active.events.append({
			"kind": key, "unit_id": unit_id, "before": before[key], "after": after[key],
			"text": "%s: %s %s → %s" % [display_name, key.capitalize(), _format_value(before[key]), _format_value(after[key])],
		})
	if before.cell != after.cell:
		if not active.paths.has(unit_id):
			active.paths[unit_id] = [before.cell]
		active.paths[unit_id].append(after.cell)
		active.events.append({"kind": "position", "unit_id": unit_id,
			"before": before.cell, "after": after.cell,
			"text": "%s: position %s → %s" % [display_name, before.cell, after.cell]})
	_previous[unit_id] = after


func finish(units: Array[TacticalCharacter], succeeded: bool) -> Dictionary:
	if active.is_empty():
		return {}
	for unit in units:
		observe(unit)
	var entry := active
	entry["succeeded"] = succeeded
	entry["duration_ms"] = Time.get_ticks_msec() - _started_msec
	var lines: Array[String] = [
		"Round %d · %s · %s" % [entry.round, entry.actor_name, entry.control],
		"%s: %s" % ["Completed" if succeeded else "Interrupted", entry.description],
		"Action: %s · Unit ID: %s · %d ms" % [entry.kind, entry.actor_id, entry.duration_ms],
	]
	for unit_id in entry.paths:
		var path: Array = entry.paths[unit_id]
		if path.size() > 1:
			var cells: Array[String] = []
			for cell in path:
				cells.append(str(cell))
			lines.append("Actual path (%s): %s" % [unit_id, " → ".join(cells)])
	lines.append("Outcomes:")
	if entry.events.is_empty():
		lines.append("No combat state changes.")
	for event in entry.events:
		lines.append(event.text)
	if not str(entry.diagnostics).is_empty():
		lines.append("\nAI decision:\n%s" % entry.diagnostics)
	entry["text"] = "\n".join(lines)
	active = {}
	_previous.clear()
	return entry


func _snapshot(unit: TacticalCharacter) -> Dictionary:
	var statuses: Array[String] = []
	for status in unit.get_active_statuses():
		if status.definition != null:
			statuses.append("%s ×%d (%s; source %s)" % [status.definition.display_name,
				status.stack_count, "battle" if status.definition.lasts_until_battle_end else "%d turns" % status.remaining_turns,
				status.source_unit.scenario_unit_id if is_instance_valid(status.source_unit) else "none"])
	return {"health": unit.current_health, "armor": unit.current_armor,
		"ap": unit.action_points, "movement": unit.remaining_movement,
		"cooldowns": unit.get_ability_cooldowns().duplicate(), "statuses": statuses,
		"cell": unit.grid_cell, "reaction": unit.opportunity_reaction_available,
		"form": "Defeated" if unit.current_health <= 0 else "Bone pile" if unit.is_bone_pile else "Alive"}


func _format_value(value: Variant) -> String:
	if value is Array:
		return ", ".join(value) if not value.is_empty() else "none"
	if value is Dictionary:
		var items: Array[String] = []
		for key in value:
			items.append("%s: %s" % [str(key).get_file().get_basename(), value[key]])
		return ", ".join(items) if not items.is_empty() else "none"
	return str(value)
