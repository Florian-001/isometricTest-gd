# Compact unit tokens

Press either **Ctrl** key to show all on-map units as compact round tokens. Press
Ctrl again to restore the normal artwork. Holding or releasing the key does not
change the selected view. Tokens use existing character artwork or an
assigned portrait, with blue borders for friendlies and red borders for enemies.
Bone piles use their pile image; units without artwork display an initial.

Token view shows a compact health bar above each token, with armor beneath health
when the unit has armor. Current values appear inside the bars. Status icons sit above them
and retain their stack-count badges. These displays update with combat changes.
The **Names** setting still controls unit names below tokens. Selection, movement, and targeting continue
normally, using the token's circular footprint instead of the hidden artwork.
The view also works while developer mode is paused and applies to newly added
units. Switching window focus preserves the selected view. Each newly loaded
battle starts with normal visuals; the toggle does not change saved scenarios
or run state.

The Input Map action is `battle_token_view`. `TacticalCharacter` exposes
`set_token_view_enabled(bool)` and `is_token_view_enabled()` for presentation.

Run `godot --headless --path . --script res://tests/run_token_view_integration.gd`
for input, focus, targeting, name, save-state, and developer-spawn checks.
Run without `--headless` and append `-- --capture` to save comparison images under
`.godot/token_view_validation/`.

Validation: token-view and battle-shortcut integration checks pass headlessly;
the unit-name integration check passes with rendering enabled. Its headless
developer-panel click failure also reproduces on the unchanged baseline.
