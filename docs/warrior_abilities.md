# Warrior abilities

Warrior class unlocks are authored in `resources/classes/warrior.tres`. Raise a friendly's Warrior level through the Inspector or the battle developer panel to unlock the abilities. Charge unlocks at level 2. Strike is a basic attack available to every friendly class when unarmed or equipped with a melee weapon; it has no level requirement.

| Level | Ability | Damage and targeting |
|---|---|---|
| 3 | Battle Stomp | Weapon damage + 100% effective Strength against every enemy within 1.5 grid units of the caster. |
| 4 | Taunt | Applies Taunted to enemies within 1.5 grid units, through the end of their next turn. Works without a weapon. |
| 5 | Multi Attack | Two separate melee hits on the same enemy, each dealing weapon damage + 50% effective Strength. Range matches Strike (1.414). |

All three abilities spend one normal ability action and no movement points. Stomp and Multi Attack require a melee weapon. There are no additional cooldowns or resource costs. Stomp does not stun; Taunt causes no damage or stun.

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

## Verification

Run `godot --headless --path . --script res://tests/run_warrior_tests.gd` for resource, class, radius, damage, status lifetime, save metadata, AI, reaction, and real battle UI checks. Run without `--headless` and append `-- --capture` to save battle screenshots under `.godot/warrior_validation/`.

Regression coverage includes the class, melee, Charge, opportunity, passive, developer-mode, and active-enemy-AI suites. The active-AI unit suite has an existing disengagement assertion failure documented before this change; new warrior coverage must pass independently.
