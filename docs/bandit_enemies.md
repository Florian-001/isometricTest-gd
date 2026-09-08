# Bandit enemies

Use **Bandit Warrior** and **Bandit Ranger** in the developer unit palette, or drag their reusable scenes from `scenes/enemies` into an authored map's Characters container.

| Enemy | HP | Attack | Normal damage | CR | Constitution |
|---|---:|---|---:|---:|---:|
| Bandit Warrior | 20 | Strike (range 1.414) | 6 | 1 | 5 |
| Bandit Ranger | 12 | Enemy Shot (range 5) | 5 | 1 | 3 |

Both use General AI, movement 6, speed 10, and Strength, Dexterity, and Intelligence 1. They have no additional abilities, passives, or friendly class. Base Health Override is 0; the current global health rules provide 4 HP per Constitution point.

Expand the scene's **Definition** resource in the Godot Inspector to edit stats, equipment, abilities, and CR. The definitions are `resources/enemies/bandit_warrior.tres` and `bandit_ranger.tres`. **Max Health** is derived from Constitution and appears in both the definition and unit Inspectors.

The existing **Iron Sword** supplies 5 melee damage; **Strike** adds 1 Strength for 6 damage. The existing **Weathered Bow** supplies 4 ranged damage; **Enemy Shot** adds 1 Dexterity for 5 damage. Stat modifiers and equipment changes adjust the attacks normally. The shared weapons and abilities are already available in the developer catalogs.

To generate bandits, add `scenes/enemies/bandit_warrior.tscn` or `scenes/enemies/bandit_ranger.tscn` to a map template's **Enemy Pool**. For runs, expand the run configuration's **Combat Stages**, select a stage, and add either scene to that stage's **Enemy Pool**. Existing template and run pools remain unchanged. Scenario restart and saved games use the existing format.

Four transparent sprites in `assets/characters` use the existing outlined cartoon style, character artwork frame, name label, and health bar. Scene-level **AtlasTexture** margins normalize each pair to the existing humanoid height and foot baseline without modifying the generated PNGs. Both frames include the full 1254 × 1254 image region; the warrior uses a 1490 × 1490 virtual frame and the ranger uses 1404 × 1404.

Run `godot --headless --path . --script res://tests/run_bandit_tests.gd` for combat, AI, palette, scenario persistence, and template checks. Run `godot --editor --path . --script res://tests/run_bandit_editor_tests.gd` for actual Inspector editing and save/reload checks. The editor-script harness retains the existing shutdown allocation warnings described in the skeleton/template documentation.

`tests/capture_bandit_preview.gd` renders both facings beside the existing Goblin Warrior to `.godot/bandit_preview.png` with a graphical renderer.

Verified with Godot 4.7.1: bandit runtime and Inspector checks, developer catalog unit checks, skeleton regression checks, melee integration, template generation, and run combat progression integration all passed. Runtime checks include actual and predicted damage, attribute scaling, weapon requirements, walls and range, General AI selection, developer spawning, restart, damaged scenario save/reload, and temporary template/run-stage pools. The graphical preview verifies transparency, both facings, labels, health bars, and alignment. The existing editor harness reports startup/plugin and shutdown allocation warnings; run progression reports authored spawn-capacity warnings. No functional checks failed.
