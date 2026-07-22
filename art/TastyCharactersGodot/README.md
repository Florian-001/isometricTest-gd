# Tasty Characters for Godot 4

This folder is a ready-to-open Godot 4 project converted from `Tasty Characters Full Pack.unitypackage`.

## What is included

- **64 reference character scenes**: finished, one-sprite characters in `characters/reference/`.
- **48 modular character scenes**: editable layered characters in `characters/modular/`.
- **All atlas slices**: reusable `AtlasTexture` resources in `assets/sprites/`.
- **A showcase scene**: run the project to browse all 64 characters.

## Use a character

1. Open this folder in Godot 4.
2. Drag a `.tscn` from `characters/reference/<pack>/` into your scene.
3. Use the scenes under `characters/modular/` when you want to edit or animate individual body parts.

The character root is positioned at the original Unity pivot. The conversion uses 100 pixels per Unity unit and flips Unity's Y axis to Godot's canvas coordinates.

## Customize or animate

Modular scenes contain named `Sprite2D` nodes such as `Head`, `Body`, `Eye_L`, `Hand_R`, and `Foot_L`. Move, rotate, replace, or animate those nodes directly in Godot. The original Unity sorting orders are preserved as Godot `z_index` values.

## Source and license

This conversion does not grant a new license. Your original Tasty Characters asset license still governs these files. Keep proof of purchase and check the publisher's current redistribution terms before shipping or sharing the converted art.

## Rebuild

From the parent folder, run:

```powershell
python convert_unitypackage_to_godot.py
```

The converter uses only Python's standard library.
