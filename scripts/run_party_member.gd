class_name RunPartyMember
extends RefCounted

var id: String
var display_name: String
var setup: Dictionary
var health: int
var max_health: int
var equipment: Array[String] = []
var lost: bool = false

static func from_character(character: TacticalCharacter) -> RunPartyMember:
	var member := RunPartyMember.new()
	member.id = character.scenario_unit_id
	member.display_name = str(character.name)
	member.setup = character.capture_setup_state()
	member.max_health = character.get_max_health()
	member.health = member.max_health
	for item in character.get_equipped_items():
		member.equipment.append(item.resource_path)
	return member

func to_data() -> Dictionary:
	return {"id": id, "name": display_name, "setup": setup.duplicate(true), "health": health,
		"max_health": max_health, "equipment": Array(equipment), "lost": lost}


func get_class_summary() -> String:
	return CharacterClassProgression.get_summary(CharacterClassProgression.from_data(setup.get("class_levels", [])))

static func from_data(data: Dictionary) -> RunPartyMember:
	for key in ["health", "max_health"]:
		if not RunState._integer(data.get(key)):
			return null
	if not data.get("setup") is Dictionary or not data.get("equipment") is Array:
		return null
	var member := RunPartyMember.new()
	member.id = str(data.get("id", ""))
	member.display_name = str(data.get("name", ""))
	member.setup = data.setup.duplicate(true)
	if not PassiveLoadout.validate_setup(member.setup).is_empty():
		return null
	if str(member.setup.get("id", "")) != member.id or not member.setup.get("stat_overrides") is Dictionary:
		return null
	for key in ["abilities", "equipment", "legacy_equipment", "cell"]:
		if not member.setup.get(key) is Array:
			return null
	if not member.setup.get("initial_facing") is float and not member.setup.get("initial_facing") is int:
		return null
	for key in ["strength", "dexterity", "intelligence", "constitution", "speed", "movement_range"]:
		var value: Variant = member.setup.stat_overrides.get(key)
		if not (value is int or value is float) or not is_finite(float(value)):
			return null
	for path in member.setup.abilities:
		if not path is String or not ResourceLoader.exists(path) or not load(path) is AbilityDefinition:
			return null
	var definition_path := str(member.setup.get("definition", ""))
	if not ResourceLoader.exists(definition_path) or not load(definition_path) is CharacterDefinition:
		return null
	member.health = int(data.get("health", -1))
	member.max_health = int(data.get("max_health", 0))
	member.lost = bool(data.get("lost", false))
	if member.id.is_empty() or member.max_health <= 0 or member.health < 0 or member.health > member.max_health:
		return null
	if member.lost != (member.health == 0):
		return null
	for path in data.equipment:
		if not path is String or not ResourceLoader.exists(path) or not load(path) is ItemDefinition:
			return null
		member.equipment.append(path)
	if member.lost and not member.equipment.is_empty():
		return null
	var scene_path := str(member.setup.get("scene", ""))
	if not ResourceLoader.exists(scene_path) or not load(scene_path) is PackedScene:
		return null
	if not CharacterClassProgression.prepare_setup(member.setup).is_empty():
		return null
	return member
