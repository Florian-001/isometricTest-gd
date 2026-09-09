# Friendly character classes

For an automatically updated Excel reference of every class, unlock level, and ability description, open [Class abilities](../CLASS_ABILITIES.xlsx).

Friendly characters get a basic attack from equipment, plus abilities from **Warrior**, **Archer**, **Wizard**, and **Cleric** resources in `resources/classes/`. Enemies continue using their existing template or unit ability loadouts.

Every friendly class has **Strike** when unarmed (100% effective Strength) or equipped with a melee weapon (weapon damage + 100% effective Strength). A ranged weapon replaces that basic attack with **Shoot** (weapon damage + 60% effective Dexterity). These attacks have no class or level requirement and occupy the first ability slot. Shoot retains Arrow's `resources/abilities/arrow.tres` path and UID for save compatibility. Item descriptions list the attack granted while equipped.

## Starting characters and multiclassing

Set **Starting Class** on a friendly Character Template. A character inherits that class at level 1. To customize one character, edit its **Friendly Class Progression → Class Level Overrides** array. Each `CharacterClassLevel` entry contains a class resource and invested level. An empty array inherits the template; a populated array replaces it.

FriendA and the run Archer start as Archer 1. FriendB and the Vanguard start as Warrior 1. The generic adventurer template starts as Warrior; the spellcaster template starts as Wizard. The default run still has two characters.

Total level is the sum of class levels: **Warrior 2 / Wizard 1 is level 3**, with Strike, Charge, Bloodlust, and Ice Shard when equipped with a melee weapon. Class levels do not increase each other. Any combination of classes is allowed, without prerequisites. Level changes grant no stat bonuses or equipment restrictions. Levels beyond the final unlock are valid.

This version uses manual authoring and developer edits. It does not award XP or levels for victories and has no player level-up screen.

## Editing unlocks

Open a class `.tres` resource in the Inspector. Edit its unique **Class ID**, **Display Name**, and **Ability Unlocks**. Each unlock contains an existing `AbilityDefinition` and a positive **Required Level**. The **Validate Class** action reports invalid entries. Class IDs must be unique within an allocation; save classes as resources before using them in runs or developer saves.

The current unlocks and ability descriptions are generated in [Class abilities](../CLASS_ABILITIES.xlsx). Each class has its own worksheet, ordered alphabetically, with a filterable **Index / Class / Unlock Level / Ability / Description** table. Each sheet includes that class's unlocks plus Strike and Shoot labeled **All classes**; their blank unlock levels mean no class-level requirement. The numeric index restarts on each sheet: Strike is **1**, Shoot is **2**, and class abilities follow from **3** in their existing order. Indices are reference positions, not permanent gameplay identifiers, and are recalculated during regeneration when abilities change. Levels are numeric class levels. Empty classes still get a sheet with an unnumbered informational row, and adding or removing a class automatically adds or removes its sheet. Long or invalid Excel tab names are shortened or sanitized, with suffixes to keep names unique; the full class name remains in the sheet. Edit the class, ability, or status resources in Godot to change gameplay; the workbook is a generated reference and manual spreadsheet edits are replaced during regeneration.

After the basic attack, abilities follow the character's class order, then ascending required level. Ties retain their authored order. Shared ability resources appear only once in the combat loadout. Existing weapon requirements, action availability, and opportunity-attack rules still apply, including unarmed Strike reactions. Locked abilities cannot execute through direct executor calls. Equipping or unequipping updates the loadout and damage previews immediately, cancels removed or unavailable targeting, and never restores spent actions or reactions.

See [Warrior abilities](warrior_abilities.md) for Stomp targeting, Taunt pursuit, Multi Attack damage, and Inspector settings.

See [Multiple Arrows](multiple_arrows.md) for ordered target selection, repeated targets, and per-hit Inspector settings.

Dagger Throw launches one projectile at an enemy within range 5 for physical damage equal to 100% effective Dexterity. It spends one ability action and no movement, requires no weapon, and adds no weapon damage, weapon statuses, or passive weapon-damage bonuses. Equipment and statuses that modify Dexterity still affect its damage. It is available at Archer level 4 and in the developer catalog. The Ranger enemy retains its existing loadout. Run `godot --headless --path . --script res://tests/run_dagger_throw_tests.gd` for focused validation.

See [Empower and Cleanse](empower_and_cleanse.md) for status polarity, duration, cleansing, and validation.

## Developer controls and runtime API

Open **Dev**, select a friendly, then edit its class levels, add a class at level 1, or remove a class. The last class cannot be removed. The ability list previews locked and unlocked entries with live damage details. Class changes use the existing **Restart & Play** workflow and are stored in scenario saves. Inventory and the run party strip show level/class summaries.

Enable **Developer Ability Override — Custom Loadout** to replace all equipment, unarmed, and class abilities with the checked abilities. Turn it off, or click **Use Default Abilities**, to restore the normal loadout. This bypass does not bypass equipment or action rules. The Inspector's existing `override_template_abilities` and `ability_overrides` fields retain their serialization keys. Class controls are hidden for enemies. **Dev** is available during runs too: class edits survive **Restart & Play**, and completed battle results carry the edited class allocation into the run. Save & Exit still returns to the original encounter-entry checkpoint.

Runtime callers use `TacticalCharacter.get_character_level()`, `get_class_levels()`, and `set_class_level(class_resource, level)`. Setting zero removes a class, unless it is the last one. Rejected changes return `false`. Level entries returned by the getter are independent copies; use the setter to change the character and emit `class_progression_changed`. Shared class and ability definitions remain reusable assets. Enemies return level 0 and an empty class list, and reject the setter.

## Saves and validation

Character setup snapshots store resolved `class_levels` entries with a class resource path and invested level. Total level and ability unlocks are recomputed. Allocations travel through developer snapshots, AI checkpoints, run party saves, battle entry, and battle results. Class resource edits affect recomputed unlocks; saves do not freeze ability definitions.

Legacy snapshots without class data use the instantiated scene's starting class allocation at level 1. Existing saved ability overrides remain explicit developer overrides. Invalid resource references, duplicate class IDs, empty friendly allocations, and invalid levels are rejected. New runs validate their starting party before writing a checkpoint. Save schema versions remain unchanged because class data is an optional addition when reading older saves.

## Verification

The **Class Ability Reference** editor plugin refreshes the workbook after saved resource changes and external changes detected by Godot, including referenced status resources and description scripts. It also refreshes after startup scanning when the project opens. If the plugin was added while Godot was already open, reopen the project once to load it. **Project → Tools → Regenerate Class Abilities** provides a manual refresh. Generation reads saved data in a short-lived headless Godot process and preserves unsaved Inspector edits. It compares records and workbook layout, ignoring ZIP timestamps and generated relationship IDs, so unchanged output is not rewritten. Changes to the spreadsheet exporter are checked every five seconds. Invalid resources, script errors, or missing dependencies leave the last valid workbook intact and report an editor error; worker details are under `.godot/class_ability_reference/`.

Close and reopen the workbook in Excel to see saved updates. If Excel locks the destination, Godot retains the pending workbook under `.godot/class_ability_reference/` beside the output and retries replacement every five seconds while the editor remains open. Further source changes replace the pending version with fresh data. Reopening Godot catches changes made while it was closed. The command-line generator returns exit code 3 when locked; close Excel and run it again, or let the open editor perform its automatic retry.

The exporter uses Node.js and `@oai/artifact-tool` (plus its bundled `jszip` dependency). By default it discovers the current user's bundled runtime under `~/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/`, using `bin/node.exe` on Windows or `bin/node` elsewhere and the adjacent `node_modules`. On another machine, configure absolute paths with the environment variables **CLASS_ABILITIES_NODE** and **CLASS_ABILITIES_NODE_MODULES**, or add and save the string project settings **class_ability_reference/node_executable** and **class_ability_reference/node_modules**. Environment variables take precedence. The modules path is the `node_modules` directory containing `@oai/artifact-tool`. No dependency installation is performed automatically.

Generate or check the reference from the project root (use your Godot executable path if `godot` is not on PATH):

```text
godot --headless --path . --script res://addons/class_ability_reference/generate_reference.gd
godot --headless --path . --script res://addons/class_ability_reference/generate_reference.gd -- --check
godot --headless --path . --script res://tests/run_class_ability_reference_tests.gd
godot --headless --editor --path . --script res://tests/run_class_ability_reference_editor_tests.gd
```

`--check` exits 0 when the Excel reference matches, and 1 when it is missing, stale, or cannot be generated; it never writes the reference or a pending replacement. Export scratch files are temporary. The runner also accepts `--classes-dir=...` and `--output=...` (an `.xlsx` path) for isolated checks. The generator suite checks saved records, numeric Excel cells, table filters, frozen headers, missing runtime, and failure preservation under `.godot/class_ability_reference_validation/`. The editor suite creates and removes disposable resources under `tests/class_ability_reference_validation_*`, exercises the real Inspector Save action and filesystem notifications, and verifies startup refresh, description script changes, additions/removals, Windows file-lock recovery, and read-only CLI checks. Both suites deliberately test an invalid input and label the expected error. As with other project editor tests, headless editor shutdown may report Godot allocation warnings after the assertions pass.

Using the configured Node executable, run `node tests/run_class_ability_spreadsheet_tests.mjs [absolute-node_modules-path]` to test Excel round-trip values, literal labels, layout drift, and unchanged output. After the generator tests, append `--review` (with the modules path supplied) to reopen and inspect the root workbook and render its rows and a long-description fixture under `.godot/class_ability_spreadsheet_tests/`.

Run `godot --headless --path . --script res://tests/run_equipment_ability_tests.gd` for basic attacks across all classes and levels, equipment changes, effective-stat damage, passive/status exclusions, runtime/AI agreement, reactions, saves, and UI sources. Run without `--headless` and append `-- --capture` for screenshots under `.godot/equipment_ability_validation/`. The rendered suite passes 452 checks. Class, inventory, developer, starting-hub, melee, Charge, opportunity integration, passive, Warrior, Multiple Arrows, Dagger Throw, and active-AI integration regressions pass; the active-AI and opportunity unit runners retain only the known shared disengagement assertion failure.

Run from the project directory with Godot 4.7:

```text
godot --headless --path . --script res://tests/run_character_class_tests.gd
godot --headless --editor --path . --script res://tests/run_character_class_editor_tests.gd
godot --headless --path . --script res://tests/run_dev_mode_unit.gd
godot --headless --path . --script res://tests/run_dev_mode_integration.gd
godot --headless --path . --script res://tests/run_run_state_tests.gd
godot --headless --path . --script res://tests/run_run_map_integration.gd
godot --headless --path . --script res://tests/run_melee_integration.gd
godot --headless --path . --script res://tests/run_charge_integration.gd
godot --headless --path . --script res://tests/run_opportunity_integration.gd
godot --headless --path . --script res://tests/run_battle_shortcut_integration.gd
godot --headless --path . --script res://tests/run_inventory_integration.gd
godot --headless --path . --script res://tests/run_active_enemy_ai_integration.gd
```

The class suites cover unlock boundaries, ordering, deduplication, instance isolation, invalid allocations, execution enforcement, developer bypass, controls, persistence, legacy migration, and real Inspector save/reload. Test saves are isolated under `.godot/class_validation/`.

All commands above passed on Godot 4.7.1. Combat-progression integration also passed; the full-run integration exercised ten battles. For visual captures of class controls, unlock previews, the bypass, inventory, and the run party strip, run the class suite without `--headless` and append `-- --capture`. Images are written under the same test directory.

The full `run_headless.gd` suite still reports seven failures involving existing item/catalog/stat/HP sample expectations and AI disengagement/performance, plus script errors in stale sample fixtures referencing removed content. The disengagement assertion was reproduced with the previous template-loadout behavior in an isolated fixture. Those unrelated gameplay/data expectations were not changed. As with the project's other custom editor suites, the Inspector test passes its assertions but reports Godot allocation warnings during editor shutdown.
