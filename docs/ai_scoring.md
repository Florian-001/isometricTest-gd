# Editing unit AI scores

In Godot's FileSystem dock, open `resources/ai/general_ai.tres`. Its Inspector
exposes the shared scoring values under **Effect Scoring**, **Position Scoring**,
and **Team Scoring**. Hover each field for its meaning. Save the resource after
editing, then run a battle and inspect **Dev → AI Log** to compare decisions.

To give a unit different priorities, duplicate the profile and save it as another
`.tres`. Assign it to the unit's **Tactical AI → AI Profile Override** field, or
open a friendly class resource and assign **Auto Battle → AI Profile**. Enemy
archetypes expose **Enemy AI → AI Profile**. Editing a shared resource affects
every unit that uses it.

Friendly Auto Battle uses the unit override first, then the **first class in its
allocation list with a configured profile**, then `general_ai.tres`. Empty class
profiles are skipped. For example, Warrior (empty), Cleric (support), Wizard
(damage) uses the Cleric profile; moving Wizard before Cleric uses Wizard's.
Levels do not determine priority and profiles are not blended. An empty allocation
list inherits the template's Starting Class. Class/profile changes affect the
next automated decision. Manual friendly turns remain manual while Auto Battle
is off. Enemies use the unit override, then their archetype profile, then General AI.

`TacticalCharacter.get_ai_profile()` returns the resolved profile. The hidden
`enemy_ai_profile` property and `get_enemy_ai_profile()` remain compatibility
aliases, so existing scene assignments and script calls work. Re-saving a scene
writes the new `ai_profile_override` property.

Run, scenario, restart, and AI checkpoint snapshots store only the explicit
override's resource reference. Save custom profiles as `.tres` assets (or as
authored scene subresources) before saving a battle; unsaved runtime overrides
are rejected. An absent snapshot field preserves the scene's assignment; an
empty reference clears it and enables inheritance. Inherited profiles continue
to resolve from class resources, including later edits, rather than copying their
scoring values into a save. New class profile fields default to empty.

| Inspector field | Default | Effect |
| --- | --- | --- |
| Damage Weight | 1 | Points per actual HP or armor damage; also scales damage over time and damage penalties. |
| Healing Weight | 1 | Multiplies actual healing value, retaining the missing-health fraction for allied healing. |
| Utility Weight | 1 | Multiplies signed status, Cleanse, custom-effect, and terrain utility. |
| Friendly Damage Penalty | 2 | Multiplies damage value lost when harming this unit or its allies. |
| Kill Weight | 0 | Fixed bonus points per opponent defeated, added to the maximum-HP-based defeat bonus. |
| Immediate Defeat Ratio | 0.25 | Adds this fraction of an opponent's maximum HP for a defeat; allied defeats lose the bonus. |
| Future Value Weight | 0.25 | Multiplies estimated next-turn action value from the final position. |
| Shared Pressure Weight | 0.25 | Rewards damage that allies can follow up before the opponent's next turn. |
| Setup Defeat Ratio | 0.125 | Adds this fraction of maximum HP when allied follow-up can finish the damaged opponent. |

For example, increase Healing Weight to make support units favor healing, or
increase Immediate Defeat Ratio to favor finishing opponents. A ratio of `0.25`
means 25%; a multiplier of `2` doubles its contribution. Zero disables that scoring
contribution. Defeat and effect-utility bonuses are independent of Damage Weight.

**Kill Weight** adds fixed points, rather than multiplying another score. The
opponent defeat bonus is `maximum HP × Immediate Defeat Ratio + Kill Weight`.
With Kill Weight `20` and Immediate Defeat Ratio `0.25`, defeating an opponent
with 40 maximum HP adds 30 points on top of actual damage value. Each defeated
opponent earns the bonus once, including area and multi-hit attacks. A skeleton
collapsing into a living bone pile earns no kill bonus; destroying the pile does.
The flat bonus does not change friendly-fire or terrain penalties, and it is
excluded from allied follow-up value to avoid duplicated teamwork rewards.
Existing profiles inherit Kill Weight `0`; no profile or save migration is needed.

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
godot --headless --path . --script res://tests/run_kill_weight_tests.gd
godot --headless --path . --script res://tests/run_friendly_ai_profile_tests.gd
godot --headless --editor --path . --script res://tests/run_ai_profile_editor_tests.gd
```

The runtime suite covers defaults, resource persistence, both factions' ability
choices, profile inheritance, target shortlisting, terrain, position/team scoring,
and per-hit damage-over-time forecasts. The editor suite edits all nine fields
through their actual Inspector controls and verifies the saved resource reloads.
It also assigns, clears, saves, and reloads class profiles and unit overrides.
The friendly suite covers allocation order, skipped classes, overrides, runtime
changes, legacy scene assignments, healing decisions and control handoffs, plus
validated run/scenario saves, restarts, and both inherited and overridden AI checkpoints.
The kill-weight suite covers fixed/additive bonuses, both factions' finishing
choices, shortlisting, area/repeated hits, bone piles, unchanged allied/terrain
penalties, teamwork deduplication, and counter/opportunity forecast signs.

Validated on Godot 4.7.1: 82 profile checks, 47 kill-weight checks, 91 friendly
profile checks, 41 Inspector checks, 162 Auto Battle checks, 78 Reassemble checks,
and AI checkpoint/enemy-AI integration pass. The active-AI runner retains its
existing disengagement assertion. The AP/cooldown suite passes 90 of 91 checks;
its authored-default assertion expects Fireball to cost 1 AP with cooldown 1,
while the current authored resource uses 2 AP and cooldown 2. That failure also
occurs in an isolated pre-feature copy with the current authored data.
Editor shutdown still reports the project's known allocation warnings. Kill Weight
logs and the baseline project are under `.godot/kill_weight_validation/`; prior
class-profile verification logs remain under `.godot/friendly_ai_validation/`.
