# Passive abilities

Passives are available immediately to friendly and enemy units. They consume no actions and are independent of character classes and the developer active-ability bypass. They do not appear as clickable ability-bar entries.

## Authoring and assignment

Create a `PassiveAbilityDefinition` resource in the FileSystem dock, or choose **New PassiveAbilityDefinition** in a passive array. Set a stable, unique `passive_id`, display name, description, optional icon, and typed `effects` entries. Keep the same ID when renaming an existing passive. Drag saved `.tres` resources into arrays to share them; use inline resources for local definitions.

Templates expose **Passive Abilities**. Individual TacticalCharacter scenes expose **Override Template Passives** and **Passive Overrides**. Enabling the override replaces the entire template list; an empty override intentionally grants no passives. Resetting the override restores the template list. Assignment arrays are independent per unit, while referenced assets remain shared. Duplicate references resolve once by ID. Different assets sharing an ID are reported as invalid.

The concrete effect types are:

| Effect resource | Editable settings | Behavior |
| --- | --- | --- |
| `GroundImmunityPassiveEffect` | `ignore_tile_effects`, `ignore_movement_modifiers` | The first setting ignores every entry/turn-start tile effect, including healing and statuses. The second uses movement multiplier 1.0 on every tile, including faster tiles. |
| `NearbyAlliesWeaponDamagePassiveEffect` | `radius` (finite, nonnegative), `damage_per_ally` (positive integer) | Adds the configured weapon damage for each other living unit of the same faction within Euclidean grid distance, provided it has the owning passive's ID. No line of sight is required. |
| `ReassemblePassiveEffect` | `pile_health` (positive integer), `restored_health_percentage` (1–100), `pile_texture` | Lethal damage becomes an immobile, targetable bone pile and clears statuses. Survive next-turn hazards to reform and act; damage destroying the pile is permanent. |

At least one ground-immunity setting must be enabled. Missing references, empty IDs/names, missing effects and invalid settings produce validation errors. Character scene warnings report invalid assignments. The developer catalog has a **Validate Passive Catalog** Inspector button, and run/scenario loaders validate saved passive data.

## Shipped content

- **Flight**: `resources/passives/flight.tres`, with both immunity settings enabled. Walls, occupied cells, diagonal collision, direct attacks, spells, existing statuses and opportunity attacks retain their usual rules. Forced movement also ignores terrain triggers.
- **Pack Tactics**: `resources/passives/pack_tactics.tres`, radius **1.5**, damage **+1 per ally**. Adjacent diagonals qualify; two qualifying allies grant +2. The bonus is added after normal weapon/stat calculation, once per target per ability resolution. It applies to melee, ranged and opportunity attacks, including Charge at its landing cell. It does not increase spells, healing, ground damage or periodic status damage.
- All wolves inherit Pack Tactics through `resources/enemies/wolf.tres`; their existing equipment and stats are preserved.
- **Reassemble**: both Skeleton Warrior and Skeleton Archer inherit `resources/passives/reassemble.tres`, configured for a 1 HP pile and full-health reformation every time. See [Skeleton enemies](skeleton_enemies.md#reassemble) for lifecycle, artwork, authoring, and save behavior.
- **Bat**: reusable `scenes/enemies/bat.tscn`, definition `resources/enemies/bat.tres`. It has 5 HP, speed 10, movement 6, CR 1, and the Rat's other base stats/general AI. It inherits Flight and reuses Bite with the 5-damage `resources/items/bat_fangs.tres` weapon. Bat is available in the developer palette. Run encounter pools are unchanged.

Both Bat sprites live under `assets/characters/bat_left.png` and `bat_right.png`. Their source images, exact prompts and transparency checks are recorded in [passive_artwork.json](passive_artwork.json). Both use actual RGBA transparency and mipmapped filtering at the existing 112-pixel character-art size.

## Developer controls and previews

Open **Dev**, select any unit, and scroll to **Passive Abilities · always active**. Check or uncheck entries to create a replacement loadout. **Reset Passives to Template** restores inheritance. The panel shows descriptions, whether the list is inherited or overridden, and the current nearby-allies damage bonus. Inventory character details show the same descriptions and bonus.

Add reusable passive assets to `resources/dev_tool_catalog.tres` → **Passive Catalog** to expose them in this list. Already assigned inline passives are also shown and can be removed. Edit effect settings in the Godot Inspector. Shared resource/effect edits notify assigned units.

Damage displays and movement previews refresh after movement, spawning, defeat and passive editing. Hovering a Charge target previews damage at its predicted landing cell; canceling targeting restores the ordinary damage display. Runtime and AI use the same side-effect-free proximity evaluator, with AI supplying simulated positions and health.

## Saves and code integration

`get_passive_abilities()` returns a deduplicated assignment list. `passive_abilities_changed` reports assignment/resource edits; `passive_context_changed` tells views that the surrounding battle changed. Live combat uses sibling characters in the battle's character container, keeping separate battles isolated. AI explicitly supplies an `AIBoardSnapshot`.

Setup dictionaries carry `override_passives` and `passives`, which flow through developer scenarios, run party records and battle checkpoints. Shared passive `.tres` assets are stored by resource path. Inline passives, including scene subresources, are stored as validated data; built-in effects support inline settings or shared effect `.tres` references. Use saved texture assets for icons.

Reassemble runtime captures `bone_pile`, pending `reassembly` settings, and `reassembly_destroyed`. These belong to the unit instance, never the shared passive resource. A pending transformation freezes its settings so changing or removing its passive cannot strand a pile. `form_changed(character)` updates combat views; `defeated(character)` only fires for final destruction. AI snapshots copy this state independently and do not award final-defeat utility for an intermediate collapse.

Legacy saves without passive fields retain the instantiated scene/template defaults. Explicit empty overrides remain empty. Conditional damage is always recomputed from restored units; the bonus itself is never saved.

## Verification

Run using a Godot executable from the project directory:

```text
godot --headless --path . --script res://tests/run_passive_tests.gd
godot --headless --editor --path . --script res://tests/run_passive_editor_tests.gd
godot --path . --rendering-method gl_compatibility --script res://tests/run_passive_visual_checks.gd
```

The passive suite passes all 83 checks in the rendered game and covers assignment isolation, shared/inline resource edits and saves, malformed/legacy data, developer reset, both factions, multiple allies, death and distance changes, Flight terrain/collision behavior, runtime/display/AI weapon damage, Charge, reactions, Bat content, and developer/run/checkpoint persistence. The editor suite drives actual Inspector properties and verifies saved values. The visual runner writes gameplay, developer-panel and inventory screenshots under `.godot/passive_validation/` at standard and smaller resolutions.

Existing integration suites were also exercised for classes, inventory, terrain, developer mode, opportunity attacks, melee, Charge, hub, run state/map, active AI, AI checkpoints, Rat, Skeleton and combat progression. Bat-specific catalog counts and the Rat test's legacy-health fixture list were updated for the new content.

Baseline comparison used unchanged commit `e8fecaf`. Its broad `run_headless.gd` suite already has seven failures: stale item/modifier fixtures, Arrow's old Dexterity expectation, the AI disengagement expectation, the 16 ms AI planning budget (about 30 ms on this machine), old Goblin HP, and old starting-equipment expectations. The baseline also has stale terrain/class fixture script errors, failing default combat-progression assertions, and a progression integration script error for missing `combat_progression`. These are outside the passive change. Headless Godot occasionally exits with Windows status `0xC0000005` after printing successful assertions; this also reproduced on the unchanged Rat suite. Editor-run shutdown RID warnings also reproduce on the existing class editor suite.
