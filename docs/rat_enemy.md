# Rat enemy

Drag `scenes/enemies/rat.tscn` into an authored map's Characters container, or select **Rat** in the in-game developer unit palette. To allow generated rats, add that scene to a template definition's **Enemy Pool**. Existing pools, including Spawn Template Demo, are unchanged.

Expand the Rat scene's **Definition** resource (or open `resources/enemies/rat.tres`) to edit its stats. Defaults are 5 HP, CR 1, movement 6, speed 10, and Strength, Dexterity, Intelligence, and Constitution 1, using General AI.

**Base Health Override** under Health is 5 for Rat. It sets maximum HP at the definition's authored Constitution. Equipment, statuses, and scene Constitution overrides scale this proportionally, applying the usual minimum Constitution and rounding to at least 1 HP. Setting Base Health Override to 0 restores the existing Constitution-based calculation. Derived **Max Health** is visible in both the definition and unit Inspectors. Save formats are unchanged.

**Bite** is a single-target physical melee attack with range 1.414, zero innate damage, and no stat scaling. The equipped **Rat Teeth** supply its 5 damage. Both resources are available in the developer catalogs. Changing equipment can change Bite's damage.

Transparent `assets/characters/rat_left.png` and `rat_right.png` use the standard artwork frame, label, and health bar, with padding that keeps the rat smaller than existing units. The left texture uses an AtlasTexture margin in the scene to align its original image with the right sprite's square frame.

Run `godot --headless --path . --script res://tests/run_rat_tests.gd` to verify health scaling, actual Bite damage, palette placement, scenario persistence, and template compatibility. `tests/capture_rat_preview.gd` renders both facings beside a Wolf to `.godot/rat_preview.png` when run with a graphical renderer.

Run `godot --editor --path . --script res://tests/run_rat_editor_tests.gd` to check the actual Inspector and save/reload an edit to a temporary definition. These checks pass; this editor-script harness also produces the existing Godot shutdown allocation warnings documented for the template editor tests. Game-mode tests exit cleanly.
