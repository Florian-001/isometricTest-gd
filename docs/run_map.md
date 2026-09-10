# The Ascent: playable run map

Start the game and choose **New Run**, select 1–4 characters in the [starting hub](starting_hub.md), then press **Start Run**. **Continue Run** resumes the saved journey directly; standalone battlefield buttons still start independent battles. The route has fifteen room floors and one final boss. Only connected next rooms can be selected. Escape/Menu preserves progress.

## Five Combats

Choose **New Run: Five Combats** for a separate short run using the same party-selection hub. Its five normal combats form one centered, numbered route: goblins at CR 1, 2, and 3, then skeletons at CR 4 and 5. There are no elites, boss, or noncombat rooms. Winning the fifth battle completes the run. Normal gold rewards, party health, equipment, inventory, and permanent losses carry forward as usual.

**Continue: Five Combats** resumes this run; **View Last: Five Combats** displays its final outcome. Its checkpoint is `user://run/five_combats.json`, with its own `.bak` backup. Starting or replacing either run affects only that run's save slot. The original Ascent continues to use `user://run/active.json`.

Edit `resources/run/five_combats.tres` for the short run's party and encounter configuration. Its map settings expose **Layout → Linear Combat** and **Combat Count** (1–15, default five). Separate `five_combats_goblins.tres` and `five_combats_skeletons.tres` resources hold its progression; keep their inclusive ranges covering every configured combat. Linear runs require normal encounters with a 1.0 multiplier and no chief, and do not require elite or boss catalogs. The existing battlefield and character/enemy assets are shared.

The canvas exposes separate linear spacing and padding, allowing all five rooms to fit at the supported resolutions. The screen shows the selected run's title, combat count, relevant legend, and final result. Saved graphs record their layout; older graphs without layout metadata retain Ascent validation. Scenario saves and developer restarts retain the authored map identity when combat progression creates private resource copies.

## Edit in Godot

- Open `scenes/run_map_screen.tscn` for the parchment screen, legend, party strip, room results, and merchant panel. The map canvas has an editor preview; select `Margin/VBox/MapScroll/MapCanvas` and use **Refresh map preview** after adjusting its preview seed/settings.
- The canvas Inspector exposes room and floor-label scenes, icons, spacing, jitter, dot size, and path colors. Rooms are instances of `scenes/run/room_button.tscn`. Party and shop entries also have reusable scenes in `scenes/run/`.
- Edit `resources/run/map_theme.tres` for fonts and button/panel styles. Ink symbols are original SVGs in `assets/run_map/`. The paper texture and its gradient are authored in the screen scene.
- Edit `resources/run/default_run.tres` for the starting party, gold, encounter pools, combat stages, floor overrides, rewards, healing fraction, merchant stock, prices, and unknown-room weights. Its map-settings resource holds columns, routes, generation limits, and room weights. See [Editing combat progression](combat_progression.md) for manual Inspector editing and validation.
- Edit `scenes/run/starting_party.tscn` for party templates, stable IDs, loadouts, and stats. Each run battlefield in `scenes/run/` contains `PartySpawns` with Inspector-editable grid cells. Maintain one spawn per original party member, including slots for members who may later be lost.
- Encounter resources in `resources/run/` reference these battlefields. Elite resources multiply Constitution, Strength, Dexterity, and Intelligence by 1.5. The boss resource applies a 2.0 multiplier only to its named chief. Original standalone maps and their authored combat values are separate.
- Select `Main/RunController` for a fixed development seed and the run configuration. Normal play chooses a new random seed.
- The default run uses a fifteen-spawn battlefield with goblins on floors 1–3 and skeletons on floors 4–15, using the authored stage CR budgets. Normal and elite catalogs reference this layout; elites retain their stat multiplier. **Spawn Template Demo** remains available for standalone play. See [Battle map templates](map_templates.md) for Godot painting, enemy pools, standalone parties, and checkpoint behavior.

## State and battle boundary

`RunController` owns the run through `RunState` and `RunPartyMember`. The hub calls `new_run_with_party`; `new_run` remains available for the fixed two-character party. The map calls `select_room`, `resume_room`, `buy_offer`, and `complete_room`, and observes `state_changed`. A committed combat room emits `battle_requested`; `MapManager` builds the existing battle scene with an encounter and party entry snapshot.

`TacticalBattle` restores surviving party members and inventory before initiative starts. It emits `battle_finished` once, with the result, party condition/equipment, and inventory. Temporary statuses and action state do not carry between encounters. Fallen run members cannot be revived and lose equipped items; shared spare inventory remains. Standalone battles retain their existing behavior.

The **Dev** button is always available in battles, including runs; the separate manual Restart button stays hidden during runs. Opening Dev during an action queues it until a safe pause point. Developer mode supports unit and terrain edits, scenario saves/loads, and AI checkpoint restoration. **Restart & Play** keeps the edited setup, current party health and equipment, and current inventory while resetting combat turns, actions, temporary statuses, and enemy health. Exact snapshots restore their captured runtime instead. Reloads retain the active run encounter and room, without regenerating enemies or applying elite/boss scaling again.

Developer edits affect the current encounter. Normal run results carry health, equipment, class levels, and inventory into subsequent rooms. Deleted original party members are recorded as lost, and defeated run friendlies remain permanently defeated after a developer restart. Added friendly units help in the current encounter but do not join the persistent run party or prevent defeat when all original members are lost. The legacy `enable_dev_tools` property is retained for compatibility but no longer hides or disables Dev, and it is no longer shown in the Inspector.

**Save & Exit** abandons the in-progress battle; continuation repeats that same encounter from its committed entry checkpoint, including its original party state. Developer scenario saves remain separate from that checkpoint. Results are saved before their panels are shown. A failed result save keeps the completed battle alive with a retry button.

## Saving

The active checkpoint is `user://run/active.json`; `active.json.bak` retains the previous valid checkpoint. This is independent of developer scenario saves. Writes go through a verified temporary file and atomic replacement. Failed writes roll back in-memory room/reward transactions. Invalid saves are preserved and reported; a valid backup is recovered when possible.

The checkpoint includes the generated graph, committed route and room, concrete encounter/reward/merchant choices, purchased offers, party, inventory, currency, and outcome. Interrupted combat restarts from entry. Resolved rewards cannot be claimed again after loading. Completed or lost runs can be viewed from the menu; replacing an unfinished or unreadable saved run requires confirmation at **Start Run** in the hub.

## Validation

Run with Godot 4.7 from the project directory:

```text
godot --headless --path . --script res://tests/run_run_map_tests.gd
godot --headless --path . --script res://tests/run_run_state_tests.gd
godot --path . --script res://tests/run_run_map_integration.gd
godot --headless --path . --script res://tests/run_dev_run_integration.gd
godot --headless --path . --script res://tests/run_five_combats_integration.gd
```

The Five Combats suite drives all five real battles, separate save slots, repeated controller switching, fresh-session continuation, developer fresh/exact reloads, permanent party loss, duplicate results, victory before and after acknowledgement, failed final-save retry, backup recovery, and replacement cancellation. Run it without `--headless` for screenshots of both menu rows and the complete short map at 1024×720, 1280×720, and 1920×1080, plus victory and defeat panels. Saves and screenshots are isolated under `.godot/five_combats_validation`. Combat results are accelerated with lethal test damage; these checks verify progression and persistence, not balance. Progression unit tests use explicit CR 1–15 fixtures so ordinary full-run tuning does not invalidate their mathematical expectations.

The map suite checks 1,000 seeds twice, topology and room constraints, serialization, and bounded failure for impossible weights. State tests exercise every room effect, unknown outcomes, purchases, duplicate actions, permanent loss, backup recovery, invalid saves, and failed-write rollback. Integration drives real mouse/keyboard input, scrolling and resizing, inventory equipment, a fresh application session, a full 16-room route with ten actual battle instances, merchant UI, victory, and defeat. Battle outcomes in the complete-route fixture are accelerated by applying lethal damage to test combatants; this verifies transitions and persistence rather than game balance.

Rendered checks cover 1024×720, 1280×720, and 1920×1080. Screenshots and isolated test saves go under `.godot/run_validation` and `.godot/run_state_validation`.

The developer-run suite covers normal, elite, boss, and generated-template encounters; queued opening; class edits; fresh and exact reloads; AI checkpoints; party health, equipment, and inventory; permanent defeat; result-save recovery; and rewards committed once. Its saves are isolated under `.godot/dev_run_validation`. Add `-- --capture` to a rendered run of that suite for 1280×720 screenshots of the battle Dev button and editor.

Also checked: melee integration, active enemy AI integration, battle shortcuts, developer-mode integration, and developer-save unit tests. These pass with normal Godot permissions. Restricted processes can report a Windows certificate-store/cache error; those errors are absent when Godot has its ordinary runtime permissions.

The legacy level-selection and inventory integration fixtures already failed before this change: they reference removed Terrain Showcase characters and earlier sample stats/items. The broader existing unit suite also reports sample-data expectations and AI behavior/performance failures. Those unrelated scene/content expectations were not rewritten for this feature. The dedicated run integration exercises standalone menu entry, the existing inventory UI, and the new battle boundary directly.
