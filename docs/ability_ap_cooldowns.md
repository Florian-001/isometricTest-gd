# Ability action points and cooldowns

Friendly and enemy units receive **2 AP at the start of their own turn**. Unspent
AP does not carry over. Every current active ability, including basic attacks,
costs **1 AP** and has **1 turn of cooldown**. Using an ability on turn 1 makes it
ready again at the start of that unit's turn 2. Two different abilities can be
used in one turn.

Movement uses its existing allowance. Opportunity attacks and counterattacks
use their existing reaction rules, ignoring active-cast AP and cooldowns.
Activating Counter itself costs AP and starts its cooldown. Passives cost no AP.

## Authoring and execution

`AbilityDefinition.ap_cost` and `cooldown_turns` are exported in the Inspector and
the Ability Balance overview. Existing resources inherit defaults of 1 and 1.
AP cost is a positive integer; cooldown is a nonnegative integer. A cooldown of
0 permits repeated casts while AP remains. A cooldown of 2 makes the ability
unavailable on the next owner turn, then ready on the following turn.

A validated active cast pays once and starts cooldown before delivery. Multiple
hits and independently selected targets share that single payment. Cancelled
target selection and rejected casts cost nothing. Interrupting an already
committed cast does not refund AP or cooldown. Death or collapse to bones empties
AP; cooldowns still advance once per owner turn, including stunned turns and
Reassemble turns. Equipment or loadout changes do not clear cooldowns.

The HUD shows the active unit's AP beside End Turn. Ability buttons show their
AP cost and display `CD N` while cooling down. Buttons and keyboard shortcuts use
the same cast eligibility check. Players retain manual control of End Turn.

Enemy turns replan after each cast using remaining AP, cooldowns, and movement.
They can choose another ability before deciding where to move. Planning retains
its single-cast ranking and checks progress to prevent repeated invalid actions.

## Runtime interfaces and saves

`TacticalCharacter.can_activate_ability()` checks active-cast resources;
`can_use_ability()` remains the equipment/status check used by ongoing effects.
`spend_ability_action(ability)` commits AP and cooldown atomically. Generic
`spend_action_points(cost)` supports explicit AP spending without an ability.
`ability_available` now means the unit can act and has AP; individual abilities
must still be checked for affordability and cooldown.

Exact runtime saves and AI checkpoints include `action_points` and
`ability_cooldowns`, keyed by ability resource path. Runtime-only abilities use
instance keys within the current process. Restoring a save does not advance a
turn. Older saves map an available action to 2 AP, a spent action to 0 AP, and
start with empty cooldowns. Fresh combats clear cooldowns. AI snapshots keep
independent AP/cooldown copies and pay only for active casts, not reactions.

## Verification

```text
godot --headless --path . --script res://tests/run_ap_cooldown_tests.gd
godot --headless --path . --script res://tests/run_ability_balance_tests.gd
godot --headless --editor --path . --script res://tests/run_ability_balance_editor_tests.gd
godot --path . --rendering-method gl_compatibility --script res://tests/run_ap_cooldown_tests.gd -- --capture
```

The focused suite checks authored defaults, AP budgets, owner-turn cooldowns,
stun, Reassemble, multi-hit and selected-target casts, interruptions, reactions,
equipment changes, legacy and exact saves, isolated AI forecasts, real battle
controls, and two casts in an enemy turn. The rendered run writes
`.godot/ap_cd_validation/ap_cooldown.png`.

Existing class/catalog fixture failures, the aggregate AI timing/disengagement
failures, and developer save fixture failures also reproduce with the original
code and current authored resources. They are separate from AP/CD assertions.
