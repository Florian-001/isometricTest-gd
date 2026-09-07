# Battle map templates

Choose **Spawn Template Demo** from the level menu to try a generated battle. The default run uses its own fifteen-spawn template with [editable combat stages and floor overrides](combat_progression.md). Existing authored maps and the named-chief boss remain available.

## Create or duplicate a template

1. Duplicate `scenes/maps/spawn_template_demo.tscn` for a new layout. Keep a `BattleMap` root and its `Grid`, `Terrain`, `Walls`, and empty `Characters` children. Keep a `BattleSpawnTiles` child named `SpawnTiles`.
2. Duplicate `resources/maps/spawn_template_demo.tres`, or create a new `BattleMapTemplateDefinition` resource. Set its name and `Map Scene` to your new scene.
3. Set **Encounter → Combat Rating** to a positive whole number. This is the maximum combined enemy CR.
4. Add reusable enemy `.tscn` files to **Enemy Pool**. Each scene must have a `TacticalCharacter` root with an enemy-faction `EnemyDefinition` and positive CR. Scenes retain their own abilities, equipment, and stat overrides. Repeated enemies are allowed; listing the same scene twice does not increase its selection weight.
5. Assign **Standalone Party** to a scene with friendly `TacticalCharacter` children, such as `scenes/run/starting_party.tscn`. Their child order determines friendly spawn order. Runs use their current party instead.
6. Add the resource to `Main`'s **Level Catalog → Levels** for standalone play. To use it in runs, create a `RunEncounterDefinition`, assign its **Battle Map**, and add it to a normal or elite encounter list in `resources/run/default_run.tres`. With combat stages enabled, the resolved stage/floor CR and pool replace the template defaults for that run battle; the encounter still supplies its layout and elite multiplier.

Different template resources can share one layout scene while using different CR budgets, allowed enemies, and standalone parties. Duplicate the scene too when you want independent terrain or spawn positions.

## Paint spawn cells in Godot

Open the map scene in the **2D** editor and select its root, grid, or `SpawnTiles`. In the canvas toolbar, choose **Friendly Spawn** or **Enemy Spawn**, then enable **Spawn Paint**.

- **Left-drag** paints cells. Painting over the other faction changes that cell's designation.
- **Right-drag** erases either faction's spawn designation.
- **Escape** exits painting. Activating Tile Paint, Wall Paint, or Spawn Paint turns off the previous paint tool.
- Each stroke is one undo/redo action. Painted arrays are saved with the map scene.

Blue cells marked **F1**, **F2**, etc. correspond to the party's original order. New friendly cells append to this order; edit the `Friendly Cells` array to rearrange it. Red **E** cells are possible enemy starting positions. The game places at most one enemy in each and can leave cells unused.

Spawn cells can overlay terrain effects, but cannot be painted outside the grid or onto walls. Erase and repaint cells when changing the layout. Inspector warnings also catch manually authored duplicates, faction overlaps, out-of-bounds cells, and wall overlaps. Runtime validation reports missing cells or party capacity rather than starting a partial battle. Spawn colors and labels are visible only in the editor.

## CR selection

Edit an enemy scene's **Definition → Encounter → Combat Rating**, or edit its definition `.tres` directly. All existing enemies start at CR 1. Sword and club Goblin Warriors share the same definition and therefore share its CR.

The generator finds the highest reachable total at or below the map budget, constrained by the number of enemy spawn cells. It can repeat enemy types and chooses randomly among optimal groups and available enemy positions. For example, budget 6 with CR-4 and CR-3 enemies and two spawn cells selects two CR-3 enemies. With budget 7 and only CR-4 and CR-6 enemies, it selects the CR-6 enemy.

If no enemy is affordable, increase map CR or add a cheaper enemy. Empty pools, invalid scenes, preplaced template combatants, insufficient friendly cells, and invalid spawn layouts prevent battle startup with an error.

## Restart and run saves

A new encounter gets a new composition. Standalone restart and scenario loading restore captured units and positions. Run room generation uses the run seed and room ID; the concrete enemy scenes and positions are committed to the entry checkpoint before combat opens. Continue and Save & Exit do not reroll the encounter. Lost party members retain their original friendly-cell slots.

Elite stat multipliers apply after selection and do not change the authored CR calculation. Named-chief encounters require an authored map. There are no generated chief or boss rules.

Checkpoints reference saved scene resources. Progression encounters save their resolved CR, enemy pool, and multiplier, so editing stage/floor settings or template defaults does not change a committed battle. Legacy template checkpoints still validate against the template's current default pool and budget. Changing enemy CRs, deleting enemy scenes, or removing saved spawn cells can invalidate either kind of roster; Continue preserves and reports incompatible checkpoints. Keep compatible resources available for active runs.

## Validation

Run from the project directory with Godot 4.7:

```text
godot --headless --path . --script res://tests/run_template_tests.gd
godot --headless --path . --script res://tests/run_template_integration.gd
godot --headless --path . --script res://tests/run_run_state_tests.gd
godot --headless --path . --script res://tests/run_active_enemy_ai_integration.gd
godot --headless --editor --path . --script res://tests/run_template_editor_tests.gd
```

The template suites cover optimal CR selection, capacity, repeat types, seeded variation, invalid inputs, painting commands and undo/redo, scene save/reload, standalone restart, run checkpoint restoration, lost party slots, and generation/save rollback. Test checkpoint files are isolated under `.godot/template_validation`.

The editor suite also exercises actual painter mouse input and the editor undo manager. Run it without `--headless` to capture `.godot/template_editor.png`. This Godot build reports allocation warnings while shutting down a custom `--editor --script` test harness; the same warnings occur in an otherwise empty editor probe, and the game-mode suites exit cleanly.
