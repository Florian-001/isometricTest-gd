# Encounter Balance editor

Open **Encounter Balance** in Godot’s top workspace selector. The plugin is enabled
in Project Settings → Plugins. Reopen the project if an already-open editor has
not picked up the new workspace.

## Floor table

The run selector discovers saved `RunConfig` resources under `resources` and
defaults to **The Ascent** on first use. It remembers the selected run, sorting,
and details divider. Floor count comes from that run’s map settings. Linear runs
such as **Five Combats** show only normal combat columns.

Each row shows the floor, stage, normal CR and units pool, elite CR and units pool,
and validation. The floor column stays pinned while scrolling horizontally.
Search filters floors, stages, unit names/paths, and validation; headings sort.

- **[stage]**: the value comes from the combat stage.
- **[normal]**: elite combat follows that floor’s normal settings.
- **[override]**: the value has an explicit floor override.

Double-click a CR or pool cell, or press Enter/F2. CR is a positive whole-number
enemy-selection budget. The pool picker shows reusable enemy scenes, their names,
thumbnails, authored CR, and scene paths. Paths distinguish variants such as the
goblin sword and club warriors. Search keeps selections made before filtering.
**Browse enemy scene…** accepts valid enemy scenes elsewhere in the project.

Shift-click selects a rectangle, Ctrl-click selects rows, and **Set selected…**
replaces the active field on selected visible floors. **Reset selected field**
restores inheritance for that field only. The details panel also provides separate
reset buttons for each field. Resetting normal settings affects elites that inherit
them; explicit elite settings remain independent.

Ctrl+C/V or **Copy/Paste** exchanges tab-separated rectangles. Pool cells copy
semicolon-separated `res://` scene paths. Invalid values, read-only fields, or
rectangles that do not fit are rejected before applying any edits. Duplicate
pool paths add no selection weight. Arrow keys and Tab navigate; Ctrl+Z/Y and
toolbar buttons undo/redo each complete edit, including bulk changes and paste.

## Preview and validation

Select a floor and normal/elite type, choose an encounter layout from its catalog,
and set a sample seed (initially zero). **Next sample** advances the seed. The
preview shows budget, achievable CR, unused CR, enemy/friendly spawn capacity,
the authored stat multiplier, and sample unit counts with individual CR costs.

It uses the existing encounter generator and isolated draft resources. Enemy
types can repeat. A fixed seed reproduces the roster; previews do not consume
gameplay randomness or modify gameplay resources. The preview does not simulate
combat outcomes.

Errors block saving; warnings allow it. Validation covers stages, duplicate floor
overrides, enemy scene types, budgets that cannot afford an enemy, and spawn limits
for each encounter catalog. Current stage budgets can exceed a layout’s achievable
CR; the table reports these authored capacity limits without changing the tuning.
Read the full message in the selected floor’s details or cell tooltip.

**Inspect run / stages** opens the saved run config. Edit stage defaults using the
Inspector’s normal save workflow. Runs using legacy encounters require combat
stages before floor overrides can be authored.

## Drafts and saving

Edits remain isolated until **Save All** or Godot’s external-resource save flow.
A dot marks runs affected by dirty overrides. New overrides are embedded in the
run config. Existing external overrides retain shared identity and show their
source path and number of owners; all owners see the same shared draft.

Save All validates affected runs, writes shared overrides before their owners,
preserves resource UIDs and external references, and refreshes Godot’s resource
cache. It writes only dirty resources. Failed, invalid, and conflicting drafts
remain unsaved; unrelated valid resources can still save.

Inspector or disk changes trigger **Overwrite these drafts**, **Reload these
drafts**, and Cancel. Overwrite applies changed draft fields while preserving
other fields from disk. Reload discards the selected conflicting drafts and clears
undo history. **Revert All…** confirms before discarding unsaved work. Undo after
saving creates another draft.

Recovery is written after edits to `.godot/encounter_balance/recovery.cfg`;
preferences live beside it. Godot’s close dialog reports unsaved resources.
Disabling the plugin preserves drafts for the next enable/start and emits a
warning. Save or explicitly revert before deleting the local `.godot` cache.

## Runtime behavior

Normal combat resolves **stage → normal floor override**. Elite combat resolves
each field independently through **stage → normal override → elite override**.
Unknown rooms revealing combat use normal settings. The active Ascent elite
encounter has a **1.0** stat multiplier; tune elite difficulty through its CR and
units pool. Boss encounters retain their separate configuration.

Committed battles keep their saved CR, pool, multiplier, roster, and positions.
Later balance edits affect future rooms. Older committed elite battles retain
their saved multiplier, including 1.5. No checkpoint migration is required.

## Verification

Run with Godot 4.7.1 from the project root:

```text
godot --headless --path . --script res://tests/run_encounter_balance_tests.gd
godot --headless --editor --path . --script res://tests/run_encounter_balance_editor_tests.gd
godot --path . --rendering-method gl_compatibility --script res://tests/capture_encounter_balance.gd
```

Fixtures, recovery, logs, and captures use disposable files under `.godot/`.
Captures cover The Ascent, Five Combats, and the pool picker at 1440×900 and
1000×760. Also run progression, template, run-state, map, Five Combats, and existing
balance-editor regressions. Custom editor test shutdown can emit Godot allocation
diagnostics also seen in the existing editor harnesses.
