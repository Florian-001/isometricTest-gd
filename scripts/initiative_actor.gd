@tool
class_name TacticalCharacter
extends Node2D

signal health_changed(current_health: int, max_health: int)
signal movement_started(character)
signal movement_finished(character)
signal cell_entered(character, cell: Vector2i)
signal defeated(character)
signal movement_remaining_changed(remaining: float, maximum: float)
signal ability_availability_changed(available: bool)
signal stats_changed
signal equipment_changed(slot: ItemDefinition.EquipmentSlot, item: ItemDefinition)
signal statuses_changed

@export_category("Character Template")
@export var definition: CharacterDefinition

@export_category("Enemy AI")
## Attach an EnemyAIProfile resource to enemy units. Friendly units ignore this setting.
@export var enemy_ai_profile: EnemyAIProfile:
	set(value):
		enemy_ai_profile = value
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export_category("Unit Stats")
## Set above zero to override the template's maximum health for this unit.
## Set to zero to inherit the value from Character Template.
@export_range(0, 999, 1, "or_greater") var max_health_override: int = 0:
	set(value):
		max_health_override = maxi(0, value)
		if Engine.is_editor_hint():
			current_health = get_max_health()
		queue_redraw()

## Set to zero or higher to override the template's movement range for this unit.
## Set to -1 to inherit the value from Character Template.
@export_range(-1.0, 100.0, 0.5, "or_greater") var movement_range_override: float = -1.0

## Primary-stat overrides use -1 to inherit from the Character Template.
@export_range(-1, 999, 1, "or_greater") var strength_override: int = -1
@export_range(-1, 999, 1, "or_greater") var dexterity_override: int = -1
@export_range(-1, 999, 1, "or_greater") var intelligence_override: int = -1
@export_range(-1, 999, 1, "or_greater") var speed_override: int = -1

@export_category("Ability Loadout")
## Disabled: this unit uses the abilities stored in its Character Template.
## Enabled: Ability Overrides below becomes this unit's complete loadout.
@export var override_template_abilities: bool = false
## Resize this list and choose New AbilityDefinition to author an inline, unit-specific ability.
## You can also drag existing ability .tres files here from the FileSystem dock.
@export var ability_overrides: Array[AbilityDefinition] = []

@export_category("Placement and Presentation")
@export var starting_grid_cell: Vector2i = Vector2i.ZERO:
	set(value):
		starting_grid_cell = value
		if Engine.is_editor_hint():
			grid_cell = value
			_queue_editor_position_sync()
@export_range(20.0, 1000.0, 10.0) var movement_animation_speed: float = 260.0

var current_health: int = 0
var grid_cell: Vector2i = Vector2i.ZERO
var is_moving := false
var remaining_movement: float:
	get:
		return _remaining_movement
var ability_available: bool:
	get:
		return _ability_available
var _grid: IsometricGrid
var _defeat_emitted := false
var _remaining_movement := 0.0
var _ability_available := false
var _equipped_items: Dictionary = {}
var _active_statuses: Array[ActiveStatus] = []
var _runtime_stats_initialized := false
var _editor_syncing_placement := false
var _editor_position_sync_queued := false
var _editor_cell_sync_queued := false


func _ready() -> void:
	_initialize_runtime_stats()
	grid_cell = starting_grid_cell
	current_health = get_max_health()
	if Engine.is_editor_hint():
		set_notify_transform(true)
		_queue_editor_position_sync()
	queue_redraw()


func _notification(what: int) -> void:
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
	global_position = _grid.grid_to_global(grid_cell)
	_update_sorting()
	queue_redraw()


func is_friendly() -> bool:
	return definition != null and definition.faction == CharacterDefinition.Faction.FRIENDLY


func get_movement_range() -> float:
	var base_movement := _get_base_movement_range()
	var speed_adjustment := (get_effective_stat(UnitStat.Type.SPEED) - 10.0) * 0.25
	return clampf(base_movement + speed_adjustment, 2.0, 10.0)


func _get_base_movement_range() -> float:
	if movement_range_override >= 0.0:
		return movement_range_override
	return definition.movement_range if definition != null else 0.0


func get_initiative() -> int:
	return roundi(get_effective_stat(UnitStat.Type.SPEED))


func get_base_stat(stat: UnitStat.Type) -> float:
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
		UnitStat.Type.SPEED:
			if speed_override >= 0:
				return float(speed_override)
			return float(definition.speed) if definition != null else 0.0
		_:
			return 0.0


func get_effective_stat(stat: UnitStat.Type) -> float:
	if stat == UnitStat.Type.NONE:
		return 0.0
	_initialize_runtime_stats()
	var flat_total := 0.0
	var percent_add_total := 0.0
	var percent_multiplier := 1.0
	for modifier in _get_all_modifiers():
		if modifier == null or modifier.stat != stat:
			continue
		match modifier.operation:
			StatModifierDefinition.Operation.FLAT:
				flat_total += modifier.value
			StatModifierDefinition.Operation.PERCENT_ADD:
				percent_add_total += modifier.value
			StatModifierDefinition.Operation.PERCENT_MULTIPLY:
				percent_multiplier *= maxf(0.0, 1.0 + modifier.value)
	var subtotal := get_base_stat(stat) + flat_total
	var percent_add_multiplier := maxf(0.0, 1.0 + percent_add_total)
	return maxf(0.0, subtotal * percent_add_multiplier * percent_multiplier)


func equip_item(item: ItemDefinition) -> ItemDefinition:
	if item == null:
		return null
	_initialize_runtime_stats()
	var previous_movement := get_movement_range()
	var replaced := get_equipped_item(item.slot)
	_equipped_items[item.slot] = item
	equipment_changed.emit(item.slot, item)
	_notify_stats_changed(previous_movement)
	return replaced


func unequip_item(slot: ItemDefinition.EquipmentSlot) -> ItemDefinition:
	_initialize_runtime_stats()
	if not _equipped_items.has(slot):
		return null
	var previous_movement := get_movement_range()
	var removed := _equipped_items[slot] as ItemDefinition
	_equipped_items.erase(slot)
	equipment_changed.emit(slot, null)
	_notify_stats_changed(previous_movement)
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


func apply_status(
	status_definition: StatusEffectDefinition,
	source: TacticalCharacter = null
) -> bool:
	if (
		status_definition == null
		or status_definition.status_id == &""
		or current_health <= 0
	):
		return false
	_initialize_runtime_stats()
	var previous_movement := get_movement_range()
	for active_status in _active_statuses:
		if (
			active_status.definition != null
			and active_status.definition.status_id == status_definition.status_id
		):
			active_status.definition = status_definition
			active_status.source = source
			active_status.remaining_turns = status_definition.duration_turns
			statuses_changed.emit()
			_notify_stats_changed(previous_movement)
			return true
	_active_statuses.append(ActiveStatus.new(status_definition, source))
	statuses_changed.emit()
	_notify_stats_changed(previous_movement)
	return true


func remove_status(status_id: StringName) -> bool:
	_initialize_runtime_stats()
	for index in range(_active_statuses.size() - 1, -1, -1):
		var active_status := _active_statuses[index]
		if active_status.definition != null and active_status.definition.status_id == status_id:
			var previous_movement := get_movement_range()
			_active_statuses.remove_at(index)
			statuses_changed.emit()
			_notify_stats_changed(previous_movement)
			return true
	return false


func get_active_statuses() -> Array[ActiveStatus]:
	_initialize_runtime_stats()
	var result: Array[ActiveStatus] = []
	result.assign(_active_statuses)
	return result


func advance_status_durations() -> void:
	_initialize_runtime_stats()
	if _active_statuses.is_empty():
		return
	var previous_movement := get_movement_range()
	for index in range(_active_statuses.size() - 1, -1, -1):
		var active_status := _active_statuses[index]
		active_status.remaining_turns -= 1
		if active_status.remaining_turns <= 0:
			_active_statuses.remove_at(index)
	statuses_changed.emit()
	_notify_stats_changed(previous_movement)


func get_abilities() -> Array[AbilityDefinition]:
	if override_template_abilities:
		return ability_overrides
	if definition != null:
		return definition.abilities
	var empty_abilities: Array[AbilityDefinition] = []
	return empty_abilities


func reset_movement() -> void:
	_remaining_movement = get_movement_range() if current_health > 0 else 0.0
	movement_remaining_changed.emit(_remaining_movement, get_movement_range())


func can_afford_path(cost: float) -> bool:
	return cost >= 0.0 and cost <= _remaining_movement + GridPathfinder.COST_EPSILON


func spend_movement(cost: float) -> bool:
	if cost < 0.0 or not can_afford_path(cost):
		return false
	_remaining_movement = maxf(0.0, _remaining_movement - cost)
	if _remaining_movement <= GridPathfinder.COST_EPSILON:
		_remaining_movement = 0.0
	movement_remaining_changed.emit(_remaining_movement, get_movement_range())
	return true


func reset_ability_action() -> void:
	_ability_available = current_health > 0
	ability_availability_changed.emit(_ability_available)


func spend_ability_action() -> bool:
	if not _ability_available or current_health <= 0:
		return false
	_ability_available = false
	ability_availability_changed.emit(false)
	return true


func contains_global_point(point: Vector2) -> bool:
	var body_center := global_position + Vector2(0.0, -29.0)
	return body_center.distance_to(point) <= 23.0


func move_along(path: Array[Vector2i]) -> void:
	if is_moving or _grid == null or path.size() < 2:
		return

	is_moving = true
	movement_started.emit(self)
	for index in range(1, path.size()):
		var next_cell := path[index]
		var target_position := _grid.grid_to_global(next_cell)
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
	if current_health == 0 and not _defeat_emitted:
		_ability_available = false
		ability_availability_changed.emit(false)
		_defeat_emitted = true
		defeated.emit(self)


func heal(amount: int) -> void:
	if amount <= 0:
		return
	var previous_health := current_health
	var maximum_health := get_max_health()
	current_health = mini(maximum_health, current_health + amount)
	if current_health > 0:
		_defeat_emitted = false
	if current_health != previous_health:
		health_changed.emit(current_health, maximum_health)
		queue_redraw()


func get_max_health() -> int:
	if max_health_override > 0:
		return max_health_override
	return definition.max_health if definition != null else 1


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if definition == null:
		warnings.append("Assign a Character Template before running the battle.")
	elif definition.faction == CharacterDefinition.Faction.ENEMY and enemy_ai_profile == null:
		warnings.append("Enemy units need an Enemy AI Profile to take tactical actions.")
	elif definition.faction == CharacterDefinition.Faction.FRIENDLY and enemy_ai_profile != null:
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
	return warnings


func _initialize_runtime_stats() -> void:
	if _runtime_stats_initialized:
		return
	_runtime_stats_initialized = true
	_equipped_items.clear()
	if definition == null:
		return
	for item in definition.starting_equipment:
		if item != null:
			_equipped_items[item.slot] = item


func _get_all_modifiers() -> Array[StatModifierDefinition]:
	var result: Array[StatModifierDefinition] = []
	for item in get_equipped_items():
		for modifier in item.modifiers:
			if modifier != null:
				result.append(modifier)
	for active_status in _active_statuses:
		if active_status.definition == null:
			continue
		for modifier in active_status.definition.modifiers:
			if modifier != null:
				result.append(modifier)
	return result


func _notify_stats_changed(previous_movement: float) -> void:
	var new_movement := get_movement_range()
	if _remaining_movement > new_movement:
		_remaining_movement = new_movement
	if not is_equal_approx(previous_movement, new_movement):
		movement_remaining_changed.emit(_remaining_movement, new_movement)
	stats_changed.emit()


func _show_damage_number(amount: int) -> void:
	if amount <= 0 or Engine.is_editor_hint() or not is_inside_tree():
		return
	var label := Label.new()
	label.text = "-%d" % amount
	label.set_meta("damage_number", true)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = Vector2(-36.0, -88.0)
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

	draw_circle(Vector2(0.0, -29.0), 19.0, Color(0.04, 0.07, 0.11, 1.0))
	draw_circle(Vector2(0.0, -29.0), 16.0, body_color)
	draw_circle(Vector2(-5.0, -34.0), 4.0, body_color.lightened(0.35))

	var bar_rect := Rect2(-23.0, -57.0, 46.0, 7.0)
	draw_rect(bar_rect, Color(0.025, 0.035, 0.05, 0.95), true)
	var ratio := clampf(float(current_health) / float(get_max_health()), 0.0, 1.0)
	draw_rect(Rect2(bar_rect.position + Vector2(1.0, 1.0), Vector2(44.0 * ratio, 5.0)), health_color, true)

	var health_text := str(current_health)
	var health_font := ThemeDB.fallback_font
	var health_position := Vector2(-65.0, -48.5)
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
