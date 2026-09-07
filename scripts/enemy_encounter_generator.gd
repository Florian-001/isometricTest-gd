class_name EnemyEncounterGenerator
extends RefCounted


## Scene inspection is deliberately independent of the battle tree and global random state.
static func catalog(template: BattleMapTemplateDefinition) -> Dictionary:
	var entries: Array[Dictionary] = []
	var seen := {}
	if template.combat_rating < 1:
		return {"error": "Map Combat Rating must be a positive whole number."}
	for scene in template.enemy_pool:
		if scene == null or not scene.can_instantiate():
			return {"error": "Assign an enemy scene to every Enemy Pool entry, or remove empty entries."}
		var key: Variant = scene.resource_path if not scene.resource_path.is_empty() else scene.get_instance_id()
		if seen.has(key):
			continue
		seen[key] = true
		var instance := scene.instantiate()
		if not instance is TacticalCharacter:
			instance.free()
			return {"error": "Enemy Pool scenes must have a TacticalCharacter root."}
		var actor := instance as TacticalCharacter
		var definition := actor.definition as EnemyDefinition
		if definition == null or definition.faction != CharacterDefinition.Faction.ENEMY or definition.combat_rating < 1:
			instance.free()
			return {"error": "Each enemy scene needs an EnemyDefinition with enemy faction and positive CR."}
		entries.append({"scene": scene, "cr": definition.combat_rating})
		instance.free()
	if entries.is_empty():
		return {"error": "Add at least one enemy scene to the template's Enemy Pool."}
	return {"error": "", "entries": entries}


static func generate(template: BattleMapTemplateDefinition, capacity: int, rng: RandomNumberGenerator) -> Dictionary:
	var inspected := catalog(template)
	if not inspected.error.is_empty():
		return inspected
	if capacity < 1:
		return {"error": "Paint at least one enemy spawn cell."}
	var entries: Array = inspected.entries
	var min_cr := template.combat_rating + 1
	for entry in entries:
		min_cr = mini(min_cr, int(entry.cr))
	if min_cr > template.combat_rating:
		return {"error": "Map CR cannot afford any allowed enemy. Increase map CR or add a cheaper enemy."}
	# Sparse reachable totals avoid allocating an array proportional to a large authored CR.
	# Counts are bounded by both spawn capacity and the cheapest enemy.
	var max_count := mini(capacity, template.combat_rating / min_cr)
	var reachable: Array[Dictionary] = [{0: true}]
	var best_total := 0
	for count in range(1, max_count + 1):
		var totals := {}
		for previous: int in reachable[count - 1]:
			for entry in entries:
				var total := previous + int(entry.cr)
				if total <= template.combat_rating:
					totals[total] = true
					best_total = maxi(best_total, total)
		reachable.append(totals)
	var counts: Array[int] = []
	for count in range(1, reachable.size()):
		if reachable[count].has(best_total):
			counts.append(count)
	var remaining_count := counts[rng.randi_range(0, counts.size() - 1)]
	var remaining_total := best_total
	var selected: Array[PackedScene] = []
	while remaining_count > 0:
		var choices: Array[Dictionary] = []
		for entry in entries:
			if reachable[remaining_count - 1].has(remaining_total - int(entry.cr)):
				choices.append(entry)
		var chosen := choices[rng.randi_range(0, choices.size() - 1)]
		selected.append(chosen.scene)
		remaining_total -= int(chosen.cr)
		remaining_count -= 1
	return {"error": "", "scenes": selected, "total_cr": best_total}
