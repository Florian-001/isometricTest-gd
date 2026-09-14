# Unit Balance editor

Open **Unit Balance** in Godot's top workspace selector. The plugin is enabled in
Project Settings → Plugins. It has **Enemies** and **Items** tables and needs no
running battle. If an already-open editor has not picked up the new plugin,
enable Unit Balance in that Plugins page or reopen the project.

## Enemy workflow

The default overview compares combat rating, HP, armor, movement, initiative,
attack, damage per hit, hit count, potential total, and range. Enable **Base
stats**, **Equipment**, or **Effective stats** above the table to show those
columns. Enemy names remain fixed while the other columns scroll horizontally.
The table discovers EnemyDefinition resources recursively under `resources`,
including the root-level Raider. It edits templates, not scene instances or
scene overrides.

1. Search by name, resource path, item, or visible value. Click a heading to sort;
   its arrow shows the direction.
2. Double-click a cell, or select it and press Enter/F2, to edit. Base attributes,
   movement, combat rating, and HP override are editable. An HP override of zero
   uses ordinary Constitution-based health.
3. Equipment cells open a searchable, slot-filtered picker with **None**. A
   two-handed weapon reserves Offhand, displayed as `2H: <weapon>`. Replacing or
   clearing that reserved offhand removes the two-handed weapon. Each equipment
   replacement is one undoable edit, including displaced items.
4. Select an enemy to see equipment contributions, damage explanations, AI
   profile, and ability/passive assignments below the table. The divider adjusts
   the space given to these details. Add, remove, and reorder existing abilities
   and passives here; **Inspect** opens their shared definitions in the Inspector.
5. Review the recalculated green cells and click **Save All**. A dot beside a
   resource name indicates an unsaved draft.

### Attack previews

Double-click **Preview attack** to select a damaging ability from that enemy's
loadout. The default is its first usable damaging ability in authored order;
enemies do not have a universal basic-attack field. Unusable attacks show an
explanation and dashes for damage. Enemies without damage abilities have no
damage preview.

Previews use the actual TacticalCharacter, AbilityDefinition, and damage
calculations with starting equipment, no temporary statuses, and no nearby
allies. They include equipment modifiers, stat scaling, rounding, weapon range,
health overrides, and movement limits. Damage is before target armor absorption.
Potential cast total assumes every hit resolves and is not guaranteed damage
against one target. Conditional passive descriptions are shown separately.
Attack selection is an editor preference and never changes the enemy loadout.

## Items and bulk editing

The **Items** table edits shared item name, slot, armor, weapon damage, weapon
type, handedness, and range bonus. Its details edit weapon status assignment and
stat modifiers and list enemy templates referencing the item. Changes update all
dependent enemy previews, even before saving. These are shared resources: other
game data, including friendly loadouts, may also use them.

Modifier **Flat** values are stat points. **Add %** and **Multiply %** accept
percentages (`25` means 25%); choose the stat/operation/value, then press **Apply
modifier**. The saved decimal representation remains compatible with the game.

- Arrow keys, Tab/Shift+Tab, Home, and End navigate the table.
- Shift-click selects a cell rectangle. Ctrl-click selects multiple rows.
- **Set selected…** applies one value to the selected rows in the active column.
- Ctrl+C or **Copy** copies selected cells as tab-separated rows. Equipment and
  attack references copy as resource paths to avoid ambiguous item names.
- Select the first destination cell and Ctrl+V or **Paste** to paste a rectangle.
  Invalid values, calculated columns, incompatible items, and rectangles that do
  not fit are rejected before any changes are made.
- Ctrl+Z / Ctrl+Y (or Ctrl+Shift+Z) undo/redo while the grid is focused. Toolbar
  Undo/Redo also work. Each paste or bulk edit is a single action.
- Mouse wheel scrolls rows; Shift+wheel scrolls columns.

## Saving and recovery

Table edits stay in isolated drafts. **Save All** writes only dirty resources and
updates Godot's cached resources. Godot's normal external-resource save flow also
saves these drafts. Undo after saving creates a new unsaved edit. **Revert All**
asks before reloading resources and clears the table's undo history.

If a resource changes on disk or in the Inspector after a draft starts, saving
that draft stops and offers **Overwrite these drafts**, **Reload these drafts**,
or Cancel. Overwrite applies the draft's editable fields while preserving other
fields from disk. Failed or conflicting saves remain dirty and report paths;
other resources that save successfully become clean.

Godot's close dialog reports unsaved Unit Balance edits. Disabling an editor
plugin has no cancellable pre-disable hook: instead, this plugin writes recovery
after every edit and warns on disable. Drafts are restored when enabled again.
Recovery and table preferences live under `.godot/unit_balance/`, are local to
this checkout, and are not committed. Explicitly save or revert before deleting
that cache directory. Closing without saving retains recovery drafts.

Resource creation/deletion, file renaming, ability/passive internals, scene
overrides, friendly units, target-defense simulations, and spreadsheet exchange
remain outside this tool.

## Verification

Run from the project root with Godot 4.7.1:

```text
godot --headless --path . --script res://tests/run_unit_balance_tests.gd
godot --headless --editor --path . --script res://tests/run_unit_balance_editor_tests.gd
godot --path . --rendering-method gl_compatibility --script res://tests/capture_unit_balance.gd
```

The first suite creates temporary resources under `.godot/unit_balance_tests`.
Run it before the editor suite. Checks cover runtime parity across all authored
enemy attacks, draft isolation, shared-item propagation, two-handed equipment,
HP overrides, movement bounds, multi-hit totals, undo/redo, bulk paste, conflicts,
recovery, save failures, and cached-resource refresh. The editor suite checks
plugin registration, staged edits, saving, and searchable dialogs. The capture
script renders the real tables at 1440×900 and 1000×760 without editing assets.

Related equipment (498 checks), armor (120), and passive (83) suites pass. The
aggregate `run_headless.gd` suite has eight pre-existing failing tests; the same
test names fail in an untouched checkout of `c15ca9a`, including its timing-budget
test. Existing editor startup/MCP diagnostics are separate from this plugin.
