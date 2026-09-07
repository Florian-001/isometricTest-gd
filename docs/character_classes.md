# Friendly character classes

Friendly characters get abilities from **Warrior**, **Archer**, **Wizard**, and **Cleric** resources in `resources/classes/`. Enemies continue using their existing template or unit ability loadouts.

## Starting characters and multiclassing

Set **Starting Class** on a friendly Character Template. A character inherits that class at level 1. To customize one character, edit its **Friendly Class Progression → Class Level Overrides** array. Each `CharacterClassLevel` entry contains a class resource and invested level. An empty array inherits the template; a populated array replaces it.

FriendA and the run Archer start as Archer 1. FriendB and the Vanguard start as Warrior 1. The generic adventurer template starts as Warrior; the spellcaster template starts as Wizard. The default run still has two characters.

Total level is the sum of class levels: **Warrior 2 / Wizard 1 is level 3**, with Strike, Charge, and Ice Shard. Class levels do not increase each other. Any combination of classes is allowed, without prerequisites. Level changes grant no stat bonuses or equipment restrictions. Levels beyond the final unlock are valid.

This version uses manual authoring and developer edits. It does not award XP or levels for victories and has no player level-up screen.

## Editing unlocks

Open a class `.tres` resource in the Inspector. Edit its unique **Class ID**, **Display Name**, and **Ability Unlocks**. Each unlock contains an existing `AbilityDefinition` and a positive **Required Level**. The **Validate Class** action reports invalid entries. Class IDs must be unique within an allocation; save classes as resources before using them in runs or developer saves.

| Class | Unlocks by class level |
|---|---|
| Warrior | 1: Strike; 2: Charge |
| Archer | 1: Arrow; 2: Focus |
| Wizard | 1: Ice Shard; 2: Searing Dagger; 3: Slow; 4: Fireball; 5: Beam |
| Cleric | 1: Heal and Beam; 2: Focus |

Abilities follow the character's class order, then ascending required level. Ties retain their authored order. Shared ability resources appear only once in the combat loadout. Existing weapon requirements, action availability, and opportunity-attack rules still apply. Locked abilities cannot execute through direct executor calls.

## Developer controls and runtime API

Open **Dev**, select a friendly, then edit its class levels, add a class at level 1, or remove a class. The last class cannot be removed. The ability list previews locked and unlocked entries with live damage details. Class changes use the existing **Restart & Play** workflow and are stored in scenario saves. Inventory and the run party strip show level/class summaries.

Enable **Developer Ability Override — Ignore Classes** to replace the whole class loadout with the checked abilities. Turn it off, or click **Use Class Unlocks**, to restore class abilities. This bypass does not bypass equipment or action rules. The Inspector's existing `override_template_abilities` and `ability_overrides` fields retain their serialization keys. Class controls are hidden for enemies. Run battles retain their existing disabled developer-tools policy.

Runtime callers use `TacticalCharacter.get_character_level()`, `get_class_levels()`, and `set_class_level(class_resource, level)`. Setting zero removes a class, unless it is the last one. Rejected changes return `false`. Level entries returned by the getter are independent copies; use the setter to change the character and emit `class_progression_changed`. Shared class and ability definitions remain reusable assets. Enemies return level 0 and an empty class list, and reject the setter.

## Saves and validation

Character setup snapshots store resolved `class_levels` entries with a class resource path and invested level. Total level and ability unlocks are recomputed. Allocations travel through developer snapshots, AI checkpoints, run party saves, battle entry, and battle results. Class resource edits affect recomputed unlocks; saves do not freeze ability definitions.

Legacy snapshots without class data use the instantiated scene's starting class allocation at level 1. Existing saved ability overrides remain explicit developer overrides. Invalid resource references, duplicate class IDs, empty friendly allocations, and invalid levels are rejected. New runs validate their starting party before writing a checkpoint. Save schema versions remain unchanged because class data is an optional addition when reading older saves.

## Verification

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
