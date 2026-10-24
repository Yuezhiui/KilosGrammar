# NEW MAIN — editor-authored KilosGrammar Main Menu assets

All **27 original PNG files** were copied from
`C:\Users\Yue\Downloads\NEW MAIN` to this folder. Their original
dimensions, RGBA/alpha, and appearance are preserved.

The playable Main Menu is **`res://main_menu.tscn`**. This uses the
**original Main Menu composition, positions, sizes, hover effects and intro
animation** with the new source PNGs, not a flattened screenshot.
All permanent resting positions are editable in Godot 4.7:

1. In **FileSystem**, open `main_menu.tscn`, then select the **2D** tab.
2. To **change the static classroom background**, select
   `Background` → **Inspector → Texture**. It is a full-rect anchored
   `TextureRect`; resizing the game does not move the background.
3. The **KILOS** title and the seven individual **GRAMMAR** letter tiles
   are `TextureRect` nodes under `MainLayer/LogoGroup`.
   Select a tile to drag, resize, rotate, or replace its texture.
4. Each menu button is one **visible native Godot Button**, with its PNG
   applied as a `StyleBoxTexture`. Drag the button in 2D; to change its
   appearance, expand **Inspector → Theme Overrides → Styles → Normal**
   and select/replace the `StyleBoxTexture.texture` image. Hover, Pressed,
   and Disabled use that same image so there is no second hardcoded overlay.
   Change all states if you want custom hover/pressed artwork.
5. The left navigation buttons are children of `MainLayer/LeftMenu`;
   the main action buttons are under `MainLayer/CenterMenu`.
   Both are plain `Control` groups, **not automatic containers**.
   Their children have the same positions and dimensions as the original
   Main Menu: 225×55 for small buttons, 340×72 for large buttons.
6. The **original entrance**, tile-pop, gentle idle logo motion,
   hover/bounce, falling-word effects, sound effects and routing remain
   active. The script temporarily animates controls but returns them to
   the coordinates saved in `main_menu.tscn` at the end of intro.
   This preserves drag-and-drop: moving a button in the 2D editor changes
   the target location to which its intro animation returns.
7. All scene-controlled visuals can be edited directly. No duplicate
   labels or invisible button hitbox sprites have been added.

Additional blank and alternate button skins (`green-button.png`,
`purple-button.png`, `red-button.png`), icon PNGs, and alternative
spellings of source filenames are included unmodified as reusable art.

**Do not run scene generators to make positioning changes**: edit the
`.tscn` directly in Godot, save with Ctrl+S, and your placements stay saved.
