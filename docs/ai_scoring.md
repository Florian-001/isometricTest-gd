# Editing unit AI scores

In Godot's FileSystem dock, open `resources/ai/general_ai.tres`. Its Inspector
exposes the shared scoring values under **Effect Scoring**, **Position Scoring**,
and **Team Scoring**. Hover each field for its meaning. Save the resource after
editing, then run a battle and inspect **Dev → AI Log** to compare decisions.

To give a unit different priorities, duplicate the profile and save it as another
`.tres`. Assign it to the unit's **Tactical AI → Enemy AI Profile** field. Enemy
archetypes also expose **Enemy AI → AI Profile**. A per-unit override takes
priority over the archetype. Units without either use `general_ai.tres`, including
friendly units in Auto Battle. Editing a shared resource affects every unit that
uses it.

| Inspector field | Default | Effect |
| --- | --- | --- |
| Damage Weight | 1 | Points per actual HP or armor damage; also scales damage over time and damage penalties. |
| Healing Weight | 1 | Multiplies actual healing value, retaining the missing-health fraction for allied healing. |
| Utility Weight | 1 | Multiplies signed status, Cleanse, custom-effect, and terrain utility. |
| Friendly Damage Penalty | 2 | Multiplies damage value lost when harming this unit or its allies. |
| Immediate Defeat Ratio | 0.25 | Adds this fraction of an opponent's maximum HP for a defeat; allied defeats lose the bonus. |
| Future Value Weight | 0.25 | Multiplies estimated next-turn action value from the final position. |
| Shared Pressure Weight | 0.25 | Rewards damage that allies can follow up before the opponent's next turn. |
| Setup Defeat Ratio | 0.125 | Adds this fraction of maximum HP when allied follow-up can finish the damaged opponent. |

For example, increase Healing Weight to make support units favor healing, or
increase Immediate Defeat Ratio to favor finishing opponents. A ratio of `0.25`
means 25%; a weight of `2` doubles its contribution. Zero disables that scoring
contribution. Defeat and effect-utility bonuses are independent of Damage Weight.

Individual effects retain their own **AI Utility Hint** fields, and statuses have
**AI Forecast → Affected Unit AI Utility**. Utility Weight scales those authored
values for the profile. Scores change AI preferences, not actual combat damage,
healing, AP costs, cooldowns, or movement allowances.

The defaults preserve the existing behavior. Useful casts still take priority
over movement or holding, and incoming-threat and exact-reply estimates remain
diagnostic only. The planner shortlists candidates and decides again after each
cast; these controls do not add an exhaustive multi-action search.

## Verification

```text
godot --headless --path . --script res://tests/run_ai_profile_tests.gd
godot --headless --editor --path . --script res://tests/run_ai_profile_editor_tests.gd
```

The runtime suite covers defaults, resource persistence, both factions' ability
choices, profile inheritance, target shortlisting, terrain, position/team scoring,
and per-hit damage-over-time forecasts. The editor suite edits all eight fields
through their actual Inspector controls and verifies the saved resource reloads.

Validated on Godot 4.7.1: 77 profile checks, 27 Inspector checks, 162 Auto Battle
checks, 91 AP/cooldown checks, and enemy-AI battle integration pass. The active-AI
runner retains the same disengagement assertion seen before this change. Armor's
120 assertions pass, followed by the previously documented Godot shutdown crash
(`0xc0000005`). Validation logs are under `.godot/ai_profile_validation/`.
