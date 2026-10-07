# Dev combat log

Open **Dev → Combat Log** to inspect manual friendly actions, friendly Auto Battle,
and enemy actions. The battle stays paused while browsing.

Each voluntary move, complete ability cast, and end-turn transition has one
entry and a checkpoint captured **before** the action spends resources. Reactions,
individual hits, caster movement, and knockback belong to the triggering action.
Canceled targeting and rejected commands do not create entries. Interrupted
actions retain their actual effects and resource costs.

The detail view shows actual paths, targets, HP and armor changes, healing, AP,
cooldowns, status stacks and durations, defeats, counters, opportunity attacks,
and terrain effects. Turn transitions include status ticks and action resets.
Automated actions also show the AI profile, chosen plan, ranked candidates,
search timing, and cache diagnostics. These are forecasts; the outcome lines
describe what actually happened.

## Navigation and Resume

- **Back** from Live restores the newest action's pre-action checkpoint. Further
  clicks step backward through retained actions.
- **Forward** steps toward newer checkpoints, then returns to the live battlefield
  captured when Dev opened. It restores recorded state without executing actions.
- Clicking a compact row restores its checkpoint and shows the full details.
  Rows remain newest first; the position indicator uses chronological action numbers.
- **Copy Logs** copies all retained details, including future entries while browsing.
- **Resume** from a checkpoint discards that action's old outcome and all newer
  entries. New commands or AI choices create a replacement timeline. Resume from
  Live keeps the existing history.

The battlefield shown for a selected row precedes the outcome described in its
details. Friendly restores return to manual control with Auto Battle off.
Invalid checkpoints report an error and preserve the current battlefield,
selection, pause, and scroll position.

The existing Battle Inspector **AI Debug History Limit** controls retention
(default 30). Entries, structured events, and checkpoints trim together. History
is local to the current battle and survives history navigation only; ordinary
scenario saves and restarts retain their existing formats. Dev setup edits and
inventory interactions are outside this combat timeline.

## Verification

Run `godot --headless --path . --script res://tests/run_combat_log_tests.gd`
and `godot --headless --path . --script res://tests/run_ai_log_checkpoint_integration.gd`.
For rendered layout checks, run the combat-log suite without `--headless`, using
`--rendering-method gl_compatibility -- --capture`. Screenshots are saved under
`.godot/combat_log_validation/` at 1280×720 and 800×600.

The focused suite covers real movement and casts, multi-hit costs and outcomes,
healing, stacks, nested reactions, interruptions, terrain, knockback, both AI
factions, turn transitions, live restoration, branching, defeated-unit replay,
and drawer layout. Checkpoint integration covers resource restoration, trimming,
failure recovery, scroll retention, and navigation boundaries.

Validated on Godot 4.7.1: 75 combat-log checks pass headless and rendered;
checkpoint integration, friendly AI profiles (91 checks), active enemy AI,
battle shortcuts, and terrain integration pass. The broader Dev unit, Dev
integration, and Auto Battle suites retain 3, 4, and 5 pre-existing assertions
respectively. The same failures reproduce on the pre-change code with the local
balance edits preserved. Comparison logs are under `.godot/combat_log_validation/`.
