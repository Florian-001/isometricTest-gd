# Wand

The **Wand** is a one-handed ranged weapon with **5 weapon damage** and a
**range of 5**. Its basic attack, **Wand Shot**, deals magical damage equal to
`round(5 + effective Intelligence)` before defenses and applicable passive bonuses.
It grants no stat bonuses or on-hit status. A shield or other compatible offhand
can remain equipped. The default run includes it in its equipment pool for loot
and shops, and the developer catalog includes both the item and its attack.

## Editing in Godot

Select `resources/items/weapons/wand.tres` in the FileSystem dock to edit weapon
damage, handedness, and weapon type. Expand **Weapon → Basic Attack Override**,
or select `resources/abilities/wand_shot.tres`, to edit range and scaling.
Wand Shot uses **Ranged** ability type so it requires a ranged weapon and receives
weapon damage, with **Magical** damage type and **Intelligence ×100%** scaling.
It has zero innate damage, one projectile hit, 1 AP cost, and a one-turn cooldown,
matching Shoot's action and targeting rules. Weapon range bonuses are disabled.

Other weapons with an empty Basic Attack Override retain their automatic Strike
or Shoot. The override is ignored on non-weapon items. Friendly classes keep their
unlocked abilities alongside the equipped basic attack. Enemies continue using
explicit ability loadouts. Equipping, swapping, or unequipping never restores
spent actions or reactions, and existing saves need no migration.

## Verification

Run `godot --headless --path . --script res://tests/run_wand_tests.gd` for damage,
INT modifiers, targeting, AI/runtime agreement, offhand compatibility, equipment
swaps, inventory and battle previews, saves, loot/shop availability, and Unit
Balance draft preservation. Run the corresponding `run_wand_editor_tests.gd`
with `--headless --editor` to verify Inspector editing and resource save/reload.
