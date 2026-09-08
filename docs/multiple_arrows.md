# Multiple Arrows

**Archer level 3** unlocks Multiple Arrows after Focus at level 2. Select the ability, choose exactly three enemy targets, then press **Fire**. The same unit can occupy multiple slots. Each numbered slot shows the unit name and grid position; **Remove** deletes that selection and compacts the remaining order.

Each arrow uses the existing Shoot formula: equipped ranged weapon damage plus 60% effective Dexterity, rounded by the existing damage calculator, with passive weapon bonuses and on-hit weapon statuses. Range is 5 weighted grid units; walls block targeting and delivery. The cast spends one ability action and no movement points, with no additional cooldown or resource cost.

Arrows resolve sequentially in selection order. A dead, removed, or invalid target is skipped without replacing it. A target that moves away during flight cannot redirect damage to the unit occupying its old cell. The remaining arrows stop if the caster becomes unable to act. An interrupted cast retains its spent action.

Fire is enabled only when all slots are valid. Cancel, Escape, changing abilities, ending the turn, opening inventory or developer mode, restarting, and leaving battle discard pending selections without spending the action. The list is transient UI state and is not saved.

## Inspector authoring

On any `AbilityDefinition`, use these settings:

- **Hit Count**: total hits in one action; also the number of target slots for Select Per Hit.
- **Hit Targeting → Same Target**: the compatible default; one selection receives the existing repeated-hit sequence.
- **Hit Targeting → Select Per Hit**: choose one unit per hit and confirm the complete ordered list.
- **Allow Repeated Targets**: visible in Select Per Hit mode; defaults to true. Disable to require distinct units.
- **Validate Targeting**: checks the configuration and reports its result in Godot's Output panel.

Select Per Hit supports Projectile, Cast On Target, and Melee delivery with stationary, single-unit targeting. Disable Cell targeting, keep Area of Effect at 0 or 1, and leave Caster Centered and Caster Movement disabled. Line From Caster is incompatible even with a one-cell span. Invalid configurations cannot be cast and expose the reason in the ability tooltip. Existing effect, weapon, range, and faction settings still apply.

The target panel creates slots from Hit Count and scrolls for larger counts. `calculate_hit_damage()` describes one hit; `calculate_damage()` remains the potential total across all hits, not damage dealt independently to every selected unit.

## Runtime API

`AbilityExecutor.can_execute_targets()` and `execute_targets()` accept an ordered `Array[TacticalCharacter]`, including duplicate references when allowed, followed by the existing units, grid, targeting, and optional walls arguments. `can_select_hit_target()` validates one prospective selection. The complete list is validated before the action is spent and copied before action-change signals clear UI state. Recipients remain locked to unit identity and are revalidated before each hit and at impact.

The existing single-cell `execute()` and `can_execute()` reject Select Per Hit abilities. Start/finish signals still occur once per cast; their cell is the first selected unit's cell at confirmation. Individual projectile signals expose each delivered arrow.

Enemy loadouts are unchanged. The current AI stores one target cell per plan, so per-hit-selection abilities are excluded from its cast candidates, including developer overrides. Automatic target allocation is not implemented.

## Verification

Run with Godot 4.7 from the project directory:

```text
godot --headless --path . --script res://tests/run_multiple_arrows_tests.gd
godot --headless --editor --path . --script res://tests/run_multiple_arrows_editor_tests.gd
```

The combat suite covers distinct and repeated selections, validation, damage, status/passive effects, interruptions, removed recipients, alternate deliveries, class unlocks, resource persistence, AI exclusion, and real battle controls. The editor suite changes the actual Inspector controls and checks save/reload. Run the combat suite without `--headless` and append `-- --capture` to render a 1280×720 preview under `.godot/multiple_arrows_validation/`.
