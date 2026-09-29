# Ranged abilities

Power Shoot and Piercing Shoot are reusable definitions under `resources/abilities`.
Both appear in **Ability Balance → Active Abilities** and the in-battle developer
ability picker. Add them to a unit or a class unlock through the existing Inspector
workflow when needed.

| Ability | Physical damage before armor | Range | Targeting |
| --- | --- | --- | --- |
| Power Shoot | Equipped ranged weapon damage + 150% effective Dexterity | 5 | One selected enemy |
| Piercing Shoot | Equipped ranged weapon damage + 100% effective Dexterity | 5 | Every enemy on a full-range line in the aimed direction |

Both require a ranged weapon, have no innate damage, and resolve one hit per
affected enemy. They use Shoot’s projectile color and speed. Normal armor,
equipment modifiers, applicable passive bonuses, and weapon status behavior remain
part of the existing damage pipeline. Weapon range bonuses do not extend their
fixed range.

## Piercing aim

Choose another grid cell within range to aim. The line continues beyond that cell
until range 5, the map edge, or the first wall. Units do not block the line; allies
and the caster are excluded from damage. A nearby aim point therefore still hits
enemies farther along the same direction. Empty cells can be selected, but the
caster’s own cell and cells through a blocking wall cannot.

Range uses the existing weighted distance: orthogonal steps cost 1 and diagonal
steps cost 1.414. A diagonal ray reaches three diagonal cells (4.242), while the
fourth lies outside range. Arbitrary directions follow the existing line
rasterization, extended along the original integer slope and trimmed by range.
Wall cells are projectile impact endpoints and receive no ability effects.

Damage resolves after the projectile arrives, following ordinary projectile
execution. The hover area, visual endpoint, executed recipients, and AI forecast
share the same line geometry. Existing projectile signals continue to report the
selected aim cell.

## Editor and API support

`AbilityDefinition.Shape.LINE_TO_MAX_RANGE` is appended as value 7. It requires a
stationary, one-cell-wide cast without caster-centered or per-hit selection.
Existing shape values, including Beam’s `LINE_FROM_CASTER`, retain their behavior.

`AbilityTargeting.get_delivery_endpoint(...)` returns the ray’s final range/map
cell or first blocking wall; other shapes return the selected cell.
`ProjectileDelivery.launch(...)` accepts an optional `visual_endpoint` after its
existing arguments. Omitting it preserves ordinary projectile behavior and
computes the full-range endpoint for the new shape.

## Verification

```text
godot --headless --path . --script res://tests/run_ranged_shoot_tests.gd
godot --path . --rendering-method gl_compatibility --script res://tests/run_ranged_shoot_tests.gd -- --capture
```

The focused suite checks definitions, equipment and scaling, standard armor,
cardinal/diagonal/arbitrary geometry, walls, map edges, single-hit recipients,
projectile positions and signals, AI forecast parity and planning, Ability Balance
discovery, and the real battle hover preview. Optional capture writes
`.godot/ranged_shoot_validation/piercing_preview.png`.

Ability Balance and Unit Balance regressions pass. Existing Multiple Arrows tests
have an Archer-level expectation inconsistent with the current edited Archer
resource. A focused group of 40 existing targeting/damage/AI tests has five other
failures; all six failures were reproduced in the pre-change code snapshot using
the same current resource edits.
