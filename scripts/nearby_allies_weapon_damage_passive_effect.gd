@tool
class_name NearbyAlliesWeaponDamagePassiveEffect
extends PassiveEffectDefinition

## Straight-line grid distance; 1.5 includes adjacent diagonal cells.
@export_range(0.0, 100.0, 0.1, "or_greater") var radius: float = 1.5:
	set(value):
		radius = value
		emit_changed()
## Each other living ally with the owning passive's ID contributes this amount.
@export_range(1, 999, 1, "or_greater") var damage_per_ally: int = 1:
	set(value):
		damage_per_ally = value
		emit_changed()


func validate() -> Array[String]:
	var errors: Array[String] = []
	if not is_finite(radius) or radius < 0.0:
		errors.append("Nearby-ally radius must be finite and nonnegative.")
	if damage_per_ally < 1:
		errors.append("Damage per ally must be a positive integer.")
	return errors


func get_description() -> String:
	return "+%d weapon damage per other living ally with this passive within %s grid units. Includes opportunity attacks." % [damage_per_ally, str(radius)]
