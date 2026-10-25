# Leaderboard unused-asset pruning — 25 October 2026

User request: keep only artwork actively used in the game and remove unused image/import/JSON files. All actions were limited to local project resources; no PostgreSQL deletion, Git reset, commit or push.

Before cleanup, `Components/Leaderboard/` had **42 old prototype PNGs directly in its root**. None were loaded by the active Leaderboard `.tscn` or GDScript. One (`background_fixed.png`) was referenced solely by an interchangeable-background test; the test now uses an actual deployed dropdown artwork file instead. All 42 images and their **42 matching `.png.import`** files were deleted.

Also deleted two obsolete image-extraction manifests (`source_manifest.json`, `new_reference_manifest.json`), their two Python extractor tools (`tools/extract_leaderboard_components.py` and `tools/extract_leaderboard_2026_reference.py`), and the unreferenced old screenshot `2026-10-24/522dcbe6-fab7-409a-b965-a31b573e9df9.png` plus sidecar. These were not required to start the game or render the current scene.

Retained: 20 active `2026-10-24` selected-state/action PNGs, all eight current `NotifLeader` confirmation artwork components, and the transparent native dropdown arrow. The now-superseded red `NotifLeader/permanent delete if add .png` **and its `.import`** were removed only after the user's updated `permanent delete if add_.png` was wired into the real scene and the gray/red render-size parity test passed at 1280×720, 1600×900 and 1920×1080. See `Components/Leaderboard/README.md` for the current folder structure.

Controls, editable scene nodes, CSV export/import logic and existing user-chosen button offsets were untouched by image pruning. Godot editor-import, 29-scene resource checks, interactive two-stage mock deletion, graphical alpha-size checks at three resolutions and minigame tests form the validation gate.

**Subsequent feature (26 October):** Three new user-supplied and actively used images were intentionally added under `Components/Leaderboard/Success/` (`bg.png`, `OkayButton.png`, and `00669de2-99cd-46c6-bef9-f3a0f69c72e1.png`, the decorated success header) for the wooden success notification. These are *not* orphans and are excluded from this historical October 25 deletion list. Leaderboard now has 32 image resources instead of the earlier post-prune 29.
