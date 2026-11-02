# KILOSGRAMMAR Leaderboard assets (November 2, 2026)

The active scene is `res://ui/secondary/leaderboard/leaderboard.tscn`, with behavior in `leaderboard.gd`. The Windows Downloads folder is **not** a runtime dependency.

## Reusable dropdowns

The four native Godot `OptionButton` controls—grammar style, mode, difficulty, and score sorting—share **one** image: `SharedDropdown20261102/dropdown_base.png`. It supplies the cream wooden background and decorative blue chevron, **not** option captions. The same cropped `SharedDropdownStyle` is assigned to all four buttons. Their actual changing captions are drawn with the existing Titan One font in Godot, using the same size, navy text, left alignment, and padding. Each dropdown retains its original selectable items and filter/sorting logic. The Grade and Section selectors are hidden as previously requested; grade/section data and grade sorting remain supported.

After verifying that there were no remaining runtime or test dependencies, 18 old per-selection PNGs and their 18 `.png.import` files were removed: 13 grammar/mode/difficulty variants in `2026-10-24/` and five score-sort variants in `NewButtons20261102/`. The separate 2-pixel transparent `Secondary/transparent_dropdown_arrow.png` and its import file were also removed: one editor-authored, fully transparent Godot `GradientTexture2D` now suppresses the duplicate native arrow without requiring another PNG. These files are recoverable from Git history and are **not** recreated at runtime. Do not reintroduce one PNG per selection: change the native option text or shared Inspector theme instead.

## Other illustrated controls remain separate

- `NewButtons20261102/IMPORT_transparent.png`, `EXPORT_transparent.png`, `DELETE_transparent.png` — blue, green, and red artwork for the existing three real buttons. Their teacher-authorized XLSX import/export and two-stage protected Delete behavior are unchanged. Original supplied button files remain as source artwork.
- `2026-10-24/LEADERBOARD.png` and `table_header.png` — retained title and table-header artwork.
- `NotifLeader/` — protected first- and second-stage deletion confirmation overlays.
- `Success/` — verified deletion-completed notice components.
- `Notice20261102/` — separate illustrated Leaderboard status/authorization notice components.

The background, title, buttons, OptionButtons, search field, table rows, notices, and delete overlays remain independent editor-authored nodes, not a flattened screenshot. Preserve the active node paths and test security actions before pruning any more art. In particular, a missing direct path reference alone does not prove an asset is unused when a loader constructs paths dynamically.

Focused coverage includes `tools/test_leaderboard_shared_dropdown_20261102.gd`, `tools/test_leaderboard_selected_assets.gd`, `tools/test_leaderboard_oct24_visual.gd`, `tools/test_leaderboard_design.gd`, and the protected import/export/delete integration suites. No database records were altered by this asset cleanup.
