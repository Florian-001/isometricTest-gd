@tool
class_name AbilityDefinition
extends Resource

const AbilityCasterMovementScript = preload("res://scripts/ability_caster_movement.gd")

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

enum CasterMovement {
	NONE,
	CHARGE_TO_TARGET,
}

enum HitTargeting {
	SAME_TARGET,
	SELECT_PER_HIT,
}

@export_category("Ability")
@export var display_name: String = "New Ability"
## Controls weapon requirements and weapon-damage contribution. Delivery and Damage Type
## remain independent presentation and damage-classification settings.
@export var ability_type: AbilityType = AbilityType.MAGIC:
	set(value):
		ability_type = value
		_normalize_weapon_scaling()
		if Engine.is_editor_hint():
			notify_property_list_changed()
## Optional icon used by the ability bar and projectile. A colored fallback is generated when empty.
@export var image: Texture2D
## Melee/Ranged abilities normally require their matching weapon. Disable for shouts.
@export var requires_weapon: bool = true
## Allows an empty weapon slot for friendly melee casters without removing weapon scaling.
@export var allow_unarmed_for_friendlies: bool = false
## Each hit resolves its own delivery, damage, and on-hit statuses for one action.
@export_range(1, 99, 1, "or_greater") var hit_count: int = 1
## Same Target repeats every hit on one selection. Select Per Hit requires one
## unit selection per hit and explicit confirmation. Only stationary, single-unit
## targeting is supported; cell, area, caster-centered and movement casts are invalid.
@export var hit_targeting: HitTargeting = HitTargeting.SAME_TARGET:
	set(value):
		hit_targeting = value
		if Engine.is_editor_hint():
			notify_property_list_changed()
## In Select Per Hit mode, allow the same unit to occupy multiple target slots.
@export var allow_repeated_targets: bool = true
@export_tool_button("Validate Targeting") var validate_targeting_button: Callable = _validate_targeting

@export_category("Primary Effect")
## Main result of the ability. Matching entries in Additional Effects are skipped to avoid duplicates.
@export var effect: PrimaryEffect = PrimaryEffect.NONE:
	set(value):
		effect = value
		_normalize_weapon_scaling()
		if Engine.is_editor_hint():
			notify_property_list_changed()
## Classification used by defenses and status systems. Weapon use is controlled by Ability Type.
@export var damage_type: DamageCalculator.Type = DamageCalculator.Type.PHYSICAL
## Innate damage contributes to both Physical and Magical damage.
@export_range(0, 9999, 1, "or_greater") var innate_damage: int = 0
## Base healing for Heal.
@export_range(0, 9999, 1, "or_greater") var effect_amount: int = 0
## Effective stat used by Damage and Heal. Damaging Melee/Ranged abilities can
## instead select Weapon to scale only their matching weapon-damage contribution.
@export var scaling_stat: int = DamageCalculator.ScalingSource.STRENGTH
## Percentage of the selected stat or weapon damage added to Damage or Heal.
@export_range(0.0, 10000.0, 5.0, "or_greater", "suffix:%") var scaling_amount: float = 100.0

@export_category("Applied Status")
## Optional reusable status applied after the primary effect if the target survives.
@export var status_effect: StatusEffectDefinition

@export_category("Targeting")
## Maximum weighted grid distance. Orthogonal steps cost 1 and diagonal steps cost 1.414.
@warning_ignore("shadowed_global_identifier")
@export_range(0.0, 100.0, 0.5, "or_greater") var range: float = 5.0
## Adds the compatible equipped weapon's range bonus to normal casts and melee reach.
## This never extends opportunity-attack reach. Only Strike enables it by default.
@export var accepts_weapon_range_bonus: bool = false
@export var delivery_type: DeliveryType = DeliveryType.CAST_ON_TARGET
## 0 or 1 affects one cell. Even values above 1 automatically become the next odd number.
@export_range(0, 99, 1, "or_greater") var area_of_effect: int = 0:
	set(value):
		area_of_effect = maxi(0, value)
		if area_of_effect > 1 and area_of_effect % 2 == 0:
			area_of_effect += 1
@export_flags("Friend:1", "Enemy:2", "Self:4", "Cell:8") var target_flags: int = TargetFlags.ENEMY
@export var shape: Shape = Shape.SQUARE
## Only the caster's cell confirms the cast; Range becomes the affected radius.
## Target Flags still control recipients. Shape and Area of Effect are unused.
@export var caster_centered: bool = false

@export_category("Caster Movement")
## Optional movement performed before the configured delivery and effects resolve.
@export var caster_movement: CasterMovement = CasterMovement.NONE

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


func get_hit_count() -> int:
	return maxi(1, hit_count)


func selects_per_hit() -> bool:
	return hit_targeting == HitTargeting.SELECT_PER_HIT


func get_targeting_configuration_error() -> String:
	if not selects_per_hit():
		return ""
	if has_target_flag(TargetFlags.CELL):
		return "Select Per Hit requires unit targets; disable Cell targeting."
	if get_effective_area_span() > 1 or shape == Shape.LINE_FROM_CASTER:
		return "Select Per Hit requires a single-unit area and cannot use Line From Caster."
	if caster_centered or moves_caster():
		return "Select Per Hit requires a stationary cast without Caster Centered targeting."
	if target_flags == 0:
		return "Select Per Hit requires at least one unit Target Flag."
	return ""


func _validate_targeting() -> void:
	var error := get_targeting_configuration_error()
	if error.is_empty():
		print("%s: targeting is valid." % display_name)
	else:
		push_warning("%s: %s" % [display_name, error])


func moves_caster() -> bool:
	return caster_movement != CasterMovement.NONE


func get_caster_movement_path(
	caster_cell: Vector2i,
	target_cell: Vector2i,
	grid_size: Vector2i,
	blocked_cells: Dictionary = {}
) -> Array[Vector2i]:
	match caster_movement:
		CasterMovement.CHARGE_TO_TARGET:
			return AbilityCasterMovementScript.get_charge_path(
				caster_cell,
				target_cell,
				grid_size,
				blocked_cells
			)
	var stationary_path: Array[Vector2i] = [caster_cell]
	return stationary_path


func _validate_property(property: Dictionary) -> void:
	var property_name: StringName = property.name
	var should_hide := false
	if property_name in [&"damage_type", &"innate_damage"]:
		should_hide = effect != PrimaryEffect.DAMAGE
	elif property_name == &"effect_amount":
		should_hide = effect != PrimaryEffect.HEAL
	elif property_name in [&"scaling_stat", &"scaling_amount"]:
		should_hide = effect not in [PrimaryEffect.DAMAGE, PrimaryEffect.HEAL]
	elif property_name == &"allow_repeated_targets":
		should_hide = not selects_per_hit()
	if should_hide:
		property.usage = property.usage & ~PROPERTY_USAGE_EDITOR
	elif property_name == &"scaling_stat":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = (
			DamageCalculator.WEAPON_SCALING_OPTIONS
			if _can_select_weapon_scaling()
			else DamageCalculator.UNIT_STAT_SCALING_OPTIONS
		)


func _can_select_weapon_scaling() -> bool:
	return (
		effect == PrimaryEffect.DAMAGE
		and ability_type in [AbilityType.MELEE, AbilityType.RANGED]
	)


func _normalize_weapon_scaling() -> void:
	if scaling_stat == DamageCalculator.ScalingSource.WEAPON and not _can_select_weapon_scaling():
		scaling_stat = DamageCalculator.ScalingSource.NONE


func has_target_flag(flag: TargetFlags) -> bool:
	return (target_flags & int(flag)) != 0


func get_required_weapon_type() -> int:
	if not requires_weapon:
		return DamageCalculator.NO_WEAPON_REQUIRED
	match ability_type:
		AbilityType.MELEE:
			return ItemDefinition.WeaponType.MELEE
		AbilityType.RANGED:
			return ItemDefinition.WeaponType.RANGED
		_:
			return DamageCalculator.NO_WEAPON_REQUIRED


func can_be_used_by(caster: TacticalCharacter) -> bool:
	if (
		not is_instance_valid(caster)
		or not get_targeting_configuration_error().is_empty()
		or caster.current_health <= 0
		or not caster.can_use_abilities()
	):
		return false
	return has_compatible_equipment(caster)


func has_compatible_equipment(caster: TacticalCharacter) -> bool:
	if not is_instance_valid(caster):
		return false
	var required_weapon_type := get_required_weapon_type()
	return (
		required_weapon_type == DamageCalculator.NO_WEAPON_REQUIRED
		or caster.has_equipped_weapon_type(required_weapon_type)
		or (allow_unarmed_for_friendlies
			and required_weapon_type == ItemDefinition.WeaponType.MELEE
			and caster.is_friendly()
			and caster.get_equipped_weapon() == null)
	)


func get_weapon_range_bonus(caster: TacticalCharacter = null) -> float:
	if not accepts_weapon_range_bonus or not is_instance_valid(caster):
		return 0.0
	var weapon := caster.get_weapon_for_ability(self)
	return maxf(0.0, weapon.weapon_range_bonus) if weapon != null else 0.0


func get_effective_range(caster: TacticalCharacter = null) -> float:
	return range + get_weapon_range_bonus(caster)


## Base melee delivery remains adjacent even for abilities with a long cast range (Charge).
func get_effective_melee_reach(caster: TacticalCharacter = null) -> float:
	return GridPathfinder.DIAGONAL_COST + get_weapon_range_bonus(caster)


func get_unavailable_reason(caster: TacticalCharacter) -> String:
	var configuration_error := get_targeting_configuration_error()
	if not configuration_error.is_empty():
		return configuration_error
	if can_be_used_by(caster):
		return ""
	if is_instance_valid(caster) and caster.current_health > 0 and caster.is_stunned():
		return "Stunned"
	if get_required_weapon_type() == ItemDefinition.WeaponType.MELEE:
		return "Requires a Melee weapon"
	if get_required_weapon_type() == ItemDefinition.WeaponType.RANGED:
		return "Requires a Ranged weapon"
	return "Caster unavailable"


func get_ability_type_name() -> String:
	return AbilityType.keys()[ability_type].capitalize()


func uses_weapon_damage(caster: TacticalCharacter) -> bool:
	if (
		not has_damage()
		or not can_be_used_by(caster)
		or get_required_weapon_type() < 0
		or caster.get_weapon_for_ability(self) == null
	):
		return false
	if effect == PrimaryEffect.DAMAGE:
		return (
			scaling_stat != DamageCalculator.ScalingSource.WEAPON
			or scaling_amount > 0.0
		)
	# Ability-owned legacy damage effects retain the automatic full weapon term.
	return true


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


func get_passive_damage_bonus(caster: TacticalCharacter, snapshot: AIBoardSnapshot = null, origin := Vector2i(-1, -1)) -> int:
	if not is_instance_valid(caster) or not has_damage() or get_required_weapon_type() < 0 or caster.get_weapon_for_ability(self) == null:
		return 0
	return PassiveAbilityResolver.weapon_damage_bonus(caster, snapshot, origin)


func calculate_damage(caster: TacticalCharacter, snapshot: AIBoardSnapshot = null, origin := Vector2i(-1, -1)) -> int:
	return calculate_hit_damage(caster, snapshot, origin) * get_hit_count()


func calculate_hit_damage(caster: TacticalCharacter, snapshot: AIBoardSnapshot = null, origin := Vector2i(-1, -1)) -> int:
	if effect == PrimaryEffect.DAMAGE:
		return calculate_primary_effect_amount(caster, snapshot, origin)
	var total := 0
	for additional_effect in effects:
		if additional_effect is DamageEffectDefinition:
			total += (
				additional_effect as DamageEffectDefinition
			).calculate_amount(caster, self)
	return total + get_passive_damage_bonus(caster, snapshot, origin)


func get_damage_summary(caster: TacticalCharacter, origin := Vector2i(-1, -1)) -> String:
	if get_hit_count() > 1:
		return "%d × %d DMG" % [get_hit_count(), calculate_hit_damage(caster, null, origin)]
	return "%d DMG" % calculate_damage(caster, null, origin)


## Describes every damaging term using the selected caster's live stats and equipment.
func get_damage_calculation_description(caster: TacticalCharacter) -> String:
	if not has_damage():
		return "No damage"
	var calculations: Array[String] = []
	if effect == PrimaryEffect.DAMAGE:
		calculations.append(DamageCalculator.get_amount_calculation_description(
			caster,
			damage_type,
			innate_damage,
			scaling_stat,
			scaling_amount,
			get_required_weapon_type()
		))
	else:
		for additional_effect in effects:
			if additional_effect is DamageEffectDefinition:
				var damage_effect := additional_effect as DamageEffectDefinition
				calculations.append(DamageCalculator.get_amount_calculation_description(
					caster,
					int(damage_effect.damage_type),
					damage_effect.innate_damage,
					damage_effect.scaling_stat,
					damage_effect.scaling_percentage,
					get_required_weapon_type()
				))
	var passive_bonus := get_passive_damage_bonus(caster)
	if passive_bonus > 0:
		calculations.append("+%d passive weapon damage" % passive_bonus)
	if get_hit_count() > 1:
		return "Damage: %d hits × (%s) = %d %s" % [get_hit_count(), " · ".join(calculations), calculate_damage(caster), "potential cast total" if selects_per_hit() else "total"]
	if calculations.size() == 1:
		return "Damage: %s" % calculations[0]
	return "Damage: %d total · %s" % [calculate_damage(caster), " · ".join(calculations)]


## Returns the configured primary Damage or Heal amount. Status and None have no numeric result.
func calculate_primary_effect_amount(caster: TacticalCharacter, snapshot: AIBoardSnapshot = null, origin := Vector2i(-1, -1)) -> int:
	match effect:
		PrimaryEffect.DAMAGE:
			return DamageCalculator.calculate_amount(
				caster,
				damage_type,
				innate_damage,
				scaling_stat,
				scaling_amount,
				get_required_weapon_type()
			) + get_passive_damage_bonus(caster, snapshot, origin)
		PrimaryEffect.HEAL:
			var total := float(maxi(0, effect_amount))
			if (
				is_instance_valid(caster)
				and scaling_stat != DamageCalculator.ScalingSource.NONE
				and DamageCalculator.is_unit_stat_scaling_source(scaling_stat)
			):
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
	simulated_health: int,
	include_status: bool = true,
	snapshot: AIBoardSnapshot = null
) -> Dictionary:
	var maximum := (
		snapshot.get_max_health(target) if snapshot != null
		else (target.get_max_health() if is_instance_valid(target) else maxi(0, simulated_health))
	)
	var initial_armor := (
		snapshot.get_armor(target) if snapshot != null
		else (target.current_armor if is_instance_valid(target) else 0)
	)
	var health := clampi(simulated_health, 0, maximum)
	var armor := initial_armor
	var utility := 0.0
	match effect:
		PrimaryEffect.DAMAGE:
			var damage := DamageCalculator.resolve_damage(
				calculate_primary_effect_amount(caster, snapshot), health, armor
			)
			health += int(damage.health_delta)
			armor += int(damage.armor_delta)
		PrimaryEffect.HEAL:
			health = mini(maximum, health + calculate_primary_effect_amount(caster, snapshot))
	if include_status and status_effect != null and health > 0:
		var status_estimate := status_effect.estimate_for_ai(caster, target, health, -1, armor)
		health = clampi(health + int(status_estimate.get("health_delta", 0)), 0, maximum)
		armor = maxi(0, armor + int(status_estimate.get("armor_delta", 0)))
		utility += float(status_estimate.get("utility_hint", 0.0))
	return {
		"health_delta": health - simulated_health,
		"armor_delta": armor - initial_armor,
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
		if effect != PrimaryEffect.DAMAGE and get_passive_damage_bonus(caster) > 0:
			effect_descriptions.append(get_damage_calculation_description(caster))
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
		get_effective_range(caster),
		description,
	]
	if caster_movement == CasterMovement.CHARGE_TO_TARGET:
		result += " | Charges in a clear straight line and stops adjacent"
	if caster_centered:
		result += " | Radius %.2f around caster; click caster to confirm" % get_effective_range(caster)
	if get_weapon_range_bonus(caster) > 0.0:
		result += " | +%s weapon range (normal attacks only)" % str(get_weapon_range_bonus(caster))
	if selects_per_hit():
		result += " | Choose %d targets in order; %s; confirm to fire" % [get_hit_count(), "repeats allowed" if allow_repeated_targets else "distinct units only"]
		if is_instance_valid(caster) and has_damage():
			result += " | %d damage per hit; %d potential cast total" % [calculate_hit_damage(caster), calculate_damage(caster)]
	elif get_hit_count() > 1:
		result += " | %d separate hits on the same target" % get_hit_count()
		if is_instance_valid(caster):
			result += " | %d damage per hit" % calculate_hit_damage(caster)
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
	if scaling_stat == DamageCalculator.ScalingSource.WEAPON and _can_select_weapon_scaling():
		if scaling_amount > 0.0:
			parts.append("weapon damage x%d%%" % roundi(scaling_amount))
	elif get_required_weapon_type() >= 0 and (not is_instance_valid(caster) or caster.get_weapon_for_ability(self) != null):
		parts.append("weapon damage")
	if (
		scaling_stat != DamageCalculator.ScalingSource.NONE
		and scaling_stat != DamageCalculator.ScalingSource.WEAPON
		and scaling_amount > 0.0
	):
		parts.append("%s x%d%%" % [DamageCalculator.get_scaling_source_display_name(scaling_stat), roundi(scaling_amount)])
	var passive_bonus := get_passive_damage_bonus(caster)
	if passive_bonus > 0:
		parts.append("%d passive weapon damage" % passive_bonus)
	if get_hit_count() > 1:
		return "%s (%d hits × (%s))" % [total_prefix, get_hit_count(), " + ".join(parts)]
	return "%s (%s)" % [total_prefix, " + ".join(parts) if not parts.is_empty() else "0"]


func _get_heal_description(caster: TacticalCharacter) -> String:
	var total_prefix := (
		"%d healing" % calculate_primary_effect_amount(caster)
		if is_instance_valid(caster)
		else "Healing"
	)
	var parts: Array[String] = ["%d base" % maxi(0, effect_amount)]
	if (
		scaling_stat != DamageCalculator.ScalingSource.NONE
		and DamageCalculator.is_unit_stat_scaling_source(scaling_stat)
		and scaling_amount > 0.0
	):
		parts.append("%s x%d%%" % [DamageCalculator.get_scaling_source_display_name(scaling_stat), roundi(scaling_amount)])
	return "%s (%s)" % [total_prefix, " + ".join(parts)]
