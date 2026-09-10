@tool
class_name RunConfig
extends Resource

@export_category("Map and Party")
@export var display_name: String = "The Ascent"
@export var map_settings: RunMapSettings
@export var starting_party: PackedScene
## Independent friendly character scenes offered by the starting hub.
@export var starting_character_roster: Array[PackedScene] = []
@export_tool_button("Validate Starting Roster") var validate_roster_button: Callable = _print_roster_report
@export var starting_gold: int = 50
@export_category("Encounter Catalog")
@export var normal_encounters: Array[RunEncounterDefinition] = []
@export var elite_encounters: Array[RunEncounterDefinition] = []
@export var boss_encounter: RunEncounterDefinition
@export_category("Combat Progression")
## Inclusive map-floor ranges. Empty stages and overrides preserve legacy encounter selection.
@export var combat_stages: Array[RunCombatStage] = []
## Optional replacements for a single floor's CR, enemy pool, or both.
@export var floor_overrides: Array[RunCombatFloorOverride] = []
@export_tool_button("Validate Combat Progression") var validate_progression_button: Callable = _print_progression_report
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
	return validate_configuration().errors.is_empty()


func is_linear() -> bool:
	return map_settings != null and map_settings.layout == RunMapSettings.Layout.LINEAR_COMBAT


func combat_floor_count() -> int:
	return map_settings.combat_floor_count() if map_settings != null else RunMapGenerator.ROOM_FLOORS


func progression_encounters() -> Array[RunEncounterDefinition]:
	return normal_encounters if is_linear() else normal_encounters + elite_encounters


func validate_configuration(party_slots: int = -1) -> Dictionary:
	var errors: Array[String] = []
	if map_settings == null or normal_encounters.is_empty():
		errors.append("Assign map settings and normal encounters.")
	if map_settings != null:
		errors.append_array(map_settings.validate())
	if not is_linear() and (elite_encounters.is_empty() or boss_encounter == null):
		errors.append("The Ascent requires elite encounters and a boss.")
	var encounters := progression_encounters().duplicate()
	if not is_linear():
		encounters.append(boss_encounter)
	for encounter in encounters:
		if encounter == null or encounter.battle_map == null or not encounter.battle_map.is_configured():
			errors.append("Every encounter needs a configured battle map.")
		elif is_linear() and (encounter.enemy_multiplier != 1.0 or not encounter.chief_node_name.is_empty()):
			errors.append("Linear combats require normal encounters with a 1.0 multiplier and no chief.")
	var paths := {}
	for item in equipment_pool:
		if item == null or item.resource_path.is_empty():
			errors.append("Every equipment pool item needs a saved resource.")
			continue
		paths[item.resource_path] = true
	if shop_price <= 0 or (not is_linear() and (paths.size() < shop_offer_count or unknown_combat_weight + unknown_treasure_weight + unknown_rest_weight <= 0)):
		errors.append("Provide enough distinct shop items, a positive shop price, and positive total unknown-room weight.")
	var slots := maxi(0, party_slots)
	if party_slots < 0 and starting_party != null and starting_party.can_instantiate():
		var party := starting_party.instantiate()
		for child in party.get_children():
			if child is TacticalCharacter:
				slots += 1
				if not child.is_friendly():
					errors.append("The starting party must contain only friendly characters.")
				else:
					errors.append_array(CharacterClassProgression.validate_levels(child.get_class_levels(), true))
					errors.append_array(child.get_passive_validation_errors())
		party.free()
	if slots == 0:
		errors.append("The starting party must contain characters.")
	for encounter in encounters:
		if encounter != null:
			var capacity_error := validate_encounter_capacity(encounter.battle_map, slots)
			if not capacity_error.is_empty():
				errors.append("%s: %s" % [encounter.display_name, capacity_error])
	var progression := RunCombatProgression.validate(self, slots)
	errors.append_array(progression.errors)
	return {"errors": errors, "warnings": progression.warnings}


## Read scene data without entering the tree or sharing mutable character instances.
func inspect_starting_roster() -> Dictionary:
	var entries: Array[Dictionary] = []
	var errors: Array[String] = []
	var ids := {}
	var classes: Array[CharacterClassLevel] = []
	for scene in starting_character_roster:
		if scene == null or scene.resource_path.is_empty() or scene.resource_path.contains("::") or not scene.can_instantiate():
			errors.append("Every roster entry needs a saved character scene.")
			continue
		var instance := scene.instantiate()
		if not instance is TacticalCharacter or not instance.is_friendly():
			errors.append("Roster scenes must have a friendly TacticalCharacter root.")
			instance.free()
			continue
		var character := instance as TacticalCharacter
		var id := character.scenario_unit_id
		if id.strip_edges().is_empty() or ids.has(id):
			errors.append("Roster characters need unique, nonempty scenario unit IDs.")
		ids[id] = true
		errors.append_array(character.get_passive_validation_errors())
		var levels := character.get_class_levels()
		errors.append_array(CharacterClassProgression.validate_levels(levels, true))
		if character.get_character_level() != 1 or character.override_template_abilities:
			errors.append("%s must start at level 1 with Developer Ability Override disabled." % character.name)
		# Validate IDs across different characters while allowing the same shared class asset.
		for allocation in levels:
			if allocation == null:
				continue
			for existing in classes:
				if allocation.character_class != null and existing.character_class != null and allocation.character_class != existing.character_class and allocation.character_class.class_id == existing.character_class.class_id:
					errors.append("Different roster class assets share the same class ID.")
			classes.append(allocation)
		var abilities: Array[String] = []
		for ability in character.get_abilities():
			var source_text := character.get_ability_source_text(ability)
			abilities.append(ability.display_name if source_text.is_empty() else "%s (%s)" % [ability.display_name, source_text])
		entries.append({"id": id, "scene": scene, "name": str(character.name),
			"class_summary": CharacterClassProgression.get_summary(levels), "abilities": ", ".join(abilities),
			"art": character.facing_right_texture, "health": character.get_max_health(),
			"speed": character.get_effective_stat(UnitStat.Type.SPEED), "movement": character.get_movement_range()})
		instance.free()
	if entries.is_empty():
		errors.append("Add friendly character scenes to Starting Character Roster.")
	return {"entries": entries, "errors": errors}


## Count original party slots, including lost members, to preserve their spawn indices.
static func validate_encounter_capacity(definition: BattleMapDefinition, party_slots: int) -> String:
	if definition == null or not definition.is_configured() or not definition.map_scene.can_instantiate():
		return "Assign a configured battle map."
	if definition is BattleMapTemplateDefinition:
		return TemplateEncounterSetup.inspect_layout(definition, party_slots).error
	var instance := definition.map_scene.instantiate()
	if not instance is BattleMap or not instance.is_configured():
		instance.free()
		return "The encounter scene needs a configured BattleMap root."
	var spawns := instance.get_node_or_null("PartySpawns")
	var errors: Array[String] = []
	if spawns == null or spawns.get_child_count() < party_slots:
		errors.append("Provide at least %d PartySpawns, one per original party member." % party_slots)
	else:
		var occupied := {}
		for child in instance.get_walls().get_children():
			if child is TacticalWall:
				occupied[child.grid_cell] = true
		for child in instance.get_characters().get_children():
			if child is TacticalCharacter:
				occupied[child.starting_grid_cell] = true
		for index in range(party_slots):
			var spawn := spawns.get_child(index) as RunSpawnPoint
			if spawn == null:
				errors.append("Each party spawn must be a RunSpawnPoint.")
				continue
			if not instance.get_grid().is_in_bounds(spawn.grid_cell) or occupied.has(spawn.grid_cell):
				errors.append("Party spawn %d is outside the grid or overlaps another occupant." % (index + 1))
			occupied[spawn.grid_cell] = true
	instance.free()
	return " ".join(errors)


func _print_roster_report() -> void:
	var report := inspect_starting_roster()
	for message in report.errors:
		push_error(message)
	print("Starting roster: %d character(s), %d error(s)." % [report.entries.size(), report.errors.size()])


func _print_progression_report() -> void:
	var report := validate_configuration()
	for message in report.errors:
		push_error(message)
	for message in report.warnings:
		push_warning(message)
	print("Combat progression: %d error(s), %d warning(s)." % [report.errors.size(), report.warnings.size()])
