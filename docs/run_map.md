# The Ascent: playable run map

Start the game and choose **New Run**, select 1–4 characters in the [starting hub](starting_hub.md), then press **Start Run**. **Continue Run** resumes the saved journey directly; standalone battlefield buttons still start independent battles. The route has fifteen room floors and one final boss. Only connected next rooms can be selected. Escape/Menu preserves progress.

## Edit in Godot

- Open `scenes/run_map_screen.tscn` for the parchment screen, legend, party strip, room results, and merchant panel. The map canvas has an editor preview; select `Margin/VBox/MapScroll/MapCanvas` and use **Refresh map preview** after adjusting its preview seed/settings.
- The canvas Inspector exposes room and floor-label scenes, icons, spacing, jitter, dot size, and path colors. Rooms are instances of `scenes/run/room_button.tscn`. Party and shop entries also have reusable scenes in `scenes/run/`.
- Edit `resources/run/map_theme.tres` for fonts and button/panel styles. Ink symbols are original SVGs in `assets/run_map/`. The paper texture and its gradient are authored in the screen scene.
- Edit `resources/run/default_run.tres` for the starting party, gold, encounter pools, combat stages, floor overrides, rewards, healing fraction, merchant stock, prices, and unknown-room weights. Its map-settings resource holds columns, routes, generation limits, and room weights. See [Editing combat progression](combat_progression.md) for manual Inspector editing and validation.
- Edit `scenes/run/starting_party.tscn` for party templates, stable IDs, loadouts, and stats. Each run battlefield in `scenes/run/` contains `PartySpawns` with Inspector-editable grid cells. Maintain one spawn per original party member, including slots for members who may later be lost.
- Encounter resources in `resources/run/` reference these battlefields. Elite resources multiply Constitution, Strength, Dexterity, and Intelligence by 1.5. The boss resource applies a 2.0 multiplier only to its named chief. Original standalone maps and their authored combat values are separate.
- Select `Main/RunController` for a fixed development seed and the run configuration. Normal play chooses a new random seed.
- The default run uses a fifteen-spawn battlefield with goblins on floors 1–3 and skeletons on floors 4–15, increasing base CR by one per floor. Normal and elite catalogs reference this layout; elites retain their stat multiplier. **Spawn Template Demo** remains available for standalone play. See [Battle map templates](map_templates.md) for Godot painting, enemy pools, standalone parties, and checkpoint behavior.

## State and battle boundary

`RunController` owns the run through `RunState` and `RunPartyMember`. The hub calls `new_run_with_party`; `new_run` remains available for the fixed two-character party. The map calls `select_room`, `resume_room`, `buy_offer`, and `complete_room`, and observes `state_changed`. A committed combat room emits `battle_requested`; `MapManager` builds the existing battle scene with an encounter and party entry snapshot.

`TacticalBattle` restores surviving party members and inventory before initiative starts. It emits `battle_finished` once, with the result, party condition/equipment, and inventory. Temporary statuses and action state do not carry between encounters. Fallen run members cannot be revived and lose equipped items; shared spare inventory remains. Standalone battles retain their existing behavior.

Run battles disable developer tools and manual restart. **Save & Exit** abandons the in-progress battle; continuation repeats that same encounter from its entry checkpoint. Results are saved before their panels are shown. A failed result save keeps the completed battle alive with a retry button.

## Saving

The active checkpoint is `user://run/active.json`; `active.json.bak` retains the previous valid checkpoint. This is independent of developer scenario saves. Writes go through a verified temporary file and atomic replacement. Failed writes roll back in-memory room/reward transactions. Invalid saves are preserved and reported; a valid backup is recovered when possible.

The checkpoint includes the generated graph, committed route and room, concrete encounter/reward/merchant choices, purchased offers, party, inventory, currency, and outcome. Interrupted combat restarts from entry. Resolved rewards cannot be claimed again after loading. Completed or lost runs can be viewed from the menu; replacing an unfinished or unreadable saved run requires confirmation at **Start Run** in the hub.

## Validation

Run with Godot 4.7 from the project directory:

```text
godot --headless --path . --script res://tests/run_run_map_tests.gd
godot --headless --path . --script res://tests/run_run_state_tests.gd
godot --path . --script res://tests/run_run_map_integration.gd
```

The map suite checks 1,000 seeds twice, topology and room constraints, serialization, and bounded failure for impossible weights. State tests exercise every room effect, unknown outcomes, purchases, duplicate actions, permanent loss, backup recovery, invalid saves, and failed-write rollback. Integration drives real mouse/keyboard input, scrolling and resizing, inventory equipment, a fresh application session, a full 16-room route with ten actual battle instances, merchant UI, victory, and defeat. Battle outcomes in the complete-route fixture are accelerated by applying lethal damage to test combatants; this verifies transitions and persistence rather than game balance.

Rendered checks cover 1024×720, 1280×720, and 1920×1080. Screenshots and isolated test saves go under `.godot/run_validation` and `.godot/run_state_validation`.

Also checked: melee integration, active enemy AI integration, battle shortcuts, developer-mode integration, and developer-save unit tests. These pass with normal Godot permissions. Restricted processes can report a Windows certificate-store/cache error; those errors are absent when Godot has its ordinary runtime permissions.

The legacy level-selection and inventory integration fixtures already failed before this change: they reference removed Terrain Showcase characters and earlier sample stats/items. The broader existing unit suite also reports sample-data expectations and AI behavior/performance failures. Those unrelated scene/content expectations were not rewritten for this feature. The dedicated run integration exercises standalone menu entry, the existing inventory UI, and the new battle boundary directly.
