@tool
extends RefCounted


static func make(key: String, title: String, group: String, kind := "number", minimum := 0.0, maximum := INF, choices: Array = []) -> Dictionary:
	return {"key": key, "title": title, "group": group, "kind": kind, "min": minimum, "max": maximum, "choices": choices, "width": 122.0}


static func enemies() -> Array:
	var result := [make("display_name", "Enemy", "Identity", "text"), make("combat_rating", "CR", "Identity", "integer", 1)]
	for pair in [["strength", "STR"], ["dexterity", "DEX"], ["intelligence", "INT"], ["constitution", "CON"], ["speed", "Speed"]]:
		result.append(make(pair[0], pair[1], "Base stats", "integer", 1))
	result.append(make("movement_range", "Base move", "Base stats", "number", 0, 100))
	result.append(make("base_health_override", "HP override", "Base stats", "integer"))
	for pair in [[0, "Weapon"], [1, "Armor item"], [3, "Offhand"], [2, "Accessory"]]:
		var column := make("slot_" + str(pair[0]), pair[1], "Equipment", "item")
		column.slot = pair[0]
		column.width = 175.0
		result.append(column)
	for pair in [["effective_strength", "Final STR"], ["effective_dexterity", "Final DEX"], ["effective_intelligence", "Final INT"], ["effective_constitution", "Final CON"], ["effective_speed", "Final speed"]]:
		result.append(make(pair[0], pair[1], "Effective stats", "result"))
	for pair in [["hp", "Max HP"], ["armor", "Armor"], ["move", "Movement"], ["initiative", "Initiative"], ["attack", "Preview attack"], ["per_hit", "Damage / hit"], ["hits", "Hits"], ["total", "Potential total"], ["range", "Range"]]:
		result.append(make(pair[0], pair[1], "Results", "attack" if pair[0] == "attack" else "result"))
	for column in result:
		if column.key in ["combat_rating", "hits"]:
			column.width = 65.0
		elif column.group in ["Base stats", "Effective stats"]:
			column.width = 100.0
		elif column.group == "Results":
			column.width = 110.0
			if column.key == "attack":
				column.width = 160.0
			elif column.key == "total":
				column.width = 140.0
	return result


static func items() -> Array:
	return [make("display_name", "Item", "Identity", "text"), make("slot", "Slot", "Item", "enum", 0, 3, ["Weapon", "Armor", "Accessory", "Offhand"]), make("armor", "Armor", "Item", "integer"), make("weapon_damage", "Weapon damage", "Item", "integer"), make("weapon_type", "Weapon type", "Item", "enum", 0, 1, ["Melee", "Ranged"]), make("weapon_handedness", "Handedness", "Item", "enum", 0, 1, ["One handed", "Two handed"]), make("weapon_range_bonus", "Range bonus", "Item", "number")]


static func parse(column: Dictionary, value: String) -> Dictionary:
	if column.kind == "result":
		return {"error": column.title + " is calculated and cannot be edited."}
	if column.kind == "text":
		if value.strip_edges().is_empty() or "\n" in value or "\t" in value:
			return {"error": "Enter a non-empty, single-line name."}
		return {"value": value.strip_edges()}
	if column.kind in ["item", "attack"]:
		return {"value": value.strip_edges()}
	if column.kind == "enum":
		for index in range(column.choices.size()):
			if value.to_lower() == str(column.choices[index]).to_lower():
				return {"value": index}
	if not value.is_valid_float() or not is_finite(value.to_float()):
		return {"error": column.title + " needs a finite number."}
	var number := value.to_float()
	if number < column.min or number > column.max or (column.kind in ["integer", "enum"] and number != floorf(number)):
		return {"error": "Invalid value for " + column.title + ". Check its range and use whole numbers where required."}
	return {"value": int(number) if column.kind in ["integer", "enum"] else number}
