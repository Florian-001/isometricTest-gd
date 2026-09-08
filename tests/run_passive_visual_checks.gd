extends SceneTree

const DIRECTORY := "res://.godot/passive_validation"


func _init() -> void:
	_run.call_deferred()


func _capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(DIRECTORY + "/" + name + ".png")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	root.size = Vector2i(800, 600)
	var field := Node2D.new()
	root.add_child(field)
	var grid := IsometricGrid.new()
	grid.position = Vector2(420, 120)
	grid.grid_size = Vector2i(8, 8)
	field.add_child(grid)
	for index in range(4):
		var scene := load("res://scenes/enemies/%s.tscn" % ("bat" if index < 2 else "wolf")) as PackedScene
		var unit := scene.instantiate() as TacticalCharacter
		unit.name = ["Bat Left", "Bat Right", "Wolf A", "Wolf B"][index]
		unit.starting_grid_cell = [Vector2i(2, 3), Vector2i(4, 3), Vector2i(3, 5), Vector2i(4, 5)][index]
		unit.initial_facing = TacticalCharacter.Facing.LEFT if index % 2 == 0 else TacticalCharacter.Facing.RIGHT
		field.add_child(unit)
		unit.initialize(grid)
	var title := Label.new()
	title.text = "Bat sprites at gameplay size (112 px) and wolves with Pack Tactics"
	title.position = Vector2(30, 30)
	field.add_child(title)
	await _capture("bat_gameplay_800")
	field.free()
	root.size = Vector2i(1280, 800)
	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as TacticalBattle
	battle.map_definition = load("res://resources/maps/goblin_skirmish.tres")
	root.add_child(battle)
	battle._on_dev_button_pressed()
	var actor := battle._characters[0]
	actor.set_dev_passive_loadout([load("res://resources/passives/flight.tres"), load("res://resources/passives/pack_tactics.tres")])
	battle.dev_mode_panel.select_unit(actor)
	await process_frame
	var scroll := battle.dev_mode_panel.get_node("Drawer/Margin/Main/Tabs/Unit") as ScrollContainer
	scroll.ensure_control_visible(battle.dev_mode_panel.passive_summary)
	await _capture("passive_developer_1280")
	root.size = Vector2i(800, 600)
	await process_frame
	scroll.ensure_control_visible(battle.dev_mode_panel.passive_summary)
	await _capture("passive_developer_800")
	battle.dev_mode_panel.hide()
	battle.inventory_screen.open_for(actor)
	await _capture("passive_inventory_800")
	paused = false
	battle.shutdown_battle()
	battle.free()
	await process_frame
	print("PASSIVE_VISUAL_CHECKS_OK")
	quit()
