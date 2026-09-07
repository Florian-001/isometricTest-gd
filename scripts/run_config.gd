class_name RunConfig
extends Resource

@export_category("Map and Party")
@export var map_settings: RunMapSettings
@export var starting_party: PackedScene
@export var starting_gold: int = 50
@export_category("Encounter Catalog")
@export var normal_encounters: Array[RunEncounterDefinition] = []
@export var elite_encounters: Array[RunEncounterDefinition] = []
@export var boss_encounter: RunEncounterDefinition
@export_category("Room Rewards")
@export var combat_gold: int = 15
@export var elite_gold: int = 30
@export var treasure_gold: int = 30
@export_range(0.0, 1.0, 0.05) var rest_fraction: float = 0.3
@export var equipment_pool: Array[ItemDefinition] = []
@export_category("Merchant")
@export_range(1, 6) var shop_offer_count: int = 3
@export var shop_price: int = 40
@export_category("Unknown Room Weights")
@export var unknown_combat_weight: int = 50
@export var unknown_treasure_weight: int = 25
@export var unknown_rest_weight: int = 25

func is_configured() -> bool:
	if starting_party == null or map_settings == null or normal_encounters.is_empty() or elite_encounters.is_empty() or boss_encounter == null:
		return false
	for encounter in normal_encounters + elite_encounters + [boss_encounter]:
		if encounter == null or encounter.battle_map == null or not encounter.battle_map.is_configured():
			return false
	var paths := {}
	for item in equipment_pool:
		if item == null or item.resource_path.is_empty():
			return false
		paths[item.resource_path] = true
	return paths.size() >= shop_offer_count and shop_price > 0 and unknown_combat_weight + unknown_treasure_weight + unknown_rest_weight > 0
