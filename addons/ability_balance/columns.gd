@tool
extends RefCounted

const ACTIVE_DEFAULTS := ["display_name", "ap_cost", "cooldown_turns", "ability_type", "effect", "damage_type", "innate_damage", "effect_amount", "scaling_stat", "scaling_amount", "hit_count", "range", "area_of_effect"]
const PASSIVE_DEFAULTS := ["display_name", "passive_id", "description", "effect_summary", "validation"]
const ACTIVE_EFFECTS := ["res://scripts/damage_effect_definition.gd", "res://scripts/heal_effect_definition.gd", "res://scripts/apply_status_effect_definition.gd", "res://scripts/knockback_effect_definition.gd"]
const PASSIVE_EFFECTS := ["res://scripts/counter_passive_effect.gd", "res://scripts/ground_immunity_passive_effect.gd", "res://scripts/nearby_allies_weapon_damage_passive_effect.gd", "res://scripts/reassemble_passive_effect.gd"]
const PRESENTATION := ["image", "icon", "placeholder_color", "projectile_speed", "melee_lunge_ratio", "melee_lunge_duration", "melee_return_duration", "melee_slash_duration", "melee_slash_color"]


static func defaults(table: String) -> Array:
	return ACTIVE_DEFAULTS.duplicate() if table == "active" else PASSIVE_DEFAULTS.duplicate()


static func definitions(table: String) -> Array:
	var resource: Resource = AbilityDefinition.new() if table == "active" else PassiveAbilityDefinition.new()
	if resource is AbilityDefinition:
		resource.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	var result: Array = []
	for property in resource.get_property_list():
		if not editable_property(property) or property.name in PRESENTATION or property.name == "effects":
			continue
		var column := from_property(property)
		column.group = "Overview" if column.key in defaults(table) else "Targeting and requirements"
		result.append(column)
	result.append(make_result("effect_summary", "Effects"))
	result.append(make_result("validation", "Validation"))
	var ordered: Array = []
	for key in defaults(table):
		for column in result:
			if column.key == key:
				ordered.append(column)
	for column in result:
		if column.key not in defaults(table):
			ordered.append(column)
	return ordered


static func editable_property(property: Dictionary) -> bool:
	return bool(property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) and bool(property.usage & PROPERTY_USAGE_STORAGE) and property.type not in [TYPE_ARRAY, TYPE_DICTIONARY, TYPE_CALLABLE]


static func make_result(key: String, title: String) -> Dictionary:
	return {"key": key, "title": title, "group": "Summary", "kind": "result", "width": 240.0}


static func from_property(property: Dictionary) -> Dictionary:
	var key := str(property.name)
	var column := {"key": key, "title": key.capitalize(), "group": "Properties", "kind": "text", "width": 135.0, "min": -INF, "max": INF, "choices": [], "values": [], "resource_type": str(property.hint_string)}
	match int(property.type):
		TYPE_BOOL: column.kind = "bool"
		TYPE_INT: column.kind = "integer"
		TYPE_FLOAT: column.kind = "number"
		TYPE_COLOR: column.kind = "color"
		TYPE_OBJECT: column.kind = "resource"
	if property.hint == PROPERTY_HINT_MULTILINE_TEXT:
		column.kind = "multiline"
		column.width = 300.0
	if property.hint == PROPERTY_HINT_ENUM:
		column.kind = "enum"
		var next := 0
		for option in str(property.hint_string).split(","):
			var pair := option.split(":")
			if pair.size() > 1:
				next = int(pair[1])
			column.choices.append(pair[0])
			column.values.append(next)
			next += 1
	if property.hint == PROPERTY_HINT_FLAGS:
		column.kind = "flags"
		column.min = 0
		column.max = 0
		for option in str(property.hint_string).split(","):
			var pair := option.split(":")
			column.choices.append(pair[0])
			var flag: int = int(pair[1]) if pair.size() > 1 else 1 << (column.choices.size() - 1)
			column.values.append(flag)
			column.max = int(column.max) | flag
	if property.hint == PROPERTY_HINT_RANGE:
		var hints := str(property.hint_string).split(",")
		column.min = -INF if "or_less" in hints else float(hints[0])
		column.max = INF if "or_greater" in hints else float(hints[1])
	if key in ["display_name", "passive_id"]:
		column.width = 200.0
	if key == "scaling_amount":
		column.title = "Scaling %"
	elif key == "effect_amount":
		column.title = "Base healing"
	elif key == "scaling_stat":
		column.title = "Scaling source"
	elif key == "ap_cost":
		column.title = "AP cost"
	elif key == "cooldown_turns":
		column.title = "CD (turns)"
	return column


static func property_column(resource: Resource, key: String) -> Dictionary:
	for property in resource.get_property_list():
		if property.name == key:
			if resource is AbilityDefinition and key == "scaling_stat":
				property.hint = PROPERTY_HINT_ENUM
				property.hint_string = DamageCalculator.WEAPON_SCALING_OPTIONS if resource._can_select_weapon_scaling() else DamageCalculator.UNIT_STAT_SCALING_OPTIONS
			return from_property(property)
	return {}


static func format_value(column: Dictionary, value: Variant) -> String:
	if column.kind == "enum":
		var index: int = column.values.find(value)
		return str(column.choices[index]) if index >= 0 else str(value)
	if column.kind == "bool":
		return "Yes" if value else "No"
	if column.kind == "flags":
		var labels: Array[String] = []
		for index in range(column.values.size()):
			if int(value) & int(column.values[index]):
				labels.append(column.choices[index])
		return " | ".join(labels) if not labels.is_empty() else "None"
	if column.kind == "resource":
		if value == null:
			return "None"
		return str(value.get("display_name")) if value.get("display_name") != null else value.resource_path.get_file()
	if column.kind == "color":
		return "#" + value.to_html()
	return str(value).replace("\n", " ↵ ").replace("\t", " ")


static func parse(column: Dictionary, text: String) -> Dictionary:
	var value := text.strip_edges()
	match str(column.kind):
		"result": return {"error": "This column is a read-only summary."}
		"text":
			if value.is_empty() or "\n" in value or "\t" in value:
				return {"error": "Enter a non-empty single-line value."}
			return {"value": value}
		"multiline": return {"value": text.replace(" ↵ ", "\n")}
		"bool":
			if value.to_lower() in ["yes", "true", "1", "no", "false", "0"]:
				return {"value": value.to_lower() in ["yes", "true", "1"]}
			return {"error": "Choose Yes or No."}
		"color":
			if Color.html_is_valid(value):
				return {"value": Color.html(value)}
			return {"error": "Enter a hex color, such as #ff8800ff."}
		"resource":
			if value in ["", "None"]:
				return {"value": null}
			if not ResourceLoader.exists(value):
				return {"error": "Resource does not exist: " + value}
			var resource := load(value)
			var expected: String = column.resource_type
			if (expected == "Texture2D" and resource is Texture2D) or (expected == "StatusEffectDefinition" and resource is StatusEffectDefinition):
				return {"value": {"$ref": value}}
			return {"error": "Choose a " + expected + " resource."}
		"enum":
			for index in range(column.choices.size()):
				if value.to_lower() == str(column.choices[index]).to_lower():
					return {"value": column.values[index]}
			if value.is_valid_int() and int(value) in column.values:
				return {"value": int(value)}
			return {"error": "Choose a valid " + column.title + "."}
		"flags":
			if value == "None":
				return {"value": 0}
			if not value.is_valid_int():
				var flags := 0
				for label in value.split("|"):
					var index: int = column.choices.find(label.strip_edges())
					if index < 0:
						return {"error": "Unknown target flag: " + label}
					flags |= int(column.values[index])
				return {"value": flags}
	if not value.is_valid_float() or not is_finite(value.to_float()):
		return {"error": column.title + " needs a finite number."}
	var number := value.to_float()
	if number < column.min or number > column.max or (column.kind in ["integer", "flags"] and number != floorf(number)):
		return {"error": "Value is outside the allowed range for " + column.title + "."}
	return {"value": int(number) if column.kind in ["integer", "flags"] else number}
