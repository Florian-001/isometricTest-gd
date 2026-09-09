extends SceneTree

const Xlsx = preload("res://tests/class_reference_xlsx_reader.gd")
const Generator = preload("res://addons/class_ability_reference/reference_generator.gd")

var _failures: Array[String] = []
var _checks := 0
var _directory := "res://.godot/class_ability_reference_validation/unit_%d" % Time.get_ticks_usec()
var _classes := ""
var _output := ""
var _ability: AbilityDefinition
var _status: StatusEffectDefinition
var _class: CharacterClassDefinition


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _run() -> void:
	_classes = _directory.path_join("classes")
	_output = _directory.path_join("reference.xlsx")
	DirAccess.make_dir_recursive_absolute(_classes)
	_test_shipped_reference()
	_create_fixture()
	_test_saved_data_and_formatting()
	await _test_writes_and_checks()
	_test_failures()
	for failure in _failures:
		push_error(failure)
	print("CLASS_ABILITY_REFERENCE_TESTS_%s (%d checks)" % ["OK" if _failures.is_empty() else "FAILED", _checks])
	quit(0 if _failures.is_empty() else 1)


func _test_shipped_reference() -> void:
	var result := Generator.build()
	_check(result.ok, "shipped classes generate successfully")
	if not result.ok:
		return
	var records: Array = result.rows
	var index := 2
	_check(records[0].class == "All classes" and records[0].ability == "Strike" and records[0].level == null, "shared Strike has no class unlock requirement")
	_check(records[1].class == "All classes" and records[1].ability == "Shoot" and records[1].level == null, "shared Shoot has no class unlock requirement")
	var errors: Array[String] = []
	var definitions: Array = []
	for path in Generator._class_paths(Generator.CLASSES_DIRECTORY, errors):
		definitions.append(load(path))
	definitions.sort_custom(func(a: Resource, b: Resource) -> bool: return a.display_name.nocasecmp_to(b.display_name) < 0)
	for definition in definitions:
		for unlock in definition.get_sorted_unlocks():
			_check(index < records.size(), "record exists for every saved unlock")
			if index >= records.size():
				return
			var record: Dictionary = records[index]
			_check(record.class == definition.display_name and record.ability == unlock.ability.display_name and record.level == unlock.required_level, "saved class, ability, level and tie order match at row %d" % index)
			_check(record.level is int, "unlock is numeric")
			_check(record.description.begins_with(unlock.ability.get_description().replace(" | ", ". ")), "description comes directly from saved ability methods")
			index += 1
	_check(index == records.size(), "no omitted or extra unlock records")
	var document := JSON.stringify(records)
	_check(document.contains("20 innate + Intelligence x100%") and document.contains("3 hits × (weapon damage + Dexterity x60%)"), "damage formulas come from existing descriptions")
	_check(document.contains("+1 Constitution") and document.contains("Remove all negative statuses; preserve positive statuses"), "status modifiers and cleansing are described")
	_check(document.contains("Area: circle, 7-cell span") and document.contains("Line from caster toward target"), "area and line targeting are described")
	_check(document.contains("Melee weapon required") and document.contains("Ranged weapon required") and document.contains("No weapon required"), "equipment requirements are described")
	_check(Generator.build().rows == records, "generation is deterministic")
	var scripts := {}
	Generator._collect_scripts("res://addons/class_ability_reference", scripts)
	_check(scripts.has(Generator.Spreadsheet.EXPORTER), "spreadsheet exporter participates in dependency fingerprinting")
	_write("res://.godot/class_ability_reference/shipped_rows.json", JSON.stringify({"rows": records}))


func _create_fixture() -> void:
	_status = StatusEffectDefinition.new()
	_status.status_id = &"reference_test"
	_status.display_name = "Test Status"
	_status.duration_turns = 2
	_status.modifiers = [StatModifierDefinition.new()]
	_status.modifiers[0].value = 2
	_check(ResourceSaver.save(_status, _directory.path_join("status.tres")) == OK, "save external status fixture")
	_status = load(_directory.path_join("status.tres"))
	_ability = AbilityDefinition.new()
	_ability.display_name = "Test [ability] | <&>"
	_ability.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	_ability.innate_damage = 17
	var apply_status := ApplyStatusEffectDefinition.new()
	apply_status.status_effect = _status
	_ability.effects = [apply_status]
	_check(ResourceSaver.save(_ability, _directory.path_join("ability (test).tres")) == OK, "save external ability fixture")
	_ability = load(_directory.path_join("ability (test).tres"))
	_class = CharacterClassDefinition.new()
	_class.class_id = &"alpha"
	_class.display_name = "Alpha"
	var late := ClassAbilityUnlock.new()
	late.ability = load("res://resources/abilities/beam.tres")
	late.required_level = 5
	var first := ClassAbilityUnlock.new()
	first.ability = _ability
	var tied := ClassAbilityUnlock.new()
	tied.ability = load("res://resources/abilities/heal.tres")
	_class.ability_unlocks = [late, first, tied]
	_check(ResourceSaver.save(_class, _classes.path_join("z_alpha.tres")) == OK, "save unsorted class fixture")
	_class = load(_classes.path_join("z_alpha.tres"))
	var other := CharacterClassDefinition.new()
	other.class_id = &"zulu"
	other.display_name = "Zulu"
	other.ability_unlocks = [tied]
	_check(ResourceSaver.save(other, _classes.path_join("a_zulu.tres")) == OK, "save another class sharing an ability")


func _test_saved_data_and_formatting() -> void:
	var original := Generator.build(_classes)
	_check(original.ok, "fixture generates")
	if not original.ok:
		return
	_check(original.rows[2].ability == "Test [ability] | <&>", "labels remain literal structured text")
	_check(original.rows[2].ability.begins_with("Test ") and original.rows[3].ability == "Heal" and original.rows[4].ability == "Beam", "unlocks sort by level and retain authored tie order")
	_check(original.rows[3].class == "Alpha" and original.rows[5].class == "Zulu" and original.rows[5].ability == "Heal", "a shared ability is listed for each class that grants it")
	var fingerprint := Generator.input_fingerprint(_classes)
	_ability.innate_damage = 47
	_ability.range = 9
	_status.duration_turns = 7
	_status.modifiers[0].value = 4
	_class.ability_unlocks[1].required_level = 3
	_check(Generator.build(_classes).rows == original.rows, "unsaved cached ability, class, and nested status edits are excluded")
	_check(Generator.input_fingerprint(_classes) == fingerprint, "unsaved edits do not change the source fingerprint")
	_check(_ability.innate_damage == 47 and _status.duration_turns == 7 and _class.ability_unlocks[1].required_level == 3, "generating never overwrites unsaved Inspector objects")
	ResourceSaver.save(_ability, _ability.resource_path)
	ResourceSaver.save(_status, _status.resource_path)
	ResourceSaver.save(_class, _class.resource_path)
	var changed := Generator.build(_classes)
	_check(changed.ok and JSON.stringify(changed.rows).contains("47 innate") and JSON.stringify(changed.rows).contains("Range 9.00"), "saved damage and range changes appear")
	_check(JSON.stringify(changed.rows).contains("Test Status for 7 turns") and JSON.stringify(changed.rows).contains("+4 Strength"), "saved nested status duration and modifier changes appear")
	_check(changed.rows[3].level == 3 and changed.rows[3].ability.begins_with("Test "), "saved class unlock change appears")
	_check(Generator.input_fingerprint(_classes) != fingerprint, "saved dependency changes update the fingerprint")
	var new_class := CharacterClassDefinition.new()
	new_class.class_id = &"new_class"
	new_class.display_name = "New Class"
	ResourceSaver.save(new_class, _classes.path_join("new.tres"))
	_check(JSON.stringify(Generator.build(_classes).rows).contains("New Class"), "new classes are discovered without configuration")
	_check(JSON.stringify(Generator.build(_classes).rows).contains("No class unlocks; basic attacks are still available."), "classes with no unlocks are explicit")
	DirAccess.remove_absolute(_classes.path_join("new.tres"))
	_check(not JSON.stringify(Generator.build(_classes).rows).contains("New Class"), "removed classes disappear")
	var saved_text := FileAccess.get_file_as_string(_ability.resource_path)
	_write(_ability.resource_path, saved_text.replace("innate_damage = 47", "innate_damage = 61"))
	_check(JSON.stringify(Generator.build(_classes).rows).contains("61 innate"), "external disk edits replace stale cached values")
	_check(_ability.innate_damage == 47, "reading an external edit does not replace the cached Inspector resource")


func _test_writes_and_checks() -> void:
	var missing := Generator.update(_output, _classes, true)
	_check(not missing.ok and not FileAccess.file_exists(_output), "--check detects a missing document without creating it")
	var written := Generator.update(_output, _classes)
	_check(written.ok and written.changed, "initial generation writes the reference")
	var modified := FileAccess.get_modified_time(_output)
	await create_timer(1.1).timeout
	var unchanged := Generator.update(_output, _classes)
	_check(unchanged.ok and not unchanged.changed and FileAccess.get_modified_time(_output) == modified, "unchanged output is not rewritten")
	_check(Generator.update(_output, _classes, true).ok, "--check accepts current output")
	_write(_output, "Old document\n")
	_check(not Generator.update(_output, _classes, true).ok and FileAccess.get_file_as_string(_output) == "Old document\n", "--check rejects stale content without writing")
	_check(Generator.update(_output, _classes).ok, "existing output can be replaced atomically on this platform")
	var cells := Xlsx.cells(_output)
	var records: Array = Generator.build(_classes).rows
	for index in records.size():
		var row: Dictionary = records[index]
		var number := index + 6
		_check(cells.get("A%d" % number) == row.class and cells.get("B%d" % number) == row.level and cells.get("C%d" % number) == row.ability and cells.get("D%d" % number) == row.description, "reopened workbook matches all four resource fields, including numeric levels")
	var sheet := Xlsx.part(_output, "xl/worksheets/sheet1.xml")
	var table := Xlsx.part(_output, "xl/tables/table1.xml")
	_check(sheet.contains('ySplit="5"') and sheet.contains('state="frozen"'), "headers and guidance are frozen")
	_check(table.contains("autoFilter") and table.contains('name="ClassAbilities"'), "native filterable table is present")
	_check(Xlsx.part(_output, "xl/styles.xml").contains('wrapText="1"'), "long descriptions are wrapped")
	var previous := FileAccess.get_sha256(_output)
	var had_override := OS.has_environment("CLASS_ABILITIES_NODE")
	var old_override := OS.get_environment("CLASS_ABILITIES_NODE")
	OS.set_environment("CLASS_ABILITIES_NODE", _directory.path_join("missing-node"))
	_check(not Generator.update(_output, _classes).ok and FileAccess.get_sha256(_output) == previous, "missing runtime reports failure and preserves the previous workbook")
	if had_override:
		OS.set_environment("CLASS_ABILITIES_NODE", old_override)
	else:
		OS.unset_environment("CLASS_ABILITIES_NODE")



func _test_failures() -> void:
	var previous := FileAccess.get_sha256(_output)
	_class.ability_unlocks[1].required_level = 0
	ResourceSaver.save(_class, _class.resource_path)
	_check(not Generator.update(_output, _classes).ok, "invalid unlock fails generation")
	_check(FileAccess.get_sha256(_output) == previous, "validation failure preserves the previous reference")
	_class.ability_unlocks[1].required_level = 3
	ResourceSaver.save(_class, _class.resource_path)
	var ability_text := FileAccess.get_file_as_string(_ability.resource_path)
	_write(_ability.resource_path, ability_text.replace(_status.resource_path, _directory.path_join("missing.tres")))
	var missing := Generator.update(_output, _classes)
	_check(not missing.ok and str(missing.errors).contains("missing.tres"), "missing nested dependency reports the file")
	_check(FileAccess.get_sha256(_output) == previous, "missing dependency preserves the previous reference")
	_write(_ability.resource_path, ability_text)
	var invalid_script := _directory.path_join("invalid_description.gd")
	_write(invalid_script, "@tool\nextends AbilityEffectDefinition\nfunc get_description(_caster: TacticalCharacter = null) -> String:\n\tpush_error(\"Invalid description fixture\")\n\treturn \"Partial result\"\n")
	var invalid_effect: AbilityEffectDefinition = load(invalid_script).new()
	_ability.effects.append(invalid_effect)
	ResourceSaver.save(_ability, _ability.resource_path)
	print("Testing an intentional description error; the previous document must survive.")
	var invalid_result := Generator.update(_output, _classes)
	_check(not invalid_result.ok and str(invalid_result.errors).contains("Invalid description fixture"), "nested description script errors fail instead of publishing partial output")
	_check(FileAccess.get_sha256(_output) == previous, "script failure preserves the previous reference")
	_write(_directory.path_join("blocked"), "not a directory")
	_check(not Generator.update(_directory.path_join("blocked/ref.xlsx"), Generator.CLASSES_DIRECTORY).ok, "write failure is reported")


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()
