# Ability Balance editor

Open **Ability Balance** in Godot’s top workspace selector. The plugin is enabled
in Project Settings → Plugins. If an already-open editor has not picked it up,
enable it there or reopen the project.

## Tables

**Active Abilities** discovers all `AbilityDefinition` resource files recursively
under `resources`, including player and enemy abilities. The overview shows name, AP cost, cooldown turns,
ability type, primary effect, damage type, innate damage, base healing, scaling
source and percentage, hit count, range, and area size. **Columns…** exposes weapon
requirements, targeting, delivery, movement, status assignments, effect summaries,
and validation. Values are authored settings; some settings apply only to the
selected primary effect. The details description uses the existing runtime formula
and targeting descriptions without selecting a caster.

**Passives** shows name, stable ID, description, effect summary, and validation.
Double-click a description to edit multiple lines. Passive IDs affect runtime
identity and matching effects such as Pack Tactics; edit them intentionally.

The name column stays fixed. Search by name, resource path, or values; click a
heading to sort. Each tab has independent column preferences. The searchable
column picker supports individual columns, groups, show all, names only, and reset
defaults. Hiding an active column moves cell selection to the name column while
preserving selected rows. Hiding the sort column restores name sorting.

## Editing

- Double-click a cell or press Enter/F2. Enum, boolean, and target-mask fields use
  appropriate choices. Resource fields use typed pickers with **None**.
- Shift-click selects a rectangle; Ctrl-click selects rows. **Set selected…**
  edits the active column across selected visible rows.
- Ctrl+C/V or **Copy/Paste** exchanges tab-separated rectangles. Resource cells
  copy paths, including an empty path for None. Multiline descriptions use ` ↵ `
  between lines when copied. Invalid values, summary columns, and rectangles that
  do not fit are rejected before any edits are applied.
- Arrow keys, Tab/Shift+Tab, Home, and End navigate. Ctrl+Z, Ctrl+Y, or
  Ctrl+Shift+Z undo/redo while the grid has focus; toolbar buttons also work.
- Mouse wheel scrolls rows; Shift+wheel scrolls columns.

Drag the divider to resize the details panel. It shows descriptions, validation,
and references from classes, unit definitions, and statuses. **Add effect…**,
**Remove**, and arrow buttons manage the ordered additional-effect list. Property
buttons edit all current concrete effect types: damage, healing, apply status,
knockback, counter, ground immunity, nearby-allies weapon damage, and reassemble.
Each operation is one undoable edit. An invalid intermediate configuration may be
kept in a draft, but must be corrected before saving.

External shared effects are labeled with their resource path. Their settings use
a separate shared draft, visible through every owner; saving updates that external
resource without embedding copies in each ability. Embedded effects are copied
into isolated drafts. Unknown custom effect types and their data are preserved;
**Inspect custom effect** opens the saved effect in Godot’s Inspector. Inspector
edits use Godot’s normal save workflow and can conflict with an existing draft.

Expand **Presentation settings** to edit icons, colors, and animation values.
Texture fields show the assigned artwork; status pickers show status icons.
Status definitions themselves are edited in the Inspector. Ability Balance does
not edit unit loadouts or simulate unit-specific damage and healing; use Unit
Balance for its existing enemy combat previews.

## Saving and recovery

Edits stay in isolated drafts until **Save All** or Godot’s external-resource save
flow. A dot marks dirty definitions, including owners of dirty shared effects.
Save All validates affected definitions, saves shared effects before their owners,
and writes only dirty resources. It preserves resource UIDs and external resource
links, then refreshes Godot’s cached resources and filesystem. Existing Unit
Balance previews and the class reference generator observe saved changes.

Changes in the Inspector or on disk trigger a conflict dialog with **Overwrite
these drafts**, **Reload these drafts**, and Cancel. Overwrite applies fields
changed by the draft while preserving other fields from disk. Invalid, failed,
or conflicting drafts remain dirty; unrelated valid resources can still save.
An owner waits if its shared effect cannot save. Undo after saving creates another
unsaved edit.

**Revert All…** asks before discarding drafts and clears table undo history.
Recovery is written after each edit under `.godot/ability_balance/recovery.cfg`;
column and divider preferences live beside it. Godot’s close dialog reports
unsaved resources. Disabling a plugin cannot be cancelled, so drafts are preserved
for the next enable/start and a warning is emitted. Save or explicitly revert
before deleting the local `.godot` cache.

This editor creates embedded effect entries, but does not create/delete/rename
ability resource files, change gameplay schemas, edit status internals, or assign
abilities to units.

## Verification

Run with Godot 4.7.1 from the project root:

```text
godot --headless --path . --script res://tests/run_ability_balance_tests.gd
godot --headless --editor --path . --script res://tests/run_ability_balance_editor_tests.gd
godot --path . --rendering-method gl_compatibility --script res://tests/capture_ability_balance.gd
```

Run the data suite first. Tests use disposable resources under
`.godot/ability_balance_tests`, never authored gameplay data. They cover snapshots,
all current effect types, custom and native nested data, shared references,
normalization, validation, atomic paste, undo, conflicts, recovery, missing-file
save failures, and preferences. The editor suite checks registration, actual
property dialogs, typed resource pickers, staged edits, cache refresh, and UIDs.
Captures cover both tabs and the column picker at 1440×900 and 1000×760.

Unit Balance data, column, and editor regression suites and the passive suite
also pass. The equipment ability suite has two existing failures (`armor preserves
the weapon attack` and `unequipping restores only the default attack`); both were
reproduced in an untouched HEAD snapshot before this change. Godot test shutdown
can emit allocation/resource-leak diagnostics, also present in existing suites.
