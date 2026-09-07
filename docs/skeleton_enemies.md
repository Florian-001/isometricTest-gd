# Skeleton enemies

Use **Skeleton Warrior** or **Skeleton Archer** in the developer unit palette, or drag their reusable scenes from `scenes/enemies` into an authored map's Characters container.

| Enemy | HP | Attack | Normal damage | CR | Constitution |
|---|---:|---|---:|---:|---:|
| Skeleton Warrior | 20 | Strike (range 1.414) | 6 | 1 | 5 |
| Skeleton Archer | 12 | Enemy Shot (range 5) | 5 | 1 | 3 |

Both use General AI, movement 6, speed 10, and Strength, Dexterity, and Intelligence 1. They use normal Constitution-based health (4 HP per point under the current global rules), with Base Health Override set to 0.

Expand each scene's **Definition** resource in the Godot Inspector to edit its stats and CR. The separate definitions live in `resources/enemies/skeleton_warrior.tres` and `skeleton_archer.tres`. Derived Max Health appears in both the definition and character Inspectors.

**Rusty Sword** supplies 5 melee weapon damage; Strike adds the warrior's 1 Strength for 6 damage. **Weathered Bow** supplies 4 ranged weapon damage; Enemy Shot adds the archer's 1 Dexterity for 5 damage. Neither weapon adds stat modifiers or statuses. Both weapons have icons and are available in the developer item catalog. The existing attacks keep their normal stat scaling, weapon requirements, and targeting rules.

To allow generated skeletons, add either scene to a template definition's **Enemy Pool**. Existing pools, including Spawn Template Demo, are unchanged. Scenario saves use the existing format.

Four transparent left/right sprites under `assets/characters` retain the standard name label and health bar. AtlasTexture margins in each scene align the generated images with the existing humanoid artwork's scale and ground level.

Run `godot --headless --path . --script res://tests/run_skeleton_tests.gd` to verify stats, attacks, AI, palette spawning, scenario persistence, and template compatibility.

Run `godot --editor --path . --script res://tests/run_skeleton_editor_tests.gd` for actual Inspector checks. The editor-script harness retains the known shutdown allocation warnings described in the template editor documentation. `tests/capture_skeleton_preview.gd` renders both facings beside the existing Goblin Warrior to `.godot/skeleton_preview.png` with a graphical renderer.
