# Starting hub artwork

Generated with the **built-in imagegen tool** on 2026-09-07. The existing `assets/characters/friendly_spellblade_right.png` was inspected as the friendly-style reference and supplied as an image input during refinement. [The prompt manifest](starting_hub_artwork.json) records every generation/refinement prompt, input, and selected output.

Final project assets:

- `assets/characters/friendly_wizard_right.png`
- `assets/characters/friendly_wizard_left.png`
- `assets/characters/friendly_cleric_right.png`
- `assets/characters/friendly_cleric_left.png`

These are full-body transparent PNGs. Wizard wears a pointed purple hat and carries a crystal staff; Cleric wears ivory robes and carries a sun staff. Both facings are wired into their reusable scenes under `scenes/friendlies/`. The hub's cards and selected slots use the same right-facing textures as battles.

Initial refinements contained a rendered checkerboard, so the final images underwent built-in background extraction. All four final files were verified as RGBA with transparent background pixels. They were copied into the project without altering source pixels or alpha. Godot generates mipmaps at import and uses linear mipmap filtering for the small card, slot, and battle views.

Visual checks: `.godot/hub_validation/hub_empty_1280.png`, `hub_selected_1280.png`, `hub_small_800.png`, `hub_small_640.png`, `hub_slots_640.png`, `battle_four_1.png`, and `battle_four_left.png`. The final art was reviewed at the existing 112×112 gameplay size in both directions, as well as the hub's 132/74-pixel art areas.
