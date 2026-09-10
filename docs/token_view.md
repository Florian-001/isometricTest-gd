# Compact unit tokens

Hold either **Ctrl** key to show all on-map units as compact round tokens. Release
Ctrl to restore the normal artwork. Tokens use existing character artwork or an
assigned portrait, with blue borders for friendlies and red borders for enemies.
Bone piles use their pile image; units without artwork display an initial.

Health, armor, and status displays are hidden while Ctrl is held. The **Names**
setting still controls unit names. Selection, movement, and targeting continue
normally, using the token's circular footprint instead of the hidden artwork.
The view also works while developer mode is paused and applies to newly added
units. Losing window focus restores normal visuals. This view is temporary and
does not change saved scenarios or run state.

The Input Map action is `battle_token_view`. `TacticalCharacter` exposes
`set_token_view_enabled(bool)` and `is_token_view_enabled()` for presentation.

Run `godot --headless --path . --script res://tests/run_token_view_integration.gd`
for input, focus, targeting, name, save-state, and developer-spawn checks.
Run without `--headless` and append `-- --capture` to save comparison images under
`.godot/token_view_validation/`.

Validation: token-view and battle-shortcut integration checks pass headlessly;
the unit-name integration check passes with rendering enabled. Its headless
developer-panel click failure also reproduces on the unchanged baseline.
