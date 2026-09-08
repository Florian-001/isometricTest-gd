extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _frames() -> void:
	for index in range(5):
		await process_frame


func _property(property_name: String) -> EditorProperty:
	for property in EditorInterface.get_inspector().find_children("*", "EditorProperty", true, false):
		if property.get_edited_property() == property_name:
			return property
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	await create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
	var passive := PassiveAbilityDefinition.new()
	passive.passive_id = &"editor_test_pack"
	var effect := NearbyAlliesWeaponDamagePassiveEffect.new()
	passive.effects = [effect]
	EditorInterface.edit_resource(passive)
	await _frames()
	for key in ["passive_id", "display_name", "description", "icon", "effects"]:
		_check(_property(key) != null, "Passive Inspector exposes %s" % key)
	EditorInterface.edit_resource(effect)
	await _frames()
	for key in ["radius", "damage_per_ally"]:
		_check(_property(key) != null, "Proximity Inspector exposes %s" % key)
		if _property(key) != null:
			_property(key).emit_changed(key, 3)
	await _frames()
	var immunity := GroundImmunityPassiveEffect.new()
	EditorInterface.edit_resource(immunity)
	await _frames()
	for key in ["ignore_tile_effects", "ignore_movement_modifiers"]:
		_check(_property(key) != null, "Flight Inspector exposes %s" % key)
	var reassemble := ReassemblePassiveEffect.new()
	EditorInterface.edit_resource(reassemble)
	await _frames()
	var values := {"pile_health": 2, "restored_health_percentage": 50.0,
		"pile_texture": load("res://assets/characters/bone_pile.png")}
	for key in values:
		_check(_property(key) != null, "Reassemble Inspector exposes %s" % key)
		if _property(key) != null:
			_property(key).emit_changed(key, values[key])
	await _frames()
	var reassemble_path := "res://.godot/passive_validation/editor_reassemble.tres"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(reassemble_path.get_base_dir()))
	_check(ResourceSaver.save(reassemble, reassemble_path) == OK, "Reassemble Inspector resource saves")
	var restored_reassemble := ResourceLoader.load(reassemble_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as ReassemblePassiveEffect
	_check(restored_reassemble.pile_health == 2 and restored_reassemble.restored_health_percentage == 50.0 and restored_reassemble.pile_texture.resource_path == values.pile_texture.resource_path, "Reassemble Inspector edits survive reload")
	var definition := EnemyDefinition.new()
	definition.passive_abilities = [passive]
	EditorInterface.edit_resource(definition)
	await _frames()
	_check(_property("passive_abilities") != null, "Enemy template exposes starting passive list")
	var path := "res://.godot/passive_validation/editor_inline.tres"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	_check(ResourceSaver.save(definition, path) == OK, "Template with inline passive saves")
	var restored := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EnemyDefinition
	_check(restored.passive_abilities[0].effects[0].radius == 3.0 and restored.passive_abilities[0].effects[0].damage_per_ally == 3, "Inspector changes survive resource reload")
	for failure in failures:
		push_error(failure)
	print("PASSIVE_EDITOR_%s" % ("OK" if failures.is_empty() else "FAILED"))
	EditorInterface.get_base_control().get_tree().quit(0 if failures.is_empty() else 1)
