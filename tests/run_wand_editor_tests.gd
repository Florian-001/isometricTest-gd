extends SceneTree

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _frames() -> void:
	for index in range(5):
		await process_frame


func _property(name: String) -> EditorProperty:
	for property in EditorInterface.get_inspector().find_children("*", "EditorProperty", true, false):
		if property.get_edited_property() == name:
			return property
	return null


func _run() -> void:
	if not Engine.is_editor_hint():
		quit(1)
		return
	await create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
	var wand := load("res://resources/items/weapons/wand.tres").duplicate() as ItemDefinition
	var shot := wand.basic_attack_override.duplicate() as AbilityDefinition
	EditorInterface.edit_resource(wand)
	await _frames()
	check(_property("basic_attack_override") != null, "Weapon Inspector exposes Basic Attack Override")
	if _property("basic_attack_override") != null:
		_property("basic_attack_override").emit_changed("basic_attack_override", shot)
		await _frames()
	check(wand.basic_attack_override == shot, "Inspector assigns custom attack")
	EditorInterface.edit_resource(shot)
	await _frames()
	for field in ["range", "scaling_stat", "scaling_amount", "damage_type", "accepts_weapon_range_bonus"]:
		check(_property(field) != null, "Attack Inspector exposes %s" % field)
	if _property("scaling_amount") != null:
		_property("scaling_amount").emit_changed("scaling_amount", 150.0)
		await _frames()
	check(shot.scaling_amount == 150, "Inspector edits Intelligence scaling")
	var actor := TacticalCharacter.new()
	actor.definition = CharacterDefinition.new()
	actor.definition.starting_class = CharacterClassDefinition.new()
	actor.intelligence_override = 10
	actor.set_dev_equipment(ItemDefinition.EquipmentSlot.WEAPON, wand)
	check(actor.get_abilities()[0] == shot and shot.calculate_damage(actor) == 20, "Inspector edited attack drives character damage preview")
	var path := "res://.godot/wand_validation/inspector_wand.tres"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	check(ResourceSaver.save(wand, path) == OK, "Inspector edited resource saves")
	var restored := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as ItemDefinition
	check(restored.basic_attack_override.scaling_amount == 150 and restored.get_granted_abilities()[0].range == 5, "Override and nested attack settings survive save/reload")
	EditorInterface.edit_resource(wand)
	await _frames()
	if _property("basic_attack_override") != null:
		_property("basic_attack_override").emit_changed("basic_attack_override", null)
		await _frames()
	check(wand.get_granted_abilities() == [load("res://resources/abilities/arrow.tres")], "Clearing override in Inspector restores Shoot")
	wand.slot = ItemDefinition.EquipmentSlot.ARMOR
	EditorInterface.edit_resource(wand)
	await _frames()
	check(_property("basic_attack_override") == null, "Non-weapon Inspector hides attack override")
	EditorInterface.get_inspector().edit(null)
	actor.free()
	for failure in failures:
		push_error(failure)
	print("WAND_EDITOR_%s: %d checks, %d failures" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	EditorInterface.get_base_control().get_tree().quit(0 if failures.is_empty() else 1)
