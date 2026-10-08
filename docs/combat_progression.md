# Editing combat progression

Open `resources/run/default_run.tres` in Godot's FileSystem dock, or open `main.tscn`, select **Main → RunController**, and expand **Config**. Under **Combat Progression**, edit **Combat Stages** and **Floor Overrides**. Save the resource after making changes.

For table editing, open the **Encounter Balance** workspace. It exposes every
floor’s normal and elite CR and units pools, inheritance resets, draft saving,
and generated-roster previews. See [Encounter Balance](encounter_balance.md).

## Combat stages

Each array entry is a `RunCombatStage` resource. Expand it to edit:

| Field | Meaning |
| --- | --- |
| Display Name | Label for this stage, such as Goblins. |
| First Floor / Last Floor | Inclusive displayed map floors, from 1 to 15. |
| Starting CR | Budget on the first floor of this stage. |
| CR Per Floor | Budget added for each subsequent floor. |
| Enemy Pool | Drag reusable enemy `.tscn` files into this list. |

The default stages are **Goblins, floors 1–3**, and **Skeletons, floors 4–15**.
Their authored budgets are shown in the Inspector and Encounter Balance table.
Goblins include sword warriors, club warriors, and archers; skeletons include
warriors and archers.

To add a stage, add an array element and choose **New RunCombatStage**, then adjust the neighboring ranges. Every floor from 1 to 15 must belong to exactly one stage. Array order does not matter. You can also save stages as separate `.tres` resources and reuse them. Use **Make Unique** before changing a resource that should no longer be shared between run configurations.

Progression follows the floor, not the number of battles fought. A shop, rest, or treasure room does not become combat. Stage defaults use goblins on floors 1–3 and skeletons starting on floor 4. Normal and elite floor overrides can replace these pools independently. Unknown rooms revealing combat use normal settings. The boss remains the separately authored **Boss Encounter**.

## Manually override one floor

1. Add an entry to **Floor Overrides** and choose **New RunCombatFloorOverride**.
2. Set **Floor** to the displayed floor number.
3. Enable **Override CR** and set **Combat Rating** to replace that floor's calculated budget.
4. Enable **Override Enemy Pool** and populate **Enemy Pool** to replace its entire allowed enemy list.

The two checkboxes are independent. For example, floor 5 can use only `scenes/enemies/skeleton_archer.tscn` while retaining CR 5: enable only **Override Enemy Pool**. Enabling **Override CR** too lets you type an exact budget. Disabled values are ignored. Remove the override, or disable both checkboxes, to use stage defaults. Only one override resource is allowed per floor.

An override changes only that floor. It does not shift the CR of later floors. A deliberate decrease or plateau is honored and reported as a warning.

**Elite Floor Overrides** uses the same resource type and independent checkboxes.
An elite field inherits the resolved normal field unless its elite override is
enabled. Duplicate floors are rejected within each list; normal and elite can
each have an entry for the same floor.

## Layouts, difficulty, and validation

The **Normal Encounters** and **Elite Encounters** catalogs choose battle layouts.
When stages are enabled, every encounter in these catalogs must reference a
`BattleMapTemplateDefinition` with painted spawn cells and no named chief. The
active Ascent elite encounter uses **Enemy Multiplier 1.0**; its difficulty comes
from the elite CR and units pool. Other authored encounters retain their own
multiplier settings, applied after selection.

The default run uses `scenes/maps/run_progression.tscn`, with four friendly and fifteen enemy spawn cells. Paint or edit this scene to change the layout. The standalone Spawn Template Demo retains its original layout and budget. See [Battle map templates](map_templates.md) for spawn painting and CR selection.

CR is the combined authored cost of the selected enemies. The generator finds the highest affordable total that fits the available spawn cells. It can repeat enemy types. Duplicate pool entries do not add weight. Raising an enemy's CR changes its selection cost; it does not automatically increase that enemy's stats. Enemy costs are shown in the pool picker. Tune enemy costs and stats together when adding stronger archetypes.

Click **Validate Combat Progression** in the run Config Inspector and read Godot's Output/Debugger messages. Validation checks stage coverage, increasing stage budgets, overrides, scene types, party/spawn capacity, and achievable roster CR on all fifteen room floors. Errors block a new run. Warnings identify deliberate manual difficulty changes, budgets the pool/layout cannot spend, and achievable CR plateaus. For capacity warnings, paint more enemy cells, add stronger authored enemy types, or lower the budget. These budgets are tuning defaults; the checks do not measure tactical balance.

## Saved runs and legacy configurations

Entering a combat room saves its encounter reference, resolved floor/stage, CR, pool scene paths, multiplier, concrete enemies, and positions before opening the battle. Continue and Save & Exit restore this snapshot. Editing stages, floor overrides, or template default CR/pools affects future uncommitted rooms and does not reroll a committed battle. In a running game, resource edits require the usual Godot reload/restart to take effect.

Saved scenes, enemy definitions, and map layouts must remain compatible: deleting an enemy scene, changing its CR, or removing a saved spawn position can still make the checkpoint incompatible. Such checkpoints are preserved and reported.

Clearing **Combat Stages**, **Floor Overrides**, and **Elite Floor Overrides** restores legacy catalog behavior. Checkpoints without a progression snapshot still load their original authored encounter or fixed-budget template. The original encounter resources remain available.

## Tests

Run with Godot 4.7 from the project directory:

```text
godot --headless --path . --script res://tests/run_combat_progression_tests.gd
godot --headless --path . --script res://tests/run_combat_progression_integration.gd
godot --headless --editor --path . --script res://tests/run_combat_progression_editor_tests.gd
godot --headless --path . --script res://tests/run_template_tests.gd
godot --headless --path . --script res://tests/run_template_integration.gd
godot --headless --path . --script res://tests/run_run_state_tests.gd
godot --headless --path . --script res://tests/run_run_map_integration.gd
```

The editor suite edits actual Inspector properties and verifies `.tres` save/reload using isolated resources. Run it without `--headless` to capture `.godot/progression_validation/floor_override_inspector.png`. Integration verifies real battles, elite stats, exact checkpoint restoration after authoring edits, malformed saves, transaction rollback, and legacy encounters. All test saves are isolated under `.godot/`.

All seven suites pass, including ten real battle instances along a complete run. As with the existing template editor harness, this Godot build reports allocation warnings while shutting down the custom editor test MainLoop. The game-mode suites exit cleanly.
