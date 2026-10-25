# KILOSGRAMMAR — Live Leaderboard artwork

Only images used by the current Godot Leaderboard (and its editable confirmation dialogs) belong in this folder. The older prototype sprite packs, reference-sheet screenshots, their `.import` files, unused manifests, and retired extractor scripts were pruned on 25 October 2026 at the user's request.

**Runtime artwork is fully local to the Godot project.** The supplied Downloads folders are source-only and are **not** read at runtime or referenced by the scene. All eight notification PNGs live in `res://Components/Leaderboard/NotifLeader/`; all three success PNGs live in `res://Components/Leaderboard/Success/`. Each has its own Godot `.png.import` metadata. The three success PNGs were verified as byte-identical copies of the supplied originals.

## Live artwork

- `2026-10-24/` — Leaderboard background, title, row/table header, back/import/export/delete buttons and all grammar/mode/difficulty dropdown selected-state textures. The PNGs are referenced individually by `res://ui/secondary/leaderboard.tscn` and remain draggable/editable in the editor.
- `NotifLeader/` — First and final wooden warning panels, two-stage confirmation buttons, input frame, and separate gray/red **`FinalDeleteButton`** styles. The red and gray are **one** native Godot Button with two authored styles, not two controls.
- `Success/` — Locally copied `bg.png`, `OkayButton.png`, and `00669de2-99cd-46c6-bef9-f3a0f69c72e1.png` (decorated **Leaderboard — Completed** header), displayed only on confirmed successful deletion. `SuccessBoard` and `SuccessHeader` remain separate editable TextureRects, green OK remains a native Button, and `SuccessMessage` is a native Label populated with backend-deleted record counts.
- `Secondary/transparent_dropdown_arrow.png` — Invisible native OptionButton arrow; the selected-state PNG artwork supplies the visible arrow so it never doubles.

There is no image drawn as a screenshot of the whole Leaderboard. Native Buttons, LineEdit, OptionButtons, labels, two delete-warning overlays and a separate success overlay remain `.tscn` nodes for drag-and-drop editing. The generic `EmptyNotice` remains untouched for unrelated CSV/import/export results and failures.

The active Godot scene is `res://ui/secondary/leaderboard.tscn`, with logic in `leaderboard.gd` and rows in `leaderboard_row.tscn`. To resize the red/gray PERMANENTLY DELETE art together, select `DeleteFinalOverlay/ConfirmPanel/FinalDeleteButton`. Change its offsets/rect once; `NotifDeleteEnabledStyle` and `NotifDeleteDisabledStyle` both use the same target rectangle, despite their underlying artwork being different original PNGs.

## Safety and verification

Do not remove any texture referenced from `.tscn` or from dynamic selected-skin loaders in `.gd`, even if it appears hidden. Check both direct file references and constructed resource paths. Tests include `tools/test_leaderboard_selected_assets.gd`, `tools/test_leaderboard_design.gd`, `tools/test_leaderboard_delete_modal_visual.gd`, `tools/test_leaderboard_delete_success_visual.gd`, and `tools/test_component_prune_integrity.gd`. The latter checks resource validity across the game.

The original reference packs were not part of the playable UI and have been removed rather than duplicated across folders. No database records were deleted, and the teacher-only two-stage delete flow is preserved.
