# Inventory and equipment

Open `scenes/inventory_screen.tscn` in Godot to edit the inventory. The scene
contains the first twenty item cells, three labeled equipment cells, the hover
timer, the detail card, and the existing character stats and abilities panels.

- `GeneralPanel/Margin/VBox/Scroll/Entries` controls the number of columns and
  spacing. The root's **Minimum Rows** defaults to four; additional rows are
  instantiated from **Item Slot Scene** as the pack grows.
- `scenes/inventory_item_slot.tscn` controls the 64-pixel cells and icon padding.
  Equipment cells expose **Equipment Slot**, **Empty Icon**, and its opacity.
- `scenes/inventory_item_details.tscn` controls the adjacent card layout and its
  item gap and viewport margin. **Hover Delay** on the inventory root defaults
  to 0.2 seconds.
- `resources/ui/inventory_theme.tres` contains the shared panel, cell, focus,
  valid-drop, and invalid-drop styles.
- Each resource in `resources/items` has an editable **Icon** assignment.
  Unassigned icons use the four fallback texture fields on the inventory root.

Single-click selects a cell. Double-click or Enter equips or unequips its item.
Dragging moves or swaps cells. Equipment accepts only matching Weapon, Armor,
or Accessory items. Returning equipped gear onto occupied inventory space swaps
only if the destination item fits the vacated equipment slot. Invalid or
cancelled drops do not change either item. Dragging near the top or bottom of
the inventory scrolls it.

`GeneralInventory.get_items()` remains an occupied-item list. `get_slots()` and
`get_item_at()` expose stable grid positions. Transfers use `move_or_swap()`,
`equip_from_slot()`, and `unequip_to_slot()`, with corresponding validation
methods. Duplicate copies are addressed by their cell, not resource identity.
The UI also checks inventory revision and character context before accepting
a drop.

Run and scenario saves retain their array of resource-path strings, with an
empty string representing a vacant cell. Earlier compact saves still load.
New rewards fill the first vacancy. Positions persist at the game's existing
checkpoints; this feature does not change when the game saves.

Run `tests/run_inventory_integration.gd` with Godot's `--script` option for
transfer, mouse, keyboard, equipment/stat, and persistence checks. For rendered
screenshots, provide an output directory and resolution after `--`, for example
`-- C:/Temp/inventory 1920x1080`. The test uses isolated fixtures and writes test
saves under `.godot/inventory_validation`.
