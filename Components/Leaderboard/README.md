# Leaderboard — extracted component pack

This folder contains the **new 2026 Leaderboard component pack**, made from
`C:\Users\Yue\Downloads\431b27ff-031a-4389-9e8a-1b95a7ac53ae.png`,
as well as the earlier reference assets. The new sheet is retained intact
as `new_user_reference.png`.

The component PNGs retain original pixel color, anti-aliasing, lighting,
soft shadows and alpha. Their backgrounds were **not redrawn or replaced**:
several elements of the source sheet already contain baked atmospheric
gradients around the artwork.

## Used in game

`ui/secondary/leaderboard.tscn` is a fully **editor-authored layout**.
No reference screenshot is rendered underneath buttons. The new title,
board, buttons, table, foreground decorations and backdrop use separate
textures. A 2026 extraction manifest is included for reproducibility.

### Manual drag-and-drop editing

1. In Godot's FileSystem panel, open `res://ui/secondary/leaderboard.tscn`.
2. Select **2D**. The `Background` node is a full-window
   `TextureRect` and is **not locked**. Select it, then change
   **Inspector → Texture** to any other image. The other UI elements will
   stay in place. The default image is `new_background.png`.
3. All other permanent UI elements are **real movable nodes**:
   `WoodBoard`, `TitleArt`, `BackButton`, `FiltersArt`, the
   three independent `OptionButton` selectors, `TableHeaderArt`,
   `TableBodyArt`, `TableContent`, `EmptyMessage`,
   `DownloadButton`, `DecorativePot`, `DecorativeStar`, and
   `DecorativeBooks`.
4. Select a node from the **Scene** tree, drag it in 2D, resize its
   handles, or change its style, text, textures and anchors in the
   Inspector. **No script changes are necessary to move a button.**
5. The row cell positions belong to
   `res://ui/secondary/leaderboard_row.tscn`. Edit that scene visually
   for individual student-column spacing.
6. `ui/secondary/leaderboard.gd` only binds button signals, filters
   supplied records, populates row instances, and handles CSV export.
   It does not position UI nodes.

The background texture is separate and swappable. Changing the canvas
coordinates of a visible foreground node moves its **actual sprite,
label or selectable control**—not an invisible click area.
The original screenshots remain untouched under this folder.

## Re-extract

From project root:

```powershell
& 'C:\Espressif\tools\python\python.exe' -B tools\extract_leaderboard_components.py
```

To extract the **new reference** again:

```powershell
& 'C:\Espressif\tools\python\python.exe' -B tools\extract_leaderboard_2026_reference.py
```

`new_reference_manifest.json` records all new sprite bounds. The other
existing files under `Components/` are untouched.
