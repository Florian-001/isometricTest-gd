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

enum PrimaryEffect {
	NONE,
	DAMAGE,
	HEAL,
	STATUS,
}

enum AbilityType {
	MELEE,
	RANGED,
	MAGIC,
}

@export_category("Ability")
@export var display_name: String = "New Ability"
## Controls weapon requirements and weapon-damage contribution. Delivery and Damage Type
## remain independent presentation and damage-classification settings.
@export var ability_type: AbilityType = AbilityType.MAGIC
## Optional icon used by the ability bar and projectile. A colored fallback is generated when empty.
@export var image: Texture2D

@export_category("Primary Effect")
## Main result of the ability. Matching entries in Additional Effects are skipped to avoid duplicates.
@export var effect: PrimaryEffect = PrimaryEffect.NONE:
	set(value):
		effect = value
		if Engine.is_editor_hint():
			notify_property_list_changed()
## Classification used by defenses and status systems. Weapon use is controlled by Ability Type.
@export var damage_type: DamageCalculator.Type = DamageCalculator.Type.PHYSICAL
## Innate damage contributes to both Physical and Magical damage.
@export_range(0, 9999, 1, "or_greater") var innate_damage: int = 0
## Base healing for Heal.
@export_range(0, 9999, 1, "or_greater") var effect_amount: int = 0
## Effective stat used by Damage and Heal, including equipment and status buffs.
@export var scaling_stat: UnitStat.Type = UnitStat.Type.STRENGTH
## Percentage of the effective scaling stat added to Damage or Heal.
@export_range(0.0, 10000.0, 5.0, "or_greater", "suffix:%") var scaling_amount: float = 100.0

@export_category("Applied Status")
## Optional reusable status applied after the primary effect if the target survives.
@export var status_effect: StatusEffectDefinition

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

@export_category("Additional Effects")
## Resize the list, then choose New DamageEffectDefinition, New HealEffectDefinition,
## or another AbilityEffectDefinition subclass. The primary effect executes first. An equivalent
## nested effect is skipped while its matching primary effect is selected.
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


func _validate_property(property: Dictionary) -> void:
	var property_name: StringName = property.name
	var should_hide := false
	if property_name in [&"damage_type", &"innate_damage"]:
		should_hide = effect != PrimaryEffect.DAMAGE
	elif property_name == &"effect_amount":
		should_hide = effect != PrimaryEffect.HEAL
	elif property_name in [&"scaling_stat", &"scaling_amount"]:
		should_hide = effect not in [PrimaryEffect.DAMAGE, PrimaryEffect.HEAL]
	if should_hide:
		property.usage = property.usage & ~PROPERTY_USAGE_EDITOR


func has_target_flag(flag: TargetFlags) -> bool:
	return (target_flags & int(flag)) != 0


func get_required_weapon_type() -> int:
	match ability_type:
		AbilityType.MELEE:
			return ItemDefinition.WeaponType.MELEE
		AbilityType.RANGED:
			return ItemDefinition.WeaponType.RANGED
		_:
			return DamageCalculator.NO_WEAPON_REQUIRED


func can_be_used_by(caster: TacticalCharacter) -> bool:
	if not is_instance_valid(caster) or caster.current_health <= 0:
		return false
	var required_weapon_type := get_required_weapon_type()
	return (
		required_weapon_type == DamageCalculator.NO_WEAPON_REQUIRED
		or caster.has_equipped_weapon_type(required_weapon_type)
	)


func get_unavailable_reason(caster: TacticalCharacter) -> String:
	if can_be_used_by(caster):
		return ""
	if ability_type == AbilityType.MELEE:
		return "Requires a Melee weapon"
	if ability_type == AbilityType.RANGED:
		return "Requires a Ranged weapon"
	return "Caster unavailable"


func get_ability_type_name() -> String:
	return AbilityType.keys()[ability_type].capitalize()


func uses_weapon_damage(caster: TacticalCharacter) -> bool:
	return (
		has_damage()
		and can_be_used_by(caster)
		and get_required_weapon_type() >= 0
		and caster.get_weapon_for_ability(self) != null
	)


func get_weapon_status_effect(caster: TacticalCharacter) -> StatusEffectDefinition:
	if not uses_weapon_damage(caster):
		return null
	var weapon := caster.get_weapon_for_ability(self)
	if weapon == null or weapon.status_effect == null:
		return null
	var weapon_status := weapon.status_effect
	if weapon_status.status_id == &"" or _has_configured_status_id(weapon_status.status_id):
		return null
	return weapon_status


func apply_weapon_status(caster: TacticalCharacter, target: TacticalCharacter) -> bool:
	if not is_instance_valid(target) or target.current_health <= 0:
		return false
	var weapon_status := get_weapon_status_effect(caster)
	var weapon := caster.get_weapon_for_ability(self) if is_instance_valid(caster) else null
	if weapon_status == null or weapon == null:
		return false
	return target.apply_status(weapon_status, weapon, caster)


func estimate_weapon_status_for_ai(
	caster: TacticalCharacter,
	target: TacticalCharacter,
	simulated_health: int
) -> Dictionary:
	var weapon_status := get_weapon_status_effect(caster)
	if weapon_status == null or simulated_health <= 0:
		return {"health_delta": 0, "utility_hint": 0.0}
	return weapon_status.estimate_for_ai(caster, target, simulated_health)


func get_weapon_status_description(caster: TacticalCharacter) -> String:
	var weapon_status := get_weapon_status_effect(caster)
	return "Weapon applies %s" % weapon_status.get_description() if weapon_status != null else ""


func has_damage() -> bool:
	if effect == PrimaryEffect.DAMAGE:
		return true
	for additional_effect in effects:
		if additional_effect is DamageEffectDefinition:
			return true
	return false


func calculate_damage(caster: TacticalCharacter) -> int:
	if effect == PrimaryEffect.DAMAGE:
		return calculate_primary_effect_amount(caster)
	var total := 0
	for additional_effect in effects:
		if additional_effect is DamageEffectDefinition:
			total += (
				additional_effect as DamageEffectDefinition
			).calculate_amount(caster, self)
	return total


## Returns the configured primary Damage or Heal amount. Status and None have no numeric result.
func calculate_primary_effect_amount(caster: TacticalCharacter) -> int:
	match effect:
		PrimaryEffect.DAMAGE:
			return DamageCalculator.calculate_amount(
				caster,
				damage_type,
				innate_damage,
				scaling_stat,
				scaling_amount,
				get_required_weapon_type()
			)
		PrimaryEffect.HEAL:
			var total := float(maxi(0, effect_amount))
			if is_instance_valid(caster) and scaling_stat != UnitStat.Type.NONE:
				total += (
					caster.get_effective_stat(scaling_stat)
					* maxf(0.0, scaling_amount)
					/ 100.0
				)
			return maxi(0, roundi(total))
		_:
			return 0


func has_primary_effect() -> bool:
	return effect != PrimaryEffect.NONE or status_effect != null


## Applies the primary effect through the same calculation used by previews and AI forecasts.
func apply_primary_effect(caster: TacticalCharacter, target: TacticalCharacter) -> void:
	if not is_instance_valid(target) or target.current_health <= 0:
		return
	match effect:
		PrimaryEffect.DAMAGE:
			target.apply_damage(calculate_primary_effect_amount(caster))
		PrimaryEffect.HEAL:
			target.heal(calculate_primary_effect_amount(caster))
	if status_effect != null and target.current_health > 0:
		target.apply_status(status_effect, self, caster)


## Side-effect-free primary-effect prediction shared by every tactical AI path.
func estimate_primary_effect_for_ai(
	caster: TacticalCharacter,
	target: TacticalCharacter,
	simulated_health: int
) -> Dictionary:
	var maximum := target.get_max_health() if is_instance_valid(target) else maxi(0, simulated_health)
	var health := clampi(simulated_health, 0, maximum)
	var utility := 0.0
	match effect:
		PrimaryEffect.DAMAGE:
			health = maxi(0, health - calculate_primary_effect_amount(caster))
		PrimaryEffect.HEAL:
			health = mini(maximum, health + calculate_primary_effect_amount(caster))
	if status_effect != null and health > 0:
		var status_estimate := status_effect.estimate_for_ai(caster, target, health)
		health = clampi(
			health + int(status_estimate.get("health_delta", 0)),
			0,
			maximum
		)
		utility += float(status_estimate.get("utility_hint", 0.0))
	return {
		"health_delta": health - simulated_health,
		"utility_hint": utility,
	}


## Returns false for a nested effect already represented by the selected primary effect.
func should_apply_additional_effect(additional_effect: AbilityEffectDefinition) -> bool:
	if additional_effect == null:
		return false
	if status_effect != null and additional_effect is ApplyStatusEffectDefinition:
		var applied_status := (
			additional_effect as ApplyStatusEffectDefinition
		).status_effect
		if (
			applied_status != null
			and applied_status.status_id == status_effect.status_id
		):
			return false
	match effect:
		PrimaryEffect.DAMAGE:
			return not additional_effect is DamageEffectDefinition
		PrimaryEffect.HEAL:
			return not additional_effect is HealEffectDefinition
	return true


func _has_configured_status_id(status_id: StringName) -> bool:
	if status_id == &"":
		return false
	if status_effect != null and status_effect.status_id == status_id:
		return true
	for additional_effect in effects:
		if additional_effect is ApplyStatusEffectDefinition:
			var configured_status := (
				additional_effect as ApplyStatusEffectDefinition
			).status_effect
			if configured_status != null and configured_status.status_id == status_id:
				return true
	return false


func get_description(caster: TacticalCharacter = null) -> String:
	var effect_descriptions: Array[String] = []
	if has_primary_effect():
		effect_descriptions.append(get_primary_effect_description(caster))
	for additional_effect in effects:
		if should_apply_additional_effect(additional_effect):
			if additional_effect is DamageEffectDefinition:
				effect_descriptions.append(
					(additional_effect as DamageEffectDefinition).get_description_for_ability(
						caster,
						self
					)
				)
			else:
				effect_descriptions.append(additional_effect.get_description(caster))
	if is_instance_valid(caster):
		var weapon_status_description := get_weapon_status_description(caster)
		if not weapon_status_description.is_empty():
			effect_descriptions.append(weapon_status_description)
	var delivery := "Cast"
	match delivery_type:
		DeliveryType.PROJECTILE:
			delivery = "Projectile"
		DeliveryType.MELEE:
			delivery = "Melee"
	var description := ", ".join(effect_descriptions)
	if description.is_empty():
		description = "No effect"
	var result := "%s ability | %s | Range %.2f | %s" % [
		get_ability_type_name(),
		delivery,
		range,
		description,
	]
	if is_instance_valid(caster):
		var unavailable_reason := get_unavailable_reason(caster)
		if not unavailable_reason.is_empty():
			result += " | Unavailable: %s" % unavailable_reason
	return result


func get_primary_effect_description(caster: TacticalCharacter = null) -> String:
	var descriptions: Array[String] = []
	match effect:
		PrimaryEffect.DAMAGE:
			descriptions.append(_get_damage_description(caster))
		PrimaryEffect.HEAL:
			descriptions.append(_get_heal_description(caster))
	if status_effect != null:
		descriptions.append(status_effect.get_description())
	elif effect == PrimaryEffect.STATUS:
		descriptions.append("No status configured")
	return ", ".join(descriptions)


func _get_damage_description(caster: TacticalCharacter) -> String:
	var type_name := "physical" if damage_type == DamageCalculator.Type.PHYSICAL else "magical"
	var total_prefix := "%d %s damage" % [calculate_damage(caster), type_name] if is_instance_valid(caster) else "%s damage" % type_name.capitalize()
	var parts: Array[String] = []
	if innate_damage > 0:
		parts.append("%d innate" % innate_damage)
	if ability_type in [AbilityType.MELEE, AbilityType.RANGED]:
		parts.append("weapon damage")
	if scaling_stat != UnitStat.Type.NONE and scaling_amount > 0.0:
		parts.append("%s x%d%%" % [UnitStat.get_display_name(scaling_stat), roundi(scaling_amount)])
	return "%s (%s)" % [total_prefix, " + ".join(parts) if not parts.is_empty() else "0"]


func _get_heal_description(caster: TacticalCharacter) -> String:
	var total_prefix := (
		"%d healing" % calculate_primary_effect_amount(caster)
		if is_instance_valid(caster)
		else "Healing"
	)
	var parts: Array[String] = ["%d base" % maxi(0, effect_amount)]
	if scaling_stat != UnitStat.Type.NONE and scaling_amount > 0.0:
		parts.append("%s x%d%%" % [UnitStat.get_display_name(scaling_stat), roundi(scaling_amount)])
	return "%s (%s)" % [total_prefix, " + ".join(parts)]
