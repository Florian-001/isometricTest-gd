# Skeleton enemies

Use **Skeleton Warrior** or **Skeleton Archer** in the developer unit palette, or drag their reusable scenes from `scenes/enemies` into an authored map's Characters container.

| Enemy | HP | Attack | Normal damage | CR | Constitution |
|---|---:|---|---:|---:|---:|
| Skeleton Warrior | 20 | Strike (range 1.414) | 6 | 1 | 5 |
| Skeleton Archer | 12 | Enemy Shot (range 5) | 5 | 1 | 3 |

Both use General AI, movement 6, speed 10, and Strength, Dexterity, and Intelligence 1. They use normal Constitution-based health (4 HP per point under the current global rules), with Base Health Override set to 0.

## Reassemble

Both skeleton definitions inherit the shared **Reassemble** passive (`resources/passives/reassemble.tres`). Lethal damage turns the same unit into a **1 HP Bone Pile**, clearing temporary buffs and debuffs. It keeps its cell, faction, equipment, facing and initiative position. The pile blocks movement, remains targetable and prevents battle victory, but cannot move, attack or make opportunity attacks. Healing cannot increase its health above the pile maximum or reform it early.

The damage that causes collapse does not spill into the pile. Later damage events can destroy it, including a later arrow in Multiple Arrows. Destroying the pile is permanent and emits the unit's ordinary defeat signal once. If the pile survives, terrain and newly applied status damage resolve first at its next turn; it then reforms at full normal maximum health and gets its normal actions. Collapse during that turn's hazards waits until the following turn. Reassembly can repeat indefinitely.

Create a **ReassemblePassiveEffect** in any passive's Effects array to reuse this behavior. Its Inspector exposes **Pile Health** (positive integer), **Restored Health Percentage** (1–100%, rounded up), and **Pile Texture**. The shipped values are 1 and 100%. Reassemble also appears in Dev's passive list. Removing it prevents future collapses; an already waiting pile retains its captured settings until it reforms or is destroyed.

Exact scenario saves and AI Log checkpoints retain the pile and its initiative timing. **Restart & Play** restores enemies to full skeleton form from their edited setup. Run encounter scaling is applied only on entry; reformation and developer reloads use the already scaled maximum. Legacy snapshots without form state restore normally, including already defeated skeletons.

The transparent bone-pile sprite is `assets/characters/bone_pile.png`; its built-in image-generation prompt and source are recorded in [skeleton_reassemble_artwork.json](skeleton_reassemble_artwork.json). The battlefield label and initiative tooltip explain the pending reformation.

Expand each scene's **Definition** resource in the Godot Inspector to edit its stats and CR. The separate definitions live in `resources/enemies/skeleton_warrior.tres` and `skeleton_archer.tres`. Derived Max Health appears in both the definition and character Inspectors.

**Rusty Sword** supplies 5 melee weapon damage; Strike adds the warrior's 1 Strength for 6 damage. **Short Bow** supplies 4 ranged weapon damage; Enemy Shot adds the archer's 1 Dexterity for 5 damage. Neither weapon adds stat modifiers or statuses. Both weapons have icons and are available in the developer item catalog. The existing attacks keep their normal stat scaling, weapon requirements, and targeting rules.

To allow generated skeletons, add either scene to a template definition's **Enemy Pool**. Existing pools, including Spawn Template Demo, are unchanged. Scenario saves use the existing format.

Four transparent left/right sprites under `assets/characters` retain the standard name label and health bar. AtlasTexture margins in each scene align the generated images with the existing humanoid artwork's scale and ground level.

Run `godot --headless --path . --script res://tests/run_skeleton_tests.gd` to verify stats, attacks, AI, palette spawning, scenario persistence, and template compatibility.

Run `godot --headless --path . --script res://tests/run_reassemble_tests.gd` for collapse/reformation, repeated defeat, hazards, movement interruption, Multiple Arrows, AI simulation, developer overrides, scenario/AI rewind, and scaled run completion. Saves use `.godot/reassemble_validation`. Run with a graphical renderer and `-- --capture` for the 1280×720 bone-pile screenshot. The passive editor suite also edits Reassemble's actual Inspector fields and checks saved values.

Run `godot --editor --path . --script res://tests/run_skeleton_editor_tests.gd` for actual Inspector checks. The editor-script harness retains the known shutdown allocation warnings described in the template editor documentation. `tests/capture_skeleton_preview.gd` renders both facings beside the existing Goblin Warrior to `.godot/skeleton_preview.png` with a graphical renderer.
