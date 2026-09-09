# Armor

Equipped items grant a separate armor pool. Every ItemDefinition has an editable
**Armor** integer (zero by default). Wooden Shield provides **10 armor** while
retaining **+3 Constitution**. Contributions from equipment add together; a
two-handed item counts once. Both friendly and enemy units use the same rules.

All damage, including physical and magical attacks, additional effects, terrain,
opportunity attacks, and damage over time, consumes armor first. Any excess
reduces health: 14 damage against 10 armor removes 10 armor and 4 HP. Health
healing, Constitution changes, and Reassemble do not refill armor. Losing all
armor does not defeat a unit.

Armor starts full in a fresh encounter. The battle restores every survivor's
armor once, after the final action, movement, and nested reactions have finished.
This works on victory and defeat, without changing health or reviving fallen
units. Run results are emitted after restoration. Run-party saves continue to
derive the next encounter's full armor from equipped items.

## Equipment and saves

The following Armor-slot resources are available under `resources/items/armor/`:

| Item | Armor | Flat stat bonuses |
|---|---:|---|
| Leather Armor | 5 | +1 Strength, +1 Dexterity |
| Plate Armor | 10 | None |
| Robe | 3 | +3 Intelligence |

Each has its own inventory icon and can be assigned through the Inspector item
selector or the developer item catalog. These three items are editor-only additions;
they are not included in shop/reward pools, sample inventory, or starting equipment.

The unit remembers armor damage spent during the encounter, even with no armor
equipped. Current armor is max(0, equipped armor minus spent armor damage).
After absorbing 6 damage, removing and re-equipping a 10-armor shield leaves
4 armor. Increasing capacity to 15 would give 9 remaining armor. Health damage
never increases the spent armor counter.

Runtime scenario saves and AI checkpoints preserve `armor_damage_spent`,
including when armor equipment is removed. Old saves without that field start
with zero spent armor. Fresh developer restarts start with full armor; exact
restores retain damage.

## Presentation and extension points

Units with positive armor capacity display a blue bar and armor number below HP,
including when armor reaches zero. Absorbed damage numbers are blue, with separate
red numbers for HP overflow. Inventory shows current/max armor, and item details
show the granted amount.

`TacticalCharacter` exposes `current_armor`, `get_max_armor()`,
`restore_armor()`, and `armor_changed(current, maximum)`.
`DamageCalculator.resolve_damage(amount, health, armor)` returns separate
`health_delta` and `armor_delta` without changing state.

AI snapshots carry armor independently of health. Built-in estimates use
`estimate_with_armor(caster, target, health, armor)`; custom effect classes can
override this method to forecast armor. Existing `estimate_for_ai` overrides
remain compatible, retaining their health-delta contract. Apply the split
deltas once through `AIBoardSnapshot.apply_effect_estimate`; do not absorb the
health delta a second time. Forecast armor damage contributes to attack value,
while healing and defeat decisions use HP.

## Verification

Run `godot --headless --path . --script res://tests/run_armor_tests.gd`.
For screenshots at 1280×720 and 800×600, run without `--headless` and append
`-- --capture`. Test saves, screenshots, and regression logs are isolated under
`.godot/armor_validation/`.

The focused suite covers pool boundaries, equipment swaps and stacking, legacy
and exact saves, fresh restarts, both factions, AI/cache behavior, healing,
statuses, terrain, normal and selected repeated hits, reactions, Reassemble,
run transitions, and an aborted encounter-ending Charge. It also verifies that
a queued Dev panel waits until the final attack and armor restoration complete.

Equipment, inventory, active AI, terrain, opportunity attacks, Multiple Arrows,
Reassemble, AI checkpoints, run state, full-run integration, and developer-run
integration regressions pass. The full-run fixture now waits for encounter
resolution instead of assuming four frames suffice during an enemy animation.

The broad suite's stale catalog/item/ability/HP fixtures and AI disengagement and
timing expectations also fail before this change. The developer-panel width and
save-listing assertions reproduce in an isolated copy of the starting project.
Godot also intermittently exits with Windows status `0xC0000005` after successful
assertions, as already recorded for the existing suites in
[Passive abilities](passive_abilities.md).
