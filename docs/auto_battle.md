# Auto Battle

Use **Auto Battle: Off / On** in the battle's top-right action row to automate every friendly turn. Friendly units use the same planner, scoring, movement, and ability executor as enemies, retaining their faction and their own equipment and ability loadouts. Enemies remain automated regardless of the toggle.

Enabling the toggle takes over the current friendly unit's remaining turn. Pending targeting is discarded without spending AP. A movement or cast already underway finishes before AI takes over. Turning the toggle off finishes the current movement or complete cast, including all hits and reactions, then restores manual control without resetting AP, cooldowns, or movement. Manual movement, abilities, and End Turn stay disabled until handback completes.

The setting lasts for this battle only. New battles, restarts, and scenario reloads begin with Auto Battle off. Restoring a friendly AI checkpoint returns to manual control immediately before its saved decision, preserving its remaining resources. Dev pauses after the current AI action and resumes the same turn with the existing toggle setting. Return-to-menu confirmation pauses the battle normally. Automation stops when combat ends or the battle closes.

## Per-hit abilities

Both sides' AI can use Select Per Hit abilities, including Multiple Arrows. Each plan carries an ordered `EnemyTurnPlan.selected_targets: Array[TacticalCharacter]`; ordinary casts leave it empty. The shared planner chooses each slot by the existing effect score after simulating preceding hits, breaking ties by initiative order and then scene order. It honors repeated/distinct target settings, equipment, range, walls, faction flags, and taunt. Too few distinct legal recipients exclude a cast. Repeated selections can fill remaining slots even when preceding hits are expected to defeat every recipient; those later hits are skipped by the executor.

AP and cooldowns are paid once for the complete cast. Forecasts account for immediate health and armor changes, statuses, weapon passives, on-kill buffs, and knockback. Turn-start damage from statuses has tactical value but does not damage recipients between arrows. Counter reactions resolve once per surviving eligible defender after the complete cast. Execution locks recipients to unit identities, validates the full list before paying its cost, and skips invalid later recipients without replacing them.

`TacticalBattle.set_auto_battle_enabled(bool)` updates the toggle and schedules a safe control handoff. `auto_battle_enabled` defaults to `false` and is not serialized. Assign a profile under the unit's **Tactical AI → AI Profile Override** or the class resource's **Auto Battle → AI Profile**. Friendly priority is unit override → first allocated class with a profile → General AI. Empty classes are skipped; allocation order, rather than level, determines the inherited profile. The planner resolves the profile again for each action. The hidden `enemy_ai_profile` alias still accepts existing scenes and callers. No enemy abilities are added automatically.

Setup snapshots preserve the explicit override's saved resource reference across runs, scenarios, restarts, and AI checkpoints. An empty reference enables inheritance; older snapshots without the field preserve the authored scene assignment. Inherited profiles stay attached to class resources, so later resource edits remain effective. See [AI scoring](ai_scoring.md) for scoring controls and assignment examples.

## Verification

Run `godot --headless --path . --script res://tests/run_auto_battle_tests.gd`. The suite covers both factions' per-hit planning and execution, resource costs, early kills, distinct targets, taunt, walls, cooldowns, statuses, counters, knockback, manual takeover, rapid toggles, enemy turns, pause/Dev behavior, checkpoint restoration, restart defaults, and automatic combat completion.

Run without `--headless`, using `--rendering-method gl_compatibility` and appending `-- --capture`, to save 1280×720 and 800×600 screenshots under `.godot/auto_battle_validation/`.

Validated on Godot 4.7.1: the focused suite passes 162 headless and rendered checks. Enemy AI integration, battle shortcuts, AI checkpoint integration, AP/cooldown (91 checks), and run-state tests pass. The broader Multiple Arrows, active-AI, Warrior, Five Combats, and developer-run runners retain pre-existing assertions involving class unlocks, AI disengagement, run roster budgets/families, and the saved entry-class expectation. These assertion categories were compared with an isolated pre-feature project retaining the original local configuration edits. Logs and the comparison project are under `.godot/auto_battle_validation/`.
