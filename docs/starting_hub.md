# Starting hub

**New Run** opens an unsaved character-selection draft with four empty slots. Select 1–4 unique characters. Clicking a character again, or clicking their occupied slot, removes them without shifting the other slots. New selections fill the first empty slot. **Start Run** uses slot order and omits gaps. **Back** returns to the menu without changing saved progress. Reopening New Run clears the draft.

If a saved journey needs replacement, confirmation appears only after Start Run. Cancel preserves the selection. Validation and save failures leave the hub open with an error and preserve the previous run. Continue restores the saved party directly, including order, equipment, classes, health, and lost members.

## Editing the roster

Open `resources/run/default_run.tres` and edit **Starting Character Roster**. Use **Validate Starting Roster** to report authoring errors. Each entry must be a separately saved scene whose root is a friendly `TacticalCharacter`. Set a unique **Scenario Unit ID**, class allocation totaling level 1, facing textures, and equipment. Disable **Developer Ability Override — Custom Loadout**. Hub presentation and snapshots come from the scene, so changing its stats or level-one unlocks updates the card automatically.

| Scene | Stable ID | Starting class | Equipment |
| --- | --- | --- | --- |
| `scenes/friendlies/warrior.tscn` | `vanguard` | Warrior 1 | Iron Sword |
| `scenes/friendlies/archer.tscn` | `archer` | Archer 1 | Goblin Bow |
| `scenes/friendlies/wizard.tscn` | `wizard` | Wizard 1 | Staff |
| `scenes/friendlies/cleric.tscn` | `cleric` | Cleric 1 | Staff |

Warrior and Archer inherit the original run character stats. Wizard and Cleric share `friendly_spellcaster.tres` stats, with an individual scene class assignment; both start with 24 HP and a two-handed **Staff** granting +2 Intelligence. Their sprite artwork is independent of equipment. Cleric unlocks **Heal and Beam at level 1**, then **Focus at level 2**. Existing saved characters keep their recorded equipment. See [class editing](character_classes.md) for multiclass allocations and the developer bypass.

`RunController.new_run_with_party(character_ids, seed_override = -1)` validates the IDs, roster, and encounter capacities before instantiating independent characters and saving a candidate `RunState`. State is replaced only after the existing atomic save store succeeds. `new_run(seed_override)` continues to use the original two-character `scenes/run/starting_party.tscn`; standalone encounters are unchanged.

## Encounter capacity

All shipped run layouts have four friendly spawns in this order: `(4, 9)`, `(7, 9)`, `(4, 10)`, `(7, 10)`. Templates use `SpawnTiles.friendly_cells`; authored run scenes use `PartySpawns` children. Normal, elite, and boss capacities are checked when creating a selected run and again before committing a room checkpoint. Lost members retain their original index; their empty spawn is never reused by another survivor.

The hub uses responsive grids inside a vertical scroll area. Back and Start remain outside the scroll area. The run party strip wraps when needed. No XP, walkable hub, customization, saved selection draft, or party-size difficulty scaling is added.

## Verification

Run `godot --headless --path . --script res://tests/run_starting_hub_tests.gd`. It covers every nonempty roster subset, invalid selections and authoring, slot removal/order, replacement cancellation, a forced disk-write failure, duplicate starts, saved roster independence, solo Cleric damage/healing, four-character normal/elite/boss entry and restoration, lost-member indices, and capacity failures before checkpoint creation.

Run the same script with a graphical renderer to produce screenshots under `.godot/hub_validation/` for the hub at 1280×720, 800×600, and 640×480 and the four-character battles. It checks imported alpha in both facings and saves/reloads the Inspector-editable roster resource.

Additional checks: `run_character_class_tests.gd`, `run_character_class_editor_tests.gd`, `run_run_state_tests.gd`, `run_run_map_integration.gd`, `run_inventory_integration.gd`, `run_dev_mode_unit.gd`, `run_dev_mode_integration.gd`, `run_combat_progression_integration.gd`, and the combat integration suites. The existing broad headless-suite failures recorded in [character classes](character_classes.md) predate this hub.

Artwork provenance and exact prompts are recorded in [starting hub artwork](starting_hub_artwork.md).

Verified on Godot 4.7.1: the hub suite passes both headlessly and with the OpenGL renderer. Class runtime/Inspector, developer unit/integration, run state/map generation/full-act integration, inventory, template unit/integration, combat progression unit/integration, melee, Charge, opportunity attacks, battle shortcuts, and active enemy AI checks pass. Full-act integration exercised ten battles. The broad `run_headless.gd` rerun still reports the same seven existing item/catalog/stat/HP and AI failures plus stale-fixture script errors. The class Inspector suite passes its assertions and retains the existing Godot allocation warnings at editor shutdown.
