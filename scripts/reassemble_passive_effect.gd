@tool
class_name ReassemblePassiveEffect
extends PassiveEffectDefinition

## Health of the targetable, immobile pile after lethal damage. Overkill is discarded.
@export_range(1, 999, 1, "or_greater") var pile_health: int = 1:
	set(value):
		pile_health = value
		emit_changed()
## Percentage of normal maximum health restored on the next turn, after hazards.
@export_range(1.0, 100.0, 1.0, "suffix:%") var restored_health_percentage: float = 100.0:
	set(value):
		restored_health_percentage = value
		emit_changed()
## Transparent artwork used while waiting to reform. Assigned passives share this asset.
@export var pile_texture: Texture2D:
	set(value):
		pile_texture = value
		emit_changed()


func validate() -> Array[String]:
	var errors: Array[String] = []
	if pile_health < 1:
		errors.append("Reassemble pile health must be a positive integer.")
	if not is_finite(restored_health_percentage) or restored_health_percentage < 1.0 or restored_health_percentage > 100.0:
		errors.append("Reassemble restored health must be between 1% and 100%.")
	if pile_texture == null:
		errors.append("Assign transparent artwork for the bone pile.")
	return errors


func get_description() -> String:
	return "At zero health, become a %d HP bone pile and clear temporary effects. Survive until your next turn to reform at %s%% health and act normally. Destroying the pile is permanent." % [pile_health, str(restored_health_percentage)]


func to_data() -> Dictionary:
	return {"type": "reassemble", "pile_health": pile_health,
		"restored_health_percentage": restored_health_percentage,
		"pile_texture": pile_texture.resource_path if pile_texture != null else ""}


static func from_data(data: Dictionary) -> ReassemblePassiveEffect:
	var effect := ReassemblePassiveEffect.new()
	effect.pile_health = int(data.get("pile_health", 1))
	effect.restored_health_percentage = float(data.get("restored_health_percentage", 100.0))
	var texture_path := str(data.get("pile_texture", ""))
	if ResourceLoader.exists(texture_path):
		effect.pile_texture = load(texture_path) as Texture2D
	return effect


static func validate_data(data: Dictionary) -> Array[String]:
	var health: Variant = data.get("pile_health")
	var percent: Variant = data.get("restored_health_percentage")
	if not (health is int or health is float) or not is_finite(float(health)) or float(health) < 1.0 or float(health) != floorf(float(health)):
		return ["Invalid Reassemble pile health."]
	if not (percent is int or percent is float) or not is_finite(float(percent)) or float(percent) < 1.0 or float(percent) > 100.0:
		return ["Invalid Reassemble restored health percentage."]
	if not data.get("pile_texture") is String or not ResourceLoader.exists(data.pile_texture) or not load(data.pile_texture) is Texture2D:
		return ["Invalid Reassemble pile texture."]
	return []
