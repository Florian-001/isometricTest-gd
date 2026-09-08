class_name PassiveLoadout
extends RefCounted


static func validate(passives: Array[PassiveAbilityDefinition]) -> Array[String]:
	var errors: Array[String] = []
	var ids: Dictionary = {}
	for passive in passives:
		if passive == null:
			errors.append("Missing passive ability reference.")
			continue
		errors.append_array(passive.validate())
		if ids.has(passive.passive_id) and ids[passive.passive_id] != passive:
			errors.append("Different passive assets share ID '%s'." % passive.passive_id)
		ids[passive.passive_id] = passive
	return errors


static func to_data(passives: Array[PassiveAbilityDefinition]) -> Array:
	var result: Array = []
	var seen: Array[PassiveAbilityDefinition] = []
	for passive in passives:
		if passive != null and seen.has(passive):
			continue
		seen.append(passive)
		if passive == null:
			result.append(null)
		elif not passive.resource_path.is_empty() and not passive.resource_path.contains("::"):
			result.append(passive.resource_path)
		else:
			var effects: Array = []
			for effect in passive.effects:
				if effect != null and not effect.resource_path.is_empty() and not effect.resource_path.contains("::"):
					effects.append({"resource": effect.resource_path})
				elif effect is GroundImmunityPassiveEffect:
					effects.append({"type": "ground_immunity", "ignore_tile_effects": effect.ignore_tile_effects, "ignore_movement_modifiers": effect.ignore_movement_modifiers})
				elif effect is NearbyAlliesWeaponDamagePassiveEffect:
					effects.append({"type": "nearby_allies_weapon_damage", "radius": effect.radius, "damage_per_ally": effect.damage_per_ally})
				elif effect is ReassemblePassiveEffect:
					effects.append(effect.to_data())
				else:
					effects.append(null)
			result.append({"id": str(passive.passive_id), "name": passive.display_name, "description": passive.description, "icon": passive.icon.resource_path if passive.icon != null else "", "effects": effects})
	return result


static func from_data(data: Array) -> Array[PassiveAbilityDefinition]:
	var result: Array[PassiveAbilityDefinition] = []
	for entry in data:
		if entry is String:
			result.append(load(entry) as PassiveAbilityDefinition)
		else:
			var passive := PassiveAbilityDefinition.new()
			passive.passive_id = StringName(entry["id"])
			passive.display_name = entry["name"]
			passive.description = entry.get("description", "")
			if not str(entry.get("icon", "")).is_empty():
				passive.icon = load(entry["icon"]) as Texture2D
			var effects: Array[PassiveEffectDefinition] = []
			for settings in entry["effects"]:
				if settings.has("resource"):
					effects.append(load(settings["resource"]) as PassiveEffectDefinition)
				elif settings["type"] == "ground_immunity":
					var effect := GroundImmunityPassiveEffect.new()
					effect.ignore_tile_effects = settings["ignore_tile_effects"]
					effect.ignore_movement_modifiers = settings["ignore_movement_modifiers"]
					effects.append(effect)
				elif settings["type"] == "reassemble":
					effects.append(ReassemblePassiveEffect.from_data(settings))
				else:
					var effect := NearbyAlliesWeaponDamagePassiveEffect.new()
					effect.radius = settings["radius"]
					effect.damage_per_ally = int(settings["damage_per_ally"])
					effects.append(effect)
			passive.effects = effects
			result.append(passive)
	return result


static func validate_setup(setup: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if setup.has("override_passives") and not setup["override_passives"] is bool:
		errors.append("Passive override must be a boolean.")
	var data: Variant = setup.get("passives", [])
	if not data is Array:
		return ["Passive assignments must be an array."]
	for entry in data:
		if entry is String:
			if not ResourceLoader.exists(entry) or not load(entry) is PassiveAbilityDefinition:
				errors.append("Invalid passive resource: %s." % entry)
		elif entry is Dictionary:
			if not entry.get("id") is String or str(entry.get("id", "")).strip_edges().is_empty() or not entry.get("name") is String:
				errors.append("Inline passive requires an ID and name.")
			if not entry.get("description", "") is String or not entry.get("icon", "") is String:
				errors.append("Invalid passive presentation.")
			elif not str(entry.get("icon", "")).is_empty() and (not ResourceLoader.exists(entry["icon"]) or not load(entry["icon"]) is Texture2D):
				errors.append("Invalid passive icon.")
			if not entry.get("effects") is Array:
				errors.append("Passive effects must be an array.")
				continue
			for settings in entry["effects"]:
				if not settings is Dictionary:
					errors.append("Invalid passive effect.")
					continue
				if settings.has("resource"):
					var path: Variant = settings["resource"]
					if not path is String or not ResourceLoader.exists(path) or not load(path) is PassiveEffectDefinition:
						errors.append("Invalid shared passive effect reference.")
					continue
				match settings.get("type", ""):
					"reassemble":
						errors.append_array(ReassemblePassiveEffect.validate_data(settings))
					"ground_immunity":
						if not settings.get("ignore_tile_effects") is bool or not settings.get("ignore_movement_modifiers") is bool:
							errors.append("Ground immunity settings must be booleans.")
					"nearby_allies_weapon_damage":
						for key in ["radius", "damage_per_ally"]:
							var value: Variant = settings.get(key)
							if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0:
								errors.append("Invalid nearby ally effect %s." % key)
							elif key == "damage_per_ally" and (float(value) < 1.0 or float(value) != floorf(float(value))):
								errors.append("Damage per ally must be a positive integer.")
					_:
						errors.append("Unknown passive effect type.")
		else:
			errors.append("Invalid passive assignment.")
	if errors.is_empty():
		errors.append_array(validate(from_data(data)))
	if not setup.get("override_passives", false):
		var definition_path := str(setup.get("definition", ""))
		if ResourceLoader.exists(definition_path):
			var definition := load(definition_path) as CharacterDefinition
			if definition != null:
				errors.append_array(validate(definition.passive_abilities))
	return errors
