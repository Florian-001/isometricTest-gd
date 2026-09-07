@tool
class_name StatScalingRules
extends Resource

## Project-wide Constitution and Speed conversions. Ability-specific Strength,
## Dexterity, and Intelligence scaling remains on each AbilityDefinition.

@export_category("Constitution to Health")
## Maximum health granted by each effective Constitution point.
@export_range(0.0, 1000.0, 0.25, "or_greater") var health_per_constitution_point: float = 4.0
## Constitution cannot count as less than this value when maximum health is calculated.
@export_range(0.0, 1000.0, 0.25, "or_greater") var minimum_constitution_for_health: float = 1.0

@export_category("Speed to Initiative")
## Initiative granted by each effective Speed point.
@export_range(0.0, 1000.0, 0.05, "or_greater") var initiative_per_speed_point: float = 1.0

@export_category("Speed to Movement")
## Speed equal to this value leaves a character's configured base movement unchanged.
@export_range(0.0, 1000.0, 0.25, "or_greater") var movement_speed_reference: float = 10.0
## Movement added or removed for each Speed point above or below the reference.
@export_range(0.0, 1000.0, 0.05, "or_greater") var movement_per_speed_point: float = 0.25
## Floor applied after Speed adjusts base movement, before equipment and statuses.
@export_range(0.0, 1000.0, 0.25, "or_greater") var minimum_base_movement_range: float = 2.0
## Floor applied after every movement modifier, including equipment and statuses.
@export_range(0.0, 1000.0, 0.25, "or_greater") var minimum_effective_movement_range: float = 0.0
## Ceiling applied to both Speed-adjusted base movement and final effective movement.
@export_range(0.0, 1000.0, 0.25, "or_greater") var maximum_movement_range: float = 10.0


func calculate_max_health(effective_constitution: float) -> int:
	var constitution := maxf(0.0, effective_constitution)
	constitution = maxf(constitution, maxf(0.0, minimum_constitution_for_health))
	var health_per_point := maxf(0.0, health_per_constitution_point)
	return maxi(1, roundi(constitution * health_per_point))


func calculate_initiative(effective_speed: float) -> int:
	return maxi(
		0,
		roundi(maxf(0.0, effective_speed) * maxf(0.0, initiative_per_speed_point))
	)


func calculate_speed_adjusted_base_movement(
	configured_base_movement: float,
	effective_speed: float
) -> float:
	var adjusted := (
		maxf(0.0, configured_base_movement)
		+ (maxf(0.0, effective_speed) - maxf(0.0, movement_speed_reference))
		* maxf(0.0, movement_per_speed_point)
	)
	return clampf(adjusted, _get_base_movement_minimum(), _get_movement_maximum())


func clamp_effective_movement_range(effective_movement: float) -> float:
	return clampf(
		effective_movement,
		_get_effective_movement_minimum(),
		_get_movement_maximum()
	)


func _get_effective_movement_minimum() -> float:
	return maxf(0.0, minimum_effective_movement_range)


func _get_base_movement_minimum() -> float:
	return maxf(
		_get_effective_movement_minimum(),
		maxf(0.0, minimum_base_movement_range)
	)


func _get_movement_maximum() -> float:
	return maxf(
		_get_effective_movement_minimum(),
		maxf(_get_base_movement_minimum(), maxf(0.0, maximum_movement_range))
	)
