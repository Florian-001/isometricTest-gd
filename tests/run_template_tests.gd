extends SceneTree

const Painter = preload("res://addons/spawn_painter/spawn_painter_plugin.gd")
const PaintMode = preload("res://addons/spawn_painter/paint_tool_mode.gd")
const DEMO := "res://resources/maps/spawn_template_demo.tres"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_selection()
	_test_invalid_enemies()
	_test_painting()
	_test_layout_and_saved_rosters()
	await process_frame
	if _failures.is_empty():
		print("TEMPLATE_TESTS_OK")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _scene(cr: int, label: String = "Enemy") -> PackedScene:
	var actor := TacticalCharacter.new()
	actor.name = label
	var definition := EnemyDefinition.new()
	definition.combat_rating = cr
	actor.definition = definition
	var scene := PackedScene.new()
	scene.pack(actor)
	actor.free()
	return scene


func _template(budget: int, ratings: Array[int]) -> BattleMapTemplateDefinition:
	var template := BattleMapTemplateDefinition.new()
	template.combat_rating = budget
	for index in range(ratings.size()):
		template.enemy_pool.append(_scene(ratings[index], "Type%d" % index))
	return template


func _generate(template: BattleMapTemplateDefinition, capacity: int, seed_value: int = 17) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return EnemyEncounterGenerator.generate(template, capacity, rng)


func _test_selection() -> void:
	var exact := _generate(_template(6, [4, 3]), 2)
	_check(exact.error.is_empty() and exact.total_cr == 6 and exact.scenes.size() == 2, "Budget 6 must choose 3 + 3, not greedy 4")
	var below := _generate(_template(7, [4, 6]), 2)
	_check(below.total_cr == 6, "Never exceed budget to reach a closer total")
	var limited := _generate(_template(10, [3, 4]), 2)
	_check(limited.total_cr == 8 and limited.scenes.size() == 2, "Spawn capacity constrains the optimum")
	_check(_generate(_template(4, [2]), 8).scenes.size() == 2, "Unused spawn cells remain empty")
	_check(not _generate(_template(2, [3, 4]), 5).error.is_empty(), "Unaffordable pools fail instead of making empty battles")
	_check(not _generate(_template(10, [1]), 0).error.is_empty(), "No enemy cells is an error")
	var large := _generate(_template(1000000000, [300000000, 400000000]), 2)
	_check(large.total_cr == 800000000, "Large sparse CR values do not allocate budget-sized arrays")
	var template := _template(6, [2, 3, 2])
	var first := _generate(template, 3, 123)
	var same := _generate(template, 3, 123)
	_check(first.scenes == same.scenes and first.total_cr == same.total_cr, "Equal seeds reproduce selection")
	var counts := {}
	var variants := {}
	for seed_value in range(80):
		var result := _generate(template, 3, seed_value)
		_check(result.total_cr == 6, "Every seed retains the optimum")
		counts[result.scenes.size()] = true
		var indices: Array[int] = []
		for scene in result.scenes:
			indices.append(template.enemy_pool.find(scene))
		variants[str(indices)] = true
	_check(counts.has(2) and counts.has(3), "Random ties include different optimal enemy counts")
	_check(variants.size() > 2, "Equal-CR enemy types produce varied optimal groups")
	var unique := _generate(template, 3, 27)
	template.enemy_pool.append(template.enemy_pool[0])
	_check(_generate(template, 3, 27).scenes == unique.scenes, "Duplicate pool entries do not change weighting or deterministic output")


func _test_invalid_enemies() -> void:
	for rating in [0, -1]:
		_check(not _generate(_template(3, [rating]), 2).error.is_empty(), "Nonpositive enemy CR is rejected")
	_check(not _generate(_template(0, [1]), 2).error.is_empty(), "Nonpositive map CR is rejected")
	_check(not _generate(_template(3, []), 2).error.is_empty(), "Empty pools are rejected")
	var template := _template(3, [1])
	template.enemy_pool.append(null)
	_check(not _generate(template, 2).error.is_empty(), "Empty entries are rejected")
	var node := Node2D.new()
	var wrong_scene := PackedScene.new()
	wrong_scene.pack(node)
	node.free()
	template.enemy_pool = [wrong_scene]
	_check(not _generate(template, 2).error.is_empty(), "Wrong scene roots are rejected")
	template.enemy_pool = [load("res://scenes/friendlies/friend_a.tscn")]
	_check(not _generate(template, 2).error.is_empty(), "Friendly scenes are rejected from enemy pools")
	template.enemy_pool = [PackedScene.new()]
	_check(not _generate(template, 2).error.is_empty(), "Unpopulated PackedScene resources are rejected safely")


func _test_painting() -> void:
	var map := (load("res://scenes/maps/spawn_template_demo.tscn") as PackedScene).instantiate() as BattleMap
	root.add_child(map)
	var spawns := map.get_node("SpawnTiles") as BattleSpawnTiles
	_check(not spawns.visible, "Spawn markings are hidden during gameplay")
	spawns.set_cells([], [])
	var undo := UndoRedo.new()
	Painter.commit_paint(undo, spawns, [Vector2i(1, 1), Vector2i(2, 1)], false, false)
	_check(spawns.friendly_cells == [Vector2i(1, 1), Vector2i(2, 1)], "Friendly painting preserves authored party order")
	Painter.commit_paint(undo, spawns, [Vector2i(1, 1)], true, false)
	_check(spawns.friendly_cells == [Vector2i(2, 1)] and spawns.enemy_cells == [Vector2i(1, 1)], "Enemy paint replaces friendly designation")
	undo.undo()
	_check(spawns.friendly_cells == [Vector2i(1, 1), Vector2i(2, 1)] and spawns.enemy_cells.is_empty(), "Undo restores faction and original order")
	undo.redo()
	_check(spawns.enemy_cells == [Vector2i(1, 1)], "Redo restores painted cells")
	Painter.commit_paint(undo, spawns, [Vector2i(1, 1), Vector2i(2, 1)], false, true)
	_check(spawns.friendly_cells.is_empty() and spawns.enemy_cells.is_empty(), "Erase removes either faction in one stroke")
	undo.undo()
	_check(spawns.friendly_cells == [Vector2i(2, 1)], "Undo restores erased friendly cells")
	var grid := map.get_grid()
	var walls := map.get_walls()
	var wall := TacticalWall.new()
	wall.grid_cell = Vector2i(3, 3)
	walls.add_child(wall)
	_check(not Painter.can_paint(Vector2i(3, 3), grid, walls), "Walls reject paint")
	_check(not Painter.can_paint(Vector2i(-1, 1), grid, walls), "Out-of-bounds cells reject paint")
	_check(Painter.can_paint(Vector2i(4, 4), grid, walls), "Open terrain accepts spawn paint")
	var a := Button.new()
	var b := Button.new()
	a.toggle_mode = true
	b.toggle_mode = true
	root.add_child(a)
	root.add_child(b)
	PaintMode.register(a)
	PaintMode.register(b)
	a.button_pressed = true
	b.button_pressed = true
	PaintMode.activate(b)
	_check(not a.button_pressed and b.button_pressed, "Paint tools are mutually exclusive")
	a.free()
	b.free()
	var packed := PackedScene.new()
	_check(packed.pack(map) == OK, "Painted map packs")
	var path := "res://.godot/template_paint_roundtrip.tscn"
	_check(ResourceSaver.save(packed, path) == OK, "Painted map saves")
	var reloaded := (ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	_check(reloaded.get_node("SpawnTiles").friendly_cells == spawns.friendly_cells and reloaded.get_node("SpawnTiles").enemy_cells == spawns.enemy_cells, "Painted cells persist through scene save and reload")
	reloaded.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	undo.clear_history()
	undo.free()
	map.free()


func _test_layout_and_saved_rosters() -> void:
	var template := load(DEMO) as BattleMapTemplateDefinition
	_check(TemplateEncounterSetup.inspect_layout(template, 4).error.is_empty(), "Demo has a valid four-character layout")
	_check(not TemplateEncounterSetup.inspect_layout(template, 5).error.is_empty(), "Insufficient friendly capacity is rejected")
	var map := template.map_scene.instantiate() as BattleMap
	var spawns := map.get_node("SpawnTiles") as BattleSpawnTiles
	var wall := TacticalWall.new()
	wall.grid_cell = spawns.enemy_cells[0]
	map.get_walls().add_child(wall)
	_check(not spawns.validate_layout(map.get_grid(), map.get_walls()).is_empty(), "Inspector validation catches walls added over existing spawns")
	wall.free()
	var actor := (load("res://scenes/enemies/wolf.tscn") as PackedScene).instantiate()
	map.get_characters().add_child(actor)
	actor.owner = map
	var packed := PackedScene.new()
	packed.pack(map)
	var authored := template.duplicate() as BattleMapTemplateDefinition
	authored.map_scene = packed
	_check(not TemplateEncounterSetup.inspect_layout(authored, 2).error.is_empty(), "Preplaced template combatants are rejected")
	actor.free()
	spawns.enemy_cells.append(spawns.friendly_cells[0])
	_check(not spawns.validate_layout(map.get_grid(), map.get_walls(), 2).is_empty(), "Cross-faction spawn overlap is rejected")
	spawns.enemy_cells = [Vector2i(15, 0), Vector2i(15, 0)]
	_check(spawns.validate_layout(map.get_grid(), map.get_walls()).size() >= 3, "Duplicate and out-of-bounds cells are reported")
	map.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var generated := TemplateEncounterSetup.create(template, 2, rng)
	_check(generated.error.is_empty() and generated.total_cr == 3, "Demo produces three combined CR")
	_check(TemplateEncounterSetup.validate_saved(template, generated, 2).is_empty(), "Generated roster passes saved validation")
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(generated))
	_check(TemplateEncounterSetup.validate_saved(template, decoded, 2).is_empty(), "Roster survives JSON number conversion")
	rng.seed = 42
	_check(TemplateEncounterSetup.create(template, 2, rng) == generated, "Equal seeds reproduce both roster and spawn positions")
	var positions := {}
	for seed_value in range(12):
		rng.seed = seed_value
		var entry := TemplateEncounterSetup.create(template, 2, rng)
		var cells: Array = []
		for enemy in entry.enemies:
			cells.append(enemy.cell)
		positions[str(cells)] = true
	_check(positions.size() > 1, "Different seeds vary enemy spawn positions")
	var broken := generated.duplicate(true)
	broken.enemies[1].cell = broken.enemies[0].cell.duplicate()
	_check(not TemplateEncounterSetup.validate_saved(template, broken, 2).is_empty(), "Saved duplicate positions are rejected")
	broken = generated.duplicate(true)
	broken.enemies[0].scene = "res://scenes/friendlies/friend_a.tscn"
	_check(not TemplateEncounterSetup.validate_saved(template, broken, 2).is_empty(), "Saved enemies outside the allowed pool are rejected")
	broken = generated.duplicate(true)
	broken.total_cr = 99
	_check(not TemplateEncounterSetup.validate_saved(template, broken, 2).is_empty(), "Saved CR mismatches are rejected")
