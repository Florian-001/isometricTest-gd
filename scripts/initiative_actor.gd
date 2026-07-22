@tool
class_name TacticalCharacter
extends Node2D

signal health_changed(current_health: int, max_health: int)
signal movement_started(character)
signal movement_finished(character)
signal defeated(character)
signal movement_remaining_changed(remaining: float, maximum: float)
signal ability_availability_changed(available: bool)

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

## Set to zero or higher to override the template initiative for this unit.
## Set to -1 to inherit the value from Character Template.
@export_range(-1, 1000, 1, "or_greater") var initiative_override: int = -1

@export_category("Ability Loadout")
## Disabled: this unit uses the abilities stored in its Character Template.
## Enabled: Ability Overrides below becomes this unit's complete loadout.
@export var override_template_abilities: bool = false
## Resize this list and choose New AbilityDefinition to author an inline, unit-specific ability.
## You can also drag existing ability .tres files here from the FileSystem dock.
@export var ability_overrides: Array[AbilityDefinition] = []

@export_category("Placement and Presentation")
@export var starting_grid_cell: Vector2i = Vector2i.ZERO
@export_range(20.0, 1000.0, 10.0) var movement_speed: float = 260.0

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


func _ready() -> void:
	grid_cell = starting_grid_cell
	current_health = get_max_health()
	queue_redraw()


func initialize(grid: IsometricGrid) -> void:
	_grid = grid
	grid_cell = starting_grid_cell
	global_position = _grid.grid_to_global(grid_cell)
	_update_sorting()
	queue_redraw()


func is_friendly() -> bool:
	return definition != null and definition.faction == CharacterDefinition.Faction.FRIENDLY


func get_movement_range() -> float:
	if movement_range_override >= 0.0:
		return movement_range_override
	return definition.movement_range if definition != null else 0.0


func get_initiative() -> int:
	if initiative_override >= 0:
		return initiative_override
	return definition.initiative if definition != null else 0


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
		var duration := maxf(0.04, distance / movement_speed)
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(self, "global_position", target_position, duration)
		await tween.finished
		grid_cell = next_cell
		_update_sorting()

	is_moving = false
	movement_finished.emit(self)


func apply_damage(amount: int) -> void:
	if amount <= 0 or current_health <= 0:
		return
	current_health = maxi(0, current_health - amount)
	health_changed.emit(current_health, get_max_health())
	queue_redraw()
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
	return warnings


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
