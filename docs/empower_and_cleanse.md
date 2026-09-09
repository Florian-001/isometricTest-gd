# Empower and Cleanse

Clerics unlock **Empower at level 3** and **Cleanse at level 4**. Both are magic abilities that target one living ally or the caster within weighted range 5. Each spends one ability action and requires no weapon. Both are also available in the developer ability catalog.

## Empowered

Empower applies the positive **Empowered** status for three full turns of the affected unit. Applying it during a turn does not immediately consume a duration turn. Reapplying refreshes the duration rather than adding another copy. Empowered and Focus can coexist.

Empowered adds a flat +1 to Strength, Dexterity, Intelligence, Constitution, Speed, and Movement Range. These are normal stat modifiers: percentage modifiers and caps still apply. Constitution increases maximum health without healing, and health above the restored maximum is clamped when the buff expires. Speed also affects initiative and contributes to movement. At the default scaling, an uncapped unit at Speed 10 gains 1.25 movement range from the combined Speed and Movement Range bonuses. Increasing the movement allowance never refills movement already spent.

The status resource exposes its duration, all six modifiers, positive AI utility (12 by default), color, and SVG icon in the Inspector. Tooltips display its bonuses, duration, and polarity.

## Status polarity and Cleanse

Every status definition has an editable **Polarity** of Positive or Negative. New definitions default to Negative. Focus and Empowered are Positive. Burning, Slow, Stun, and Taunted are Negative. This explicit field determines whether Cleanse removes a status, independently of its effect, modifiers, or source.

Cleanse removes all negative statuses together and preserves positive statuses and their remaining duration. It does not reverse damage already taken or prevent terrain, weapons, or abilities from applying another negative status later. Casting on a valid target with no negative statuses still spends the action.

A stunned unit cannot cast Cleanse on itself, but an ally can cleanse its Stun. Removing Stun exposes any unspent actions, movement, and reactions; it does not restore spent resources. Removing Taunted clears its forced target.

Runtime callers can use `TacticalCharacter.remove_negative_statuses()`, which returns the number removed and emits the existing status/stat notifications once when something changes. `AbilityDefinition.PrimaryEffect.CLEANSE` uses this same operation. AI forecasts remove statuses only from simulated state, recompute movement and Constitution from retained modifiers, and score the remaining debuffs and prevented damage without healing the target. Empty cleansing has zero AI benefit.

Saved runtime statuses continue referencing their definition resource paths. Their remaining duration, processing flag, and source are preserved by the existing save format.

## Verification

Run with Godot 4.7.1 from the project root:

```text
godot --headless --path . --script res://tests/run_empower_cleanse_tests.gd
godot --headless --editor --path . --script res://tests/run_empower_cleanse_editor_tests.gd
godot --headless --path . --script res://tests/run_character_class_tests.gd
godot --headless --path . --script res://tests/run_equipment_ability_tests.gd
godot --headless --path . --script res://tests/run_headless.gd
```

For a rendered check, run the focused runtime suite without `--headless` and append `-- --capture`. Captures and temporary editor round-trip resources go under `.godot/empower_validation/`.

Validated on Godot 4.7.1: the rendered focused suite passes 122 checks, the Inspector suite passes 14 checks, and the equipment suite passes 470 checks. Character-class and active-enemy-AI integration tests also pass. The Inspector process retains the project's existing shutdown allocation warnings.

The aggregate headless suite retains eight pre-existing assertion failures in sample fixtures, inventory expectations, AI disengagement, and planning performance, plus the same stale-fixture script errors. It introduces no new assertion failures compared with the pre-change baseline. The developer-mode integration suite retains four failures in drawer width and exact-save handling, also reproduced from the previous commit in an isolated project copy.
