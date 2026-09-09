extends SceneTree

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
	_output = _directory.path_join("reference.md")
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
	var document: String = result.text
	var expected := {
		"archer": [[2, "Focus"], [3, "Multiple Arrows"], [4, "Dagger Throw"]],
		"cleric": [[1, "Heal"], [1, "Beam"], [2, "Focus"], [3, "Empower"], [4, "Cleanse"]],
		"warrior": [[2, "Charge"], [3, "Battle Stomp"], [4, "Taunt"], [5, "Multi Attack"]],
		"wizard": [[1, "Ice Shard"], [2, "Searing Dagger"], [3, "Slow"], [4, "Fireball"], [5, "Beam"]],
	}
	for class_id in expected:
		var definition := load("res://resources/classes/%s.tres" % class_id) as CharacterClassDefinition
		var section := document.split("## " + definition.display_name + "\n")[1].split("\n## ")[0]
		for unlock in expected[class_id]:
			_check(section.contains("| %d | [%s]" % [unlock[0], unlock[1]]), "%s shows %s at level %d" % [class_id, unlock[1], unlock[0]])
	_check(document.find("## Archer") < document.find("## Cleric") and document.find("## Cleric") < document.find("## Warrior") and document.find("## Warrior") < document.find("## Wizard"), "classes are alphabetical")
	_check(document.contains("[Strike](resources/abilities/strike.tres)") and document.contains("[Shoot](resources/abilities/arrow.tres)"), "shared basic attacks have resource links")
	_check(document.contains("20 innate + Intelligence x100%") and document.contains("3 hits × (weapon damage + Dexterity x60%)"), "damage formulas come from the existing descriptions")
	_check(document.contains("+1 Constitution") and document.contains("Remove all negative statuses; preserve positive statuses"), "status modifiers and cleansing are described")
	_check(document.contains("Area: circle, 7-cell span") and document.contains("Line from caster toward target"), "area and line targeting are described")
	_check(document.contains("Melee weapon required") and document.contains("Ranged weapon required") and document.contains("No weapon required"), "equipment requirements are described")
	_check(Generator.build().text == document, "generation is deterministic")
	# Every generated link resolves to a real project file, including the guide link.
	var links := RegEx.new()
	links.compile("\\]\\(([^)]+)\\)")
	for link in links.search_all(document):
		_check(FileAccess.file_exists("res://" + link.get_string(1).uri_decode()), "link resolves: " + link.get_string(1))


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
	_check(original.text.contains("Test \\[ability\\] \\| &lt;&amp;&gt;"), "Markdown labels escape brackets, pipes, and HTML")
	_check(original.text.contains("ability%20%28test%29.tres"), "resource link encodes spaces and parentheses")
	var section: String = original.text.split("## Alpha\n")[1].split("\n## ")[0]
	_check(section.find("Test ") < section.find("[Heal]") and section.find("[Heal]") < section.find("[Beam]"), "unlocks sort by level and retain authored tie order")
	_check(original.text.count("| 1 | [Heal]") == 2, "a shared ability is listed for each class that grants it")
	var fingerprint := Generator.input_fingerprint(_classes)
	_ability.innate_damage = 47
	_ability.range = 9
	_status.duration_turns = 7
	_status.modifiers[0].value = 4
	_class.ability_unlocks[1].required_level = 3
	_check(Generator.build(_classes).text == original.text, "unsaved cached ability, class, and nested status edits are excluded")
	_check(Generator.input_fingerprint(_classes) == fingerprint, "unsaved edits do not change the source fingerprint")
	_check(_ability.innate_damage == 47 and _status.duration_turns == 7 and _class.ability_unlocks[1].required_level == 3, "generating never overwrites unsaved Inspector objects")
	ResourceSaver.save(_ability, _ability.resource_path)
	ResourceSaver.save(_status, _status.resource_path)
	ResourceSaver.save(_class, _class.resource_path)
	var changed := Generator.build(_classes)
	_check(changed.ok and changed.text.contains("47 innate") and changed.text.contains("Range 9.00"), "saved damage and range changes appear")
	_check(changed.text.contains("Test Status for 7 turns") and changed.text.contains("+4 Strength"), "saved nested status duration and modifier changes appear")
	_check(changed.text.contains("| 3 | [Test "), "saved class unlock change appears")
	_check(Generator.input_fingerprint(_classes) != fingerprint, "saved dependency changes update the fingerprint")
	var new_class := CharacterClassDefinition.new()
	new_class.class_id = &"new_class"
	new_class.display_name = "New Class"
	ResourceSaver.save(new_class, _classes.path_join("new.tres"))
	_check(Generator.build(_classes).text.contains("## New Class\n"), "new classes are discovered without configuration")
	_check(Generator.build(_classes).text.contains("No class unlocks; basic attacks are still available."), "classes with no unlocks are explicit")
	DirAccess.remove_absolute(_classes.path_join("new.tres"))
	_check(not Generator.build(_classes).text.contains("## New Class\n"), "removed classes disappear")
	var saved_text := FileAccess.get_file_as_string(_ability.resource_path)
	_write(_ability.resource_path, saved_text.replace("innate_damage = 47", "innate_damage = 61"))
	_check(Generator.build(_classes).text.contains("61 innate"), "external disk edits replace stale cached values")
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
	var temporary_files := Array(DirAccess.get_files_at(_directory)).filter(func(path: String) -> bool: return path.begins_with("reference.md.tmp-"))
	_check(temporary_files.is_empty(), "completed generation leaves no temporary file")


func _test_failures() -> void:
	var previous := FileAccess.get_file_as_string(_output)
	_class.ability_unlocks[1].required_level = 0
	ResourceSaver.save(_class, _class.resource_path)
	_check(not Generator.update(_output, _classes).ok, "invalid unlock fails generation")
	_check(FileAccess.get_file_as_string(_output) == previous, "validation failure preserves the previous reference")
	_class.ability_unlocks[1].required_level = 3
	ResourceSaver.save(_class, _class.resource_path)
	var ability_text := FileAccess.get_file_as_string(_ability.resource_path)
	_write(_ability.resource_path, ability_text.replace(_status.resource_path, _directory.path_join("missing.tres")))
	var missing := Generator.update(_output, _classes)
	_check(not missing.ok and str(missing.errors).contains("missing.tres"), "missing nested dependency reports the file")
	_check(FileAccess.get_file_as_string(_output) == previous, "missing dependency preserves the previous reference")
	_write(_ability.resource_path, ability_text)
	var invalid_script := _directory.path_join("invalid_description.gd")
	_write(invalid_script, "@tool\nextends AbilityEffectDefinition\nfunc get_description(_caster: TacticalCharacter = null) -> String:\n\tpush_error(\"Invalid description fixture\")\n\treturn \"Partial result\"\n")
	var invalid_effect: AbilityEffectDefinition = load(invalid_script).new()
	_ability.effects.append(invalid_effect)
	ResourceSaver.save(_ability, _ability.resource_path)
	print("Testing an intentional description error; the previous document must survive.")
	var invalid_result := Generator.update(_output, _classes)
	_check(not invalid_result.ok and str(invalid_result.errors).contains("Invalid description fixture"), "nested description script errors fail instead of publishing partial output")
	_check(FileAccess.get_file_as_string(_output) == previous, "script failure preserves the previous reference")
	_check(not Generator.update(_directory.path_join("missing_directory/ref.md"), Generator.CLASSES_DIRECTORY).ok, "write failure is reported")


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()
