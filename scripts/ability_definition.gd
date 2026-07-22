@tool
class_name AbilityDefinition
extends Resource

enum DeliveryType {
	PROJECTILE,
	CAST_ON_TARGET,
	MELEE,
}

enum TargetFlags {
	FRIEND = 1,
	ENEMY = 2,
	SELF = 4,
	CELL = 8,
}

enum Shape {
	SQUARE,
	CIRCLE,
	PLUS,
	LINE_VERTICAL,
	LINE_HORIZONTAL,
	LINE_FROM_CASTER,
}

@export_category("Ability")
@export var display_name: String = "New Ability"
## Optional icon used by the ability bar and projectile. A colored fallback is generated when empty.
@export var image: Texture2D

@export_category("Targeting")
## Maximum weighted grid distance. Orthogonal steps cost 1 and diagonal steps cost 1.414.
@warning_ignore("shadowed_global_identifier")
@export_range(0.0, 100.0, 0.5, "or_greater") var range: float = 5.0
@export var delivery_type: DeliveryType = DeliveryType.CAST_ON_TARGET
## 0 or 1 affects one cell. Even values above 1 automatically become the next odd number.
@export_range(0, 99, 1, "or_greater") var area_of_effect: int = 0:
	set(value):
		area_of_effect = maxi(0, value)
		if area_of_effect > 1 and area_of_effect % 2 == 0:
			area_of_effect += 1
@export_flags("Friend:1", "Enemy:2", "Self:4", "Cell:8") var target_flags: int = TargetFlags.ENEMY
@export var shape: Shape = Shape.SQUARE

@export_category("Effects")
## Resize the list, then choose New DamageEffectDefinition, New HealEffectDefinition,
## or another AbilityEffectDefinition subclass. Effects execute from top to bottom.
@export var effects: Array[AbilityEffectDefinition] = []

@export_group("Placeholder Presentation")
@export var placeholder_color: Color = Color("ff7a36")
@export_range(20.0, 2000.0, 10.0, "or_greater") var projectile_speed: float = 520.0

@export_group("Melee Presentation")
@export_range(0.1, 0.75, 0.01) var melee_lunge_ratio: float = 0.38
@export_range(0.02, 2.0, 0.01, "or_greater") var melee_lunge_duration: float = 0.12
@export_range(0.02, 2.0, 0.01, "or_greater") var melee_return_duration: float = 0.16
@export_range(0.02, 2.0, 0.01, "or_greater") var melee_slash_duration: float = 0.18
@export var melee_slash_color: Color = Color("fff1a1")


func get_effective_area_span() -> int:
	return 1 if area_of_effect <= 1 else area_of_effect


func has_target_flag(flag: TargetFlags) -> bool:
	return (target_flags & int(flag)) != 0


func get_description() -> String:
	var effect_descriptions: Array[String] = []
	for effect in effects:
		if effect != null:
			effect_descriptions.append(effect.get_description())
	var delivery := "Cast"
	match delivery_type:
		DeliveryType.PROJECTILE:
			delivery = "Projectile"
		DeliveryType.MELEE:
			delivery = "Melee"
	return "%s | Range %.2f | %s" % [delivery, range, ", ".join(effect_descriptions)]
