# Stackable stat buffs

Strength Up, Dexterity Up, Constitution Up, and Intelligence Up are positive status resources under `resources/statuses`. Each application adds one stack granting a flat +1 to its named stat. There is no stack cap. They coexist with each other, Focus, and Empowered, and Cleanse preserves them.

Stacks last until battle ends. Combat finalization removes them after pending attacks, reactions, and movement finish, before run results are captured. Starting or restarting a battle clears them. Reassemble retains its existing behavior: collapsing clears all active statuses. Explicitly removing a status removes its whole stack count.

Constitution uses the central health scaling rules: at the current settings, each unmodified +1 Constitution adds four maximum HP. Adding stacks does not heal. Losing them clamps current health to the resulting maximum. Stat percentage modifiers continue to apply after flat bonuses.

## Authoring

Choose these resources through the existing status dropdown on an ability, weapon, or tile. This change does not assign the buffs to any existing gameplay content. The saved resource IDs are `strength_up`, `dexterity_up`, `constitution_up`, and `intelligence_up`.

`StatusEffectDefinition.stackable` enables one additional stack per application. Stacks multiply stat modifiers; damage ticks, Stun, Taunt, and granted passives do not multiply. Flat and additive percentage modifiers sum once per stack; multiplicative stat modifiers compose once per stack. The shared resource is never modified by active stacks. Nonstacking statuses still refresh their duration and keep a single stack. Timed stackable statuses share a duration, refreshed on application.

`lasts_until_battle_end` disables both duration countdown modes and hides their Inspector fields. Both new options default to false for compatibility. The four bundled buffs enable both options and set editable affected-unit AI utility to +2 per application.

The unit displays one icon per status with a count badge for stackable statuses. Badge spacing accommodates multiple digits without overlapping the health bar. Descriptions state the per-stack bonus and battle lifetime.

## Runtime and persistence

`ActiveStatus.stack_count` starts at one. Applications from different sources combine by status ID; the latest source metadata is retained. `get_stat_modifiers(stack_count = 1)` evaluates the effective modifiers, and `calculate_stat_with_statuses` accepts an optional status-ID-to-count dictionary for simulation.

Exact scenario saves and AI checkpoints preserve stack counts. Older saved statuses without this field restore as one stack. AI snapshots copy counts independently, include them in planner cache keys, and forecast each new stack's stat bonus and utility without modifying the live unit. Constitution forecasts increase maximum health without healing.

## Verification

Run `godot --headless --path . --script res://tests/run_stackable_status_tests.gd` for focused resource, stacking, modifier, lifetime, health, persistence, AI, combat-finalization, and badge-layout checks. Run without `--headless`, using `--rendering-method gl_compatibility` and appending `-- --capture`, for a screenshot saved under `.godot/stack_buffs_validation/stacks.png`.

The Empower/Cleanse Inspector suite checks the new controls and resource round trips. The AI checkpoint and run developer integration suites also exercise stacked buffs through rewind and restart. Related regression coverage includes Empower/Cleanse, terrain, active enemy AI, run state, Reassemble, armor, and the aggregate headless suite.

Validated on Godot 4.7.1: the focused suite passes 201 headless checks and 202 rendered checks, including the screenshot. Inspector validation passes 23 checks. Empower/Cleanse (121), run developer integration (156), Reassemble (78), armor (120), terrain, AI checkpoint, active enemy AI, and run-state suites also pass. The aggregate suite retains the baseline's eight assertion failures and four stale-fixture error lines; the only log differences are timing sample values. The Inspector runner retains the existing shutdown allocation warnings.
