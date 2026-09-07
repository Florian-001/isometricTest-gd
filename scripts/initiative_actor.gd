@tool
class_name TacticalCharacter
extends Node2D

enum Facing {
	LEFT,
	RIGHT,
}

const STATUS_ICON_SIZE := 18.0
const STATUS_ICON_GAP := 3.0
const FALLBACK_STATUS_ICON_TOP := -79.0
const ARTWORK_STATUS_ICON_TOP := -139.0
const CHARACTER_ART_RECT := Rect2(-56.0, -104.0, 112.0, 112.0)
const CHARACTER_ART_HIT_RECT := Rect2(-36.0, -100.0, 72.0, 98.0)
const FALLBACK_HEALTH_BAR_RECT := Rect2(-23.0, -57.0, 46.0, 7.0)
const ARTWORK_HEALTH_BAR_RECT := Rect2(-27.0, -117.0, 54.0, 7.0)

signal health_changed(current_health: int, max_health: int)
signal movement_started(character)
signal movement_finished(character)
signal cell_entered(character, cell: Vector2i)
signal defeated(character)
signal movement_remaining_changed(remaining: float, maximum: float)
signal ability_availability_changed(available: bool)
signal opportunity_reaction_availability_changed(available: bool)
signal stats_changed
signal equipment_changed(slot: ItemDefinition.EquipmentSlot, item: ItemDefinition)
signal statuses_changed
signal class_progression_changed

@export_category("Scenario Identity")
## Stable identifier used by developer scenario saves and status-source references.
@export var scenario_unit_id: String = ""

@export_category("Character Template")
@export var definition: CharacterDefinition:
	set(value):
		definition = value
		_runtime_stats_initialized = false
		if Engine.is_editor_hint():
			notify_property_list_changed()
		queue_redraw()

@export_category("Enemy AI")
## Optional per-unit override. EnemyDefinition resources provide the normal bundled profile.
@export var enemy_ai_profile: EnemyAIProfile:
	set(value):
		enemy_ai_profile = value
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export_category("Unit Stats")
## Set to zero or higher to override the template's Constitution for this unit.
## Set to -1 to inherit the value from Character Template.
@export_range(-1, 999, 1, "or_greater") var constitution_override: int = -1:
	set(value):
		constitution_override = maxi(-1, value)
		if Engine.is_editor_hint():
			notify_property_list_changed()
		queue_redraw()

@export_custom(
	PROPERTY_HINT_NONE,
	"",
	PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
) var max_health: int:
	get:
		return get_max_health()

## Set to zero or higher to override the template's movement range for this unit.
## Set to -1 to inherit the value from Character Template.
@export_range(-1.0, 100.0, 0.5, "or_greater") var movement_range_override: float = -1.0

## Primary-stat overrides use -1 to inherit from the Character Template.
@export_range(-1, 999, 1, "or_greater") var strength_override: int = -1
@export_range(-1, 999, 1, "or_greater") var dexterity_override: int = -1
@export_range(-1, 999, 1, "or_greater") var intelligence_override: int = -1
@export_range(-1, 999, 1, "or_greater") var speed_override: int = -1

@export_category("Friendly Class Progression")
## Empty inherits the template's Starting Class at level one. Entries are independent per unit.
@export var class_level_overrides: Array[CharacterClassLevel] = []:
	set(value):
		class_level_overrides = CharacterClassProgression.copy_levels(value)
		class_progression_changed.emit()
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export_category("Developer Ability Override — Ignore Classes")
## Friendly developer bypass: replaces ALL class abilities. Enemies override their template loadout.
@export var override_template_abilities: bool = false
## Resize this list and choose New AbilityDefinition to author an inline, unit-specific ability.
## You can also drag existing ability .tres files here from the FileSystem dock.
@export var ability_overrides: Array[AbilityDefinition] = []

@export_category("Starting Equipment Overrides")
## Applied after the Character Template equipment. Matching slots replace inherited items.
@export var starting_equipment_overrides: Array[ItemDefinition] = []
## When enabled, Complete Equipment Overrides replaces the template loadout entirely.
## Missing slots are intentionally empty. Existing scenes keep the legacy layered behavior.
@export var use_complete_equipment_override: bool = false
@export var complete_equipment_overrides: Array[ItemDefinition] = []

@export_category("Placement and Presentation")
@export var facing_left_texture: Texture2D:
	set(value):
		facing_left_texture = value
		queue_redraw()
@export var facing_right_texture: Texture2D:
	set(value):
		facing_right_texture = value
		queue_redraw()
@export var initial_facing: Facing = Facing.RIGHT:
	set(value):
		initial_facing = value
		current_facing = value
		queue_redraw()
@export var starting_grid_cell: Vector2i = Vector2i.ZERO:
	set(value):
		starting_grid_cell = value
		if Engine.is_editor_hint():
			grid_cell = value
			_queue_editor_position_sync()
@export_range(20.0, 1000.0, 10.0) var movement_animation_speed: float = 260.0

var current_health: int = 0
var grid_cell: Vector2i = Vector2i.ZERO
var current_facing: Facing = Facing.RIGHT
var is_moving := false
var remaining_movement: float:
	get:
		return 0.0 if is_stunned() else _remaining_movement
var ability_available: bool:
	get:
		return _ability_available and can_use_abilities()
var opportunity_reaction_available: bool:
	get:
		return _opportunity_reaction_available and can_use_opportunity_reactions()
var _grid: IsometricGrid
var _defeat_emitted := false
## Run battles opt into permanent defeat; standalone encounters keep revival behavior.
var permanent_defeat: bool = false
var _remaining_movement := 0.0
var _ability_available := false
var _opportunity_reaction_available := true
var _equipped_items: Dictionary = {}
var _active_statuses: Array[ActiveStatus] = []
var _runtime_stats_initialized := false
var _editor_syncing_placement := false
var _editor_position_sync_queued := false
var _editor_cell_sync_queued := false
var _unit_name_visible := true
var _unit_name_label: Label


func _ready() -> void:
	_unit_name_label = get_node_or_null("UnitNameLabel") as Label
	_initialize_runtime_stats()
	grid_cell = starting_grid_cell
	current_facing = initial_facing
	current_health = get_max_health()
	_sync_map_presence()
	_refresh_unit_name_label()
	if Engine.is_editor_hint():
		set_notify_transform(true)
		_queue_editor_position_sync()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PATH_RENAMED and is_node_ready():
		_refresh_unit_name_label()
	if (
		what == NOTIFICATION_TRANSFORM_CHANGED
		and Engine.is_editor_hint()
		and is_node_ready()
		and not _editor_syncing_placement
		and not _editor_cell_sync_queued
	):
		_editor_cell_sync_queued = true
		call_deferred("_sync_editor_cell_from_position")


func _validate_property(property: Dictionary) -> void:
	if property.name == "position":
		property.usage = property.usage & ~PROPERTY_USAGE_STORAGE
	if property.name == "class_level_overrides" and not is_friendly():
		property.usage = property.usage & ~PROPERTY_USAGE_EDITOR


func _queue_editor_position_sync() -> void:
	if (
		not Engine.is_editor_hint()
		or not is_inside_tree()
		or _editor_syncing_placement
		or _editor_position_sync_queued
	):
		return
	_editor_position_sync_queued = true
	call_deferred("_sync_editor_position_from_cell")


func _sync_editor_position_from_cell() -> void:
	_editor_position_sync_queued = false
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var editor_grid := _get_editor_grid()
	if editor_grid == null:
		return
	_editor_syncing_placement = true
	global_position = editor_grid.grid_to_global(starting_grid_cell)
	grid_cell = starting_grid_cell
	_update_sorting()
	_editor_syncing_placement = false
	queue_redraw()


func _sync_editor_cell_from_position() -> void:
	_editor_cell_sync_queued = false
	if not Engine.is_editor_hint() or not is_inside_tree() or _editor_syncing_placement:
		return
	var editor_grid := _get_editor_grid()
	if editor_grid == null:
		return
	var snapped_cell := editor_grid.global_to_grid(global_position)
	snapped_cell.x = clampi(snapped_cell.x, 0, editor_grid.grid_size.x - 1)
	snapped_cell.y = clampi(snapped_cell.y, 0, editor_grid.grid_size.y - 1)
	_editor_syncing_placement = true
	starting_grid_cell = snapped_cell
	grid_cell = snapped_cell
	global_position = editor_grid.grid_to_global(snapped_cell)
	_update_sorting()
	_editor_syncing_placement = false
	queue_redraw()


func _get_editor_grid() -> IsometricGrid:
	if owner == null:
		return null
	return owner.get_node_or_null("Grid") as IsometricGrid


func initialize(grid: IsometricGrid) -> void:
	_initialize_runtime_stats()
	_grid = grid
	grid_cell = starting_grid_cell
	current_facing = initial_facing
	global_position = _grid.grid_to_global(grid_cell)
	_update_sorting()
	queue_redraw()


func is_friendly() -> bool:
	return definition != null and definition.faction == CharacterDefinition.Faction.FRIENDLY


func is_present_on_map() -> bool:
	return is_friendly() or current_health > 0


func _sync_map_presence() -> void:
	visible = is_present_on_map()


func set_unit_name_visible(value: bool) -> void:
	_unit_name_visible = value
	_refresh_unit_name_label()


func is_unit_name_visible() -> bool:
	return _unit_name_visible


func _refresh_unit_name_label() -> void:
	if not is_instance_valid(_unit_name_label):
		_unit_name_label = get_node_or_null("UnitNameLabel") as Label
	if _unit_name_label == null:
		return
	_unit_name_label.text = str(name)
	_unit_name_label.visible = _unit_name_visible


func set_facing(value: Facing) -> void:
	if current_facing == value:
		return
	current_facing = value
	queue_redraw()


func face_toward_world_position(world_position: Vector2) -> void:
	var horizontal_delta := world_position.x - global_position.x
	if is_zero_approx(horizontal_delta):
		return
	set_facing(Facing.LEFT if horizontal_delta < 0.0 else Facing.RIGHT)


func has_directional_artwork() -> bool:
	return facing_left_texture != null or facing_right_texture != null


func _get_facing_texture() -> Texture2D:
	var preferred := (
		facing_left_texture
		if current_facing == Facing.LEFT
		else facing_right_texture
	)
	if preferred != null:
		return preferred
	return facing_right_texture if facing_right_texture != null else facing_left_texture


func get_enemy_ai_profile() -> EnemyAIProfile:
	if enemy_ai_profile != null:
		return enemy_ai_profile
	if definition is EnemyDefinition:
		return (definition as EnemyDefinition).ai_profile
	return null


func get_movement_range() -> float:
	return UnitStat.get_scaling_rules().clamp_effective_movement_range(
		get_effective_stat(UnitStat.Type.MOVEMENT_RANGE)
	)


func _get_base_movement_range() -> float:
	if movement_range_override >= 0.0:
		return movement_range_override
	return definition.movement_range if definition != null else 0.0


func get_initiative() -> int:
	return UnitStat.get_scaling_rules().calculate_initiative(
		get_effective_stat(UnitStat.Type.SPEED)
	)


func get_base_stat(stat: UnitStat.Type) -> float:
	return _get_base_stat_for_sources(stat, true)


func _get_base_stat_for_sources(stat: UnitStat.Type, include_equipment: bool) -> float:
	match stat:
		UnitStat.Type.STRENGTH:
			if strength_override >= 0:
				return float(strength_override)
			return float(definition.strength) if definition != null else 0.0
		UnitStat.Type.DEXTERITY:
			if dexterity_override >= 0:
				return float(dexterity_override)
			return float(definition.dexterity) if definition != null else 0.0
		UnitStat.Type.INTELLIGENCE:
			if intelligence_override >= 0:
				return float(intelligence_override)
			return float(definition.intelligence) if definition != null else 0.0
		UnitStat.Type.CONSTITUTION:
			if constitution_override >= 0:
				return float(constitution_override)
			return float(definition.constitution) if definition != null else 1.0
		UnitStat.Type.SPEED:
			if speed_override >= 0:
				return float(speed_override)
			return float(definition.speed) if definition != null else 0.0
		UnitStat.Type.MOVEMENT_RANGE:
			return UnitStat.get_scaling_rules().calculate_speed_adjusted_base_movement(
				_get_base_movement_range(),
				_calculate_effective_stat(UnitStat.Type.SPEED, include_equipment)
			)
		_:
			return 0.0


func get_effective_stat(stat: UnitStat.Type) -> float:
	return _calculate_effective_stat(stat, true)


## Returns the same live stat calculation with item modifiers omitted. Active statuses,
## definition values, and per-instance overrides remain included for equipment comparisons.
func get_effective_stat_without_equipment(stat: UnitStat.Type) -> float:
	return _calculate_effective_stat(stat, false)


func _calculate_effective_stat(stat: UnitStat.Type, include_equipment: bool, include_statuses: bool = true) -> float:
	if stat == UnitStat.Type.NONE:
		return 0.0
	_initialize_runtime_stats()
	var flat_total := 0.0
	var percent_add_total := 0.0
	var percent_multiplier := 1.0
	for modifier in _get_all_modifiers(include_equipment, include_statuses):
		if modifier == null or modifier.stat != stat:
			continue
		match modifier.operation:
			StatModifierDefinition.Operation.FLAT:
				flat_total += modifier.value
			StatModifierDefinition.Operation.PERCENT_ADD:
				percent_add_total += modifier.value
			StatModifierDefinition.Operation.PERCENT_MULTIPLY:
				percent_multiplier *= maxf(0.0, 1.0 + modifier.value)
	var subtotal := _get_base_stat_for_sources(stat, include_equipment) + flat_total
	var percent_add_multiplier := maxf(0.0, 1.0 + percent_add_total)
	return maxf(0.0, subtotal * percent_add_multiplier * percent_multiplier)


func equip_item(item: ItemDefinition) -> ItemDefinition:
	if item == null:
		return null
	_initialize_runtime_stats()
	var previous_movement := get_movement_range()
	var previous_max_health := get_max_health()
	var replaced := get_equipped_item(item.slot)
	_equipped_items[item.slot] = item
	equipment_changed.emit(item.slot, item)
	_notify_stats_changed(previous_movement, previous_max_health)
	return replaced


func unequip_item(slot: ItemDefinition.EquipmentSlot) -> ItemDefinition:
	_initialize_runtime_stats()
	if not _equipped_items.has(slot):
		return null
	var previous_movement := get_movement_range()
	var previous_max_health := get_max_health()
	var removed := _equipped_items[slot] as ItemDefinition
	_equipped_items.erase(slot)
	equipment_changed.emit(slot, null)
	_notify_stats_changed(previous_movement, previous_max_health)
	return removed


func get_equipped_item(slot: ItemDefinition.EquipmentSlot) -> ItemDefinition:
	_initialize_runtime_stats()
	return _equipped_items.get(slot) as ItemDefinition


func get_equipped_items() -> Array[ItemDefinition]:
	_initialize_runtime_stats()
	var result: Array[ItemDefinition] = []
	for slot in [
		ItemDefinition.EquipmentSlot.WEAPON,
		ItemDefinition.EquipmentSlot.ARMOR,
		ItemDefinition.EquipmentSlot.ACCESSORY,
	]:
		var item := get_equipped_item(slot)
		if item != null:
			result.append(item)
	return result


func get_equipped_weapon() -> ItemDefinition:
	return get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON)


func get_weapon_for_ability(ability: AbilityDefinition) -> ItemDefinition:
	if ability == null:
		return null
	var required_weapon_type := ability.get_required_weapon_type()
	if required_weapon_type < 0:
		return null
	var weapon := get_equipped_weapon()
	if weapon == null or int(weapon.weapon_type) != required_weapon_type:
		return null
	return weapon


func has_equipped_weapon_type(weapon_type: ItemDefinition.WeaponType) -> bool:
	var weapon := get_equipped_weapon()
	return weapon != null and weapon.weapon_type == weapon_type


func get_equipped_weapon_type() -> int:
	var weapon := get_equipped_weapon()
	return int(weapon.weapon_type) if weapon != null else -1


func get_weapon_damage(required_weapon_type: int = -1) -> int:
	var weapon := get_equipped_item(ItemDefinition.EquipmentSlot.WEAPON)
	if weapon == null:
		return 0
	if required_weapon_type >= 0 and weapon.weapon_type != required_weapon_type:
		return 0
	return maxi(0, weapon.weapon_damage)


func can_use_ability(ability: AbilityDefinition) -> bool:
	return ability != null and ability.can_be_used_by(self)


func get_ability_unavailable_reason(ability: AbilityDefinition) -> String:
	return ability.get_unavailable_reason(self) if ability != null else "Ability unavailable"


func is_stunned() -> bool:
	_initialize_runtime_stats()
	for active_status in _active_statuses:
		if (
			active_status.definition != null
			and active_status.remaining_turns > 0
			and active_status.definition.blocks_actions()
		):
			return true
	return false


func can_move() -> bool:
	return current_health > 0 and not is_stunned()


func can_use_abilities() -> bool:
	return current_health > 0 and not is_stunned()


func can_use_opportunity_reactions() -> bool:
	return current_health > 0 and not is_stunned()


func apply_status(
	status_definition: StatusEffectDefinition,
	source: Object = null,
	source_unit: TacticalCharacter = null
) -> bool:
	if (
		status_definition == null
		or status_definition.status_id == &""
		or current_health <= 0
	):
		return false
	_initialize_runtime_stats()
	var previous_state := _capture_status_state()
	for active_status in _active_statuses:
		if (
			active_status.definition != null
			and active_status.definition.status_id == status_definition.status_id
		):
			active_status.definition = status_definition
			active_status.source = source
			active_status.source_unit = source_unit
			if active_status.source_unit == null and source is TacticalCharacter:
				active_status.source_unit = source as TacticalCharacter
			active_status.remaining_turns = status_definition.duration_turns
			active_status.processed_this_turn = false
			_notify_statuses_changed(previous_state)
			return true
	_active_statuses.append(ActiveStatus.new(status_definition, source, source_unit))
	_notify_statuses_changed(previous_state)
	return true


func remove_status(status_id: StringName) -> bool:
	_initialize_runtime_stats()
	for index in range(_active_statuses.size() - 1, -1, -1):
		var active_status := _active_statuses[index]
		if active_status.definition != null and active_status.definition.status_id == status_id:
			var previous_state := _capture_status_state()
			_active_statuses.remove_at(index)
			_notify_statuses_changed(previous_state)
			return true
	return false


func get_active_statuses() -> Array[ActiveStatus]:
	_initialize_runtime_stats()
	var result: Array[ActiveStatus] = []
	result.assign(_active_statuses)
	return result


func process_status_turn_start() -> void:
	_initialize_runtime_stats()
	for active_status in _active_statuses:
		if active_status.definition == null:
			continue
		active_status.processed_this_turn = true
		active_status.definition.apply_turn_start(self)
		if current_health <= 0:
			break


func advance_status_durations() -> void:
	_initialize_runtime_stats()
	if _active_statuses.is_empty():
		return
	var previous_state := _capture_status_state()
	var changed := false
	for index in range(_active_statuses.size() - 1, -1, -1):
		var active_status := _active_statuses[index]
		if not active_status.processed_this_turn:
			continue
		active_status.processed_this_turn = false
		active_status.remaining_turns -= 1
		changed = true
		if active_status.remaining_turns <= 0:
			_active_statuses.remove_at(index)
	if changed:
		_notify_statuses_changed(previous_state)


func get_abilities() -> Array[AbilityDefinition]:
	if override_template_abilities:
		return ability_overrides
	if is_friendly():
		var unlocked: Array[AbilityDefinition] = []
		for entry in get_class_levels():
			if entry == null or entry.character_class == null or entry.level < 1:
				continue
			for unlock in entry.character_class.get_sorted_unlocks():
				if unlock.ability != null and unlock.required_level >= 1 and unlock.required_level <= entry.level and not unlocked.has(unlock.ability):
					unlocked.append(unlock.ability)
		return unlocked
	if definition != null:
		return definition.abilities
	var empty_abilities: Array[AbilityDefinition] = []
	return empty_abilities


func get_class_levels() -> Array[CharacterClassLevel]:
	var result: Array[CharacterClassLevel] = []
	if not is_friendly():
		return result
	if not class_level_overrides.is_empty():
		return CharacterClassProgression.copy_levels(class_level_overrides)
	if definition.starting_class != null:
		result.append(CharacterClassLevel.create(definition.starting_class))
	return result


func get_character_level() -> int:
	if not is_friendly():
		return 0
	var total := 0
	for entry in get_class_levels():
		if entry != null:
			total += maxi(0, entry.level)
	return maxi(1, total)


## Level zero removes a class; removing the last class is rejected without changes.
func set_class_level(character_class: CharacterClassDefinition, level: int) -> bool:
	if not is_friendly() or character_class == null or level < 0:
		return false
	var levels := get_class_levels()
	var found := false
	for index in range(levels.size()):
		if levels[index] != null and levels[index].character_class != null and levels[index].character_class.class_id == character_class.class_id:
			if levels[index].character_class != character_class:
				return false
			found = true
			if level == 0:
				levels.remove_at(index)
			else:
				levels[index].level = level
			break
	if not found and level > 0:
		levels.append(CharacterClassLevel.create(character_class, level))
	if not CharacterClassProgression.validate_levels(levels).is_empty():
		return false
	class_level_overrides = levels
	return true


func set_dev_stat_override(stat: UnitStat.Type, value: float) -> void:
	var previous_movement := get_movement_range()
	var previous_max_health := get_max_health()
	match stat:
		UnitStat.Type.STRENGTH:
			strength_override = maxi(0, roundi(value))
		UnitStat.Type.DEXTERITY:
			dexterity_override = maxi(0, roundi(value))
		UnitStat.Type.INTELLIGENCE:
			intelligence_override = maxi(0, roundi(value))
		UnitStat.Type.CONSTITUTION:
			constitution_override = maxi(0, roundi(value))
		UnitStat.Type.SPEED:
			speed_override = maxi(0, roundi(value))
		UnitStat.Type.MOVEMENT_RANGE:
			movement_range_override = maxf(0.0, value)
		_:
			return
	_notify_stats_changed(previous_movement, previous_max_health)


func clear_dev_stat_override(stat: UnitStat.Type) -> void:
	var previous_movement := get_movement_range()
	var previous_max_health := get_max_health()
	match stat:
		UnitStat.Type.STRENGTH:
			strength_override = -1
		UnitStat.Type.DEXTERITY:
			dexterity_override = -1
		UnitStat.Type.INTELLIGENCE:
			intelligence_override = -1
		UnitStat.Type.CONSTITUTION:
			constitution_override = -1
		UnitStat.Type.SPEED:
			speed_override = -1
		UnitStat.Type.MOVEMENT_RANGE:
			movement_range_override = -1.0
		_:
			return
	_notify_stats_changed(previous_movement, previous_max_health)


func set_dev_ability_loadout(values: Array[AbilityDefinition]) -> void:
	override_template_abilities = true
	ability_overrides.assign(values)
	class_progression_changed.emit()


func reset_dev_ability_loadout() -> void:
	override_template_abilities = false
	ability_overrides.clear()
	class_progression_changed.emit()


func set_dev_equipment(slot: ItemDefinition.EquipmentSlot, item: ItemDefinition) -> void:
	if not use_complete_equipment_override:
		complete_equipment_overrides.assign(get_equipped_items())
		use_complete_equipment_override = true
	for index in range(complete_equipment_overrides.size() - 1, -1, -1):
		var existing := complete_equipment_overrides[index]
		if existing != null and existing.slot == slot:
			complete_equipment_overrides.remove_at(index)
	if item != null:
		complete_equipment_overrides.append(item)
	if item == null:
		unequip_item(slot)
	else:
		equip_item(item)


func reset_dev_equipment_to_template() -> void:
	var previous_movement := get_movement_range()
	var previous_max_health := get_max_health()
	use_complete_equipment_override = false
	complete_equipment_overrides.clear()
	starting_equipment_overrides.clear()
	_runtime_stats_initialized = false
	_initialize_runtime_stats()
	_notify_stats_changed(previous_movement, previous_max_health)
	for slot in [
		ItemDefinition.EquipmentSlot.WEAPON,
		ItemDefinition.EquipmentSlot.ARMOR,
		ItemDefinition.EquipmentSlot.ACCESSORY,
	]:
		equipment_changed.emit(slot, get_equipped_item(slot))


func set_grid_cell_immediate(cell: Vector2i) -> void:
	starting_grid_cell = cell
	_set_runtime_grid_cell_immediate(cell)


func _set_runtime_grid_cell_immediate(cell: Vector2i) -> void:
	grid_cell = cell
	if _grid != null:
		global_position = _grid.grid_to_global(cell)
	_update_sorting()
	queue_redraw()


func capture_setup_state() -> Dictionary:
	return {
		"id": scenario_unit_id,
		"name": str(name),
		"scene": scene_file_path,
		"definition": definition.resource_path if definition != null else "",
		"faction": int(definition.faction) if definition != null else -1,
		"cell": [starting_grid_cell.x, starting_grid_cell.y],
		"initial_facing": int(initial_facing),
		"stat_overrides": {
			"strength": strength_override,
			"dexterity": dexterity_override,
			"intelligence": intelligence_override,
			"constitution": constitution_override,
			"speed": speed_override,
			"movement_range": movement_range_override,
		},
		"override_abilities": override_template_abilities,
		"class_levels": CharacterClassProgression.to_data(get_class_levels()),
		"abilities": _resource_paths(ability_overrides),
		"complete_equipment": use_complete_equipment_override,
		"equipment": _resource_paths(complete_equipment_overrides),
		"legacy_equipment": _resource_paths(starting_equipment_overrides),
	}


func apply_setup_state(state: Dictionary) -> void:
	scenario_unit_id = str(state.get("id", ""))
	var definition_path := str(state.get("definition", ""))
	if ResourceLoader.exists(definition_path):
		definition = load(definition_path) as CharacterDefinition
	if is_friendly() and state.has("class_levels"):
		var class_errors := CharacterClassProgression.validate_data(state["class_levels"])
		if class_errors.is_empty():
			class_level_overrides = CharacterClassProgression.from_data(state["class_levels"])
		else:
			push_error("Invalid class setup: %s" % " ".join(class_errors))
	var cell_value: Array = state.get("cell", [0, 0])
	if cell_value.size() >= 2:
		starting_grid_cell = Vector2i(int(cell_value[0]), int(cell_value[1]))
	initial_facing = int(state.get("initial_facing", Facing.RIGHT))
	var stats: Dictionary = state.get("stat_overrides", {})
	strength_override = int(stats.get("strength", -1))
	dexterity_override = int(stats.get("dexterity", -1))
	intelligence_override = int(stats.get("intelligence", -1))
	constitution_override = int(stats.get("constitution", -1))
	speed_override = int(stats.get("speed", -1))
	movement_range_override = float(stats.get("movement_range", -1.0))
	override_template_abilities = bool(state.get("override_abilities", false))
	ability_overrides = _load_abilities(state.get("abilities", []))
	use_complete_equipment_override = bool(state.get("complete_equipment", false))
	complete_equipment_overrides = _load_items(state.get("equipment", []))
	starting_equipment_overrides = _load_items(state.get("legacy_equipment", []))
	_runtime_stats_initialized = false
	class_progression_changed.emit()


func capture_runtime_state() -> Dictionary:
	var statuses: Array[Dictionary] = []
	for active_status in _active_statuses:
		if active_status.definition == null:
			continue
		var source_resource := ""
		var source_kind := ""
		if active_status.source is Resource:
			source_resource = (active_status.source as Resource).resource_path
			source_kind = "resource"
		elif active_status.source is TacticalCharacter:
			source_kind = "unit"
		statuses.append({
			"definition": active_status.definition.resource_path,
			"remaining_turns": active_status.remaining_turns,
			"processed_this_turn": active_status.processed_this_turn,
			"source_kind": source_kind,
			"source_resource": source_resource,
			"source_unit": (
				active_status.source_unit.scenario_unit_id
				if is_instance_valid(active_status.source_unit)
				else ""
			),
		})
	return {
		"id": scenario_unit_id,
		"cell": [grid_cell.x, grid_cell.y],
		"facing": int(current_facing),
		"current_health": current_health,
		"remaining_movement": _remaining_movement,
		"ability_available": _ability_available,
		"reaction_available": _opportunity_reaction_available,
		"equipped_items": _resource_paths(get_equipped_items()),
		"statuses": statuses,
	}


func restore_runtime_state(state: Dictionary, units_by_id: Dictionary) -> void:
	var cell_value: Array = state.get("cell", [starting_grid_cell.x, starting_grid_cell.y])
	if cell_value.size() >= 2:
		_set_runtime_grid_cell_immediate(Vector2i(int(cell_value[0]), int(cell_value[1])))
	current_facing = int(state.get("facing", initial_facing))
	var saved_health := int(state.get("current_health", get_max_health()))
	_remaining_movement = maxf(0.0, float(state.get("remaining_movement", 0.0)))
	_ability_available = bool(state.get("ability_available", false))
	_opportunity_reaction_available = bool(state.get("reaction_available", false))
	_equipped_items.clear()
	_runtime_stats_initialized = true
	for item in _load_items(state.get("equipped_items", [])):
		_equipped_items[item.slot] = item
	_active_statuses.clear()
	for raw_status in state.get("statuses", []):
		if not raw_status is Dictionary:
			continue
		var status: Dictionary = raw_status
		var definition_path := str(status.get("definition", ""))
		var status_definition := load(definition_path) as StatusEffectDefinition
		if status_definition == null:
			continue
		var source_unit := units_by_id.get(str(status.get("source_unit", ""))) as TacticalCharacter
		var source: Object = null
		var source_resource_path := str(status.get("source_resource", ""))
		if not source_resource_path.is_empty():
			source = load(source_resource_path)
		elif str(status.get("source_kind", "")) == "unit":
			source = source_unit
		var restored := ActiveStatus.new(status_definition, source, source_unit)
		restored.remaining_turns = int(status.get("remaining_turns", status_definition.duration_turns))
		restored.processed_this_turn = bool(status.get("processed_this_turn", false))
		_active_statuses.append(restored)
	current_health = clampi(saved_health, 0, get_max_health())
	_defeat_emitted = current_health <= 0
	_sync_map_presence()
	health_changed.emit(current_health, get_max_health())
	movement_remaining_changed.emit(remaining_movement, get_movement_range())
	ability_availability_changed.emit(ability_available)
	opportunity_reaction_availability_changed.emit(opportunity_reaction_available)
	statuses_changed.emit()
	queue_redraw()


func reset_movement() -> void:
	_remaining_movement = get_movement_range() if current_health > 0 else 0.0
	movement_remaining_changed.emit(remaining_movement, get_movement_range())


func can_afford_path(cost: float) -> bool:
	return can_move() and cost >= 0.0 and cost <= remaining_movement + GridPathfinder.COST_EPSILON


func spend_movement(cost: float) -> bool:
	if not can_move() or cost < 0.0 or not can_afford_path(cost):
		return false
	_remaining_movement = maxf(0.0, _remaining_movement - cost)
	if _remaining_movement <= GridPathfinder.COST_EPSILON:
		_remaining_movement = 0.0
	movement_remaining_changed.emit(remaining_movement, get_movement_range())
	return true


func reset_ability_action() -> void:
	_ability_available = current_health > 0
	ability_availability_changed.emit(ability_available)


func spend_ability_action() -> bool:
	if not ability_available:
		return false
	_ability_available = false
	ability_availability_changed.emit(false)
	return true


func reset_opportunity_reaction() -> void:
	_opportunity_reaction_available = current_health > 0
	opportunity_reaction_availability_changed.emit(opportunity_reaction_available)


func spend_opportunity_reaction() -> bool:
	if not opportunity_reaction_available:
		return false
	_opportunity_reaction_available = false
	opportunity_reaction_availability_changed.emit(false)
	return true


func contains_global_point(point: Vector2) -> bool:
	if has_directional_artwork():
		return CHARACTER_ART_HIT_RECT.has_point(to_local(point))
	var body_center := global_position + Vector2(0.0, -29.0)
	return body_center.distance_to(point) <= 23.0


func move_along(path: Array[Vector2i], before_step: Callable = Callable()) -> void:
	if is_moving or not can_move() or _grid == null or path.size() < 2:
		return

	is_moving = true
	movement_started.emit(self)
	for index in range(1, path.size()):
		if not can_move():
			break
		var next_cell := path[index]
		if before_step.is_valid():
			var can_continue: bool = await before_step.call(self, grid_cell, next_cell)
			if not can_continue or not can_move():
				break
		var target_position := _grid.grid_to_global(next_cell)
		face_toward_world_position(target_position)
		var distance := global_position.distance_to(target_position)
		var duration := maxf(0.04, distance / movement_animation_speed)
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(self, "global_position", target_position, duration)
		await tween.finished
		grid_cell = next_cell
		_update_sorting()
		cell_entered.emit(self, grid_cell)
		if current_health <= 0:
			break

	is_moving = false
	movement_finished.emit(self)


func apply_damage(amount: int) -> void:
	if amount <= 0 or current_health <= 0:
		return
	var previous_health := current_health
	current_health = maxi(0, current_health - amount)
	var damage_taken := previous_health - current_health
	health_changed.emit(current_health, get_max_health())
	queue_redraw()
	_show_damage_number(damage_taken)
	_sync_map_presence()
	if current_health == 0 and not _defeat_emitted:
		_ability_available = false
		ability_availability_changed.emit(false)
		_opportunity_reaction_available = false
		opportunity_reaction_availability_changed.emit(false)
		_defeat_emitted = true
		defeated.emit(self)


func heal(amount: int) -> void:
	if amount <= 0 or (permanent_defeat and _defeat_emitted):
		return
	var previous_health := current_health
	var maximum_health := get_max_health()
	current_health = mini(maximum_health, current_health + amount)
	if current_health > 0:
		_defeat_emitted = false
	if current_health != previous_health:
		_sync_map_presence()
		health_changed.emit(current_health, maximum_health)
		queue_redraw()


func get_max_health() -> int:
	return calculate_max_health_for_constitution(
		get_effective_stat(UnitStat.Type.CONSTITUTION)
	)


func get_max_health_without_statuses() -> int:
	return calculate_max_health_for_constitution(
		_calculate_effective_stat(UnitStat.Type.CONSTITUTION, true, false)
	)


func calculate_max_health_for_constitution(effective_constitution: float) -> int:
	if definition != null:
		return definition.calculate_max_health(effective_constitution)
	return UnitStat.get_scaling_rules().calculate_max_health(effective_constitution)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if is_friendly():
		warnings.append_array(CharacterClassProgression.validate_levels(get_class_levels()))
	if definition == null:
		warnings.append("Assign a Character Template before running the battle.")
	elif definition.faction == CharacterDefinition.Faction.ENEMY and get_enemy_ai_profile() == null:
		warnings.append("Enemy units need an Enemy AI Profile to take tactical actions.")
	elif definition.faction == CharacterDefinition.Faction.FRIENDLY and get_enemy_ai_profile() != null:
		warnings.append("Enemy AI Profile is ignored because this unit is friendly.")
	if definition != null:
		var occupied_slots: Dictionary = {}
		for item in definition.starting_equipment:
			if item == null:
				continue
			if occupied_slots.has(item.slot):
				warnings.append(
					"Starting Equipment contains more than one item for the %s slot; the last item wins."
					% ItemDefinition.EquipmentSlot.keys()[item.slot]
				)
			occupied_slots[item.slot] = true
	var override_slots: Dictionary = {}
	var configured_overrides := (
		complete_equipment_overrides
		if use_complete_equipment_override
		else starting_equipment_overrides
	)
	for item in configured_overrides:
		if item == null:
			continue
		if override_slots.has(item.slot):
			warnings.append(
				"Starting Equipment Overrides contains more than one item for the %s slot; the last item wins."
				% ItemDefinition.EquipmentSlot.keys()[item.slot]
			)
		override_slots[item.slot] = true
	return warnings


func _initialize_runtime_stats() -> void:
	if _runtime_stats_initialized:
		return
	_runtime_stats_initialized = true
	_equipped_items.clear()
	if definition == null:
		return
	if not use_complete_equipment_override:
		for item in definition.starting_equipment:
			if item != null:
				_equipped_items[item.slot] = item
		for item in starting_equipment_overrides:
			if item != null:
				_equipped_items[item.slot] = item
	else:
		for item in complete_equipment_overrides:
			if item != null:
				_equipped_items[item.slot] = item


func _resource_paths(resources: Array) -> Array[String]:
	var paths: Array[String] = []
	for resource in resources:
		if resource is Resource and not (resource as Resource).resource_path.is_empty():
			paths.append((resource as Resource).resource_path)
	return paths


func _load_abilities(values) -> Array[AbilityDefinition]:
	var result: Array[AbilityDefinition] = []
	for value in values:
		var ability := load(str(value)) as AbilityDefinition
		if ability != null:
			result.append(ability)
	return result


func _load_items(values) -> Array[ItemDefinition]:
	var result: Array[ItemDefinition] = []
	for value in values:
		var item := load(str(value)) as ItemDefinition
		if item != null:
			result.append(item)
	return result


func _get_all_modifiers(include_equipment: bool = true, include_statuses: bool = true) -> Array[StatModifierDefinition]:
	var result: Array[StatModifierDefinition] = []
	if include_equipment:
		for item in get_equipped_items():
			for modifier in item.modifiers:
				if modifier != null:
					result.append(modifier)
	if not include_statuses:
		return result
	for active_status in _active_statuses:
		if active_status.definition == null:
			continue
		for modifier in active_status.definition.get_stat_modifiers():
			if modifier != null:
				result.append(modifier)
	return result


func _notify_stats_changed(previous_movement: float, previous_max_health: int) -> void:
	var new_movement := get_movement_range()
	if _remaining_movement > new_movement:
		_remaining_movement = new_movement
	if not is_equal_approx(previous_movement, new_movement):
		movement_remaining_changed.emit(_remaining_movement, new_movement)
	_reconcile_health_after_max_change(previous_max_health)
	stats_changed.emit()


func _capture_status_state() -> Dictionary:
	return {
		"movement_range": get_movement_range(),
		"max_health": get_max_health(),
		"remaining_movement": remaining_movement,
		"ability_available": ability_available,
		"opportunity_reaction_available": opportunity_reaction_available,
	}


func _notify_statuses_changed(previous_state: Dictionary) -> void:
	statuses_changed.emit()
	queue_redraw()
	var previous_movement_range := float(previous_state.get("movement_range", get_movement_range()))
	var new_movement_range := get_movement_range()
	if _remaining_movement > new_movement_range:
		_remaining_movement = new_movement_range
	if (
		not is_equal_approx(
			float(previous_state.get("remaining_movement", remaining_movement)),
			remaining_movement
		)
		or not is_equal_approx(previous_movement_range, new_movement_range)
	):
		movement_remaining_changed.emit(remaining_movement, new_movement_range)
	var previous_ability := bool(previous_state.get("ability_available", ability_available))
	if previous_ability != ability_available:
		ability_availability_changed.emit(ability_available)
	var previous_reaction := bool(previous_state.get(
		"opportunity_reaction_available",
		opportunity_reaction_available
	))
	if previous_reaction != opportunity_reaction_available:
		opportunity_reaction_availability_changed.emit(opportunity_reaction_available)
	_reconcile_health_after_max_change(int(previous_state.get("max_health", get_max_health())))
	stats_changed.emit()


func _reconcile_health_after_max_change(previous_max_health: int) -> void:
	var previous_current_health := current_health
	var maximum_health := get_max_health()
	current_health = clampi(current_health, 0, maximum_health)
	if current_health != previous_current_health or maximum_health != previous_max_health:
		health_changed.emit(current_health, maximum_health)
		queue_redraw()


func _show_damage_number(amount: int) -> void:
	if amount <= 0 or Engine.is_editor_hint() or not is_inside_tree():
		return
	var label := Label.new()
	label.text = "-%d" % amount
	label.set_meta("damage_number", true)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = Vector2(-36.0, -148.0) if has_directional_artwork() else Vector2(-36.0, -88.0)
	label.size = Vector2(72.0, 28.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.z_index = 300
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color("ff5a5f"))
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.03, 0.95))
	label.add_theme_constant_override("outline_size", 5)
	add_child(label)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", label.position + Vector2(0.0, -30.0), 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.65).set_delay(0.15)
	tween.chain().tween_callback(label.queue_free)


func _update_sorting() -> void:
	z_index = 100 + grid_cell.x + grid_cell.y


func _draw() -> void:
	var body_color := definition.body_color if definition != null else Color.WHITE
	var health_color := definition.health_bar_color if definition != null else Color.GREEN
	var shadow_color := Color(0.0, 0.0, 0.0, 0.38)

	draw_set_transform(Vector2(0.0, -5.0), 0.0, Vector2(1.35, 0.48))
	draw_circle(Vector2.ZERO, 18.0, shadow_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var facing_texture := _get_facing_texture()
	if facing_texture != null:
		draw_texture_rect(facing_texture, CHARACTER_ART_RECT, false)
	else:
		draw_circle(Vector2(0.0, -29.0), 19.0, Color(0.04, 0.07, 0.11, 1.0))
		draw_circle(Vector2(0.0, -29.0), 16.0, body_color)
		draw_circle(Vector2(-5.0, -34.0), 4.0, body_color.lightened(0.35))

	var bar_rect := ARTWORK_HEALTH_BAR_RECT if facing_texture != null else FALLBACK_HEALTH_BAR_RECT
	draw_rect(bar_rect, Color(0.025, 0.035, 0.05, 0.95), true)
	var ratio := clampf(float(current_health) / float(get_max_health()), 0.0, 1.0)
	draw_rect(
		Rect2(
			bar_rect.position + Vector2(1.0, 1.0),
			Vector2((bar_rect.size.x - 2.0) * ratio, bar_rect.size.y - 2.0)
		),
		health_color,
		true
	)

	var health_text := str(current_health)
	var health_font := ThemeDB.fallback_font
	var health_position := (
		Vector2(-70.0, -108.5)
		if facing_texture != null
		else Vector2(-65.0, -48.5)
	)
	draw_string_outline(
		health_font,
		health_position,
		health_text,
		HORIZONTAL_ALIGNMENT_RIGHT,
		38.0,
		12,
		3,
		Color(0.01, 0.015, 0.025, 0.95)
	)
	draw_string(
		health_font,
		health_position,
		health_text,
		HORIZONTAL_ALIGNMENT_RIGHT,
		38.0,
		12,
		Color.WHITE
	)
	_draw_status_icons()


func _draw_status_icons() -> void:
	for entry in _get_status_icon_entries():
		var status := entry.definition as StatusEffectDefinition
		var icon_rect := entry.rect as Rect2
		var accent := status.color
		accent.a = 1.0
		draw_rect(icon_rect, Color(0.025, 0.035, 0.05, 0.96), true)
		draw_rect(icon_rect, accent, false, 1.5)
		if status.icon != null:
			draw_texture_rect(status.icon, icon_rect.grow(-2.0), false)
			continue
		var fallback_name := status.display_name
		if fallback_name.strip_edges().is_empty():
			fallback_name = String(status.status_id)
		var fallback_text := fallback_name.left(1).to_upper()
		draw_string(
			ThemeDB.fallback_font,
			Vector2(icon_rect.position.x, icon_rect.position.y + 13.0),
			fallback_text,
			HORIZONTAL_ALIGNMENT_CENTER,
			icon_rect.size.x,
			11,
			Color.WHITE
		)


func _get_status_icon_entries() -> Array[Dictionary]:
	var definitions: Array[StatusEffectDefinition] = []
	for active_status in _active_statuses:
		if active_status.definition != null:
			definitions.append(active_status.definition)
	var result: Array[Dictionary] = []
	if definitions.is_empty():
		return result
	var total_width := (
		float(definitions.size()) * STATUS_ICON_SIZE
		+ float(definitions.size() - 1) * STATUS_ICON_GAP
	)
	var start_x := -total_width * 0.5
	var status_icon_top := ARTWORK_STATUS_ICON_TOP if has_directional_artwork() else FALLBACK_STATUS_ICON_TOP
	for index in range(definitions.size()):
		result.append({
			"definition": definitions[index],
			"rect": Rect2(
				start_x + float(index) * (STATUS_ICON_SIZE + STATUS_ICON_GAP),
				status_icon_top,
				STATUS_ICON_SIZE,
				STATUS_ICON_SIZE
			),
		})
	return result
