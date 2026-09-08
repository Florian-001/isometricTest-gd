# Boar enemy

Open a battle's **Dev** panel, select the **Unit** tab, and scroll the unit palette to **Boar**. Drag it onto an empty board cell. For authored encounters, instance `scenes/enemies/boar.tscn` in the map's Characters container and set its Starting Grid Cell.

| Setting | Default |
|---|---:|
| Constitution / maximum HP | 5 / 20 |
| Strength | 2 |
| Dexterity / Intelligence | 1 / 1 |
| Speed / movement | 10 / 6 |
| Combat rating | 1 |
| Weapon | Boar Tusks: 6 melee damage |
| Abilities, in order | Charge, Strike |
| AI | General |

Both attacks deal **8 damage**: 6 from the weapon plus 2 Strength. Health follows the ordinary Constitution rules (currently 4 HP per point); Base Health Override remains 0. The Boar inherits its equipment and abilities from its definition, starts without passives, and has no developer overrides. The Tusks have an icon and no stat modifiers or status effects.

Expand the scene's **Definition** in the Inspector, or open `resources/enemies/boar.tres`, to edit shared stats, combat rating, AI Profile, Starting Equipment, and the ordered Abilities array. Max Health updates from Constitution. Open `resources/items/boar_tusks.tres` to edit the weapon's damage and icon. Editing shared resources affects every unit using them; use a scene's individual overrides or the developer panel for an isolated change. The developer panel's reset controls restore the template values.

The Boar uses the existing shared `charge.tres` and `strike.tres`. Editing those resources changes their other users too. Charge retains its straight horizontal, vertical, or diagonal path, adjacent-target behavior, walls and occupancy checks, terrain entry triggers, and action cost. Strike provides the normal opportunity attack. General AI evaluates both attacks using its existing rules.

Boar and Boar Tusks are appended to the developer unit and item catalogs. Existing run encounter pools are unchanged. To include Boars in a generated encounter deliberately, add the scene to that encounter template's Enemy Pool. Scenario saves and battle checkpoints retain the scene, stats, equipment, abilities, and runtime state through the existing persistence format.

## Artwork

The transparent sprites are `assets/characters/boar_left.png` and `assets/characters/boar_right.png`. Both use the standard 112 x 112 character-art frame, name label, and health bar. Mipmaps and the scene's linear mipmap filtering keep the artwork readable at gameplay size. The item icon is `assets/item_icons/boar_tusks.svg`.

[Artwork generation record](boar_artwork.json) contains the exact prompts, reference images, original generated files, and final paths. Both PNGs are 1254 x 1254 RGBA with alpha spanning 0-255. Rendered previews at 1280 x 720 and 800 x 600 were inspected beside the existing Wolf.

## Verification

```text
godot --headless --path . --script res://tests/run_boar_tests.gd
godot --headless --editor --path . --script res://tests/run_boar_editor_tests.gd
godot --path . --rendering-method gl_compatibility --script res://tests/capture_boar_preview.gd
```

The Boar suite passes 62 checks covering defaults, both facings, instance isolation, scene save/reload, attack damage, straight/diagonal/adjacent Charges, walls, corner blocking, occupied landing cells, terrain statuses, equipment requirements, AI forecasts, reactions, developer spawning, and scenario/checkpoint restoration. The editor suite verifies actual Inspector fields and edits, derived health, and resource save/reload. The preview script writes both resolutions under `.godot/boar_validation`.

The pre-change and post-change runs on this workspace agree:

- Pass: Charge integration, opportunity-attack integration, active enemy AI integration, developer unit and integration suites, run-state tests, and skeleton content tests.
- Existing failure: the active enemy AI unit suite's disengagement-after-reaction assertion.
- Existing broad-suite failures: status/item catalog expectations, item modifier fixtures, old Arrow damage and Wizard loadout expectations, the same AI disengagement assertion, the AI timing budget, old Goblin health and friendly equipment expectations, and terrain status catalog expectations. Existing stale fixtures also emit index and missing-node script errors.
- Headless editor import and the editor test harness emit existing shutdown allocation warnings despite successful completion.

No new failing test cases appeared in those comparison suites. Baseline and post-change logs are under `.godot/boar_validation`.
