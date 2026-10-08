# Combat speed

Click **Speed: 1×** beside Auto Battle to cycle **1× → 2× → 3× → 1×**. The speed applies to manual and automated combat, including movement, melee attacks, projectiles, charges, knockback, and floating combat numbers. Changing speed affects actions already underway. Damage, AP costs, cooldowns, initiative, movement resources, and audio playback are unchanged.

The choice is saved to `user://settings.cfg` under `[combat]`, key `speed`, and persists across game launches, battles, restarts, scenario loads, and AI checkpoint restores. Missing or invalid settings default to 1×. If saving fails, the current session keeps the selection and emits a warning.

The speed button is disabled during Dev mode, return confirmation, and after combat ends. Paused actions resume at the selected speed. Camera controls and FPS refresh use real time. Menus, the hub, and run maps use normal time; combat speed is released after the last action finishes resolving or when the battle closes.

`CombatSpeedSettings.set_speed(int)` accepts 1, 2, and 3 and emits `speed_changed(int)` when the selection changes. `activate_battle(Node)` applies the preference to the combat clock; `deactivate_battle(Node)` resets the clock only when the caller owns it, preserving replacement battles during reloads. Combat saves do not serialize this user preference.

Run `godot --headless --path . --max-fps 120 --script res://tests/run_combat_speed_tests.gd`. The suite isolates settings under `.godot/combat_speed_validation/` and checks persistence, invalid settings, save failure, lifecycle transitions, timing at all speeds, changes during actions, pauses, damage and resource invariants, camera/FPS timing, and layout at 1280×720 and 800×600. Run without `--headless`, with `--rendering-method gl_compatibility` and `-- --capture`, to save screenshots in that directory.

Verified on Godot 4.7.1: the combat-speed suite passes 181 checks, including a finishing Auto Battle cast and failed replacement initialization. Melee integration, battle shortcuts, and the Ram/knockback suite (956 checks) pass. Existing Auto Battle (5 failures), Charge (1 failure), and AP/cooldown (6 failures) assertions reproduce on the untouched `063f018` baseline; these expect older AP costs. Baseline logs and rendered screenshots are retained under `.godot/combat_speed_validation/`.
