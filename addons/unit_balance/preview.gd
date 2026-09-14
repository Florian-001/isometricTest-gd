@tool
extends RefCounted


static func calculate(store: RefCounted, path: String, attack_path := "") -> Dictionary:
	var definition := store.draft(path) as EnemyDefinition
	var equipment: Array[ItemDefinition] = []
	for item in definition.starting_equipment:
		if item != null:
			equipment.append(store.draft(item.resource_path) if store.states.has(item.resource_path) else item)
	definition.starting_equipment = equipment
	var actor := TacticalCharacter.new()
	actor.definition = definition
	actor.current_health = actor.get_max_health()
	var result := {"hp": actor.get_max_health(), "armor": actor.get_max_armor(), "move": actor.get_movement_range(), "initiative": actor.get_initiative(), "equipment": {}, "attack": "", "attack_path": "", "per_hit": "—", "hits": "—", "total": "—", "range": "—", "explanation": "No damaging ability", "abilities": [], "available": false}
	for stat in [UnitStat.Type.STRENGTH, UnitStat.Type.DEXTERITY, UnitStat.Type.INTELLIGENCE, UnitStat.Type.CONSTITUTION, UnitStat.Type.SPEED]:
		result["effective_" + UnitStat.get_display_name(stat).to_lower()] = actor.get_effective_stat(stat)
	for slot in ItemDefinition.EquipmentSlot.values():
		var occupant := actor.get_slot_occupant(slot)
		# Drafts do not own a resource path; map them by the matching source index.
		var source_path := ""
		if occupant != null:
			var index := equipment.find(occupant)
			if index >= 0:
				source_path = store.states[path].starting_equipment.filter(func(p): return not str(p).is_empty())[index]
		result.equipment[slot] = source_path
	var selected: AbilityDefinition
	for ability in actor.get_abilities():
		if ability == null or not ability.has_damage():
			continue
		result.abilities.append(ability.resource_path)
		if ability.resource_path == attack_path:
			selected = ability
	if selected == null:
		for ability in actor.get_abilities():
			if ability != null and ability.has_damage() and actor.can_use_ability(ability):
				selected = ability
				break
	if selected == null and not result.abilities.is_empty():
		selected = load(result.abilities[0])
	if selected != null:
		result.attack = selected.display_name
		result.attack_path = selected.resource_path
		result.available = actor.can_use_ability(selected)
		result.range = selected.get_effective_range(actor)
		if result.available:
			result.per_hit = selected.calculate_hit_damage(actor)
			result.hits = selected.get_hit_count()
			result.total = selected.calculate_damage(actor)
			result.explanation = selected.get_damage_calculation_description(actor)
		else:
			result.explanation = "Unavailable: " + actor.get_ability_unavailable_reason(selected)
	result.passives = actor.get_passive_description()
	actor.free()
	return result
