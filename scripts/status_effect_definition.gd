@tool
class_name StatusEffectDefinition
extends Resource

enum Effect {
	NONE,
	DAMAGE_EACH_TURN,
	STAT_MODIFIER,
	STUN,
}

enum ModifierDirection {
	INCREASE,
	REDUCE,
}

enum ModifierValueType {
	FLAT,
	PERCENTAGE,
}

@export_category("Status")
## Stable identifier used to refresh an existing status instead of stacking another copy.
@export var status_id: StringName = &"new_status"
@export var display_name: String = "New Status"
@export_range(1, 99, 1, "or_greater") var duration_turns: int = 1

@export_category("Primary Effect")
@export var effect: Effect = Effect.NONE:
	set(value):
		effect = value
		if Engine.is_editor_hint():
			notify_property_list_changed()
## Fixed, unscaled damage. It never includes weapon damage or source-unit stats.
@export var damage_type: DamageCalculator.Type = DamageCalculator.Type.MAGICAL
@export_range(0, 9999, 1, "or_greater") var damage_per_turn: int = 1
@export var affected_stat: UnitStat.Type = UnitStat.Type.MOVEMENT_RANGE
@export var modifier_direction: ModifierDirection = ModifierDirection.REDUCE
@export var modifier_value_type: ModifierValueType = ModifierValueType.PERCENTAGE:
	set(value):
		modifier_value_type = value
		if Engine.is_editor_hint():
			notify_property_list_changed()
@export_range(0.0, 10000.0, 0.05, "or_greater") var flat_amount: float = 1.0
@export_range(0.0, 10000.0, 1.0, "or_greater", "suffix:%") var percentage_amount: float = 10.0

@export_category("AI Forecast")
## Signed value from the affected unit's perspective. Penalties should use a negative value.
@export_range(-10000.0, 10000.0, 0.5) var affected_unit_ai_utility: float = 0.0

@export_category("Presentation")
@export var icon: Texture2D
@export var color: Color = Color.WHITE

@export_category("Additional Modifiers")
@export var modifiers: Array[StatModifierDefinition] = []


func _validate_property(property: Dictionary) -> void:
	var property_name: StringName = property.name
	var should_hide := false
	if property_name in [&"damage_type", &"damage_per_turn"]:
		should_hide = effect != Effect.DAMAGE_EACH_TURN
	elif property_name == &"affected_unit_ai_utility":
		should_hide = effect not in [Effect.STAT_MODIFIER, Effect.STUN]
	elif property_name in [
		&"affected_stat",
		&"modifier_direction",
		&"modifier_value_type",
	]:
		should_hide = effect != Effect.STAT_MODIFIER
	elif property_name == &"flat_amount":
		should_hide = (
			effect != Effect.STAT_MODIFIER
			or modifier_value_type != ModifierValueType.FLAT
		)
	elif property_name == &"percentage_amount":
		should_hide = (
			effect != Effect.STAT_MODIFIER
			or modifier_value_type != ModifierValueType.PERCENTAGE
		)
	if should_hide:
		property.usage = property.usage & ~PROPERTY_USAGE_EDITOR


func blocks_actions() -> bool:
	return effect == Effect.STUN


func get_stat_modifiers() -> Array[StatModifierDefinition]:
	var result: Array[StatModifierDefinition] = []
	if effect == Effect.STAT_MODIFIER and affected_stat != UnitStat.Type.NONE:
		var primary_modifier := StatModifierDefinition.new()
		primary_modifier.stat = affected_stat
		var direction := -1.0 if modifier_direction == ModifierDirection.REDUCE else 1.0
		if modifier_value_type == ModifierValueType.FLAT:
			primary_modifier.operation = StatModifierDefinition.Operation.FLAT
			primary_modifier.value = direction * maxf(0.0, flat_amount)
		else:
			primary_modifier.operation = StatModifierDefinition.Operation.PERCENT_ADD
			primary_modifier.value = direction * maxf(0.0, percentage_amount) / 100.0
		result.append(primary_modifier)
	for additional_modifier in modifiers:
		if additional_modifier != null:
			result.append(additional_modifier)
	return result


func apply_turn_start(target: TacticalCharacter) -> void:
	if (
		effect == Effect.DAMAGE_EACH_TURN
		and is_instance_valid(target)
		and target.current_health > 0
	):
		target.apply_damage(maxi(0, damage_per_turn))


func estimate_for_ai(
	caster: TacticalCharacter,
	target: TacticalCharacter,
	simulated_health: int,
	remaining_turns: int = -1
) -> Dictionary:
	var turns := duration_turns if remaining_turns < 0 else remaining_turns
	var health_delta := 0
	if effect == Effect.DAMAGE_EACH_TURN:
		health_delta = -mini(
			maxi(0, damage_per_turn) * maxi(0, turns),
			maxi(0, simulated_health)
		)
	var utility := affected_unit_ai_utility
	if (
		is_instance_valid(caster)
		and is_instance_valid(target)
		and caster.is_friendly() != target.is_friendly()
	):
		utility = -utility
	return {
		"health_delta": health_delta,
		"utility_hint": utility,
	}


func get_description(turns_override: int = -1) -> String:
	var turns := duration_turns if turns_override < 0 else turns_override
	var turn_text := "%d turn%s" % [turns, "" if turns == 1 else "s"]
	match effect:
		Effect.DAMAGE_EACH_TURN:
			var type_name := (
				"physical"
				if damage_type == DamageCalculator.Type.PHYSICAL
				else "magical"
			)
			return "%s: %d %s damage at turn start for %s" % [
				display_name,
				maxi(0, damage_per_turn),
				type_name,
				turn_text,
			]
		Effect.STAT_MODIFIER:
			var direction_name := (
				"Reduce"
				if modifier_direction == ModifierDirection.REDUCE
				else "Increase"
			)
			var amount_text := (
				"%d%%" % roundi(maxf(0.0, percentage_amount))
				if modifier_value_type == ModifierValueType.PERCENTAGE
				else "%.2f" % maxf(0.0, flat_amount)
			)
			return "%s: %s %s by %s for %s" % [
				display_name,
				direction_name,
				UnitStat.get_display_name(affected_stat),
				amount_text,
				turn_text,
			]
		Effect.STUN:
			return "%s: Cannot move, use abilities, or make opportunity attacks for %s" % [
				display_name,
				turn_text,
			]
		_:
			return "%s for %s" % [display_name, turn_text]
