# Warrior abilities

Warrior class unlocks are authored in `resources/classes/warrior.tres`. Raise a friendly's Warrior level through the Inspector or the battle developer panel to unlock the abilities. Charge unlocks at level 2. Strike is a basic attack available to every friendly class when unarmed or equipped with a melee weapon; it has no level requirement.

| Level | Ability | Damage and targeting |
|---|---|---|
| 3 | Battle Stomp | Weapon damage + 100% effective Strength against every enemy within 1.5 grid units of the caster. |
| 4 | Taunt | Applies Taunted to enemies within 1.5 grid units, through the end of their next turn. Works without a weapon. |
| 5 | Multi Attack | Two separate melee hits on the same enemy, each dealing weapon damage + 50% effective Strength. Range matches Strike (1.414). |
| 6 | Counter | Grants the Counter passive until the start of the caster's next turn. Click the caster to activate. |
| 7 | Swipe | Weapon damage + 100% effective Strength to each enemy in a three-cell row immediately in front of the caster. |
| 8 | Ram | 100% effective Strength to one orthogonally adjacent enemy, followed by up to 2 tiles of knockback. |

All three abilities spend one normal ability action and no movement points. Stomp and Multi Attack require a melee weapon. There are no additional cooldowns or resource costs. Stomp does not stun; Taunt causes no damage or stun.

Counter and Swipe also spend one normal ability action, with no movement cost or cooldown. Counter works with any equipment, including unarmed; Swipe requires a melee weapon.

## Counter

Counter grants a positive status and a reusable passive. It retaliates once after each complete damaging attack that actually hits the unit, even when armor absorbs all damage. Melee, ranged, magic, area, and opportunity attacks qualify. A multi-hit cast or a cast with repeated target selections still triggers only one retaliation per defender. Terrain, damage over time, support abilities, and Counter retaliations never trigger it.

The retaliation uses the current equipment-granted basic attack (Strike or Shoot, including unarmed Strike for friendlies), normal range and line of sight, weapon range bonuses, effective stats, passive damage bonuses, armor, and weapon statuses. It costs neither movement, an action, nor an opportunity reaction. The defender must still be alive, present, able to attack, and in range of the living original attacker; it never moves or retargets. Incoming stun or lethal damage prevents retaliation. Other units receiving Counter through the developer passive picker use their equipment-granted attack; units without a usable basic attack cannot retaliate.

An area attack finishes damaging all recipients before surviving defenders counter in initiative order, breaking ties by roster order. An attacker's death stops remaining counters. Retaliations remain inside the original cast's resolution boundary, so a defeated acting unit cannot advance the turn mid-animation and combat finalization waits for completion.

The temporary status expires before the owner's next turn-start terrain and status processing, including stunned turns. Other units' turns and the activation turn's end do not consume it. Reapplication refreshes instead of stacking. Cleanse preserves it. Runtime saves retain its duration and grant; temporary and authored copies deduplicate by passive ID, and expiry preserves an authored Counter passive.

## Swipe

Click one of the four orthogonally adjacent cells to aim. The selected cell is the middle of a three-cell row perpendicular to that direction. For a caster at `(x, y)` aiming at `(x, y-1)`, the row is `(x-1, y-1)`, `(x, y-1)`, `(x+1, y-1)`. Self and diagonal aiming are invalid. The row rotates with the chosen direction, independently of sprite facing.

Each enemy in the row takes one Strike-strength hit. Allies and the caster are excluded. The center may be empty, and an entirely empty cast still spends the action. Board edges clip the row; wall cells and blocked diagonal corners cannot be hit. Weapon range bonuses do not extend Swipe. Hover previews, AI forecasts, and execution share this geometry; the slash spans the affected row.

## Ram and knockback

Ram spends one ability action, no movement, and has no cooldown. It works unarmed or with any equipment. Only effective Strength contributes damage: weapons do not add damage, passive weapon bonuses, weapon statuses, or reach. Select an enemy exactly one tile north, south, east, or west; allies, empty cells, diagonals, and self are invalid. The caster stays in place.

Damage applies at melee impact, then the surviving target is pushed up to two tiles directly away. A wall or board edge stops the push in the last valid cell and deals 1 damage to the target. Another unit stops it before the occupied cell and both units take 1 damage, regardless of faction. Armor absorbs collision damage normally. Each push has at most one collision; there is no chain push or continuation if the blocker dies. Defeated friendlies remain obstacles under the existing occupancy rules, but cannot take additional damage.

Knockback preserves facing and action, movement, and reaction budgets. It moves living stunned units and bone piles. It ignores terrain costs and triggers neither tile-entry effects nor opportunity attacks; terrain effects on later turns apply normally. Death or removal stops displacement. Collision damage does not trigger Counter; the original Ram target can counter once after the complete push only if still alive, able to attack, and within basic-attack reach.

`KnockbackEffectDefinition` is a reusable additional ability effect with `distance` (default 2) and `collision_damage` (default 1). The executor owns board-aware animated delivery; `KnockbackSystem` supplies shared collision geometry for execution, AI, and hover previews. The preview shows the path, landing tile, and colliding unit after accounting for the initial damage. Displacement and collision resolution finish before Counter, turn advancement, battle finalization, or saving. Existing runtime save fields retain the resulting position, health, and armor.

## Targeting and damage

Select Stomp or Taunt, then click the caster to confirm. Hovering the caster previews the affected tiles. A radius of 1.5 includes orthogonal and diagonal neighbors, excludes units two tiles away, and respects the existing grid line-of-sight and wall rules. Allies and the caster are never recipients.

Multi Attack plays two melee lunges and applies damage at each impact. The original target remains locked; death, removal, or loss of valid targeting stops subsequent hits without refunding the action or selecting another unit. Damage is rounded separately for each hit. Weapon statuses apply after each surviving hit and refresh by status ID. Applicable passive weapon bonuses are added once per hit. For a weapon dealing 4 damage and Strength 5, each hit deals 7 damage; a one-point Pack Tactics bonus makes that 8 per hit, or 16 total.

The ability bar shows Multi Attack as `2 × N DMG`; its tooltip includes the total. Hover previews and AI forecasts use the same damage calculations as execution.

## Taunt behavior

A taunted enemy must use a damaging ability that hits its taunter, moving into range if possible. Area attacks can damage other units as long as they also hit the taunter. If an attack is unavailable, the enemy pursues an attack position toward the caster. If no complete route exists, it makes reachable progress toward the caster, or holds when none is possible. It does not substitute attacks on other targets or support abilities. Movement costs, terrain, stun, and opportunity reactions still apply.

Taunt is checked before AI target limits and again after movement before a planned cast. Reapplying the status refreshes its one-turn duration and replaces the source with the latest taunter. A dead, removed, or no-longer-hostile source releases the restriction. Other units' turns do not consume the duration. Opportunity attacks outside the affected unit's turn remain unrestricted. Runtime saves and AI snapshots retain the source unit and remaining duration.

## Authoring

`AbilityDefinition` adds these exported properties with compatible defaults:

- **Caster Centered** (`false`): use Range as the effect radius, accept only the caster's cell for confirmation, and apply Target Flags only to recipients. Shape and Area of Effect are unused in this mode. The shipped radial abilities use Cast On Target delivery.
- **Hit Count** (`1`): repeat delivery and the effect sequence for one action; Multi Attack uses 2. `calculate_primary_effect_amount()` and `calculate_hit_damage()` describe one hit; `calculate_damage()` describes the full per-target total.
- **Requires Weapon** (`true`): disable matching weapon requirements and weapon contribution for Taunt while retaining the Melee ability classification.

The Taunted resource uses the appended `StatusEffectDefinition.Effect.TAUNT` enum value and `ActiveStatus.source_unit`. Existing serialized enum values and save formats remain valid. All new abilities appear in the developer catalog; the status appears in the existing resource-based status picker.

Swipe adds the appended `AbilityDefinition.Shape.LINE_IN_FRONT` value. `area_of_effect` controls its odd row width; the shipped resource uses 3 and range 1. This shape requires a stationary cast without caster-centered or per-hit selection modes.

Statuses now optionally reference `granted_passive` (default null) and set `expires_at_turn_start` (default false). With turn-start expiry enabled, `duration_turns` counts owner turn starts. Existing statuses retain their turn-end behavior. Counter uses `CounterPassiveEffect`; its resource and inline developer-save forms are supported. `AbilityExecutor.execute_counter_attack()` is the resource-free, non-chaining reaction entry point; `resolution_finished` signals completion of the outer cast and all reactions.

## Verification

Run `godot --headless --path . --script res://tests/run_ram_tests.gd` for Ram resources, all four directions, collisions, equipment and damage rules, forced movement, Counter interactions, save round trips, AI forecasts, and real battle UI checks. A rendered run with `-- --capture` saves a preview under `.godot/ram_validation/`.

Ram validation on Godot 4.7 passes 956 headless checks and 957 rendered checks. Warrior (81), Counter/Swipe (222), passive (83), equipment/ability (482), spear (695), Multiple Arrows (100), and Empower/Cleanse (121) checks pass, along with class, melee, Charge, terrain, opportunity integration, active-AI integration, and run-state suites. Class Inspector assertions also pass; that editor runner reports leaked rendering resources on shutdown.

The broad headless runner reports the same 12 errors as a clean checkout of `85384e1`, covering existing fixtures, item expectations, and AI assertions (timing values vary). Developer-mode unit coverage retains its existing equipment-count failure, and the opportunity/active-AI unit suites retain the disengagement assertion. Armor still passes all 120 assertions; the working checkout exited with `0xc0000005` afterward while the isolated baseline exited normally, consistent with the intermittent shutdown limitation below.

Run `godot --headless --path . --script res://tests/run_warrior_tests.gd` for resource, class, radius, damage, status lifetime, save metadata, AI, reaction, and real battle UI checks. Run without `--headless` and append `-- --capture` to save battle screenshots under `.godot/warrior_validation/`.

Run `godot --headless --path . --script res://tests/run_counter_swipe_tests.gd` for Counter and Swipe resource, geometry, damage, armor, reaction timing, lifecycle, save, AI, and battle UI coverage. Run without `--headless` and append `-- --capture` for screenshots under `.godot/counter_swipe_validation/`.

Regression coverage includes the class, melee, Charge, opportunity, passive, developer-mode, and active-enemy-AI suites. The active-AI unit suite has an existing disengagement assertion failure documented before this change; new warrior coverage must pass independently.

Counter/Swipe validation on Godot 4.7 passes 222 headless checks and 223 rendered checks, including a real battle's lethal counter, delayed turn advancement, and delayed armor restoration. The broader `run_headless.gd` and `run_dev_mode_unit.gd` runners retain the same fixture, equipment-catalog, and AI assertions reproduced in an isolated checkout of the pre-change commit; their failures are not introduced by these skills.

The armor runner reports 120 passing assertions. Windows Godot shutdown sometimes exits with `0xc0000005` afterward, a symptom also observed during pre-implementation planning; other runs, including an isolated copy with these changes, exit normally. Keep that process-exit limitation separate from assertion results.
