class_name TemplateEncounterSetup
extends RefCounted


static func inspect_layout(template: BattleMapTemplateDefinition, party_slots: int) -> Dictionary:
	if not template.is_configured() or not template.map_scene.can_instantiate():
		return {"error": "Assign a name and map scene to the template."}
	var instance := template.map_scene.instantiate()
	if not instance is BattleMap or not instance.is_configured():
		instance.free()
		return {"error": "Template scenes need a BattleMap root with Grid, Terrain, Walls, and Characters."}
	var map := instance as BattleMap
	var spawns := map.get_node_or_null("SpawnTiles") as BattleSpawnTiles
	if spawns == null:
		instance.free()
		return {"error": "Add a BattleSpawnTiles child named SpawnTiles to the template scene."}
	var errors := spawns.validate_layout(map.get_grid(), map.get_walls(), party_slots)
	if map.get_characters().get_child_count() != 0:
		errors.append("Template Characters must be empty. Paint spawn cells instead of placing combatants.")
	var result := {"error": " ".join(errors), "friendly_cells": spawns.friendly_cells.duplicate(),
		"enemy_cells": spawns.enemy_cells.duplicate()}
	instance.free()
	return result


static func create(template: BattleMapTemplateDefinition, party_slots: int, rng: RandomNumberGenerator) -> Dictionary:
	var layout := inspect_layout(template, party_slots)
	if not layout.error.is_empty():
		return layout
	var generated := EnemyEncounterGenerator.generate(template, layout.enemy_cells.size(), rng)
	if not generated.error.is_empty():
		return generated
	var cells: Array[Vector2i] = layout.enemy_cells.duplicate()
	for index in range(cells.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var swap := cells[index]
		cells[index] = cells[other]
		cells[other] = swap
	var enemies: Array[Dictionary] = []
	for index in range(generated.scenes.size()):
		var scene := generated.scenes[index] as PackedScene
		if scene.resource_path.is_empty() or scene.resource_path.contains("::"):
			return {"error": "Save every Enemy Pool scene as a separate .tscn file so encounters can be restored."}
		enemies.append({"scene": scene.resource_path, "cell": [cells[index].x, cells[index].y],
			"id": "template_enemy_%d" % index, "name": "Enemy%d" % (index + 1)})
	return {"error": "", "enemies": enemies, "total_cr": generated.total_cr}


## Validate concrete roster data without regenerating or consuming random values.
static func validate_saved(template: BattleMapTemplateDefinition, saved: Variant, party_slots: int) -> String:
	var layout := inspect_layout(template, party_slots)
	if not layout.error.is_empty():
		return layout.error
	if not saved is Dictionary or not saved.get("enemies") is Array or not _integer(saved.get("total_cr")):
		return "The saved template enemy setup is missing or invalid."
	var entries: Array = saved.enemies
	if entries.is_empty() or entries.size() > layout.enemy_cells.size():
		return "The saved enemy count does not fit this template's spawn cells."
	var inspected := EnemyEncounterGenerator.catalog(template)
	if not inspected.error.is_empty():
		return inspected.error
	var allowed := {}
	for entry in inspected.entries:
		allowed[entry.scene.resource_path] = entry.cr
	var occupied := {}
	var total := 0
	for index in range(entries.size()):
		var entry: Variant = entries[index]
		if not entry is Dictionary or not entry.get("scene") is String or not allowed.has(entry.scene):
			return "A saved enemy scene is missing from the template's allowed pool."
		if entry.get("id") != "template_enemy_%d" % index or entry.get("name") != "Enemy%d" % (index + 1):
			return "Saved template enemy identities are invalid."
		var raw_cell: Variant = entry.get("cell")
		if not raw_cell is Array or raw_cell.size() != 2 or not _integer(raw_cell[0]) or not _integer(raw_cell[1]):
			return "A saved enemy spawn cell is invalid."
		var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
		if not layout.enemy_cells.has(cell) or occupied.has(cell):
			return "Saved enemies must occupy distinct authored enemy spawn cells."
		occupied[cell] = true
		total += int(allowed[entry.scene])
	if total != int(saved.total_cr) or total > template.combat_rating:
		return "Saved enemy CR no longer matches the template budget or enemy ratings."
	return ""


static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))
