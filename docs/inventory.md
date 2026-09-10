# Inventory and equipment

Open `scenes/inventory_screen.tscn` in Godot to edit the inventory. The scene
contains the first twenty item cells, four labeled equipment cells, the hover
timer, the detail card, and the existing character stats and abilities panels.

- `GeneralPanel/Margin/VBox/Scroll/Entries` controls the number of columns and
  spacing. The root's **Minimum Rows** defaults to four; additional rows are
  instantiated from **Item Slot Scene** as the pack grows.
- `scenes/inventory_item_slot.tscn` controls the 64-pixel cells and icon padding.
  Equipment cells expose **Equipment Slot**, **Empty Icon**, and its opacity.
- `scenes/inventory_item_details.tscn` controls the adjacent card layout and its
  item gap and viewport margin. **Hover Delay** on the inventory root defaults
  to 0.2 seconds.
- `resources/ui/inventory_theme.tres` contains the shared panel, cell, focus,
  valid-drop, and invalid-drop styles.
- Item resources are grouped under `resources/items/weapons`, `resources/items/armor`,
  `resources/items/offhand`, and `resources/items/accessory` by equipment slot.
  The Inspector item catalog searches all four folders recursively.
  Each resource has an editable **Icon** assignment.
  Unassigned icons use the five fallback texture fields on the inventory root.

Saved runs and developer scenarios store item resource paths. Saves created before
this folder reorganization are not migrated and may fail to load; start a new run
or create a new scenario save to use the updated paths.

Single-click selects a cell. Double-click or Enter equips or unequips its item.
Dragging moves or swaps cells. Equipment accepts only matching Weapon, Offhand,
Armor, or Accessory items. Returning equipped gear onto occupied inventory space swaps
only if the destination item fits the vacated equipment slot. Invalid or
cancelled drops do not change either item. Dragging near the top or bottom of
the inventory scrolls it.

Equipment is arranged as Weapon/Offhand above Armor/Accessory. Weapon resources
expose **Weapon Handedness** in the Inspector: One-handed (the default) or
Two-handed. All bows, Staff, Long Sword, and Spear use both hands; other
current weapons use one. Dedicated offhand items fit alongside a one-handed weapon or an empty
weapon slot. Weapons cannot be equipped directly into Offhand.

A two-handed weapon is stored once in Weapon and reserves Offhand. The reserved
cell shows a dim weapon icon with the tooltip **Occupied by [weapon] — Two-handed**;
it is not a second item that can be dragged or unequipped. Dropping an offhand
there returns the two-handed weapon to inventory. Equipping a two-handed weapon
returns both the previous weapon and offhand. The first displaced item returns
to the source cell, with any additional item placed in the first vacancy.
Transfers preserve duplicate copies and notify observers after the complete swap.

Six stat accessories are available under `resources/items/accessory/`:

| Item | Flat bonus |
|---|---|
| Strength Charm | +1 Strength |
| Dexterity Charm | +1 Dexterity |
| Intelligence Charm | +1 Intelligence |
| Constitution Charm | +1 Constitution |
| Speed Charm | +1 Speed |
| Movement Charm | +1 Movement Range |

Each occupies the single Accessory slot, grants only its listed modifier, and has
its own pendant icon. Assign them through the Inspector selector or developer item
catalog. These are editor-only additions; shop/reward pools, sample inventory, and
starting equipment retain their existing contents. Sage Charm still grants +2 Intelligence.

Constitution uses the existing maximum-health scaling (+4 maximum HP per point
with current settings) without healing. Speed uses the existing initiative and
movement scaling (+1 initiative and +0.25 movement per point with current settings).
Movement Charm adds its +1 range subject to the existing movement cap of 10.
Equipping a different accessory replaces the previous accessory's contribution.

**Wooden Shield** grants **10 armor** and a flat **+3 Constitution**, using the normal maximum
health calculation. Equipping it does not heal health; removing it clamps current health
only if it exceeds the new maximum. It is available from run loot and merchants,
the developer equipment catalog, and the sample battle's shared inventory.
Starting character loadouts are unchanged.

Armor absorbs damage before health and fully restores for survivors at encounter
end. Swapping equipment preserves spent armor: after losing 6 armor, re-equipping
a 10-armor shield leaves 4 armor. See [Armor](armor.md) for damage, save, and AI rules.

**Long Sword** provides 10 weapon damage. **Spear** provides 5 weapon damage
and **+1 Strike range (normal attacks only)**. Both are two-handed melee weapons
with no additional stat modifiers or status effects. They are available in the
same run loot/merchant pool, developer catalog, and sample battle inventory.

Items expose **Weapon Range Bonus** in the Inspector (zero by default).
Abilities opt in with **Accepts Weapon Range Bonus**; only Strike enables it.
`AbilityDefinition.get_effective_range(caster)` adds the compatible equipped
weapon's bonus without editing the shared ability, and
`get_effective_melee_reach(caster)` extends the otherwise adjacent melee delivery.
Descriptions, range/target highlights, runtime validation, and AI use these
effective values. Changing equipment immediately refreshes targeting.

Strike's authored range remains 1.414. Spear raises its effective range to 2.414
using the existing weighted grid distance (1 per straight step, 1.414 per diagonal).
It reaches offsets (2,0) and (2,1), but not (2,2). Walls and diagonal corners along
the attack line still block melee delivery. Other abilities, including Battle
Stomp, Multi Attack, and Charge, retain their original ranges. Opportunity attacks
retain adjacent-cell reach: moving from adjacency into the outer spear range can
still trigger a reaction, while leaving only the outer spear range does not.
Direct opportunity-attack execution also rejects distant targets.

`GeneralInventory.get_items()` remains an occupied-item list. `get_slots()` and
`get_item_at()` expose stable grid positions. Transfers use `move_or_swap()`,
`equip_from_slot()`, and `unequip_to_slot()`, with corresponding validation
methods. Duplicate copies are addressed by their cell, not resource identity.
`TacticalCharacter.get_displaced_items(item)` previews all conflicts without
changing equipment; `equip_item(item)` returns an array of all displaced items,
with the destination's previous item first. `get_equipped_item()` returns only
the real item in that slot; `get_slot_occupant()` also resolves reservations.
Modifiers and saved resource lists include each equipped item once. Authored
equipment and overrides are processed in order, with the last conflicting item
winning; configuration warnings identify conflicts. Developer edits and restored
equipment follow the same rules.
The UI also checks inventory revision and character context before accepting
a drop.

Run and scenario saves retain their array of resource-path strings, with an
empty string representing a vacant cell. Earlier compact saves still load.
New rewards fill the first vacancy. Positions persist at the game's existing
checkpoints; this feature does not change when the game saves.

Weapon details show **Grants while equipped: Strike** for melee weapons and
**Grants while equipped: Shoot** for ranged weapons. `ItemDefinition.get_granted_abilities()`
derives this automatically from the item slot and weapon type, including inline items.
All friendly classes receive that attack first in their normal ability loadout;
an empty weapon slot gives Strike for 100% effective Strength. Armed Strike adds
weapon damage to 100% Strength; Shoot adds weapon damage to 60% Dexterity.
Equipment swaps refresh attacks, source labels, and damage previews without
restoring actions or reactions. Explicit developer custom loadouts replace these defaults.

Strike enables the Inspector's **Allow Unarmed For Friendlies** option while
keeping **Requires Weapon** enabled for normal melee weapon scaling and on-hit
effects. Other abilities default to the existing equipment rules. The runtime and
AI use the same equipment compatibility check. Shoot retains `arrow.tres` for
existing resource references and saves.

Run `tests/run_inventory_integration.gd` with Godot's `--script` option for
transfer, mouse, keyboard, equipment/stat, and persistence checks. For rendered
screenshots, provide an output directory and resolution after `--`, for example
`-- C:/Temp/inventory 1920x1080`. The test uses isolated fixtures and writes test
saves under `.godot/inventory_validation`.

Run `tests/run_offhand_tests.gd` headlessly for hand conflicts, copy conservation,
atomic notifications, health, authoring, developer edits, and equipment persistence.
The inventory integration suite also checks offhand mouse/keyboard interaction,
reservation tooltips, and rendered shield and two-handed configurations.

Offhand validation on Godot 4.7 passes 962 focused checks. Inventory mouse and
keyboard checks pass with rendered captures at 1280×720 and 1920×1080; equipment
abilities (447 checks), developer unit/integration, run state, and full run-map
integration also pass. The run-map suite exercised ten battles. Existing combat
progression warnings remain. The older level-selection integration runner stops
before its equipment checks because its two-level/FriendA fixture no longer
matches the current three-level map catalog and Terrain Showcase units.

Run `tests/run_spear_tests.gd` for the new weapon resources, range boundaries,
wall/corner blocking, actual melee delivery, runtime/AI agreement, reaction
reach, hand conflicts, and run/scenario equipment restoration. Run with a
graphical renderer and append `-- --capture` to save both weapon detail cards
and spear targeting under `.godot/spear_validation`.

The spear suite passes 690 headless checks and 693 with rendered captures on
Godot 4.7. Melee, Charge, opportunity attacks, equipment abilities, inventory,
offhand, developer unit/integration, active enemy AI, Warrior abilities, run
state, and full run-map integration regressions pass. The new range bonus does
not change the save format or any starting character loadout.

## Weapon names and saved paths

**Staff** and **Short Bow** use `staff.tres` and `short_bow.tres`, with matching
SVG icon filenames. Their stats and artwork are unchanged. New Wizards and
Clerics start with Staff; saved equipment choices are preserved.

`ItemDefinition.normalize_saved_paths` returns a copied save structure with the
historical `mage_staff.tres` and `weathered_bow.tres` paths mapped to their new
resources. Scenario/run validation and direct equipment/inventory restoration
use it before loading resources, including status sources and pending shop or
reward items. Reading does not rewrite a file; subsequent saves use the new paths.
Unknown resource paths still fail normal validation, and save versions are unchanged.

Run `godot --headless --path . --script res://tests/run_item_rename_tests.gd`
for legacy save migration, renamed resources, and caster starting equipment.
