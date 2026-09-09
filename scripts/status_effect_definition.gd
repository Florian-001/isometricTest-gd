@tool
class_name StatusEffectDefinition
extends Resource

enum Effect {
	NONE,
	DAMAGE_EACH_TURN,
	STAT_MODIFIER,
	STUN,
	TAUNT,
}

enum Polarity {
	POSITIVE,
	NEGATIVE,
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
## Stable identifier used to combine applications into one active status.
@export var status_id: StringName = &"new_status"
@export var display_name: String = "New Status"
## Cleanse removes negative statuses, regardless of their source or effect.
@export var polarity: Polarity = Polarity.NEGATIVE
## Reapplication adds one stack. Each stack contributes the status's stat modifiers.
@export var stackable: bool = false
## No turn countdown; removed when combat finishes, before run results are captured.
@export var lasts_until_battle_end: bool = false:
	set(value):
		lasts_until_battle_end = value
		if Engine.is_editor_hint():
			notify_property_list_changed()
@export_range(1, 99, 1, "or_greater") var duration_turns: int = 1
## Count down at the owner's turn start instead of the existing turn-end duration tick.
@export var expires_at_turn_start: bool = false
## Temporary passive; removed with this status and deduplicated against authored passives.
@export var granted_passive: PassiveAbilityDefinition

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
@export var modifiers: Array[StatModifierDefinition] = []:
	set(value):
		modifiers = value
		if Engine.is_editor_hint():
			notify_property_list_changed()


func _validate_property(property: Dictionary) -> void:
	var property_name: StringName = property.name
	var should_hide := false
	if property_name in [&"duration_turns", &"expires_at_turn_start"]:
		should_hide = lasts_until_battle_end
	elif property_name in [&"damage_type", &"damage_per_turn"]:
		should_hide = effect != Effect.DAMAGE_EACH_TURN
	elif property_name == &"affected_unit_ai_utility":
		should_hide = effect not in [Effect.STAT_MODIFIER, Effect.STUN, Effect.TAUNT] and modifiers.is_empty() and granted_passive == null
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


func is_negative() -> bool:
	return polarity == Polarity.NEGATIVE


func get_stat_modifiers(stack_count: int = 1) -> Array[StatModifierDefinition]:
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
	var count := maxi(1, stack_count) if stackable else 1
	if count > 1:
		# Fold repeated modifiers without allocating one resource per stack or editing
		# shared definitions. Multiplicative modifiers compose once per stack.
		for index in range(result.size()):
			var scaled := result[index].duplicate() as StatModifierDefinition
			if scaled.operation == StatModifierDefinition.Operation.PERCENT_MULTIPLY:
				scaled.value = pow(maxf(0.0, 1.0 + scaled.value), count) - 1.0
			else:
				scaled.value *= count
			result[index] = scaled
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
	remaining_turns: int = -1,
	simulated_armor: int = -1
) -> Dictionary:
	var turns := duration_turns if remaining_turns < 0 else remaining_turns
	var armor := simulated_armor if simulated_armor >= 0 else (target.current_armor if is_instance_valid(target) else 0)
	var resolved := DamageCalculator.resolve_damage(
		maxi(0, damage_per_turn) * maxi(0, turns) if effect == Effect.DAMAGE_EACH_TURN else 0,
		simulated_health,
		armor
	)
	var utility := affected_unit_ai_utility
	if (
		is_instance_valid(caster)
		and is_instance_valid(target)
		and caster.is_friendly() != target.is_friendly()
	):
		utility = -utility
	return {
		"health_delta": int(resolved.health_delta),
		"armor_delta": int(resolved.armor_delta),
		"utility_hint": utility,
	}


func get_description(turns_override: int = -1) -> String:
	var description := _get_primary_description(turns_override)
	if granted_passive != null:
		description += " | " + granted_passive.get_description()
	if expires_at_turn_start and not lasts_until_battle_end:
		var turns := duration_turns if turns_override < 0 else turns_override
		description += " | Expires at next turn start" if turns == 1 else " | Expires in %d owner turn starts" % turns
	var modifier_descriptions: Array[String] = []
	for modifier in modifiers:
		if modifier == null or modifier.stat == UnitStat.Type.NONE:
			continue
		var amount := ("+" if modifier.value >= 0.0 else "") + _format_amount(modifier.value)
		if modifier.operation == StatModifierDefinition.Operation.PERCENT_ADD:
			amount = ("+" if modifier.value >= 0.0 else "") + _format_amount(modifier.value * 100.0) + "%"
		elif modifier.operation == StatModifierDefinition.Operation.PERCENT_MULTIPLY:
			amount = "×" + _format_amount(maxf(0.0, 1.0 + modifier.value))
		modifier_descriptions.append("%s %s%s" % [amount, UnitStat.get_display_name(modifier.stat), " per stack" if stackable else ""])
	if not modifier_descriptions.is_empty():
		description += " | " + ", ".join(modifier_descriptions)
	if lasts_until_battle_end:
		description += " | Until battle ends"
	return description + (" | Negative status" if is_negative() else " | Positive status")


func _get_primary_description(turns_override: int = -1) -> String:
	var turns := duration_turns if turns_override < 0 else turns_override
	var turn_text := "%d turn%s" % [turns, "" if turns == 1 else "s"]
	var duration_text := "" if lasts_until_battle_end else " for " + turn_text
	match effect:
		Effect.DAMAGE_EACH_TURN:
			var type_name := (
				"physical"
				if damage_type == DamageCalculator.Type.PHYSICAL
				else "magical"
			)
			return "%s: %d %s damage at turn start%s" % [
				display_name,
				maxi(0, damage_per_turn),
				type_name,
				duration_text,
			]
		Effect.STAT_MODIFIER:
			if stackable:
				var amount := _format_amount(maxf(0.0, flat_amount)) if modifier_value_type == ModifierValueType.FLAT else _format_amount(maxf(0.0, percentage_amount)) + "%"
				return "%s: %s%s %s per stack%s" % [
					display_name, "+" if modifier_direction == ModifierDirection.INCREASE else "-",
					amount, UnitStat.get_display_name(affected_stat), duration_text,
				]
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
			return "%s: %s %s by %s%s" % [
				display_name,
				direction_name,
				UnitStat.get_display_name(affected_stat),
				amount_text,
				duration_text,
			]
		Effect.STUN:
			return "%s: Cannot move, use abilities, or make opportunity attacks%s" % [
				display_name,
				duration_text,
			]
		Effect.TAUNT:
			return "%s: Attack the caster if possible; otherwise pursue them%s" % [display_name, duration_text]
		_:
			return "%s%s" % [display_name, duration_text]


func _format_amount(value: float) -> String:
	return ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".")
